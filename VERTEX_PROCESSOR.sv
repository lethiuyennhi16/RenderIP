module VERTEX_PROCESSOR #(
    parameter CORE_ID = 7'd0
)(
    input logic clk,
    input logic rst_n,
    
    // Control interface  
    input logic start_render,
    
    // Matrix interface với CONTROL_MATRIX
    output logic matrix_request,
    output logic [2:0] matrix_opcode,
    input logic [31:0] matrix_data,
    input logic [6:0] matrix_target_core_id,
    input logic matrix_valid,
    output logic matrix_read_done,
    
    // Vertex data interface với ARBITER_VERTEX
    input logic [31:0] vertex_data,
    input logic [6:0] vertex_target_core_id, 
    input logic vertex_valid,
    output logic vertex_request,
    output logic vertex_read_done,
    
    // Output cho RASTERIZER (internal pipeline)
    output logic vertex_output_valid,
    output logic [31:0] clip_vert[3][4],    // gl_Position
    output logic [31:0] view_vert[3][3],    // gl_Position_view  
    output logic [31:0] varying_uv[3][2],   // texture coordinates
    output logic [31:0] varying_nrm[3][3],  // transformed normals
    output logic face_valid                 // after face culling
);

    // Matrix opcodes
    localparam MATRIX_MODELVIEW   = 3'd1;
    localparam MATRIX_PROJECTION  = 3'd2;
    localparam MATRIX_VIEWPORT    = 3'd3;
    localparam MATRIX_COMBINED    = 3'd4;  // ModelView * Projection
    localparam MATRIX_LIGHT       = 3'd5;  // Light vector
    
    // FSM States
    typedef enum logic [4:0] {
        IDLE                = 5'd0,
        REQUEST_MODELVIEW   = 5'd1,
        WAIT_MODELVIEW      = 5'd2,
        REQUEST_PROJECTION  = 5'd3,
        WAIT_PROJECTION     = 5'd4,
        INVERT_MODELVIEW    = 5'd5,
        TRANSPOSE_INVERTED  = 5'd6,
        REQUEST_VERTEX      = 5'd7,
        RECEIVE_VERTEX      = 5'd8,
        CALC_GL_POSITION_VIEW = 5'd9,
        CALC_GL_POSITION    = 5'd10,
        CALC_VARYING_NRM    = 5'd11,
        CALC_FACE_VECTORS   = 5'd12,
        CALC_FACE_NORMAL    = 5'd13,
        FACE_CULLING_TEST   = 5'd14,
        OUTPUT_VALID        = 5'd15,
        REQUEST_NEW_FACE    = 5'd16
    } vertex_state_t;
    
    vertex_state_t current_state, next_state;
    
    // Matrix storage
    logic [31:0] modelview_matrix[16];      // 4x4 ModelView matrix
    logic [31:0] projection_matrix[16];     // 4x4 Projection matrix
    logic [31:0] inverted_mv[16];          // Inverted ModelView
    logic [31:0] transposed_inv_mv[16];    // (ModelView^-1)^T for normals
    logic [4:0] matrix_element_count;       // 0-15 for matrix elements
    
    // Vertex data storage - 1 face = 3 vertices
    // Each vertex: v(xyz) + vt(uv) + vn(xyz) = 8 floats
    logic [31:0] face_data[24];            // 3 vertices * 8 components = 24
    logic [4:0] vertex_word_count;         // 0-23 for face data
    
    // Parsed vertex data
    logic [31:0] v_pos[3][3];             // 3 vertices, xyz positions  
    logic [31:0] vt_tex[3][2];            // 3 vertices, uv coordinates
    logic [31:0] vn_norm[3][3];           // 3 vertices, xyz normals (original)
    
    // Intermediate calculations
    logic [31:0] gl_pos_view_temp[4];     // Temporary for matrix-vector mult
    logic [31:0] gl_pos_temp[4];          // Temporary for matrix-vector mult
    logic [31:0] varying_nrm_temp[4];     // Temporary for normal transformation
    logic [31:0] face_vector1[3];         // view_vert[1] - view_vert[0]
    logic [31:0] face_vector2[3];         // view_vert[2] - view_vert[0]
    logic [31:0] face_normal[3];          // Cross product result
    logic [31:0] face_culling_dot;        // Dot product result
    
    // Processing indices
    logic [1:0] vertex_index;            // Which vertex (0-2) being processed
    logic [1:0] component_index;         // Which component (0-2 for xyz)
    logic [4:0] stream_count;            // Counter for streaming data
    logic [1:0] matrix_mult_stage;       // Which matrix multiplication
    
    // Hardcoded view direction (normalized camera direction)
    logic [31:0] view_dir[3];
    initial begin
        view_dir[0] = 32'h00000000;  // 0.0f
        view_dir[1] = 32'hBF000000;  // -0.5f  
        view_dir[2] = 32'hBF800000;  // -1.0f (pointing into screen)
    end
    
    // Arithmetic units interfaces
    
    // Basic float units
    logic [31:0] add_input_a, add_input_b;
    logic add_input_a_stb, add_input_b_stb;
    logic add_input_a_ack, add_input_b_ack;
    logic [31:0] add_output_z;
    logic add_output_z_stb, add_output_z_ack;
    
    logic [31:0] mul_input_a, mul_input_b;
    logic mul_input_a_stb, mul_input_b_stb;
    logic mul_input_a_ack, mul_input_b_ack;
    logic [31:0] mul_output_z;
    logic mul_output_z_stb, mul_output_z_ack;
    
    // Matrix operations
    logic mv_ready, mv_data_valid, mv_calc_done, mv_read_done;
    logic [31:0] mv_data, mv_result;
    
    logic inv_ready, inv_data_valid, inv_calc_done, inv_read_done;
    logic [31:0] inv_data_in, inv_data_out;
    
    // Vector operations
    logic cross_ready, cross_data_valid, cross_calc_done, cross_read_done;
    logic [31:0] cross_data, cross_result;
    
    logic dot_ready, dot_data_valid, dot_calc_done, dot_read_done;
    logic [31:0] dot_data, dot_result;
    
    // Arithmetic unit instances
    adder float_adder (
        .clk(clk),
        .rst(~rst_n),
        .input_a(add_input_a),
        .input_b(add_input_b),
        .input_a_stb(add_input_a_stb),
        .input_b_stb(add_input_b_stb),
        .input_a_ack(add_input_a_ack),
        .input_b_ack(add_input_b_ack),
        .output_z(add_output_z),
        .output_z_stb(add_output_z_stb),
        .output_z_ack(add_output_z_ack)
    );
    
    multiplier float_multiplier (
        .clk(clk),
        .rst(~rst_n),
        .input_a(mul_input_a),
        .input_b(mul_input_b),
        .input_a_stb(mul_input_a_stb),
        .input_b_stb(mul_input_b_stb),
        .input_a_ack(mul_input_a_ack),
        .input_b_ack(mul_input_b_ack),
        .output_z(mul_output_z),
        .output_z_stb(mul_output_z_stb),
        .output_z_ack(mul_output_z_ack)
    );
    
    mul4x4_4x1_wrapper mv_transform (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(mv_ready),
        .data_valid(mv_data_valid),
        .data(mv_data),
        .calc_done(mv_calc_done),
        .result(mv_result),
        .read_done(mv_read_done)
    );
    
    matrix_invert_4x4 matrix_inverter (
        .clk(clk),
        .rst_n(rst_n),
        .ready(inv_ready),
        .data_valid(inv_data_valid),
        .calc_done(inv_calc_done),
        .read_done(inv_read_done),
        .data_in(inv_data_in),
        .data_out(inv_data_out)
    );
    
    cross_product_3x1_wrapper cross_unit (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(cross_ready),
        .data_valid(cross_data_valid),
        .data(cross_data),
        .calc_done(cross_calc_done),
        .result(cross_result),
        .read_done(cross_read_done)
    );
    
    dot_product_3x1_wrapper dot_unit (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(dot_ready),
        .data_valid(dot_data_valid),
        .data(dot_data),
        .calc_done(dot_calc_done),
        .result(dot_result),
        .read_done(dot_read_done)
    );
    
    // State machine
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (start_render) begin
                    next_state = REQUEST_MODELVIEW;
                end
            end
            
            REQUEST_MODELVIEW: begin
                next_state = WAIT_MODELVIEW;
            end
            
            WAIT_MODELVIEW: begin
                if (matrix_valid && (matrix_target_core_id == CORE_ID) && (matrix_element_count >= 15)) begin
                    next_state = REQUEST_PROJECTION;
                end
            end
            
            REQUEST_PROJECTION: begin
                next_state = WAIT_PROJECTION;
            end
            
            WAIT_PROJECTION: begin
                if (matrix_valid && (matrix_target_core_id == CORE_ID) && (matrix_element_count >= 15)) begin
                    next_state = INVERT_MODELVIEW;
                end
            end
            
            INVERT_MODELVIEW: begin
                if (inv_calc_done) begin
                    next_state = TRANSPOSE_INVERTED;
                end
            end
            
            TRANSPOSE_INVERTED: begin
                // Simple transpose operation, can be done in 1 cycle
                next_state = REQUEST_VERTEX;
            end
            
            REQUEST_VERTEX: begin
                next_state = RECEIVE_VERTEX;
            end
            
            RECEIVE_VERTEX: begin
                if (vertex_valid && (vertex_target_core_id == CORE_ID) && (vertex_word_count >= 23)) begin
                    next_state = CALC_GL_POSITION_VIEW;
                end
            end
            
            CALC_GL_POSITION_VIEW: begin
                if (mv_calc_done && vertex_index >= 2) begin
                    next_state = CALC_GL_POSITION;
                end
            end
            
            CALC_GL_POSITION: begin
                if (mv_calc_done && vertex_index >= 2) begin
                    next_state = CALC_VARYING_NRM;
                end
            end
            
            CALC_VARYING_NRM: begin
                if (mv_calc_done && vertex_index >= 2) begin
                    next_state = CALC_FACE_VECTORS;
                end
            end
            
            CALC_FACE_VECTORS: begin
                if (component_index >= 2) begin // Calculated all xyz components
                    next_state = CALC_FACE_NORMAL;
                end
            end
            
            CALC_FACE_NORMAL: begin
                if (cross_calc_done) begin
                    next_state = FACE_CULLING_TEST;
                end
            end
            
            FACE_CULLING_TEST: begin
                if (dot_calc_done) begin
                    // Check if face should be culled
                    if (face_culling_dot[31] == 1'b0) begin // Positive dot product
                        next_state = OUTPUT_VALID;
                    end else begin
                        next_state = REQUEST_NEW_FACE; // Face culled, get new face
                    end
                end
            end
            
            OUTPUT_VALID: begin
                next_state = REQUEST_NEW_FACE;
            end
            
            REQUEST_NEW_FACE: begin
                next_state = RECEIVE_VERTEX;
            end
        endcase
    end
    
    // Matrix operations control
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            matrix_request <= 1'b0;
            matrix_opcode <= 3'b0;
            matrix_element_count <= 5'b0;
            matrix_read_done <= 1'b0;
        end else begin
            matrix_request <= 1'b0;
            matrix_read_done <= 1'b0;
            
            case (current_state)
                REQUEST_MODELVIEW: begin
                    matrix_request <= 1'b1;
                    matrix_opcode <= MATRIX_MODELVIEW;
                    matrix_element_count <= 5'b0;
                end
                
                WAIT_MODELVIEW: begin
                    if (matrix_valid && (matrix_target_core_id == CORE_ID)) begin
                        modelview_matrix[matrix_element_count] <= matrix_data;
                        matrix_element_count <= matrix_element_count + 1'b1;
                        if (matrix_element_count >= 15) begin
                            matrix_read_done <= 1'b1;
                        end
                    end
                end
                
                REQUEST_PROJECTION: begin
                    matrix_request <= 1'b1;
                    matrix_opcode <= MATRIX_PROJECTION;
                    matrix_element_count <= 5'b0;
                end
                
                WAIT_PROJECTION: begin
                    if (matrix_valid && (matrix_target_core_id == CORE_ID)) begin
                        projection_matrix[matrix_element_count] <= matrix_data;
                        matrix_element_count <= matrix_element_count + 1'b1;
                        if (matrix_element_count >= 15) begin
                            matrix_read_done <= 1'b1;
                        end
                    end
                end
            endcase
        end
    end
    
    // Matrix inversion control
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            inv_data_valid <= 1'b0;
            inv_read_done <= 1'b0;
            stream_count <= 5'b0;
        end else begin
            inv_data_valid <= 1'b0;
            inv_read_done <= 1'b0;
            
            case (current_state)
                INVERT_MODELVIEW: begin
                    if (inv_ready && !inv_calc_done && stream_count < 16) begin
                        inv_data_valid <= 1'b1;
                        inv_data_in <= modelview_matrix[stream_count];
                        stream_count <= stream_count + 1'b1;
                    end
                    
                    if (inv_calc_done && stream_count < 16) begin
                        inverted_mv[stream_count] <= inv_data_out;
                        stream_count <= stream_count + 1'b1;
                        if (stream_count >= 15) begin
                            inv_read_done <= 1'b1;
                            stream_count <= 5'b0;
                        end
                    end
                end
            endcase
        end
    end
    
    // Matrix transpose (for normal transformation)
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 16; i++) begin
                transposed_inv_mv[i] <= 32'b0;
            end
        end else begin
            if (current_state == TRANSPOSE_INVERTED) begin
                // Transpose 4x4 matrix: transposed[i][j] = original[j][i]
                for (int row = 0; row < 4; row++) begin
                    for (int col = 0; col < 4; col++) begin
                        transposed_inv_mv[row*4 + col] <= inverted_mv[col*4 + row];
                    end
                end
            end
        end
    end
    
    // Vertex data reception and parsing
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            vertex_request <= 1'b0;
            vertex_word_count <= 5'b0;
            vertex_read_done <= 1'b0;
            
            // Initialize vertex arrays
            for (int i = 0; i < 3; i++) begin
                for (int j = 0; j < 3; j++) begin
                    v_pos[i][j] <= 32'b0;
                    vn_norm[i][j] <= 32'b0;
                end
                for (int k = 0; k < 2; k++) begin
                    vt_tex[i][k] <= 32'b0;
                end
            end
        end else begin
            vertex_request <= 1'b0;
            vertex_read_done <= 1'b0;
            
            case (current_state)
                REQUEST_VERTEX, REQUEST_NEW_FACE: begin
                    vertex_request <= 1'b1;
                    vertex_word_count <= 5'b0;
                end
                
                RECEIVE_VERTEX: begin
                    if (vertex_valid && (vertex_target_core_id == CORE_ID)) begin
                        face_data[vertex_word_count] <= vertex_data;
                        vertex_word_count <= vertex_word_count + 1'b1;
                        
                        if (vertex_word_count >= 23) begin
                            vertex_read_done <= 1'b1;
                            
                            // Parse face_data into structured format
                            for (int vtx = 0; vtx < 3; vtx++) begin
                                // Position: v(xyz)
                                v_pos[vtx][0] <= face_data[vtx*8 + 0];  // x
                                v_pos[vtx][1] <= face_data[vtx*8 + 1];  // y
                                v_pos[vtx][2] <= face_data[vtx*8 + 2];  // z
                                
                                // Texture coords: vt(uv)
                                vt_tex[vtx][0] <= face_data[vtx*8 + 3]; // u
                                vt_tex[vtx][1] <= face_data[vtx*8 + 4]; // v
                                
                                // Normals: vn(xyz)
                                vn_norm[vtx][0] <= face_data[vtx*8 + 5]; // nx
                                vn_norm[vtx][1] <= face_data[vtx*8 + 6]; // ny
                                vn_norm[vtx][2] <= face_data[vtx*8 + 7]; // nz
                            end
                        end
                    end
                end
            endcase
        end
    end
    
    // gl_Position_view calculation: ModelView * vertex
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            mv_data_valid <= 1'b0;
            mv_read_done <= 1'b0;
            vertex_index <= 2'b0;
            stream_count <= 5'b0;
            matrix_mult_stage <= 2'b0;
        end else begin
            mv_data_valid <= 1'b0;
            mv_read_done <= 1'b0;
            
            case (current_state)
                CALC_GL_POSITION_VIEW: begin
                    if (mv_ready && !mv_calc_done && stream_count < 20) begin
                        mv_data_valid <= 1'b1;
                        
                        // Stream ModelView matrix (16) + current vertex position (4)
                        if (stream_count < 16) begin
                            mv_data <= modelview_matrix[stream_count];
                        end else begin
                            case (stream_count - 16)
                                2'd0: mv_data <= v_pos[vertex_index][0]; // x
                                2'd1: mv_data <= v_pos[vertex_index][1]; // y  
                                2'd2: mv_data <= v_pos[vertex_index][2]; // z
                                2'd3: mv_data <= 32'h3F800000;           // w = 1.0
                            endcase
                        end
                        stream_count <= stream_count + 1'b1;
                    end
                    
                    if (mv_calc_done) begin
                        // Store gl_Position_view (first 3 components)
                        view_vert[vertex_index][component_index] <= mv_result;
                        component_index <= component_index + 1'b1;
                        
                        if (component_index >= 2) begin // Got all xyz
                            mv_read_done <= 1'b1;
                            component_index <= 2'b0;
                            
                            if (vertex_index >= 2) begin
                                vertex_index <= 2'b0;
                                stream_count <= 5'b0;
                            end else begin
                                vertex_index <= vertex_index + 1'b1;
                                stream_count <= 5'b0;
                            end
                        end
                    end
                end
                
                CALC_GL_POSITION: begin
                    if (mv_ready && !mv_calc_done && stream_count < 20) begin
                        mv_data_valid <= 1'b1;
                        
                        // Stream Projection*ModelView matrix (16) + current vertex position (4)
                        if (stream_count < 16) begin
                            // Need combined matrix - for now use sequential multiplication
                            // This is simplified - should use proper combined matrix
                            mv_data <= projection_matrix[stream_count];
                        end else begin
                            mv_data <= gl_pos_view_temp[stream_count - 16];
                        end
                        stream_count <= stream_count + 1'b1;
                    end
                    
                    if (mv_calc_done) begin
                        // Store gl_Position (4 components)
                        clip_vert[vertex_index][component_index] <= mv_result;
                        component_index <= component_index + 1'b1;
                        
                        if (component_index >= 3) begin // Got all xyzw
                            mv_read_done <= 1'b1;
                            component_index <= 2'b0;
                            
                            if (vertex_index >= 2) begin
                                vertex_index <= 2'b0;
                                stream_count <= 5'b0;
                            end else begin
                                vertex_index <= vertex_index + 1'b1;
                                stream_count <= 5'b0;
                            end
                        end
                    end
                end
                
                CALC_VARYING_NRM: begin
                    if (mv_ready && !mv_calc_done && stream_count < 20) begin
                        mv_data_valid <= 1'b1;
                        
                        // Stream transposed inverted ModelView (16) + current normal (4)
                        if (stream_count < 16) begin
                            mv_data <= transposed_inv_mv[stream_count];
                        end else begin
                            case (stream_count - 16)
                                2'd0: mv_data <= vn_norm[vertex_index][0]; // nx
                                2'd1: mv_data <= vn_norm[vertex_index][1]; // ny  
                                2'd2: mv_data <= vn_norm[vertex_index][2]; // nz
                                2'd3: mv_data <= 32'h00000000;             // w = 0.0 for vectors
                            endcase
                        end
                        stream_count <= stream_count + 1'b1;
                    end
                    
                    if (mv_calc_done) begin
                        // Store varying_nrm (first 3 components)
                        varying_nrm[vertex_index][component_index] <= mv_result;
                        component_index <= component_index + 1'b1;
                        
                        if (component_index >= 2) begin // Got all xyz
                            mv_read_done <= 1'b1;
                            component_index <= 2'b0;
                            
                            if (vertex_index >= 2) begin
                                vertex_index <= 2'b0;
                                stream_count <= 5'b0;
                            end else begin
                                vertex_index <= vertex_index + 1'b1;
                                stream_count <= 5'b0;
                            end
                        end
                    end
                end
                
                default: begin
                    vertex_index <= 2'b0;
                    stream_count <= 5'b0;
                    matrix_mult_stage <= 2'b0;
                    component_index <= 2'b0;
                end
            endcase
        end
    end
    
    // Face vector calculation: view_vert[1] - view_vert[0], view_vert[2] - view_vert[0]
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            add_input_a_stb <= 1'b0;
            add_input_b_stb <= 1'b0;
            add_output_z_ack <= 1'b0;
            component_index <= 2'b0;
        end else begin
            add_input_a_stb <= 1'b0;
            add_input_b_stb <= 1'b0;
            add_output_z_ack <= 1'b0;
            
            case (current_state)
                CALC_FACE_VECTORS: begin
                    if (!add_input_a_stb && !add_input_b_stb && component_index < 3) begin
                        // Calculate face_vector1[component] = view_vert[1][component] - view_vert[0][component]
                        add_input_a <= view_vert[1][component_index];
                        add_input_b <= {~view_vert[0][component_index][31], view_vert[0][component_index][30:0]}; // Negate
                        add_input_a_stb <= 1'b1;
                        add_input_b_stb <= 1'b1;
                    end else if (add_input_a_ack && add_input_b_ack) begin
                        add_input_a_stb <= 1'b0;
                        add_input_b_stb <= 1'b0;
                    end else if (add_output_z_stb) begin
                        if (component_index < 3) begin
                            face_vector1[component_index] <= add_output_z;
                        end else begin
                            face_vector2[component_index - 3] <= add_output_z;
                        end
                        add_output_z_ack <= 1'b1;
                        component_index <= component_index + 1'b1;
                    end
                end
                
                default: begin
                    component_index <= 2'b0;
                end
            endcase
        end
    end
    
    // Face normal calculation: cross(face_vector1, face_vector2)
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            cross_data_valid <= 1'b0;
            cross_read_done <= 1'b0;
            stream_count <= 5'b0;
        end else begin
            cross_data_valid <= 1'b0;
            cross_read_done <= 1'b0;
            
            case (current_state)
                CALC_FACE_NORMAL: begin
                    if (cross_ready && !cross_calc_done && stream_count < 6) begin
                        cross_data_valid <= 1'b1;
                        
                        // Stream two 3D vectors: face_vector1, face_vector2
                        if (stream_count < 3) begin
                            cross_data <= face_vector1[stream_count];
                        end else begin
                            cross_data <= face_vector2[stream_count - 3];
                        end
                        stream_count <= stream_count + 1'b1;
                    end
                    
                    if (cross_calc_done) begin
                        face_normal[component_index] <= cross_result;
                        component_index <= component_index + 1'b1;
                        
                        if (component_index >= 2) begin // Got all xyz components
                            cross_read_done <= 1'b1;
                            component_index <= 2'b0;
                            stream_count <= 5'b0;
                        end
                    end
                end
                
                default: begin
                    stream_count <= 5'b0;
                    component_index <= 2'b0;
                end
            endcase
        end
    end
    
    // Face culling test: dot(face_normal, view_dir)
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            dot_data_valid <= 1'b0;
            dot_read_done <= 1'b0;
            stream_count <= 5'b0;
        end else begin
            dot_data_valid <= 1'b0;
            dot_read_done <= 1'b0;
            
            case (current_state)
                FACE_CULLING_TEST: begin
                    if (dot_ready && !dot_calc_done && stream_count < 6) begin
                        dot_data_valid <= 1'b1;
                        
                        // Stream two 3D vectors: face_normal, view_dir
                        if (stream_count < 3) begin
                            dot_data <= face_normal[stream_count];
                        end else begin
                            dot_data <= view_dir[stream_count - 3];
                        end
                        stream_count <= stream_count + 1'b1;
                    end
                    
                    if (dot_calc_done) begin
                        face_culling_dot <= dot_result;
                        dot_read_done <= 1'b1;
                        stream_count <= 5'b0;
                    end
                end
                
                default: begin
                    stream_count <= 5'b0;
                end
            endcase
        end
    end
    
    // Output control and texture coordinate assignment
    always_comb begin
        // Default outputs
        vertex_output_valid = 1'b0;
        face_valid = 1'b0;
        
        // Output valid face data
        if (current_state == OUTPUT_VALID) begin
            vertex_output_valid = 1'b1;
            face_valid = 1'b1;
            
            // Copy texture coordinates to output (unchanged)
            for (int i = 0; i < 3; i++) begin
                varying_uv[i][0] = vt_tex[i][0];
                varying_uv[i][1] = vt_tex[i][1];
            end
        end else begin
            // Clear outputs when not valid
            for (int i = 0; i < 3; i++) begin
                varying_uv[i][0] = 32'b0;
                varying_uv[i][1] = 32'b0;
            end
        end
    end
    
    // Reset control variables when starting new face
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            vertex_index <= 2'b0;
            component_index <= 2'b0;
            stream_count <= 5'b0;
            matrix_mult_stage <= 2'b0;
        end else begin
            if (current_state == REQUEST_NEW_FACE || current_state == REQUEST_VERTEX) begin
                vertex_index <= 2'b0;
                component_index <= 2'b0;
                stream_count <= 5'b0;
                matrix_mult_stage <= 2'b0;
            end
        end
    end

endmodule