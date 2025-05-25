module CONTROL_MATRIX (
    input logic clk,
    input logic rst_n,
    
    // Interface với READ_MASTER (nhận lookat data)
    input logic        lookat_data_valid,
    input logic [31:0] lookat_data,     // Stream: eye_xyz, center_xyz, up_xyz, light_xyz
    output logic       lookat_ready,
    
    // Interface với CONTROL
    input logic        start_calc_matrix,
    output logic       calc_matrix_done,
    input logic [31:0] width_framebuffer,
    input logic [31:0] height_framebuffer,
    
    // Interface với RENDER_CORE (shared access)
    input logic [86:0] matrix_request,      // Core requests
    input logic [86:0][2:0] matrix_opcode,  // Matrix type: 1=ModelView, 2=Projection, 3=Viewport, 4=Combined, 5=Light
    output logic [31:0] matrix_data,        // Matrix elements 
    output logic [6:0]  target_core_id,
    output logic        matrix_valid,
    input logic [86:0]  matrix_read_done    // Core completed reading matrix
);

    // Matrix opcodes
    localparam MATRIX_MODELVIEW   = 3'd1;
    localparam MATRIX_PROJECTION  = 3'd2; 
    localparam MATRIX_VIEWPORT    = 3'd3;
    localparam MATRIX_COMBINED    = 3'd4;  // ModelView * Projection
    localparam MATRIX_LIGHT       = 3'd5;  // Light vector in view coordinates
    
    // Main FSM states
    typedef enum logic [4:0] {
        IDLE            = 5'd0,
        RECEIVE_DATA    = 5'd1,
        
        // ModelView calculation pipeline
        CALC_Z_SUB      = 5'd2,   // z = center - eye (3 subtractions)
        CALC_Z_NORM     = 5'd3,   // z = normalize(z)
        CALC_X_CROSS    = 5'd4,   // x = cross(up, z)
        CALC_X_NORM     = 5'd5,   // x = normalize(x)
        CALC_Y_CROSS    = 5'd6,   // y = cross(z, x)
        BUILD_MINV      = 5'd7,   // Construct Minv matrix
        BUILD_TR        = 5'd8,   // Construct Tr matrix  
        MULT_MODELVIEW  = 5'd9,   // ModelView = Minv * Tr
        
        // Projection calculation
        CALC_EYE_CENTER_DIST = 5'd10,  // |eye - center|
        CALC_PROJECTION = 5'd11,
        
        // Other calculations
        CALC_VIEWPORT   = 5'd12,
        MULT_COMBINED   = 5'd13,  // ModelView * Projection
        MULT_LIGHT      = 5'd14,  // ModelView * light_vector
        
        MATRICES_READY  = 5'd15,
        SERVE_REQUEST   = 5'd16,
        SEND_MATRIX     = 5'd17,
        WAIT_ACK        = 5'd18
    } state_t;
    
    state_t current_state, next_state;
    
    // Sub-FSM for vector subtraction
    typedef enum logic [2:0] {
        SUB_IDLE  = 3'd0,
        SUB_SEND_A = 3'd1,
        SUB_WAIT_A = 3'd2,
        SUB_SEND_B = 3'd3,
        SUB_WAIT_B = 3'd4,
        SUB_GET_RESULT = 3'd5,
        SUB_DONE = 3'd6
    } sub_state_t;
    
    sub_state_t sub_current_state, sub_next_state;
    
    // Input data storage
    logic [31:0] eye[3];         // Camera position
    logic [31:0] center[3];      // Camera target
    logic [31:0] up[3];          // Camera up vector
    logic [31:0] light[3];       // Light direction
    logic [3:0]  data_count;     // Input counter (0-11)
    
    // Intermediate calculation vectors
    logic [31:0] z_temp[3];      // center - eye
    logic [31:0] z_vec[3];       // normalized z
    logic [31:0] x_temp[3];      // cross(up, z)
    logic [31:0] x_vec[3];       // normalized x
    logic [31:0] y_vec[3];       // cross(z, x)
    logic [31:0] eye_center_dist; // |eye - center| for projection
    
    // Matrix storage
    logic [31:0] modelview_matrix[16];   // 4x4 ModelView matrix
    logic [31:0] projection_matrix[16];  // 4x4 Projection matrix
    logic [31:0] viewport_matrix[16];    // 4x4 Viewport matrix
    logic [31:0] combined_matrix[16];    // 4x4 Combined matrix
    logic [31:0] light_view[3];          // Light vector in view coordinates
    logic [31:0] minv_matrix[16];        // Temporary Minv matrix
    logic [31:0] tr_matrix[16];          // Temporary Tr matrix
    
    // Operation counters and flags
    logic [1:0]  vector_count;           // For 3-element vector operations
    logic [4:0]  matrix_count;           // For matrix element streaming
    logic [4:0]  stream_count;           // For streaming operations
    logic        sub_op_done;
    
    // Matrix serving
    logic [6:0]  serving_core;
    logic [2:0]  serving_opcode;
    logic [4:0]  matrix_element_count;   // 0-15 for matrices, 0-2 for vectors
    
    // Priority encoder for requests
    logic [6:0]  requesting_core;
    logic [2:0]  requesting_opcode;
    logic        valid_request_found;
    
    // Arithmetic unit interfaces
    
    // Adder/Subtractor 1
    logic [31:0] add1_input_a, add1_input_b;
    logic        add1_input_a_stb, add1_input_b_stb;
    logic        add1_input_a_ack, add1_input_b_ack;
    logic [31:0] add1_output_z;
    logic        add1_output_z_stb;
    logic        add1_output_z_ack;
    
    // Adder/Subtractor 2
    logic [31:0] add2_input_a, add2_input_b;
    logic        add2_input_a_stb, add2_input_b_stb;
    logic        add2_input_a_ack, add2_input_b_ack;
    logic [31:0] add2_output_z;
    logic        add2_output_z_stb;
    logic        add2_output_z_ack;
    
    // Multiplier 1
    logic [31:0] mul1_input_a, mul1_input_b;
    logic        mul1_input_a_stb, mul1_input_b_stb;
    logic        mul1_input_a_ack, mul1_input_b_ack;
    logic [31:0] mul1_output_z;
    logic        mul1_output_z_stb;
    logic        mul1_output_z_ack;
    
    // Multiplier 2
    logic [31:0] mul2_input_a, mul2_input_b;
    logic        mul2_input_a_stb, mul2_input_b_stb;
    logic        mul2_input_a_ack, mul2_input_b_ack;
    logic [31:0] mul2_output_z;
    logic        mul2_output_z_stb;
    logic        mul2_output_z_ack;
    
    // Divider 1
    logic [31:0] div1_input_a, div1_input_b;
    logic        div1_input_a_stb, div1_input_b_stb;
    logic        div1_input_a_ack, div1_input_b_ack;
    logic [31:0] div1_output_z;
    logic        div1_output_z_stb;
    logic        div1_output_z_ack;
    
    // Divider 2
    logic [31:0] div2_input_a, div2_input_b;
    logic        div2_input_a_stb, div2_input_b_stb;
    logic        div2_input_a_ack, div2_input_b_ack;
    logic [31:0] div2_output_z;
    logic        div2_output_z_stb;
    logic        div2_output_z_ack;
    
    // Vector normalize (parallel interface)
    logic        norm_ready;
    logic        norm_data_valid;
    logic        norm_calc_done;
    logic        norm_read_done;
    logic [31:0] norm_x_in, norm_y_in, norm_z_in;
    logic [31:0] norm_x_out, norm_y_out, norm_z_out;
    
    // Cross product (stream interface)
    logic        cross_ready;
    logic        cross_data_valid;
    logic [31:0] cross_data;
    logic        cross_data_done;
    logic        cross_calc_done;
    logic [31:0] cross_result;
    logic        cross_read_done;
    
    // Matrix multiplier (stream interface)
    logic        mat_mult_ready;
    logic        mat_mult_data_valid;
    logic [31:0] mat_mult_data;
    logic        mat_mult_calc_done;
    logic [31:0] mat_mult_result;
    logic        mat_mult_read_done;
    
    // Square root for distance calculation
    logic        sqrt_ready;
    logic        sqrt_data_valid;
    logic [31:0] sqrt_data_in;
    logic        sqrt_calc_done;
    logic [31:0] sqrt_result_out;
    logic        sqrt_read_done;
    
    // Instantiate arithmetic units
    
    adder float_adder_1 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(add1_input_a),
        .input_b(add1_input_b),
        .input_a_stb(add1_input_a_stb),
        .input_b_stb(add1_input_b_stb),
        .input_a_ack(add1_input_a_ack),
        .input_b_ack(add1_input_b_ack),
        .output_z(add1_output_z),
        .output_z_stb(add1_output_z_stb),
        .output_z_ack(add1_output_z_ack)
    );
    
    adder float_adder_2 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(add2_input_a),
        .input_b(add2_input_b),
        .input_a_stb(add2_input_a_stb),
        .input_b_stb(add2_input_b_stb),
        .input_a_ack(add2_input_a_ack),
        .input_b_ack(add2_input_b_ack),
        .output_z(add2_output_z),
        .output_z_stb(add2_output_z_stb),
        .output_z_ack(add2_output_z_ack)
    );
    
    multiplier float_multiplier_1 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(mul1_input_a),
        .input_b(mul1_input_b),
        .input_a_stb(mul1_input_a_stb),
        .input_b_stb(mul1_input_b_stb),
        .input_a_ack(mul1_input_a_ack),
        .input_b_ack(mul1_input_b_ack),
        .output_z(mul1_output_z),
        .output_z_stb(mul1_output_z_stb),
        .output_z_ack(mul1_output_z_ack)
    );
    
    multiplier float_multiplier_2 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(mul2_input_a),
        .input_b(mul2_input_b),
        .input_a_stb(mul2_input_a_stb),
        .input_b_stb(mul2_input_b_stb),
        .input_a_ack(mul2_input_a_ack),
        .input_b_ack(mul2_input_b_ack),
        .output_z(mul2_output_z),
        .output_z_stb(mul2_output_z_stb),
        .output_z_ack(mul2_output_z_ack)
    );
    
    divider float_divider_1 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(div1_input_a),
        .input_b(div1_input_b),
        .input_a_stb(div1_input_a_stb),
        .input_b_stb(div1_input_b_stb),
        .input_a_ack(div1_input_a_ack),
        .input_b_ack(div1_input_b_ack),
        .output_z(div1_output_z),
        .output_z_stb(div1_output_z_stb),
        .output_z_ack(div1_output_z_ack)
    );
    
    divider float_divider_2 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(div2_input_a),
        .input_b(div2_input_b),
        .input_a_stb(div2_input_a_stb),
        .input_b_stb(div2_input_b_stb),
        .input_a_ack(div2_input_a_ack),
        .input_b_ack(div2_input_b_ack),
        .output_z(div2_output_z),
        .output_z_stb(div2_output_z_stb),
        .output_z_ack(div2_output_z_ack)
    );
    
    // Vector normalize - parallel interface
    vector_normalize_3d norm_unit (
        .clk(clk),
        .rst_n(rst_n),
        .ready(norm_ready),
        .data_valid(norm_data_valid),
        .calc_done(norm_calc_done),
        .read_done(norm_read_done),
        .x_in(norm_x_in),
        .y_in(norm_y_in),
        .z_in(norm_z_in),
        .x_out(norm_x_out),
        .y_out(norm_y_out),
        .z_out(norm_z_out)
    );
    
    // Cross product - stream interface
    cross_product_3x1_wrapper cross_unit (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(cross_ready),
        .data_valid(cross_data_valid),
        .data(cross_data),
        .data_done(cross_data_done),
        .calc_done(cross_calc_done),
        .result(cross_result),
        .read_done(cross_read_done)
    );
    
    // Matrix multiplier - stream interface
    mul4x4_4x4_wrapper matrix_mult_unit (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(mat_mult_ready),
        .data_valid(mat_mult_data_valid),
        .data(mat_mult_data),
        .calc_done(mat_mult_calc_done),
        .result(mat_mult_result),
        .read_done(mat_mult_read_done)
    );
    
    // Square root
    sqrt_slave sqrt_unit (
        .clk(clk),
        .rst_n(rst_n),
        .ready(sqrt_ready),
        .data_valid(sqrt_data_valid),
        .data_in(sqrt_data_in),
        .calc_done(sqrt_calc_done),
        .result_out(sqrt_result_out),
        .read_done(sqrt_read_done)
    );
    
    // Priority encoder for core requests
    always_comb begin
        requesting_core = 7'd127;
        requesting_opcode = 3'b0;
        valid_request_found = 1'b0;
        
        for (int i = 0; i < 87; i++) begin
            if (matrix_request[i] && (i < requesting_core)) begin
                requesting_core = i[6:0];
                requesting_opcode = matrix_opcode[i];
                valid_request_found = 1'b1;
            end
    end
    
    // Projection calculation using divider unit
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            neg_one_div_f <= 32'h00000000;
            // Divider 1 controls  
            div1_input_a <= 32'b0;
            div1_input_b <= 32'b0;
            div1_input_a_stb <= 1'b0;
            div1_input_b_stb <= 1'b0;
            div1_output_z_ack <= 1'b0;
        end else begin
            // Default values
            div1_input_a_stb <= 1'b0;
            div1_input_b_stb <= 1'b0;
            div1_output_z_ack <= 1'b0;
            
            case (proj_current_state)
                PROJ_CALC_DIV: begin
                    // Calculate -1 / eye_center_dist
                    if (!div1_input_a_stb && !div1_input_b_stb) begin
                        div1_input_a <= 32'hBF800000;  // -1.0f
                        div1_input_a_stb <= 1'b1;
                    end else if (div1_input_a_ack && !div1_input_b_stb) begin
                        div1_input_a_stb <= 1'b0;
                        div1_input_b <= eye_center_dist;
                        div1_input_b_stb <= 1'b1;
                    end else if (div1_input_b_ack) begin
                        div1_input_b_stb <= 1'b0;
                    end else if (div1_output_z_stb) begin
                        neg_one_div_f <= div1_output_z;
                        div1_output_z_ack <= 1'b1;
                    end
                end
            endcase
        end
    end
    
    // Viewport calculation using multiplier unit
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            w_div_8 <= 32'b0;
            h_div_8 <= 32'b0;
            w_3div4 <= 32'b0;
            h_3div4 <= 32'b0;
        end else begin
            case (vp_current_state)
                VP_CALC_W_DIV8: begin
                    // Calculate width / 8 using multiplier (multiply by 1/8 = 0.125)
                    if (!mul_input_a_stb && !mul_input_b_stb) begin
                        mul_input_a <= width_framebuffer;
                        mul_input_a_stb <= 1'b1;
                    end else if (mul_input_a_ack && !mul_input_b_stb) begin
                        mul_input_a_stb <= 1'b0;
                        mul_input_b <= 32'h3E000000;  // 0.125f (1/8)
                        mul_input_b_stb <= 1'b1;
                    end else if (mul_input_b_ack) begin
                        mul_input_b_stb <= 1'b0;
                    end else if (mul_output_z_stb) begin
                        w_div_8 <= mul_output_z;
                        mul_output_z_ack <= 1'b1;
                    end
                end
                
                VP_CALC_H_DIV8: begin
                    // Calculate height / 8
                    if (!mul_input_a_stb && !mul_input_b_stb) begin
                        mul_input_a <= height_framebuffer;
                        mul_input_a_stb <= 1'b1;
                    end else if (mul_input_a_ack && !mul_input_b_stb) begin
                        mul_input_a_stb <= 1'b0;
                        mul_input_b <= 32'h3E000000;  // 0.125f (1/8)
                        mul_input_b_stb <= 1'b1;
                    end else if (mul_input_b_ack) begin
                        mul_input_b_stb <= 1'b0;
                    end else if (mul_output_z_stb) begin
                        h_div_8 <= mul_output_z;
                        mul_output_z_ack <= 1'b1;
                    end
                end
                
                VP_CALC_W_3DIV4: begin
                    // Calculate width * 3/4
                    if (!mul_input_a_stb && !mul_input_b_stb) begin
                        mul_input_a <= width_framebuffer;
                        mul_input_a_stb <= 1'b1;
                    end else if (mul_input_a_ack && !mul_input_b_stb) begin
                        mul_input_a_stb <= 1'b0;
                        mul_input_b <= 32'h3F400000;  // 0.75f (3/4)
                        mul_input_b_stb <= 1'b1;
                    end else if (mul_input_b_ack) begin
                        mul_input_b_stb <= 1'b0;
                    end else if (mul_output_z_stb) begin
                        w_3div4 <= mul_output_z;
                        mul_output_z_ack <= 1'b1;
                    end
                end
                
                VP_CALC_H_3DIV4: begin
                    // Calculate height * 3/4
                    if (!mul_input_a_stb && !mul_input_b_stb) begin
                        mul_input_a <= height_framebuffer;
                        mul_input_a_stb <= 1'b1;
                    end else if (mul_input_a_ack && !mul_input_b_stb) begin
                        mul_input_a_stb <= 1'b0;
                        mul_input_b <= 32'h3F400000;  // 0.75f (3/4)
                        mul_input_b_stb <= 1'b1;
                    end else if (mul_input_b_ack) begin
                        mul_input_b_stb <= 1'b0;
                    end else if (mul_output_z_stb) begin
                        h_3div4 <= mul_output_z;
                        mul_output_z_ack <= 1'b1;
                    end
                end
            endcase
        end
        end
    end
    
    // Main state machine
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Sub-FSM for vector operations
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            sub_current_state <= SUB_IDLE;
        end else begin
            sub_current_state <= sub_next_state;
        end
    end
    
    // Main next state logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (start_calc_matrix && lookat_data_valid) begin
                    next_state = RECEIVE_DATA;
                end else if (valid_request_found) begin
                    next_state = SERVE_REQUEST;
                end
            end
            
            RECEIVE_DATA: begin
                if (data_count >= 11) begin
                    next_state = CALC_Z_SUB;
                end
            end
            
            CALC_Z_SUB: begin
                if (sub_op_done) begin
                    next_state = CALC_Z_NORM;
                end
            end
            
            CALC_Z_NORM: begin
                if (norm_calc_done) begin
                    next_state = CALC_X_CROSS;
                end
            end
            
            CALC_X_CROSS: begin
                if (cross_calc_done) begin
                    next_state = CALC_X_NORM;
                end
            end
            
            CALC_X_NORM: begin
                if (norm_calc_done) begin
                    next_state = CALC_Y_CROSS;
                end
            end
            
            CALC_Y_CROSS: begin
                if (cross_calc_done) begin
                    next_state = BUILD_MINV;
                end
            end
            
            BUILD_MINV: begin
                next_state = BUILD_TR;
            end
            
            BUILD_TR: begin
                next_state = MULT_MODELVIEW;
            end
            
            MULT_MODELVIEW: begin
                if (mat_mult_calc_done) begin
                    next_state = CALC_EYE_CENTER_DIST;
                end
            end
            
            CALC_EYE_CENTER_DIST: begin
                if (sqrt_calc_done) begin
                    next_state = CALC_PROJECTION;
                end
            end
            
            CALC_PROJECTION: begin
                if (proj_current_state == PROJ_IDLE) begin  // Wait for projection calculation to complete
                    next_state = CALC_VIEWPORT;
                end
            end
            
            CALC_VIEWPORT: begin
                if (vp_current_state == VP_IDLE) begin  // Wait for viewport calculation to complete
                    next_state = MULT_COMBINED;
                end
            end
            
            MULT_COMBINED: begin
                if (mat_mult_calc_done) begin
                    next_state = MULT_LIGHT;
                end
            end
            
            MULT_LIGHT: begin
                if (mat_mult_calc_done) begin
                    next_state = MATRICES_READY;
                end
            end
            
            MATRICES_READY: begin
                if (valid_request_found) begin
                    next_state = SERVE_REQUEST;
                end
            end
            
            SERVE_REQUEST: begin
                next_state = SEND_MATRIX;
            end
            
            SEND_MATRIX: begin
                if ((serving_opcode == MATRIX_LIGHT && matrix_element_count >= 2) ||
                    (serving_opcode != MATRIX_LIGHT && matrix_element_count >= 15)) begin
                    next_state = WAIT_ACK;
                end
            end
            
            WAIT_ACK: begin
                if (matrix_read_done[serving_core]) begin
                    next_state = MATRICES_READY;
                end
            end
        endcase
    end
    
    // Sub-FSM next state logic for vector subtraction
    always_comb begin
        sub_next_state = sub_current_state;
        
        case (sub_current_state)
            SUB_IDLE: begin
                if (current_state == CALC_Z_SUB && vector_count < 3) begin
                    sub_next_state = SUB_SEND_A;
                end
            end
            
            SUB_SEND_A: begin
                if (add1_input_a_ack) begin
                    sub_next_state = SUB_WAIT_A;
                end
            end
            
            SUB_WAIT_A: begin
                sub_next_state = SUB_SEND_B;
            end
            
            SUB_SEND_B: begin
                if (add1_input_b_ack) begin
                    sub_next_state = SUB_WAIT_B;
                end
            end
            
            SUB_WAIT_B: begin
                sub_next_state = SUB_GET_RESULT;
            end
            
            SUB_GET_RESULT: begin
                if (add1_output_z_stb) begin
                    sub_next_state = SUB_DONE;
                end
            end
            
            SUB_DONE: begin
                sub_next_state = SUB_IDLE;
            end
        endcase
    end
    
    // Input data reception
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            data_count <= 4'b0;
            for (int i = 0; i < 3; i++) begin
                eye[i] <= 32'b0;
                center[i] <= 32'b0;
                up[i] <= 32'b0;
                light[i] <= 32'b0;
            end
        end else begin
            if (current_state == RECEIVE_DATA && lookat_data_valid) begin
                case (data_count)
                    4'd0: eye[0] <= lookat_data;      // eye_x
                    4'd1: eye[1] <= lookat_data;      // eye_y
                    4'd2: eye[2] <= lookat_data;      // eye_z
                    4'd3: center[0] <= lookat_data;   // center_x
                    4'd4: center[1] <= lookat_data;   // center_y
                    4'd5: center[2] <= lookat_data;   // center_z
                    4'd6: up[0] <= lookat_data;       // up_x
                    4'd7: up[1] <= lookat_data;       // up_y
                    4'd8: up[2] <= lookat_data;       // up_z
                    4'd9: light[0] <= lookat_data;    // light_x
                    4'd10: light[1] <= lookat_data;   // light_y
                    4'd11: light[2] <= lookat_data;   // light_z
                endcase
                data_count <= data_count + 1'b1;
            end else if (current_state == IDLE) begin
                data_count <= 4'b0;
            end
        end
    end
    
    // Vector subtraction control (z = center - eye) - using adder_1
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            vector_count <= 2'b0;
            sub_op_done <= 1'b0;
            add1_input_a <= 32'b0;
            add1_input_b <= 32'b0;
            add1_input_a_stb <= 1'b0;
            add1_input_b_stb <= 1'b0;
            add1_output_z_ack <= 1'b0;
        end else begin
            // Default values
            add1_input_a_stb <= 1'b0;
            add1_input_b_stb <= 1'b0;
            add1_output_z_ack <= 1'b0;
            
            case (current_state)
                CALC_Z_SUB: begin
                    case (sub_current_state)
                        SUB_SEND_A: begin
                            add1_input_a <= center[vector_count];
                            add1_input_a_stb <= 1'b1;
                        end
                        
                        SUB_SEND_B: begin
                            // For subtraction: add1_input_b should be negative of eye
                            add1_input_b <= {~eye[vector_count][31], eye[vector_count][30:0]}; // Flip sign bit
                            add1_input_b_stb <= 1'b1;
                        end
                        
                        SUB_GET_RESULT: begin
                            add1_output_z_ack <= 1'b1;
                            z_temp[vector_count] <= add1_output_z;
                        end
                        
                        SUB_DONE: begin
                            vector_count <= vector_count + 1'b1;
                            if (vector_count == 2) begin
                                sub_op_done <= 1'b1;
                                vector_count <= 2'b0;
                            end
                        end
                    endcase
                end
                
                default: begin
                    sub_op_done <= 1'b0;
                    vector_count <= 2'b0;
                end
            endcase
        end
    end
    
    // Vector normalize control
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            norm_data_valid <= 1'b0;
            norm_read_done <= 1'b0;
        end else begin
            norm_data_valid <= 1'b0;
            norm_read_done <= 1'b0;
            
            case (current_state)
                CALC_Z_NORM: begin
                    if (norm_ready && !norm_data_valid) begin
                        norm_x_in <= z_temp[0];
                        norm_y_in <= z_temp[1];
                        norm_z_in <= z_temp[2];
                        norm_data_valid <= 1'b1;
                    end
                    if (norm_calc_done) begin
                        z_vec[0] <= norm_x_out;
                        z_vec[1] <= norm_y_out;
                        z_vec[2] <= norm_z_out;
                        norm_read_done <= 1'b1;
                    end
                end
                
                CALC_X_NORM: begin
                    if (norm_ready && !norm_data_valid) begin
                        norm_x_in <= x_temp[0];
                        norm_y_in <= x_temp[1];
                        norm_z_in <= x_temp[2];
                        norm_data_valid <= 1'b1;
                    end
                    if (norm_calc_done) begin
                        x_vec[0] <= norm_x_out;
                        x_vec[1] <= norm_y_out;
                        x_vec[2] <= norm_z_out;
                        norm_read_done <= 1'b1;
                    end
                end
            endcase
        end
    end
    
    // Cross product control (stream interface)
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            cross_data_valid <= 1'b0;
            cross_read_done <= 1'b0;
            stream_count <= 5'b0;
        end else begin
            cross_data_valid <= 1'b0;
            cross_read_done <= 1'b0;
            
            case (current_state)
                CALC_X_CROSS: begin
                    if (cross_ready && stream_count < 6) begin
                        cross_data_valid <= 1'b1;
                        // Stream: up[0], up[1], up[2], z_vec[0], z_vec[1], z_vec[2]
                        case (stream_count)
                            5'd0: cross_data <= up[0];
                            5'd1: cross_data <= up[1];
                            5'd2: cross_data <= up[2];
                            5'd3: cross_data <= z_vec[0];
                            5'd4: cross_data <= z_vec[1];
                            5'd5: cross_data <= z_vec[2];
                        endcase
                        stream_count <= stream_count + 1'b1;
                    end
                    if (cross_calc_done && stream_count < 3) begin
                        x_temp[stream_count] <= cross_result;
                        stream_count <= stream_count + 1'b1;
                        if (stream_count == 2) begin
                            cross_read_done <= 1'b1;
                            stream_count <= 5'b0;
                        end
                    end
                end
                
                CALC_Y_CROSS: begin
                    if (cross_ready && stream_count < 6) begin
                        cross_data_valid <= 1'b1;
                        // Stream: z_vec[0], z_vec[1], z_vec[2], x_vec[0], x_vec[1], x_vec[2]
                        case (stream_count)
                            5'd0: cross_data <= z_vec[0];
                            5'd1: cross_data <= z_vec[1];
                            5'd2: cross_data <= z_vec[2];
                            5'd3: cross_data <= x_vec[0];
                            5'd4: cross_data <= x_vec[1];
                            5'd5: cross_data <= x_vec[2];
                        endcase
                        stream_count <= stream_count + 1'b1;
                    end
                    if (cross_calc_done && stream_count < 3) begin
                        y_vec[stream_count] <= cross_result;
                        stream_count <= stream_count + 1'b1;
                        if (stream_count == 2) begin
                            cross_read_done <= 1'b1;
                            stream_count <= 5'b0;
                        end
                    end
                end
                
                default: begin
                    stream_count <= 5'b0;
                end
            endcase
        end
    end
    
    // Matrix construction logic
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 16; i++) begin
                minv_matrix[i] <= 32'b0;
                tr_matrix[i] <= 32'b0;
                projection_matrix[i] <= 32'b0;
                viewport_matrix[i] <= 32'b0;
            end
        end else begin
            case (current_state)
                BUILD_MINV: begin
                    // Minv = {{x.x,x.y,x.z,0}, {y.x,y.y,y.z,0}, {z.x,z.y,z.z,0}, {0,0,0,1}}
                    minv_matrix[0] <= x_vec[0];  minv_matrix[1] <= x_vec[1];  minv_matrix[2] <= x_vec[2];  minv_matrix[3] <= 32'h00000000;
                    minv_matrix[4] <= y_vec[0];  minv_matrix[5] <= y_vec[1];  minv_matrix[6] <= y_vec[2];  minv_matrix[7] <= 32'h00000000;  
                    minv_matrix[8] <= z_vec[0];  minv_matrix[9] <= z_vec[1];  minv_matrix[10] <= z_vec[2]; minv_matrix[11] <= 32'h00000000;
                    minv_matrix[12] <= 32'h00000000; minv_matrix[13] <= 32'h00000000; minv_matrix[14] <= 32'h00000000; minv_matrix[15] <= 32'h3F800000; // 1.0f
                end
                
                BUILD_TR: begin
                    // Tr = {{1,0,0,-eye.x}, {0,1,0,-eye.y}, {0,0,1,-eye.z}, {0,0,0,1}}
                    tr_matrix[0] <= 32'h3F800000;  tr_matrix[1] <= 32'h00000000;  tr_matrix[2] <= 32'h00000000;  tr_matrix[3] <= {~eye[0][31], eye[0][30:0]};
                    tr_matrix[4] <= 32'h00000000;  tr_matrix[5] <= 32'h3F800000;  tr_matrix[6] <= 32'h00000000;  tr_matrix[7] <= {~eye[1][31], eye[1][30:0]};
                    tr_matrix[8] <= 32'h00000000;  tr_matrix[9] <= 32'h00000000;  tr_matrix[10] <= 32'h3F800000; tr_matrix[11] <= {~eye[2][31], eye[2][30:0]};
                    tr_matrix[12] <= 32'h00000000; tr_matrix[13] <= 32'h00000000; tr_matrix[14] <= 32'h00000000; tr_matrix[15] <= 32'h3F800000;
                end
                
                CALC_PROJECTION: begin
                    // Projection calculation handled by sub-FSM
                    if (proj_current_state == PROJ_BUILD) begin
                        // Projection = {{1,0,0,0}, {0,-1,0,0}, {0,0,1,0}, {0,0,-1/f,0}}
                        projection_matrix[0] <= 32'h3F800000;  projection_matrix[1] <= 32'h00000000;  projection_matrix[2] <= 32'h00000000;  projection_matrix[3] <= 32'h00000000;
                        projection_matrix[4] <= 32'h00000000;  projection_matrix[5] <= 32'hBF800000;  projection_matrix[6] <= 32'h00000000;  projection_matrix[7] <= 32'h00000000; // -1.0f
                        projection_matrix[8] <= 32'h00000000;  projection_matrix[9] <= 32'h00000000;  projection_matrix[10] <= 32'h3F800000; projection_matrix[11] <= 32'h00000000;
                        projection_matrix[12] <= 32'h00000000; projection_matrix[13] <= 32'h00000000; projection_matrix[14] <= neg_one_div_f; projection_matrix[15] <= 32'h00000000; // -1/f
                    end
                end
                
                CALC_VIEWPORT: begin
                    // Viewport calculation handled by sub-FSM
                    if (vp_current_state == VP_BUILD_MATRIX) begin
                        // viewport(width/8, height/8, width*3/4, height*3/4)
                        // Viewport = {{w*3/8, 0, 0, w/8+w*3/8}, {0, h*3/8, 0, h/8+h*3/8}, {0,0,1,0}, {0,0,0,1}}
                        
                        viewport_matrix[0] <= w_3div4;        // w * 3/4 for scaling
                        viewport_matrix[1] <= 32'h00000000;
                        viewport_matrix[2] <= 32'h00000000;  
                        viewport_matrix[3] <= w_sum;          // w/8 + w*3/4 for translation (computed)
                        
                        viewport_matrix[4] <= 32'h00000000;
                        viewport_matrix[5] <= h_3div4;        // h * 3/4 for scaling
                        viewport_matrix[6] <= 32'h00000000;
                        viewport_matrix[7] <= h_sum;          // h/8 + h*3/4 for translation (computed)
                        
                        viewport_matrix[8] <= 32'h00000000;
                        viewport_matrix[9] <= 32'h00000000;
                        viewport_matrix[10] <= 32'h3F800000; // 1.0f
                        viewport_matrix[11] <= 32'h00000000;
                        
                        viewport_matrix[12] <= 32'h00000000;
                        viewport_matrix[13] <= 32'h00000000;
                        viewport_matrix[14] <= 32'h00000000;
                        viewport_matrix[15] <= 32'h3F800000; // 1.0f
                    end
                end
            endcase
        end
    end
    
    // Matrix multiplication control (stream interface)
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            mat_mult_data_valid <= 1'b0;
            mat_mult_read_done <= 1'b0;
            matrix_count <= 5'b0;
        end else begin
            mat_mult_data_valid <= 1'b0;
            mat_mult_read_done <= 1'b0;
            
            case (current_state)
                MULT_MODELVIEW: begin
                    if (mat_mult_ready && matrix_count < 32) begin
                        mat_mult_data_valid <= 1'b1;
                        // Stream Minv matrix first (16 elements), then Tr matrix (16 elements)
                        if (matrix_count < 16) begin
                            mat_mult_data <= minv_matrix[matrix_count];
                        end else begin
                            mat_mult_data <= tr_matrix[matrix_count - 16];
                        end
                        matrix_count <= matrix_count + 1'b1;
                    end
                    if (mat_mult_calc_done && matrix_count < 16) begin
                        modelview_matrix[matrix_count] <= mat_mult_result;
                        matrix_count <= matrix_count + 1'b1;
                        if (matrix_count == 15) begin
                            mat_mult_read_done <= 1'b1;
                            matrix_count <= 5'b0;
                        end
                    end
                end
                
                MULT_COMBINED: begin
                    if (mat_mult_ready && matrix_count < 32) begin
                        mat_mult_data_valid <= 1'b1;
                        // Stream ModelView matrix first, then Projection matrix
                        if (matrix_count < 16) begin
                            mat_mult_data <= modelview_matrix[matrix_count];
                        end else begin
                            mat_mult_data <= projection_matrix[matrix_count - 16];
                        end
                        matrix_count <= matrix_count + 1'b1;
                    end
                    if (mat_mult_calc_done && matrix_count < 16) begin
                        combined_matrix[matrix_count] <= mat_mult_result;
                        matrix_count <= matrix_count + 1'b1;
                        if (matrix_count == 15) begin
                            mat_mult_read_done <= 1'b1;
                            matrix_count <= 5'b0;
                        end
                    end
                end
                
                MULT_LIGHT: begin
                    if (mat_mult_ready && matrix_count < 20) begin
                        mat_mult_data_valid <= 1'b1;
                        // Stream ModelView matrix (16 elements), then light vector (4 elements, last one is 0)
                        if (matrix_count < 16) begin
                            mat_mult_data <= modelview_matrix[matrix_count];
                        end else if (matrix_count < 19) begin
                            mat_mult_data <= light[matrix_count - 16];
                        end else begin
                            mat_mult_data <= 32'h00000000; // w component = 0
                        end
                        matrix_count <= matrix_count + 1'b1;
                    end
                    if (mat_mult_calc_done && matrix_count < 3) begin
                        light_view[matrix_count] <= mat_mult_result;
                        matrix_count <= matrix_count + 1'b1;
                        if (matrix_count == 2) begin
                            mat_mult_read_done <= 1'b1;
                            matrix_count <= 5'b0;
                        end
                    end
                end
                
                default: begin
                    matrix_count <= 5'b0;
                end
            endcase
        end
    end
    
    // Viewport calculation FSM - optimized with parallel operations
    typedef enum logic [2:0] {
        VP_IDLE           = 3'd0,
        VP_CALC_PARALLEL1 = 3'd1,  // w/8 and h/8 parallel
        VP_CALC_PARALLEL2 = 3'd2,  // w*3/4 and h*3/4 parallel
        VP_ADD_PARALLEL   = 3'd3,  // w/8+w*3/4 and h/8+h*3/4 parallel
        VP_BUILD_MATRIX   = 3'd4
    } viewport_state_t;
    
    viewport_state_t vp_current_state, vp_next_state;
    logic [31:0] w_div_8, h_div_8, w_3div4, h_3div4;
    logic [31:0] w_sum, h_sum;  // Final sums for viewport matrix
    
    // Projection calculation FSM  
    typedef enum logic [1:0] {
        PROJ_IDLE     = 2'd0,
        PROJ_CALC_DIV = 2'd1,
        PROJ_BUILD    = 2'd2
    } proj_state_t;
    
    proj_state_t proj_current_state, proj_next_state;
    logic [31:0] neg_one_div_f;  // -1/f result
    
    // Viewport calculation sub-FSM
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            vp_current_state <= VP_IDLE;
        end else begin
            vp_current_state <= vp_next_state;
        end
    end
    
    // Projection calculation sub-FSM
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            proj_current_state <= PROJ_IDLE;
        end else begin
            proj_current_state <= proj_next_state;
        end
    end
    
    always_comb begin
        vp_next_state = vp_current_state;
        
        case (vp_current_state)
            VP_IDLE: begin
                if (current_state == CALC_VIEWPORT) begin
                    vp_next_state = VP_CALC_PARALLEL1;
                end
            end
            VP_CALC_PARALLEL1: begin
                if (mul1_output_z_stb && mul2_output_z_stb) begin
                    vp_next_state = VP_CALC_PARALLEL2;
                end
            end
            VP_CALC_PARALLEL2: begin
                if (mul1_output_z_stb && mul2_output_z_stb) begin
                    vp_next_state = VP_ADD_PARALLEL;
                end
            end
            VP_ADD_PARALLEL: begin
                if (add1_output_z_stb && add2_output_z_stb) begin
                    vp_next_state = VP_BUILD_MATRIX;
                end
            end
            VP_BUILD_MATRIX: begin
                vp_next_state = VP_IDLE;
            end
        endcase
    end
    
    always_comb begin
        proj_next_state = proj_current_state;
        
        case (proj_current_state)
            PROJ_IDLE: begin
                if (current_state == CALC_PROJECTION) begin
                    proj_next_state = PROJ_CALC_DIV;
                end
            end
            PROJ_CALC_DIV: begin
                if (div1_output_z_stb) begin
                    proj_next_state = PROJ_BUILD;
                end
            end
            PROJ_BUILD: begin
                proj_next_state = PROJ_IDLE;
            end
        endcase
    end
    typedef enum logic [2:0] {
        DIST_IDLE     = 3'd0,
        DIST_MULT_PARALLEL = 3'd1,  // x² and y² parallel
        DIST_MULT_Z   = 3'd2,       // z²
        DIST_ADD_PARALLEL = 3'd3,   // (x²+y²) and z² parallel prep
        DIST_SQRT     = 3'd4
    } dist_state_t;
    
    dist_state_t dist_current_state, dist_next_state;
    logic [31:0] x_squared, y_squared, z_squared;
    logic [31:0] xy_sum, xyz_sum;
    
    // Distance calculation sub-FSM
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            dist_current_state <= DIST_IDLE;
        end else begin
            dist_current_state <= dist_next_state;
        end
    end
    
    always_comb begin
        dist_next_state = dist_current_state;
        
        case (dist_current_state)
            DIST_IDLE: begin
                if (current_state == CALC_EYE_CENTER_DIST) begin
                    dist_next_state = DIST_MULT_PARALLEL;
                end
            end
            DIST_MULT_PARALLEL: begin
                if (mul1_output_z_stb && mul2_output_z_stb) begin // Both parallel mults done
                    dist_next_state = DIST_MULT_Z;
                end
            end
            DIST_MULT_Z: begin
                if (mul1_output_z_stb) begin
                    dist_next_state = DIST_ADD_PARALLEL;
                end
            end
            DIST_ADD_PARALLEL: begin
                if (add1_output_z_stb) begin // x²+y²+z² done
                    dist_next_state = DIST_SQRT;
                end
            end
            DIST_SQRT: begin
                if (sqrt_calc_done) begin
                    dist_next_state = DIST_IDLE;
                end
            end
        endcase
    end
    
    // Distance calculation using parallel arithmetic units
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            sqrt_data_valid <= 1'b0;
            sqrt_read_done <= 1'b0;
            eye_center_dist <= 32'h3F800000; // Default 1.0f
            x_squared <= 32'b0;
            y_squared <= 32'b0; 
            z_squared <= 32'b0;
            xy_sum <= 32'b0;
            xyz_sum <= 32'b0;
            
            // Multiplier 1 controls
            mul1_input_a <= 32'b0;
            mul1_input_b <= 32'b0;
            mul1_input_a_stb <= 1'b0;
            mul1_input_b_stb <= 1'b0;
            mul1_output_z_ack <= 1'b0;
            
            // Multiplier 2 controls
            mul2_input_a <= 32'b0;
            mul2_input_b <= 32'b0;
            mul2_input_a_stb <= 1'b0;
            mul2_input_b_stb <= 1'b0;
            mul2_output_z_ack <= 1'b0;
            
            // Adder 1 controls (for final sum)
            add1_input_a <= 32'b0;
            add1_input_b <= 32'b0;
            add1_input_a_stb <= 1'b0;
            add1_input_b_stb <= 1'b0;
            add1_output_z_ack <= 1'b0;
        end else begin
            // Default values
            sqrt_data_valid <= 1'b0;
            sqrt_read_done <= 1'b0;
            mul1_input_a_stb <= 1'b0;
            mul1_input_b_stb <= 1'b0;
            mul1_output_z_ack <= 1'b0;
            mul2_input_a_stb <= 1'b0;
            mul2_input_b_stb <= 1'b0;
            mul2_output_z_ack <= 1'b0;
            add1_output_z_ack <= 1'b0;
            
            case (dist_current_state)
                DIST_MULT_PARALLEL: begin
                    // Calculate z_temp[0]² and z_temp[1]² in parallel
                    if (!mul1_input_a_stb && !mul1_input_b_stb && !mul2_input_a_stb && !mul2_input_b_stb) begin
                        // Start both multiplications
                        mul1_input_a <= z_temp[0];
                        mul1_input_b <= z_temp[0];
                        mul1_input_a_stb <= 1'b1;
                        mul1_input_b_stb <= 1'b1;
                        
                        mul2_input_a <= z_temp[1];
                        mul2_input_b <= z_temp[1];
                        mul2_input_a_stb <= 1'b1;
                        mul2_input_b_stb <= 1'b1;
                    end else if (mul1_input_a_ack && mul1_input_b_ack) begin
                        mul1_input_a_stb <= 1'b0;
                        mul1_input_b_stb <= 1'b0;
                    end else if (mul2_input_a_ack && mul2_input_b_ack) begin
                        mul2_input_a_stb <= 1'b0;
                        mul2_input_b_stb <= 1'b0;
                    end else if (mul1_output_z_stb && mul2_output_z_stb) begin
                        x_squared <= mul1_output_z;
                        y_squared <= mul2_output_z;
                        mul1_output_z_ack <= 1'b1;
                        mul2_output_z_ack <= 1'b1;
                    end
                end
                
                DIST_MULT_Z: begin
                    // Calculate z_temp[2]²
                    if (!mul1_input_a_stb && !mul1_input_b_stb) begin
                        mul1_input_a <= z_temp[2];
                        mul1_input_b <= z_temp[2];
                        mul1_input_a_stb <= 1'b1;
                        mul1_input_b_stb <= 1'b1;
                    end else if (mul1_input_a_ack && mul1_input_b_ack) begin
                        mul1_input_a_stb <= 1'b0;
                        mul1_input_b_stb <= 1'b0;
                    end else if (mul1_output_z_stb) begin
                        z_squared <= mul1_output_z;
                        mul1_output_z_ack <= 1'b1;
                    end
                end
                
                DIST_ADD_PARALLEL: begin
                    // First add x² + y², then add z²
                    if (!add1_input_a_stb && !add1_input_b_stb) begin
                        add1_input_a <= x_squared;
                        add1_input_b <= y_squared;
                        add1_input_a_stb <= 1'b1;
                        add1_input_b_stb <= 1'b1;
                    end else if (add1_input_a_ack && add1_input_b_ack) begin
                        add1_input_a_stb <= 1'b0;
                        add1_input_b_stb <= 1'b0;
                    end else if (add1_output_z_stb) begin
                        xy_sum <= add1_output_z;
                        add1_output_z_ack <= 1'b1;
                        
                        // Immediately start second addition: (x²+y²) + z²
                        add1_input_a <= add1_output_z;
                        add1_input_b <= z_squared;
                        add1_input_a_stb <= 1'b1;
                        add1_input_b_stb <= 1'b1;
                    end else if (add1_output_z_stb && xy_sum != 32'b0) begin // Second addition done
                        xyz_sum <= add1_output_z;
                        add1_output_z_ack <= 1'b1;
                    end
                end
                
                DIST_SQRT: begin
                    if (sqrt_ready && !sqrt_data_valid) begin
                        sqrt_data_in <= xyz_sum;
                        sqrt_data_valid <= 1'b1;
                    end
                    if (sqrt_calc_done) begin
                        eye_center_dist <= sqrt_result_out;
                        sqrt_read_done <= 1'b1;
                    end
                end
            endcase
        end
    endb0;
            mul_input_a_stb <= 1'b0;
            mul_input_b_stb <= 1'b0;
            mul_output_z_ack <= 1'b0;
        end else begin
            // Default values
            sqrt_data_valid <= 1'b0;
            sqrt_read_done <= 1'b0;
            mul_input_a_stb <= 1'b0;
            mul_input_b_stb <= 1'b0;
            mul_output_z_ack <= 1'b0;
            add_output_z_ack <= 1'b0;
            
            case (dist_current_state)
                DIST_MULT_X: begin
                    // Calculate z_temp[0]^2
                    if (!mul_input_a_stb && !mul_input_b_stb) begin
                        mul_input_a <= z_temp[0];
                        mul_input_a_stb <= 1'b1;
                    end else if (mul_input_a_ack && !mul_input_b_stb) begin
                        mul_input_a_stb <= 1'b0;
                        mul_input_b <= z_temp[0];
                        mul_input_b_stb <= 1'b1;
                    end else if (mul_input_b_ack) begin
                        mul_input_b_stb <= 1'b0;
                    end else if (mul_output_z_stb) begin
                        x_squared <= mul_output_z;
                        mul_output_z_ack <= 1'b1;
                    end
                end
                
                DIST_MULT_Y: begin
                    // Calculate z_temp[1]^2
                    if (!mul_input_a_stb && !mul_input_b_stb) begin
                        mul_input_a <= z_temp[1];
                        mul_input_a_stb <= 1'b1;
                    end else if (mul_input_a_ack && !mul_input_b_stb) begin
                        mul_input_a_stb <= 1'b0;
                        mul_input_b <= z_temp[1];
                        mul_input_b_stb <= 1'b1;
                    end else if (mul_input_b_ack) begin
                        mul_input_b_stb <= 1'b0;
                    end else if (mul_output_z_stb) begin
                        y_squared <= mul_output_z;
                        mul_output_z_ack <= 1'b1;
                    end
                end
                
                DIST_MULT_Z: begin
                    // Calculate z_temp[2]^2
                    if (!mul_input_a_stb && !mul_input_b_stb) begin
                        mul_input_a <= z_temp[2];
                        mul_input_a_stb <= 1'b1;
                    end else if (mul_input_a_ack && !mul_input_b_stb) begin
                        mul_input_a_stb <= 1'b0;
                        mul_input_b <= z_temp[2];
                        mul_input_b_stb <= 1'b1;
                    end else if (mul_input_b_ack) begin
                        mul_input_b_stb <= 1'b0;
                    end else if (mul_output_z_stb) begin
                        z_squared <= mul_output_z;
                        mul_output_z_ack <= 1'b1;
                    end
                end
                
                DIST_ADD_XY: begin
                    // Calculate x_squared + y_squared
                    if (!add_input_a_stb && !add_input_b_stb) begin
                        add_input_a <= x_squared;
                        add_input_a_stb <= 1'b1;
                    end else if (add_input_a_ack && !add_input_b_stb) begin
                        add_input_a_stb <= 1'b0;
                        add_input_b <= y_squared;
                        add_input_b_stb <= 1'b1;
                    end else if (add_input_b_ack) begin
                        add_input_b_stb <= 1'b0;
                    end else if (add_output_z_stb) begin
                        xy_sum <= add_output_z;
                        add_output_z_ack <= 1'b1;
                    end
                end
                
                DIST_ADD_Z: begin
                    // Calculate xy_sum + z_squared
                    if (!add_input_a_stb && !add_input_b_stb) begin
                        add_input_a <= xy_sum;
                        add_input_a_stb <= 1'b1;
                    end else if (add_input_a_ack && !add_input_b_stb) begin
                        add_input_a_stb <= 1'b0;
                        add_input_b <= z_squared;
                        add_input_b_stb <= 1'b1;
                    end else if (add_input_b_ack) begin
                        add_input_b_stb <= 1'b0;
                    end else if (add_output_z_stb) begin
                        xyz_sum <= add_output_z;
                        add_output_z_ack <= 1'b1;
                    end
                end
                
                DIST_SQRT: begin
                    if (sqrt_ready && !sqrt_data_valid) begin
                        sqrt_data_in <= xyz_sum;
                        sqrt_data_valid <= 1'b1;
                    end
                    if (sqrt_calc_done) begin
                        eye_center_dist <= sqrt_result_out;
                        sqrt_read_done <= 1'b1;
                    end
                end
            endcase
        end
    end
    
    // Matrix serving logic
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            serving_core <= 7'b0;
            serving_opcode <= 3'b0;
            matrix_element_count <= 5'b0;
        end else begin
            case (current_state)
                SERVE_REQUEST: begin
                    serving_core <= requesting_core;
                    serving_opcode <= requesting_opcode;
                    matrix_element_count <= 5'b0;
                end
                
                SEND_MATRIX: begin
                    matrix_element_count <= matrix_element_count + 1'b1;
                end
                
                WAIT_ACK: begin
                    if (matrix_read_done[serving_core]) begin
                        matrix_element_count <= 5'b0;
                    end
                end
            endcase
        end
    end
    
    // Output control signals
    assign lookat_ready = (current_state == RECEIVE_DATA);
    assign calc_matrix_done = (current_state == MATRICES_READY);
    
    // Matrix serving output
    always_comb begin
        matrix_data = 32'b0;
        target_core_id = 7'b0;
        matrix_valid = 1'b0;
        
        if (current_state == SEND_MATRIX) begin
            target_core_id = serving_core;
            matrix_valid = 1'b1;
            
            case (serving_opcode)
                MATRIX_MODELVIEW: matrix_data = modelview_matrix[matrix_element_count];
                MATRIX_PROJECTION: matrix_data = projection_matrix[matrix_element_count];
                MATRIX_VIEWPORT: matrix_data = viewport_matrix[matrix_element_count];
                MATRIX_COMBINED: matrix_data = combined_matrix[matrix_element_count];
                MATRIX_LIGHT: begin
                    if (matrix_element_count < 3) begin
                        matrix_data = light_view[matrix_element_count];
                    end
                end
                default: matrix_data = 32'b0;
            endcase
        end
    end

endmodule