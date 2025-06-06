//module FRAGMENT (
//    input logic clk,
//    input logic rst_n,
//    
//    //interface fifo_fragdepth: -1, uniform_l, varying_nrm, varying_uv, view_tri, pixel_x, pixel_y, bar, pixel_x, pixel_y, bar,... -1
//    output logic FF_readrequest,
//    input logic FF_empty,
//    input logic [31:0] FF_data,
//    
//    //interface small arbiter TEXTURE
//    output logic request,
//    output logic [23:0] addr_tex,
//    input logic texture_valid,
//    input logic [31:0] tex_data,
//    output logic read_done,
//    
//    ////interface small arbiter framebuffer
//    output logic request,
//    output logic [23:0] addr_frame,
//    input logic frame_valid,
//    output logic [31:0] color,
//    input logic ,
//    
//    // Base addresses and texture dimensions
//    input logic [31:0] addr_normalmap,    // Base address of normal map
//	 input logic [31:0] addr_specmap,
//	 input logic [31:0] addr_
//    input logic [31:0] addr_framebuffer,  // Frame buffer base address  
//    input logic [31:0] width_tex,         // Texture width
//    input logic [31:0] height_tex         // Texture height
//);
//
//    // State machine
//    typedef enum logic [4:0] {
//        IDLE,
//        READ_MARKER1,           // Đọc -1 đầu
//        READ_UNIFORM_L,         // Đọc uniform_l
//        READ_VARYING_NRM,       // Đọc varying_nrm (9 values: 3x3 matrix)
//        READ_VARYING_UV,        // Đọc varying_uv (6 values: 2x3 matrix)
//        READ_VIEW_TRI,          // Đọc view_tri (9 values: 3x3 matrix)
//        READ_BAR,               // Đọc barycentric coordinates (3 values)
//        CALC_BN,                // Tính barycentric normal
//        WAIT_BN,                // Chờ BN calculation
//        CALC_UV,                // Tính UV interpolation
//        WAIT_UV,                // Chờ UV calculation
//        CALC_TANGENT,           // Tính tangent space matrix
//        WAIT_TANGENT,           // Chờ tangent calculation
//        CONVERT_UV,             // Convert UV to integer coordinates
//        WAIT_CONVERT_UV,        // Chờ UV conversion
//        SAMPLE_NORMAL,          // Sample normal map
//        WAIT_SAMPLE_NORMAL,     // Chờ normal sampling
//        TRANSFORM_NORMAL,       // Transform normal to tangent space
//        WAIT_TRANSFORM_NORMAL,  // Chờ normal transformation
//        CALC_LIGHTING,          // Calculate diffuse and specular
//        WAIT_LIGHTING,          // Chờ lighting calculation
//        READ_MARKER2,           // Đọc -1 cuối
//        PROCESS_COMPLETE        // Hoàn thành xử lý triangle
//    } state_t;
//    
//    state_t current_state;
//    
//    // Data storage
//    logic [31:0] uniform_l;
//    logic [31:0] varying_nrm [0:8];     // 3x3 matrix (row major)
//    logic [31:0] varying_uv [0:5];      // 2x3 matrix (u0,v0,u1,v1,u2,v2)
//    logic [31:0] view_tri [0:8];        // 3x3 matrix
//    logic [31:0] bar [0:2];             // barycentric coordinates
//    
//    // Counters
//    logic [3:0] read_counter;
//    
//    // BN calculation signals (3x3 * 3x1)
//    logic bn_ready, bn_data_valid, bn_calc_done, bn_read_done;
//    logic [31:0] bn_data_in, bn_result_out;
//    logic [31:0] bn_x_interp, bn_y_interp, bn_z_interp;  // interpolated results
//    logic [31:0] bn_x, bn_y, bn_z;                       // normalized results
//    
//    // UV calculation signals (2x3 * 3x1)
//    logic uv_ready, uv_data_valid, uv_calc_done, uv_read_done;
//    logic [31:0] uv_data_in, uv_result_out;
//    logic [31:0] uv_u, uv_v;
//    
//    // Tangent space calculation signals
//    logic tangent_ready, tangent_data_valid, tangent_calc_done, tangent_read_done;
//    logic [31:0] tangent_matrix_B [0:8];  // 3x3 tangent space matrix
//    
//    // UV to integer conversion signals
//    logic f2i_u_stb, f2i_v_stb;
//    logic f2i_u_ack, f2i_v_ack;
//    logic [31:0] f2i_u_result, f2i_v_result;
//    logic f2i_u_z_stb, f2i_v_z_stb;
//    logic f2i_u_z_ack, f2i_v_z_ack;
//    logic [31:0] tex_u_int, tex_v_int;
//    
//    // Normal map sampling signals
//    logic [31:0] normal_tex_addr;
//    logic [31:0] normal_tex_data;
//    logic normal_request_done;
//    
//    // Normal transformation signals  
//    logic [31:0] tex_normal [0:2];       // Normal from texture (R,G,B)
//    logic [31:0] world_normal [0:2];     // Transformed normal
//    
//    // Lighting calculation signals
//    logic [31:0] diffuse_intensity;
//    logic [31:0] specular_intensity;
//    
//    // BN calculation control
//    logic [3:0] bn_send_counter;
//    logic [1:0] bn_receive_counter;
//    logic bn_sending_matrix, bn_sending_vector, bn_receiving_result;
//    
//    // UV calculation control
//    logic [2:0] uv_send_counter;
//    logic [0:0] uv_receive_counter;
//    logic uv_sending_matrix, uv_sending_vector, uv_receiving_result;
//    
//    // Vector normalize for BN
//    logic norm_ready, norm_data_valid, norm_calc_done, norm_read_done;
//    logic [31:0] norm_x_in, norm_y_in, norm_z_in;
//    logic [31:0] norm_x_out, norm_y_out, norm_z_out;
//    
//    // Matrix multiplication wrapper for BN (3x3 * 3x1)
//    mul3x3_3x1_wrapper bn_calc (
//        .iClk(clk),
//        .iRstn(rst_n),
//        .ready(bn_ready),
//        .data_valid(bn_data_valid),
//        .data(bn_data_in),
//        .calc_done(bn_calc_done),
//        .result(bn_result_out),
//        .read_done(bn_read_done)
//    );
//    
//    // Matrix multiplication wrapper for UV (2x3 * 3x1)
//    mul2x3_3x1_wrapper uv_calc (
//        .iClk(clk),
//        .iRstn(rst_n),
//        .ready(uv_ready),
//        .data_valid(uv_data_valid),
//        .data(uv_data_in),
//        .calc_done(uv_calc_done),
//        .result(uv_result_out),
//        .read_done(uv_read_done)
//    );
//    
//    // Vector normalize for BN
//    vector_normalize_3d bn_normalize (
//        .clk(clk),
//        .rst_n(rst_n),
//        .ready(norm_ready),
//        .data_valid(norm_data_valid),
//        .calc_done(norm_calc_done),
//        .read_done(norm_read_done),
//        .x_in(norm_x_in),
//        .y_in(norm_y_in),
//        .z_in(norm_z_in),
//        .x_out(norm_x_out),
//        .y_out(norm_y_out),
//        .z_out(norm_z_out)
//    );
//    
//    // Tangent space calculation
//    TANGENT_SPACE_CALC tangent_calc (
//        .clk(clk),
//        .rst_n(rst_n),
//        .ready(tangent_ready),
//        .data_valid(tangent_data_valid),
//        .calc_done(tangent_calc_done),
//        .read_done(tangent_read_done),
//        .view_tri(view_tri),
//        .varying_uv(varying_uv),
//        .bn_x(bn_x),
//        .bn_y(bn_y),
//        .bn_z(bn_z),
//        .matrix_B(tangent_matrix_B)
//    );
//    
//    // Float to Integer converters for UV coordinates
//    float_to_int f2i_u (
//        .clk(clk),
//        .rst(~rst_n),
//        .input_a(uv_u),
//        .input_a_stb(f2i_u_stb),
//        .input_a_ack(f2i_u_ack),
//        .output_z(f2i_u_result),
//        .output_z_stb(f2i_u_z_stb),
//        .output_z_ack(f2i_u_z_ack)
//    );
//    
//    float_to_int f2i_v (
//        .clk(clk),
//        .rst(~rst_n),
//        .input_a(uv_v),
//        .input_a_stb(f2i_v_stb),
//        .input_a_ack(f2i_v_ack),
//        .output_z(f2i_v_result),
//        .output_z_stb(f2i_v_z_stb),
//        .output_z_ack(f2i_v_z_ack)
//    );
//    
//    // Next state logic
//    state_t next_state;
//    
//    // State transition logic (combinational)
//    always_comb begin
//        next_state = current_state;
//        
//        case (current_state)
//            IDLE: begin
//                if (!FF_empty) begin
//                    next_state = READ_MARKER1;
//                end
//            end
//            
//            READ_MARKER1: begin
//                if (FF_readrequest && !FF_empty) begin
//                    if (FF_data == 32'hFFFFFFFF) begin // -1 marker
//                        next_state = READ_UNIFORM_L;
//                    end else begin
//                        next_state = IDLE; // Invalid data, restart
//                    end
//                end
//            end
//            
//            READ_UNIFORM_L: begin
//                if (!FF_empty) begin
//                    next_state = READ_VARYING_NRM;
//                end
//            end
//            
//            READ_VARYING_NRM: begin
//                if (!FF_empty && FF_readrequest && read_counter == 8) begin
//                    next_state = READ_VARYING_UV;
//                end
//            end
//            
//            READ_VARYING_UV: begin
//                if (!FF_empty && FF_readrequest && read_counter == 5) begin
//                    next_state = READ_VIEW_TRI;
//                end
//            end
//            
//            READ_VIEW_TRI: begin
//                if (!FF_empty && FF_readrequest && read_counter == 8) begin
//                    next_state = READ_BAR;
//                end
//            end
//            
//            READ_BAR: begin
//                if (!FF_empty && FF_readrequest && read_counter == 2) begin
//                    next_state = CALC_BN;
//                end
//            end
//            
//            CALC_BN: begin
//                if (bn_sending_vector && bn_send_counter == 2 && bn_data_valid) begin
//                    next_state = WAIT_BN;
//                end
//            end
//            
//            WAIT_BN: begin
//                if (norm_calc_done) begin
//                    next_state = CALC_UV;
//                end
//            end
//            
//            CALC_UV: begin
//                if (uv_sending_vector && uv_send_counter == 2 && uv_data_valid) begin
//                    next_state = WAIT_UV;
//                end
//            end
//            
//            WAIT_UV: begin
//                if (uv_receiving_result && uv_receive_counter == 1 && uv_calc_done) begin
//                    next_state = CALC_TANGENT;
//                end
//            end
//            
//            CALC_TANGENT: begin
//                if (tangent_data_valid) begin
//                    next_state = WAIT_TANGENT;
//                end
//            end
//            
//            WAIT_TANGENT: begin
//                if (tangent_calc_done) begin
//                    next_state = CONVERT_UV;
//                end
//            end
//            
//            CONVERT_UV: begin
//                if (f2i_u_stb && f2i_v_stb) begin
//                    next_state = WAIT_CONVERT_UV;
//                end
//            end
//            
//            WAIT_CONVERT_UV: begin
//                if (f2i_u_z_stb && f2i_v_z_stb) begin
//                    next_state = SAMPLE_NORMAL;
//                end
//            end
//            
//            SAMPLE_NORMAL: begin
//                if (request) begin
//                    next_state = WAIT_SAMPLE_NORMAL;
//                end
//            end
//            
//            WAIT_SAMPLE_NORMAL: begin
//                if (texture_valid && normal_request_done) begin
//                    next_state = TRANSFORM_NORMAL;
//                end
//            end
//            
//            TRANSFORM_NORMAL: begin
//                next_state = WAIT_TRANSFORM_NORMAL;
//            end
//            
//            WAIT_TRANSFORM_NORMAL: begin
//                next_state = CALC_LIGHTING;
//            end
//            
//            CALC_LIGHTING: begin
//                next_state = WAIT_LIGHTING;
//            end
//            
//            WAIT_LIGHTING: begin
//                next_state = READ_MARKER2;
//            end
//            
//            READ_MARKER2: begin
//                if (!FF_empty) begin
//                    if (FF_data == 32'hFFFFFFFF) begin // -1 marker
//                        next_state = PROCESS_COMPLETE;
//                    end else begin
//                        next_state = IDLE; // Continue to next triangle
//                    end
//                end
//            end
//            
//            PROCESS_COMPLETE: begin
//                next_state = IDLE; // Ready for next triangle
//            end
//        endcase
//    end
//    
//    // State register and sequential logic
//    always_ff @(posedge clk) begin
//        if (!rst_n) begin
//            current_state <= IDLE;
//            FF_readrequest <= 1'b0;
//            read_counter <= 4'b0;
//            
//            // Reset BN signals
//            bn_data_valid <= 1'b0;
//            bn_read_done <= 1'b0;
//            bn_send_counter <= 4'b0;
//            bn_receive_counter <= 2'b0;
//            bn_sending_matrix <= 1'b0;
//            bn_sending_vector <= 1'b0;
//            bn_receiving_result <= 1'b0;
//            
//            // Reset UV signals
//            uv_data_valid <= 1'b0;
//            uv_read_done <= 1'b0;
//            uv_send_counter <= 3'b0;
//            uv_receive_counter <= 1'b0;
//            uv_sending_matrix <= 1'b0;
//            uv_sending_vector <= 1'b0;
//            uv_receiving_result <= 1'b0;
//            
//            // Reset normalize signals
//            norm_data_valid <= 1'b0;
//            norm_read_done <= 1'b0;
//            
//            // Reset tangent signals
//            tangent_data_valid <= 1'b0;
//            tangent_read_done <= 1'b0;
//            
//            // Reset float to int signals
//            f2i_u_stb <= 1'b0;
//            f2i_v_stb <= 1'b0;
//            f2i_u_z_ack <= 1'b0;
//            f2i_v_z_ack <= 1'b0;
//            
//            // Reset texture sampling signals
//            normal_request_done <= 1'b0;
//            
//        end else begin
//            // Update state
//            current_state <= next_state;
//            
//            // Datapath logic based on current state
//            case (current_state)
//                IDLE: begin
//                    if (!FF_empty) begin
//                        FF_readrequest <= 1'b1;
//                    end
//                end
//                
//                READ_MARKER1: begin
//                    if (FF_readrequest && !FF_empty) begin
//                        FF_readrequest <= 1'b0;
//                    end
//                end
//                
//                READ_UNIFORM_L: begin
//                    if (!FF_empty) begin
//                        FF_readrequest <= 1'b1;
//                        uniform_l <= FF_data;
//                        read_counter <= 4'b0;
//                    end
//                end
//                
//                READ_VARYING_NRM: begin
//                    if (!FF_empty && FF_readrequest) begin
//                        varying_nrm[read_counter] <= FF_data;
//                        if (read_counter == 8) begin
//                            FF_readrequest <= 1'b0;
//                            read_counter <= 4'b0;
//                        end else begin
//                            read_counter <= read_counter + 1;
//                        end
//                    end else if (!FF_empty) begin
//                        FF_readrequest <= 1'b1;
//                    end
//                end
//                
//                READ_VARYING_UV: begin
//                    if (!FF_empty && FF_readrequest) begin
//                        varying_uv[read_counter] <= FF_data;
//                        if (read_counter == 5) begin
//                            FF_readrequest <= 1'b0;
//                            read_counter <= 4'b0;
//                        end else begin
//                            read_counter <= read_counter + 1;
//                        end
//                    end else if (!FF_empty) begin
//                        FF_readrequest <= 1'b1;
//                    end
//                end
//                
//                READ_VIEW_TRI: begin
//                    if (!FF_empty && FF_readrequest) begin
//                        view_tri[read_counter] <= FF_data;
//                        if (read_counter == 8) begin
//                            FF_readrequest <= 1'b0;
//                            read_counter <= 4'b0;
//                        end else begin
//                            read_counter <= read_counter + 1;
//                        end
//                    end else if (!FF_empty) begin
//                        FF_readrequest <= 1'b1;
//                    end
//                end
//                
//                READ_BAR: begin
//                    if (!FF_empty && FF_readrequest) begin
//                        bar[read_counter] <= FF_data;
//                        if (read_counter == 2) begin
//                            FF_readrequest <= 1'b0;
//                            // Initialize BN calculation states
//                            bn_send_counter <= 4'b0;
//                            bn_receive_counter <= 2'b0;
//                            bn_sending_matrix <= 1'b1;
//                            bn_sending_vector <= 1'b0;
//                            bn_receiving_result <= 1'b0;
//                        end else begin
//                            read_counter <= read_counter + 1;
//                        end
//                    end else if (!FF_empty) begin
//                        FF_readrequest <= 1'b1;
//                    end
//                end
//                
//                // === BN CALCULATION (3x3 * 3x1) ===
//                CALC_BN: begin
//                    if (bn_ready && !bn_data_valid) begin
//                        if (bn_sending_matrix) begin
//                            // Send varying_nrm matrix (transposed)
//                            case (bn_send_counter)
//                                0: bn_data_in <= varying_nrm[0]; // nrm0_x
//                                1: bn_data_in <= varying_nrm[3]; // nrm1_x  
//                                2: bn_data_in <= varying_nrm[6]; // nrm2_x
//                                3: bn_data_in <= varying_nrm[1]; // nrm0_y
//                                4: bn_data_in <= varying_nrm[4]; // nrm1_y
//                                5: bn_data_in <= varying_nrm[7]; // nrm2_y
//                                6: bn_data_in <= varying_nrm[2]; // nrm0_z
//                                7: bn_data_in <= varying_nrm[5]; // nrm1_z
//                                8: bn_data_in <= varying_nrm[8]; // nrm2_z
//                            endcase
//                            
//                            bn_data_valid <= 1'b1;
//                            bn_send_counter <= bn_send_counter + 1;
//                            
//                            if (bn_send_counter == 8) begin
//                                bn_sending_matrix <= 1'b0;
//                                bn_sending_vector <= 1'b1;
//                                bn_send_counter <= 4'b0;
//                            end
//                            
//                        end else if (bn_sending_vector) begin
//                            // Send barycentric vector
//                            bn_data_in <= bar[bn_send_counter];
//                            bn_data_valid <= 1'b1;
//                            bn_send_counter <= bn_send_counter + 1;
//                        end
//                    end else begin
//                        bn_data_valid <= 1'b0;
//                    end
//                end
//                
//                WAIT_BN: begin
//                    bn_data_valid <= 1'b0;
//                    
//                    if (bn_calc_done && !bn_receiving_result) begin
//                        bn_receiving_result <= 1'b1;
//                        bn_receive_counter <= 2'b0;
//                    end
//                    
//                    if (bn_receiving_result && bn_calc_done) begin
//                        // Store interpolated results
//                        case (bn_receive_counter)
//                            0: bn_x_interp <= bn_result_out;
//                            1: bn_y_interp <= bn_result_out;
//                            2: begin
//                                bn_z_interp <= bn_result_out;
//                                bn_read_done <= 1'b1;
//                            end
//                        endcase
//                        bn_receive_counter <= bn_receive_counter + 1;
//                        
//                        if (bn_receive_counter == 2) begin
//                            bn_receiving_result <= 1'b0;
//                            // Start normalization
//                            norm_x_in <= bn_x_interp;
//                            norm_y_in <= bn_y_interp;
//                            norm_z_in <= bn_z_interp;
//                            if (norm_ready) begin
//                                norm_data_valid <= 1'b1;
//                            end
//                        end
//                    end
//                    
//                    // Wait for normalization
//                    if (norm_calc_done) begin
//                        bn_x <= norm_x_out;
//                        bn_y <= norm_y_out;
//                        bn_z <= norm_z_out;
//                        norm_read_done <= 1'b1;
//                        // Initialize UV calculation states
//                        uv_send_counter <= 3'b0;
//                        uv_receive_counter <= 1'b0;
//                        uv_sending_matrix <= 1'b1;
//                        uv_sending_vector <= 1'b0;
//                        uv_receiving_result <= 1'b0;
//                    end
//                    
//                    // Reset signals
//                    if (bn_read_done) begin
//                        bn_read_done <= 1'b0;
//                        norm_data_valid <= 1'b0;
//                    end
//                    if (norm_read_done) begin
//                        norm_read_done <= 1'b0;
//                    end
//                end
//                
//                // === UV CALCULATION (2x3 * 3x1) ===  
//                CALC_UV: begin
//                    if (uv_ready && !uv_data_valid) begin
//                        if (uv_sending_matrix) begin
//                            // Send varying_uv matrix: [u0 u1 u2; v0 v1 v2]
//                            case (uv_send_counter)
//                                0: uv_data_in <= varying_uv[0]; // u0
//                                1: uv_data_in <= varying_uv[2]; // u1  
//                                2: uv_data_in <= varying_uv[4]; // u2
//                                3: uv_data_in <= varying_uv[1]; // v0
//                                4: uv_data_in <= varying_uv[3]; // v1
//                                5: uv_data_in <= varying_uv[5]; // v2
//                            endcase
//                            
//                            uv_data_valid <= 1'b1;
//                            uv_send_counter <= uv_send_counter + 1;
//                            
//                            if (uv_send_counter == 5) begin
//                                uv_sending_matrix <= 1'b0;
//                                uv_sending_vector <= 1'b1;
//                                uv_send_counter <= 3'b0;
//                            end
//                            
//                        end else if (uv_sending_vector) begin
//                            // Send barycentric vector
//                            uv_data_in <= bar[uv_send_counter];
//                            uv_data_valid <= 1'b1;
//                            uv_send_counter <= uv_send_counter + 1;
//                        end
//                    end else begin
//                        uv_data_valid <= 1'b0;
//                    end
//                end
//                
//                WAIT_UV: begin
//                    uv_data_valid <= 1'b0;
//                    
//                    if (uv_calc_done && !uv_receiving_result) begin
//                        uv_receiving_result <= 1'b1;
//                        uv_receive_counter <= 1'b0;
//                    end
//                    
//                    if (uv_receiving_result && uv_calc_done) begin
//                        // Store UV results
//                        case (uv_receive_counter)
//                            0: uv_u <= uv_result_out;
//                            1: begin
//                                uv_v <= uv_result_out;
//                                uv_read_done <= 1'b1;
//                            end
//                        endcase
//                        uv_receive_counter <= uv_receive_counter + 1;
//                    end
//                    
//                    if (uv_read_done) begin
//                        uv_read_done <= 1'b0;
//                    end
//                end
//                
//                // === TANGENT SPACE CALCULATION ===
//                CALC_TANGENT: begin
//                    if (tangent_ready) begin
//                        tangent_data_valid <= 1'b1;
//                    end
//                end
//                
//                WAIT_TANGENT: begin
//                    tangent_data_valid <= 1'b0;
//                    
//                    if (tangent_calc_done) begin
//                        tangent_read_done <= 1'b1;
//                    end
//                    
//                    if (tangent_read_done) begin
//                        tangent_read_done <= 1'b0;
//                    end
//                end
//                
//                // === UV TO INTEGER CONVERSION ===
//                CONVERT_UV: begin
//                    // Convert UV coordinates to integer pixel coordinates
//                    // tex_u = uv_u * width_tex, tex_v = uv_v * height_tex
//                    f2i_u_stb <= 1'b1;  // Convert U coordinate
//                    f2i_v_stb <= 1'b1;  // Convert V coordinate
//                end
//                
//                WAIT_CONVERT_UV: begin
//                    // Handle U conversion
//                    if (f2i_u_ack && f2i_u_stb) begin
//                        f2i_u_stb <= 1'b0;
//                    end
//                    
//                    if (f2i_u_z_stb) begin
//                        f2i_u_z_ack <= 1'b1;
//                        tex_u_int <= f2i_u_result;
//                    end else begin
//                        f2i_u_z_ack <= 1'b0;
//                    end
//                    
//                    // Handle V conversion
//                    if (f2i_v_ack && f2i_v_stb) begin
//                        f2i_v_stb <= 1'b0;
//                    end
//                    
//                    if (f2i_v_z_stb) begin
//                        f2i_v_z_ack <= 1'b1;
//                        tex_v_int <= f2i_v_result;
//                    end else begin
//                        f2i_v_z_ack <= 1'b0;
//                    end
//                end
//                
//                // === NORMAL MAP SAMPLING ===
//                SAMPLE_NORMAL: begin
//                    // Calculate texture address: addr_normalmap + (tex_v * width_tex + tex_u) * 4
//                    normal_tex_addr <= addr_normalmap + (tex_v_int * width_tex + tex_u_int) * 4;
//                    addr_tex <= normal_tex_addr[23:0];  // Send address to arbiter
//                    request <= 1'b1;                   // Request texture access
//                end
//                
//                WAIT_SAMPLE_NORMAL: begin
//                    if (texture_valid) begin
//                        normal_tex_data <= tex_data;   // Store texture data
//                        normal_request_done <= 1'b1;
//                        request <= 1'b0;
//                        read_done <= 1'b1;
//                        
//                        // Extract RGB components and convert to normal vector
//                        // TGAColor format: [B, G, R, A] in 32-bit word
//                        // Normal = (R,G,B) * 2/255 - (1,1,1)
//                        tex_normal[0] <= {8'h00, tex_data[23:16], 16'h0000}; // R component
//                        tex_normal[1] <= {8'h00, tex_data[15:8],  16'h0000}; // G component  
//                        tex_normal[2] <= {8'h00, tex_data[7:0],   16'h0000}; // B component
//                    end else begin
//                        read_done <= 1'b0;
//                    end
//                    
//                    if (normal_request_done) begin
//                        normal_request_done <= 1'b0;
//                    end
//                end
//                
//                // === NORMAL TRANSFORMATION ===
//                TRANSFORM_NORMAL: begin
//                    // Transform normal from texture space to world space
//                    // world_normal = tangent_matrix_B * tex_normal
//                    // This needs matrix multiplication: 3x3 * 3x1
//                    
//                    // For now, simplified - would need matrix multiplier here
//                    world_normal[0] <= tex_normal[0];
//                    world_normal[1] <= tex_normal[1]; 
//                    world_normal[2] <= tex_normal[2];
//                end
//                
//                WAIT_TRANSFORM_NORMAL: begin
//                    // Wait for normal transformation to complete
//                    // In full implementation, this would wait for matrix multiplication
//                end
//                
//                // === LIGHTING CALCULATION ===
//                CALC_LIGHTING: begin
//                    // Calculate diffuse: max(0, dot(world_normal, uniform_l))
//                    // Calculate specular: pow(max(-r.z, 0), shininess)
//                    
//                    // Simplified for now - would need dot product and power calculation
//                    diffuse_intensity <= 32'h3F800000;  // 1.0 placeholder
//                    specular_intensity <= 32'h3F000000; // 0.5 placeholder
//                end
//                
//                WAIT_LIGHTING: begin
//                    // Wait for lighting calculations to complete
//                end
//                
//                READ_MARKER2: begin
//                    if (!FF_empty) begin
//                        FF_readrequest <= 1'b1;
//                    end
//                end
//                
//                PROCESS_COMPLETE: begin
//                    // Fragment shader processing complete
//                    // Final results available:
//                    // - diffuse_intensity: Diffuse lighting component
//                    // - specular_intensity: Specular lighting component
//                    // - world_normal[0..2]: Transformed normal vector
//                    
//                    // TODO: Output final pixel color to framebuffer
//                end
//            endcase
//        end
//    end
//    
//    // Texture interface assignments
//    assign request2 = 1'b0;      // Not using second texture interface yet
//    assign addr_tex2 = 24'b0;
//    assign read_done2 = 1'b0;
//
//endmodule
module FRAGMENT #(
    parameter CORE_ID = 0
)(
    input logic clk,
    input logic rst_n,
    
    // Interface fifo_fragdepth: -1, uniform_l, varying_nrm, varying_uv, view_tri, pixel_x, pixel_y, bar, pixel_x, pixel_y, bar,... -1
    output logic FF_readrequest,
    input logic FF_empty,
    input logic [31:0] FF_data,
    
    // Interface small arbiter TEXTURE
    output logic request,
    output logic [23:0] addr_tex,
    output logic [6:0] texture_core_id,
    input logic texture_valid,
    input logic [31:0] tex_data,
    output logic read_done,
    
    // Interface small arbiter framebuffer
    output logic request2,
    output logic [23:0] addr_frame,
    output logic [6:0] frame_core_id,
    input logic frame_valid,
    output logic [31:32] color,
    input logic frame_done,
    
    // Base addresses and texture dimensions
    input logic [31:32] addr_normalmap,    // Base address of normal map
    input logic [31:32] addr_specmap,      // Base address of specular map
    input logic [31:32] addr_diffusemap,   // Base address of diffuse map
    input logic [31:32] addr_framebuffer,  // Frame buffer base address  
    input logic [31:32] width_tex,         // Texture width
    input logic [31:32] height_tex         // Texture height
);

    // State machine
    typedef enum logic [5:0] {
        IDLE,
        READ_MARKER1,           // Đọc -1 đầu
        READ_UNIFORM_L,         // Đọc uniform_l
        READ_VARYING_NRM,       // Đọc varying_nrm (9 values: 3x3 matrix)
        READ_VARYING_UV,        // Đọc varying_uv (6 values: 2x3 matrix)
        READ_VIEW_TRI,          // Đọc view_tri (9 values: 3x3 matrix)
        READ_PIXEL_XY,          // Đọc pixel_x, pixel_y
        READ_BAR,               // Đọc barycentric coordinates (3 values)
        CALC_BN,                // Tính barycentric normal
        WAIT_BN,                // Chờ BN calculation
        CALC_UV,                // Tính UV interpolation
        WAIT_UV,                // Chờ UV calculation
        CALC_TANGENT,           // Tính tangent space matrix
        WAIT_TANGENT,           // Chờ tangent calculation
        CONVERT_UV,             // Convert UV to integer coordinates
        WAIT_CONVERT_UV,        // Chờ UV conversion
        SAMPLE_NORMAL,          // Sample normal map
        WAIT_SAMPLE_NORMAL,     // Chờ normal sampling
        TRANSFORM_NORMAL,       // Transform normal to tangent space
        WAIT_TRANSFORM_NORMAL,  // Chờ normal transformation
        CALC_DOT_DIFFUSE,       // Tính dot product cho diffuse
        WAIT_DOT_DIFFUSE,       // Chờ dot product diffuse
        CALC_REFLECTED,         // Tính vector phản xạ
        WAIT_REFLECTED,         // Chờ reflected calculation
        SAMPLE_SPECULAR,        // Sample specular map
        WAIT_SAMPLE_SPECULAR,   // Chờ specular sampling
        CALC_SPECULAR,          // Tính specular intensity
        WAIT_SPECULAR,          // Chờ specular calculation
        SAMPLE_DIFFUSE,         // Sample diffuse map
        WAIT_SAMPLE_DIFFUSE,    // Chờ diffuse sampling
        CALC_COLOR,             // Tính final color
        WAIT_COLOR,             // Chờ color calculation
        WRITE_FRAMEBUFFER,      // Ghi color vào framebuffer
        READ_MARKER2,           // Đọc -1 cuối
        PROCESS_COMPLETE        // Hoàn thành xử lý triangle
    } state_t;
    
    state_t current_state, next_state;
    
    // Data storage
    logic [31:0] uniform_l [0:2];        // Light direction (x, y, z)
    logic [31:0] varying_nrm [0:8];      // 3x3 matrix (row major)
    logic [31:0] varying_uv [0:5];       // 2x3 matrix (u0,v0,u1,v1,u2,v2)
    logic [31:0] view_tri [0:8];         // 3x3 matrix
    logic [31:0] pixel_xy [0:1];         // pixel_x, pixel_y
    logic [31:0] bar [0:2];              // Barycentric coordinates
    
    // Counters
    logic [3:0] read_counter;
    
    // BN calculation signals (3x3 * 3x1)
    logic bn_ready, bn_data_valid, bn_calc_done, bn_read_done;
    logic [31:0] bn_data_in, bn_result_out;
    logic [31:0] bn_x_interp, bn_y_interp, bn_z_interp;  // Interpolated results
    logic [31:0] bn_x, bn_y, bn_z;                       // Normalized results
    
    // UV calculation signals (2x3 * 3x1)
    logic uv_ready, uv_data_valid, uv_calc_done, uv_read_done;
    logic [31:0] uv_data_in, uv_result_out;
    logic [31:0] uv_u, uv_v;
    
    // Tangent space calculation signals
    logic tangent_ready, tangent_data_valid, tangent_calc_done, tangent_read_done;
    logic [31:0] tangent_matrix_B [0:8];  // 3x3 tangent space matrix
    
    // UV to integer conversion signals
    logic f2i_u_stb, f2i_v_stb;
    logic f2i_u_ack, f2i_v_ack;
    logic [31:0] f2i_u_result, f2i_v_result;
    logic f2i_u_z_stb, f2i_v_z_stb;
    logic f2i_u_z_ack, f2i_v_z_ack;
    logic [31:0] tex_u_int, tex_v_int;
    
    // Normal map sampling signals
    logic [31:0] normal_tex_addr;
    logic [31:0] normal_tex_data;
    logic normal_request_done;
    logic [31:0] tex_normal [0:2];       // Normal from texture (R,G,B)
    logic [31:0] tangent_normal [0:2];   // Normal after conversion
    logic [31:0] world_normal [0:2];     // Transformed normal
    
    // Normal transformation signals (3x3 * 3x1)
    logic norm_trans_ready, norm_trans_data_valid, norm_trans_calc_done, norm_trans_read_done;
    logic [31:0] norm_trans_data_in, norm_trans_result_out;
    logic [3:0] norm_trans_send_counter;
    logic [1:0] norm_trans_receive_counter;
    logic norm_trans_sending_matrix, norm_trans_sending_vector, norm_trans_receiving_result;
    
    // Specular map sampling signals
    logic [31:0] spec_tex_addr;
    logic [31:0] spec_tex_data;
    logic spec_request_done;
    logic [31:0] shininess;              // Specular shininess from map
    
    // Diffuse map sampling signals
    logic [31:0] diff_tex_addr;
    logic [31:0] diff_tex_data;
    logic diff_request_done;
    logic [31:0] diffuse_color [0:2];    // Diffuse color (R,G,B)
    
    // Lighting calculation signals
    logic dot_ready, dot_data_valid, dot_calc_done, dot_read_done;
    logic [31:0] dot_data_in, dot_result;
    logic [31:0] diffuse_intensity;
    logic [31:0] reflected [0:2];        // Reflected light direction
    logic spec_ready, spec_data_valid, spec_calc_done, spec_read_done;
    logic [31:0] spec_data_in, spec_result;
    logic [31:0] specular_intensity;
    
    // Reflected vector calculation signals
    logic [31:0] dot_scaled_normal [0:2]; // 2 * (n · l) * n
    logic [31:0] two_dot_result;          // 2 * (n · l)
    logic [2:0] reflect_counter;
    
    // Color calculation signals
    logic [31:0] ambient = 32'h3C23D70A;  // 0.01 in IEEE 754 float (~10/255)
    logic [31:0] final_color [0:2];      // Final RGB color
    
    // Float to integer and integer to float conversion signals
    logic i2f_norm_stb [0:2];
    logic i2f_norm_ack [0:2];
    logic [31:0] i2f_norm_result [0:2];
    logic i2f_norm_z_stb [0:2];
    logic i2f_norm_z_ack [0:2];
    logic f2i_color_stb [0:2];
    logic f2i_color_ack [0:2];
    logic [31:0] f2i_color_result [0:2];
    logic f2i_color_z_stb [0:2];
    logic f2i_color_z_ack [0:2];
    
    // BN calculation control
    logic [3:0] bn_send_counter;
    logic [1:0] bn_receive_counter;
    logic bn_sending_matrix, bn_sending_vector, bn_receiving_result;
    
    // UV calculation control
    logic [2:0] uv_send_counter;
    logic [0:0] uv_receive_counter;
    logic uv_sending_matrix, uv_sending_vector, uv_receiving_result;
    
    // Vector normalize for BN
    logic norm_ready, norm_data_valid, norm_calc_done, norm_read_done;
    logic [31:0] norm_x_in, norm_y_in, norm_z_in;
    logic [31:0] norm_x_out, norm_y_out, norm_z_out;
    
    // Dot product and specular calculation control
    logic [2:0] dot_send_counter;
    logic dot_sending_vectors;
    logic [2:0] spec_send_counter;
    logic spec_sending_data;
    
    // Submodule instances
    // Matrix multiplication wrapper for BN (3x3 * 3x1)
    mul3x3_3x1_wrapper bn_calc (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(bn_ready),
        .data_valid(bn_data_valid),
        .data(bn_data_in),
        .calc_done(bn_calc_done),
        .result(bn_result_out),
        .read_done(bn_read_done)
    );
    
    // Matrix multiplication wrapper for UV (2x3 * 3x1)
    mul2x3_3x1_wrapper uv_calc (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(uv_ready),
        .data_valid(uv_data_valid),
        .data(uv_data_in),
        .calc_done(uv_calc_done),
        .result(uv_result_out),
        .read_done(uv_read_done)
    );
    
    // Vector normalize for BN
    vector_normalize_3d bn_normalize (
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
    
    // Tangent space calculation
    TANGENT_SPACE_CALC tangent_calc (
        .clk(clk),
        .rst_n(rst_n),
        .ready(tangent_ready),
        .data_valid(tangent_data_valid),
        .calc_done(tangent_calc_done),
        .read_done(tangent_read_done),
        .view_tri(view_tri),
        .varying_uv(varying_uv),
        .bn_x(bn_x),
        .bn_y(bn_y),
        .bn_z(bn_z),
        .matrix_B(tangent_matrix_B)
    );
    
    // Float to Integer converters for UV coordinates
    float_to_int f2i_u (
        .clk(clk),
        .rst(~rst_n),
        .input_a(uv_u),
        .input_a_stb(f2i_u_stb),
        .input_a_ack(f2i_u_ack),
        .output_z(f2i_u_result),
        .output_z_stb(f2i_u_z_stb),
        .output_z_ack(f2i_u_z_ack)
    );
    
    float_to_int f2i_v (
        .clk(clk),
        .rst(~rst_n),
        .input_a(uv_v),
        .input_a_stb(f2i_v_stb),
        .input_a_ack(f2i_v_ack),
        .output_z(f2i_v_result),
        .output_z_stb(f2i_v_z_stb),
        .output_z_ack(f2i_v_z_ack)
    );
    
    // Integer to Float converters for normal map values
    genvar i;
    generate
        for (i = 0; i < 3; i++) begin : gen_i2f_norm
            int_to_float i2f_norm (
                .clk(clk),
                .rst(~rst_n),
                .input_a(tex_normal[i]),
                .input_a_stb(i2f_norm_stb[i]),
                .input_a_ack(i2f_norm_ack[i]),
                .output_z(i2f_norm_result[i]),
                .output_z_stb(i2f_norm_z_stb[i]),
                .output_z_ack(i2f_norm_z_ack[i])
            );
        end
    endgenerate
    
    // Matrix multiplication wrapper for normal transformation (3x3 * 3x1)
    mul3x3_3x1_wrapper norm_trans_calc (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(norm_trans_ready),
        .data_valid(norm_trans_data_valid),
        .data(norm_trans_data_in),
        .calc_done(norm_trans_calc_done),
        .result(norm_trans_result_out),
        .read_done(norm_trans_read_done)
    );
    
    // Dot product for diffuse lighting
    dot_product_3d dot_calc (
        .clk(clk),
        .rst_n(rst_n),
        .ready(dot_ready),
        .data_valid(dot_data_valid),
        .data(dot_data_in),
        .calc_done(dot_calc_done),
        .result(dot_result),
        .read_done(dot_read_done)
    );
    
    // Power calculation for specular
    power_calc spec_calc (
        .clk(clk),
        .rst_n(rst_n),
        .ready(spec_ready),
        .data_valid(spec_data_valid),
        .data(spec_data_in),
        .calc_done(spec_calc_done),
        .result(spec_result),
        .read_done(spec_read_done)
    );
    
    // Float to Integer converters for final color
    generate
        for (i = 0; i < 3; i++) begin : gen_f2i_color
            float_to_int f2i_color (
                .clk(clk),
                .rst(~rst_n),
                .input_a(final_color[i]),
                .input_a_stb(f2i_color_stb[i]),
                .input_a_ack(f2i_color_ack[i]),
                .output_z(f2i_color_result[i]),
                .output_z_stb(f2i_color_z_stb[i]),
                .output_z_ack(f2i_color_z_ack[i])
            );
        end
    endgenerate
    
    // Assign CORE_ID to outputs
    assign texture_core_id = CORE_ID;
    assign frame_core_id = CORE_ID;
    
    // State transition logic (combinational)
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (!FF_empty) begin
                    next_state = READ_MARKER1;
                end
            end
            READ_MARKER1: begin
                if (FF_readrequest && !FF_empty && FF_data == 32'hFFFFFFFF) begin
                    next_state = READ_UNIFORM_L;
                end else if (FF_readrequest && !FF_empty) begin
                    next_state = IDLE; // Invalid data, restart
                end
            end
            READ_UNIFORM_L: begin
                if (!FF_empty && FF_readrequest && read_counter == 2) begin
                    next_state = READ_VARYING_NRM;
                end
            end
            READ_VARYING_NRM: begin
                if (!FF_empty && FF_readrequest && read_counter == 8) begin
                    next_state = READ_VARYING_UV;
                end
            end
            READ_VARYING_UV: begin
                if (!FF_empty && FF_readrequest && read_counter == 5) begin
                    next_state = READ_VIEW_TRI;
                end
            end
            READ_VIEW_TRI: begin
                if (!FF_empty && FF_readrequest && read_counter == 8) begin
                    next_state = READ_PIXEL_XY;
                end
            end
            READ_PIXEL_XY: begin
                if (!FF_empty && FF_readrequest && read_counter == 1) begin
                    next_state = READ_BAR;
                end
            end
            READ_BAR: begin
                if (!FF_empty && FF_readrequest && read_counter == 2) begin
                    next_state = CALC_BN;
                end
            end
            CALC_BN: begin
                if (bn_sending_vector && bn_send_counter == 2 && bn_data_valid) begin
                    next_state = WAIT_BN;
                end
            end
            WAIT_BN: begin
                if (norm_calc_done) begin
                    next_state = CALC_UV;
                end
            end
            CALC_UV: begin
                if (uv_sending_vector && uv_send_counter == 2 && uv_data_valid) begin
                    next_state = WAIT_UV;
                end
            end
            WAIT_UV: begin
                if (uv_receiving_result && uv_receive_counter == 1 && uv_calc_done) begin
                    next_state = CALC_TANGENT;
                end
            end
            CALC_TANGENT: begin
                if (tangent_data_valid) begin
                    next_state = WAIT_TANGENT;
                end
            end
            WAIT_TANGENT: begin
                if (tangent_calc_done) begin
                    next_state = CONVERT_UV;
                end
            end
            CONVERT_UV: begin
                if (f2i_u_stb && f2i_v_stb) begin
                    next_state = WAIT_CONVERT_UV;
                end
            end
            WAIT_CONVERT_UV: begin
                if (f2i_u_z_stb && f2i_v_z_stb) begin
                    next_state = SAMPLE_NORMAL;
                end
            end
            SAMPLE_NORMAL: begin
                if (request) begin
                    next_state = WAIT_SAMPLE_NORMAL;
                end
            end
            WAIT_SAMPLE_NORMAL: begin
                if (texture_valid && normal_request_done) begin
                    next_state = TRANSFORM_NORMAL;
                end
            end
            TRANSFORM_NORMAL: begin
                if (norm_trans_sending_vector && norm_trans_send_counter == 2 && norm_trans_data_valid) begin
                    next_state = WAIT_TRANSFORM_NORMAL;
                end
            end
            WAIT_TRANSFORM_NORMAL: begin
                if (norm_trans_receiving_result && norm_trans_receive_counter == 2 && norm_trans_calc_done) begin
                    next_state = CALC_DOT_DIFFUSE;
                end
            end
            CALC_DOT_DIFFUSE: begin
                if (dot_sending_vectors && dot_send_counter == 2 && dot_data_valid) begin
                    next_state = WAIT_DOT_DIFFUSE;
                end
            end
            WAIT_DOT_DIFFUSE: begin
                if (dot_calc_done) begin
                    next_state = CALC_REFLECTED;
                end
            end
            CALC_REFLECTED: begin
                if (reflect_counter == 2) begin
                    next_state = WAIT_REFLECTED;
                end
            end
            WAIT_REFLECTED: begin
                next_state = SAMPLE_SPECULAR;
            end
            SAMPLE_SPECULAR: begin
                if (request) begin
                    next_state = WAIT_SAMPLE_SPECULAR;
                end
            end
            WAIT_SAMPLE_SPECULAR: begin
                if (texture_valid && spec_request_done) begin
                    next_state = CALC_SPECULAR;
                end
            end
            CALC_SPECULAR: begin
                if (spec_sending_data && spec_send_counter == 1 && spec_data_valid) begin
                    next_state = WAIT_SPECULAR;
                end
            end
            WAIT_SPECULAR: begin
                if (spec_calc_done) begin
                    next_state = SAMPLE_DIFFUSE;
                end
            end
            SAMPLE_DIFFUSE: begin
                if (request) begin
                    next_state = WAIT_SAMPLE_DIFFUSE;
                end
            end
            WAIT_SAMPLE_DIFFUSE: begin
                if (texture_valid && diff_request_done) begin
                    next_state = CALC_COLOR;
                end
            end
            CALC_COLOR: begin
                if (f2i_color_stb[0] && f2i_color_stb[1] && f2i_color_stb[2]) begin
                    next_state = WAIT_COLOR;
                end
            end
            WAIT_COLOR: begin
                if (f2i_color_z_stb[0] && f2i_color_z_stb[1] && f2i_color_z_stb[2]) begin
                    next_state = WRITE_FRAMEBUFFER;
                end
            end
            WRITE_FRAMEBUFFER: begin
                if (frame_valid && frame_done) begin
                    next_state = READ_MARKER2;
                end
            end
            READ_MARKER2: begin
                if (!FF_empty && FF_readrequest && FF_data == 32'hFFFFFFFF) begin
                    next_state = PROCESS_COMPLETE;
                end else if (!FF_empty && FF_readrequest) begin
                    next_state = READ_PIXEL_XY; // Continue with next pixel
                end
            end
            PROCESS_COMPLETE: begin
                next_state = IDLE; // Ready for next triangle
            end
        endcase
    end
    
    // State register and sequential logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            current_state <= IDLE;
            FF_readrequest <= 1'b0;
            read_counter <= 4'b0;
            
            // Reset BN signals
            bn_data_valid <= 1'b0;
            bn_read_done <= 1'b0;
            bn_send_counter <= 4'b0;
            bn_receive_counter <= 2'b0;
            bn_sending_matrix <= 1'b0;
            bn_sending_vector <= 1'b0;
            bn_receiving_result <= 1'b0;
            
            // Reset UV signals
            uv_data_valid <= 1'b0;
            uv_read_done <= 1'b0;
            uv_send_counter <= 3'b0;
            uv_receive_counter <= 1'b0;
            uv_sending_matrix <= 1'b0;
            uv_sending_vector <= 1'b0;
            uv_receiving_result <= 1'b0;
            
            // Reset normalize signals
            norm_data_valid <= 1'b0;
            norm_read_done <= 1'b0;
            
            // Reset tangent signals
            tangent_data_valid <= 1'b0;
            tangent_read_done <= 1'b0;
            
            // Reset normal transformation signals
            norm_trans_data_valid <= 1'b0;
            norm_trans_read_done <= 1'b0;
            norm_trans_send_counter <= 4'b0;
            norm_trans_receive_counter <= 2'b0;
            norm_trans_sending_matrix <= 1'b0;
            norm_trans_sending_vector <= 1'b0;
            norm_trans_receiving_result <= 1'b0;
            
            // Reset float to int signals for UV
            f2i_u_stb <= 1'b0;
            f2i_v_stb <= 1'b0;
            f2i_u_z_ack <= 1'b0;
            f2i_v_z_ack <= 1'b0;
            
            // Reset int to float signals for normal
            for (int i = 0; i < 3; i++) begin
                i2f_norm_stb[i] <= 1'b0;
                i2f_norm_z_ack[i] <= 1'b0;
            end
            
            // Reset texture sampling signals
            request <= 1'b0;
            read_done <= 1'b0;
            normal_request_done <= 1'b0;
            spec_request_done <= 1'b0;
            diff_request_done <= 1'b0;
            
            // Reset lighting signals
            dot_data_valid <= 1'b0;
            dot_read_done <= 1'b0;
            dot_send_counter <= 3'b0;
            dot_sending_vectors <= 1'b0;
            spec_data_valid <= 1'b0;
            spec_read_done <= 1'b0;
            spec_send_counter <= 3'b0;
            spec_sending_data <= 1'b0;
            reflect_counter <= 3'b0;
            
            // Reset color and framebuffer signals
            for (int i = 0; i < 3; i++) begin
                f2i_color_stb[i] <= 1'b0;
                f2i_color_z_ack[i] <= 1'b0;
            end
            request2 <= 1'b0;
            
        end else begin
            current_state <= next_state;
            
            case (current_state)
                IDLE: begin
                    if (!FF_empty) begin
                        FF_readrequest <= 1'b1;
                    end
                end
                READ_MARKER1: begin
                    if (FF_readrequest && !FF_empty) begin
                        FF_readrequest <= 1'b0;
                        read_counter <= 4'b0;
                    end
                end
                READ_UNIFORM_L: begin
                    if (!FF_empty && FF_readrequest) begin
                        uniform_l[read_counter] <= FF_data;
                        if (read_counter == 2) begin
                            FF_readrequest <= 1'b0;
                            read_counter <= 4'b0;
                        end else begin
                            read_counter <= read_counter + 1;
                        end
                    end else if (!FF_empty) begin
                        FF_readrequest <= 1'b1;
                    end
                end
                READ_VARYING_NRM: begin
                    if (!FF_empty && FF_readrequest) begin
                        varying_nrm[read_counter] <= FF_data;
                        if (read_counter == 8) begin
                            FF_readrequest <= 1'b0;
                            read_counter <= 4'b0;
                        end else begin
                            read_counter <= read_counter + 1;
                        end
                    end else if (!FF_empty) begin
                        FF_readrequest <= 1'b1;
                    end
                end
                READ_VARYING_UV: begin
                    if (!FF_empty && FF_readrequest) begin
                        varying_uv[read_counter] <= FF_data;
                        if (read_counter == 5) begin
                            FF_readrequest <= 1'b0;
                            read_counter <= 4'b0;
                        end else begin
                            read_counter <= read_counter + 1;
                        end
                    end else if (!FF_empty) begin
                        FF_readrequest <= 1'b1;
                    end
                end
                READ_VIEW_TRI: begin
                    if (!FF_empty && FF_readrequest) begin
                        view_tri[read_counter] <= FF_data;
                        if (read_counter == 8) begin
                            FF_readrequest <= 1'b0;
                            read_counter <= 4'b0;
                        end else begin
                            read_counter <= read_counter + 1;
                        end
                    end else if (!FF_empty) begin
                        FF_readrequest <= 1'b1;
                    end
                end
                READ_PIXEL_XY: begin
                    if (!FF_empty && FF_readrequest) begin
                        pixel_xy[read_counter] <= FF_data;
                        if (read_counter == 1) begin
                            FF_readrequest <= 1'b0;
                            read_counter <= 4'b0;
                        end else begin
                            read_counter <= read_counter + 1;
                        end
                    end else if (!FF_empty) begin
                        FF_readrequest <= 1'b1;
                    end
                end
                READ_BAR: begin
                    if (!FF_empty && FF_readrequest) begin
                        bar[read_counter] <= FF_data;
                        if (read_counter == 2) begin
                            FF_readrequest <= 1'b0;
                            bn_send_counter <= 4'b0;
                            bn_receive_counter <= 2'b0;
                            bn_sending_matrix <= 1'b1;
                            bn_sending_vector <= 1'b0;
                            bn_receiving_result <= 1'b0;
                        end else begin
                            read_counter <= read_counter + 1;
                        end
                    end else if (!FF_empty) begin
                        FF_readrequest <= 1'b1;
                    end
                end
                CALC_BN: begin
                    if (bn_ready && !bn_data_valid) begin
                        if (bn_sending_matrix) begin
                            case (bn_send_counter)
                                0: bn_data_in <= varying_nrm[0]; // nrm0_x
                                1: bn_data_in <= varying_nrm[3]; // nrm1_x  
                                2: bn_data_in <= varying_nrm[6]; // nrm2_x
                                3: bn_data_in <= varying_nrm[1]; // nrm0_y
                                4: bn_data_in <= varying_nrm[4]; // nrm1_y
                                5: bn_data_in <= varying_nrm[7]; // nrm2_y
                                6: bn_data_in <= varying_nrm[2]; // nrm0_z
                                7: bn_data_in <= varying_nrm[5]; // nrm1_z
                                8: bn_data_in <= varying_nrm[8]; // nrm2_z
                            endcase
                            bn_data_valid <= 1'b1;
                            bn_send_counter <= bn_send_counter + 1;
                            if (bn_send_counter == 8) begin
                                bn_sending_matrix <= 1'b0;
                                bn_sending_vector <= 1'b1;
                                bn_send_counter <= 4'b0;
                            end
                        end else if (bn_sending_vector) begin
                            bn_data_in <= bar[bn_send_counter];
                            bn_data_valid <= 1'b1;
                            bn_send_counter <= bn_send_counter + 1;
                        end
                    end else begin
                        bn_data_valid <= 1'b0;
                    end
                end
                WAIT_BN: begin
                    bn_data_valid <= 1'b0;
                    if (bn_calc_done && !bn_receiving_result) begin
                        bn_receiving_result <= 1'b1;
                        bn_receive_counter <= 2'b0;
                    end
                    if (bn_receiving_result && bn_calc_done) begin
                        case (bn_receive_counter)
                            0: bn_x_interp <= bn_result_out;
                            1: bn_y_interp <= bn_result_out;
                            2: begin
                                bn_z_interp <= bn_result_out;
                                bn_read_done <= 1'b1;
                            end
                        endcase
                        bn_receive_counter <= bn_receive_counter + 1;
                        if (bn_receive_counter == 2) begin
                            bn_receiving_result <= 1'b0;
                            norm_x_in <= bn_x_interp;
                            norm_y_in <= bn_y_interp;
                            norm_z_in <= bn_z_interp;
                            if (norm_ready) begin
                                norm_data_valid <= 1'b1;
                            end
                        end
                    end
                    if (norm_calc_done) begin
                        bn_x <= norm_x_out;
                        bn_y <= norm_y_out;
                        bn_z <= norm_z_out;
                        norm_read_done <= 1'b1;
                        uv_send_counter <= 3'b0;
                        uv_receive_counter <= 1'b0;
                        uv_sending_matrix <= 1'b1;
                        uv_sending_vector <= 1'b0;
                        uv_receiving_result <= 1'b0;
                    end
                    if (bn_read_done) begin
                        bn_read_done <= 1'b0;
                        norm_data_valid <= 1'b0;
                    end
                    if (norm_read_done) begin
                        norm_read_done <= 1'b0;
                    end
                end
                CALC_UV: begin
                    if (uv_ready && !uv_data_valid) begin
                        if (uv_sending_matrix) begin
                            case (uv_send_counter)
                                0: uv_data_in <= varying_uv[0]; // u0
                                1: uv_data_in <= varying_uv[2]; // u1  
                                2: uv_data_in <= varying_uv[4]; // u2
                                3: uv_data_in <= varying_uv[1]; // v0
                                4: uv_data_in <= varying_uv[3]; // v1
                                5: uv_data_in <= varying_uv[5]; // v2
                            endcase
                            uv_data_valid <= 1'b1;
                            uv_send_counter <= uv_send_counter + 1;
                            if (uv_send_counter == 5) begin
                                uv_sending_matrix <= 1'b0;
                                uv_sending_vector <= 1'b1;
                                uv_send_counter <= 3'b0;
                            end
                        end else if (uv_sending_vector) begin
                            uv_data_in <= bar[uv_send_counter];
                            uv_data_valid <= 1'b1;
                            uv_send_counter <= uv_send_counter + 1;
                        end
                    end else begin
                        uv_data_valid <= 1'b0;
                    end
                end
                WAIT_UV: begin
                    uv_data_valid <= 1'b0;
                    if (uv_calc_done && !uv_receiving_result) begin
                        uv_receiving_result <= 1'b1;
                        uv_receive_counter <= 1'b0;
                    end
                    if (uv_receiving_result && uv_calc_done) begin
                        case (uv_receive_counter)
                            0: uv_u <= uv_result_out;
                            1: begin
                                uv_v <= uv_result_out;
                                uv_read_done <= 1'b1;
                            end
                        endcase
                        uv_receive_counter <= uv_receive_counter + 1;
                    end
                    if (uv_read_done) begin
                        uv_read_done <= 1'b0;
                    end
                end
                CALC_TANGENT: begin
                    if (tangent_ready) begin
                        tangent_data_valid <= 1'b1;
                    end
                end
                WAIT_TANGENT: begin
                    tangent_data_valid <= 1'b0;
                    if (tangent_calc_done) begin
                        tangent_read_done <= 1'b1;
                    end
                    if (tangent_read_done) begin
                        tangent_read_done <= 1'b0;
                    end
                end
                CONVERT_UV: begin
                    f2i_u_stb <= 1'b1;  // Convert U coordinate
                    f2i_v_stb <= 1'b1;  // Convert V coordinate
                end
                WAIT_CONVERT_UV: begin
                    if (f2i_u_ack && f2i_u_stb) begin
                        f2i_u_stb <= 1'b0;
                    end
                    if (f2i_u_z_stb) begin
                        f2i_u_z_ack <= 1'b1;
                        tex_u_int <= f2i_u_result;
                    end else begin
                        f2i_u_z_ack <= 1'b0;
                    end
                    if (f2i_v_ack && f2i_v_stb) begin
                        f2i_v_stb <= 1'b0;
                    end
                    if (f2i_v_z_stb) begin
                        f2i_v_z_ack <= 1'b1;
                        tex_v_int <= f2i_v_result;
                    end else begin
                        f2i_v_z_ack <= 1'b0;
                    end
                end
                SAMPLE_NORMAL: begin
                    normal_tex_addr <= addr_normalmap + (tex_v_int * width_tex + tex_u_int) * 4;
                    addr_tex <= normal_tex_addr[23:0];
                    request <= 1'b1;
                end
                WAIT_SAMPLE_NORMAL: begin
                    if (texture_valid) begin
                        normal_tex_data <= tex_data;
                        normal_request_done <= 1'b1;
                        request <= 1'b0;
                        read_done <= 1'b1;
                        // Convert TGAColor (B,G,R,A) to normal vector: (R,G,B)
                        tex_normal[0] <= {8'h00, tex_data[23:16], 16'h0000}; // R
                        tex_normal[1] <= {8'h00, tex_data[15:8],  16'h0000}; // G
                        tex_normal[2] <= {8'h00, tex_data[7:0],   16'h0000}; // B
                        i2f_norm_stb[0] <= 1'b1;
                        i2f_norm_stb[1] <= 1'b1;
                        i2f_norm_stb[2] <= 1'b1;
                    end else begin
                        read_done <= 1'b0;
                    end
                    if (normal_request_done) begin
                        normal_request_done <= 1'b0;
                    end
                end
                TRANSFORM_NORMAL: begin
                    if (norm_trans_ready && !norm_trans_data_valid) begin
                        if (norm_trans_sending_matrix) begin
                            norm_trans_data_in <= tangent_matrix_B[norm_trans_send_counter];
                            norm_trans_data_valid <= 1'b1;
                            norm_trans_send_counter <= norm_trans_send_counter + 1;
                            if (norm_trans_send_counter == 8) begin
                                norm_trans_sending_matrix <= 1'b0;
                                norm_trans_sending_vector <= 1'b1;
                                norm_trans_send_counter <= 4'b0;
                            end
                        end else if (norm_trans_sending_vector) begin
                            norm_trans_data_in <= tangent_normal[norm_trans_send_counter];
                            norm_trans_data_valid <= 1'b1;
                            norm_trans_send_counter <= norm_trans_send_counter + 1;
                        end
                    end else begin
                        norm_trans_data_valid <= 1'b0;
                    end
                    for (int i = 0; i < 3; i++) begin
                        if (i2f_norm_ack[i] && i2f_norm_stb[i]) begin
                            i2f_norm_stb[i] <= 1'b0;
                        end
                        if (i2f_norm_z_stb[i]) begin
                            i2f_norm_z_ack[i] <= 1'b1;
                            // Normalize to [-1, 1]: (R,G,B) * 2/255 - 1
                            tangent_normal[i] <= i2f_norm_result[i];
                        end
                    end
                end
                WAIT_TRANSFORM_NORMAL: begin
                    norm_trans_data_valid <= 1'b0;
                    if (norm_trans_calc_done && !norm_trans_receiving_result) begin
                        norm_trans_receiving_result <= 1'b1;
                        norm_trans_receive_counter <= 2'b0;
                    end
                    if (norm_trans_receiving_result && norm_trans_calc_done) begin
                        world_normal[norm_trans_receive_counter] <= norm_trans_result_out;
                        norm_trans_receive_counter <= norm_trans_receive_counter + 1;
                        if (norm_trans_receive_counter == 2) begin
                            norm_trans_read_done <= 1'b1;
                            norm_trans_receiving_result <= 1'b0;
                        end
                    end
                    if (norm_trans_read_done) begin
                        norm_trans_read_done <= 1'b0;
                    end
                    for (int i = 0; i < 3; i++) begin
                        if (i2f_norm_z_stb[i]) begin
                            i2f_norm_z_ack[i] <= 1'b0;
                        end
                    end
                end
                CALC_DOT_DIFFUSE: begin
                    if (dot_ready && !dot_data_valid) begin
                        if (dot_sending_vectors) begin
                            dot_data_in <= world_normal[dot_send_counter];
                            dot_data_valid <= 1'b1;
                            dot_send_counter <= dot_send_counter + 1;
                            if (dot_send_counter == 2) begin
                                dot_sending_vectors <= 1'b0;
                                dot_send_counter <= 3'b0;
                            end
                        end else begin
                            dot_data_in <= uniform_l[dot_send_counter];
                            dot_data_valid <= 1'b1;
                            dot_send_counter <= dot_send_counter + 1;
                        end
                    end else begin
                        dot_data_valid <= 1'b0;
                    end
                end
                WAIT_DOT_DIFFUSE: begin
                    dot_data_valid <= 1'b0;
                    if (dot_calc_done) begin
                        diffuse_intensity <= dot_result > 32'h00000000 ? dot_result : 32'h00000000; // max(0, dot)
                        dot_read_done <= 1'b1;
                        dot_sending_vectors <= 1'b1;
                        two_dot_result <= dot_result + dot_result; // 2 * (n · l)
                    end
                    if (dot_read_done) begin
                        dot_read_done <= 1'b0;
                    end
                end
                CALC_REFLECTED: begin
                    // Calculate: reflected = 2 * (n · l) * n - l
                    dot_scaled_normal[reflect_counter] <= two_dot_result * world_normal[reflect_counter];
                    reflected[reflect_counter] <= dot_scaled_normal[reflect_counter] - uniform_l[reflect_counter];
                    reflect_counter <= reflect_counter + 1;
                end
                WAIT_REFLECTED: begin
                    reflect_counter <= 3'b0;
                end
                SAMPLE_SPECULAR: begin
                    spec_tex_addr <= addr_specmap + (tex_v_int * width_tex + tex_u_int) * 4;
                    addr_tex <= spec_tex_addr[23:0];
                    request <= 1'b1;
                end
                WAIT_SAMPLE_SPECULAR: begin
                    if (texture_valid) begin
                        spec_tex_data <= tex_data;
                        spec_request_done <= 1'b1;
                        request <= 1'b0;
                        read_done <= 1'b1;
                        shininess <= {8'h00, tex_data[23:16], 16'h0000}; // Use R component for shininess
                    end else begin
                        read_done <= 1'b0;
                    end
                    if (spec_request_done) begin
                        spec_request_done <= 1'b0;
                    end
                end
                CALC_SPECULAR: begin
                    if (spec_ready && !spec_data_valid) begin
                        if (spec_sending_data) begin
                            spec_data_in <= reflected[2]; // -r.z (view vector assumed as (0,0,-1))
                            spec_data_valid <= 1'b1;
                            spec_send_counter <= spec_send_counter + 1;
                            if (spec_send_counter == 0) begin
                                spec_sending_data <= 1'b0;
                            end
                        end else begin
                            spec_data_in <= shininess; // Exponent from specular map
                            spec_data_valid <= 1'b1;
                            spec_send_counter <= spec_send_counter + 1;
                        end
                    end else begin
                        spec_data_valid <= 1'b0;
                    end
                end
                WAIT_SPECULAR: begin
                    spec_data_valid <= 1'b0;
                    if (spec_calc_done) begin
                        specular_intensity <= spec_result > 32'h00000000 ? spec_result : 32'h00000000; // max(0, pow)
                        spec_read_done <= 1'b1;
                        spec_sending_data <= 1'b1;
                    end
                    if (spec_read_done) begin
                        spec_read_done <= 1'b0;
                    end
                end
                SAMPLE_DIFFUSE: begin
                    diff_tex_addr <= addr_diffusemap + (tex_v_int * width_tex + tex_u_int) * 4;
                    addr_tex <= diff_tex_addr[23:0];
                    request <= 1'b1;
                end
                WAIT_SAMPLE_DIFFUSE: begin
                    if (texture_valid) begin
                        diff_tex_data <= tex_data;
                        diff_request_done <= 1'b1;
                        request <= 1'b0;
                        read_done <= 1'b1;
                        diffuse_color[0] <= {8'h00, tex_data[23:16], 16'h0000}; // R
                        diffuse_color[1] <= {8'h00, tex_data[15:8],  16'h0000}; // G
                        diffuse_color[2] <= {8'h00, tex_data[7:0],   16'h0000}; // B
                    end else begin
                        read_done <= 1'b0;
                    end
                    if (diff_request_done) begin
                        diff_request_done <= 1'b0;
                    end
                end
                CALC_COLOR: begin
                    for (int i = 0; i < 3; i++) begin
                        // final_color = ambient + diffuse_color * (diffuse_intensity + specular_intensity)
                        final_color[i] <= ambient + diffuse_color[i] * (diffuse_intensity + specular_intensity);
                        f2i_color_stb[i] <= 1'b1;
                    end
                end
                WAIT_COLOR: begin
                    for (int i = 0; i < 3; i++) begin
                        if (f2i_color_ack[i] && f2i_color_stb[i]) begin
                            f2i_color_stb[i] <= 1'b0;
                        end
                        if (f2i_color_z_stb[i]) begin
                            f2i_color_z_ack[i] <= 1'b1;
                            final_color[i] <= f2i_color_result[i] > 32'd255 ? 32'd255 : f2i_color_result[i]; // Clamp to 255
                        end else begin
                            f2i_color_z_ack[i] <= 1'b0;
                        end
                    end
                end
                WRITE_FRAMEBUFFER: begin
                    addr_frame <= addr_framebuffer[23:0] + (pixel_xy[1] * width_tex + pixel_xy[0]) * 4;
                    color <= {8'hFF, final_color[0][7:0], final_color[1][7:0], final_color[2][7:0]}; // ARGB
                    request2 <= 1'b1;
                    if (frame_valid && frame_done) begin
                        request2 <= 1'b0;
                    end
                end
                READ_MARKER2: begin
                    if (!FF_empty) begin
                        FF_readrequest <= 1'b1;
                    end else if (FF_readrequest) begin
                        FF_readrequest <= 1'b0;
                    end
                end
                PROCESS_COMPLETE: begin
                    FF_readrequest <= 1'b0;
                end
            endcase
        end
    end

endmodule