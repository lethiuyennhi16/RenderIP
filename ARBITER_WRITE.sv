module ARBITER_WRITE (
    input logic clk,
    input logic rst_n,
    
    // Interface với 87 RENDER_CORE (unified write interface)
    input logic [86:0] write_req,           // Write request signals từ cores
    input logic [86:0][31:0] write_addr,    // Write addresses từ cores  
    input logic [86:0][31:0] write_data,    // Write data từ cores
    input logic [86:0][6:0] write_core_id,  // Core IDs (mỗi core gửi ID riêng)
    
    output logic [86:0] write_valid,        // Valid signals tới cores
    output logic [86:0] write_done,         // Write completed signals
    
    // Interface với WRITE_MASTER
    output logic start_write,
    output logic [31:0] write_address,
    output logic [31:0] write_value,
    output logic [6:0] requesting_core_id,
    input logic write_complete
);module FRAGMENT_PROCESSOR (
    input logic clk,
    input logic rst_n,
    
    // Interface với RASTERIZER (nhận pixels)
    input logic pixel_valid,
    input logic [31:0] pixel_screen_x,
    input logic [31:0] pixel_screen_y,
    input logic [31:0] pixel_bc_screen[3],     // barycentric screen coords
    input logic [31:0] pixel_bc_clip[3],       // barycentric clip coords  
    input logic [31:0] pixel_frag_depth,       // interpolated depth
    input logic [31:0] pixel_current_z,        // current z-buffer value
    input logic [31:0] pixel_varying_uv[2],    // interpolated UV
    input logic [31:0] pixel_varying_nrm[3],   // interpolated normal
    output logic pixel_ready,
    
    // Interface với CONTROL_MATRIX (matrix operations)
    output logic matrix_request,
    output logic [2:0] matrix_opcode,
    input logic [31:0] matrix_data,
    input logic [6:0] target_core_id,
    input logic matrix_valid,
    output logic matrix_read_done,
    
    // Interface với ARBITER_TEXTURE (texture sampling)
    output logic texture_req,
    output logic [23:0] texture_addr,
    output logic [6:0] texture_core_id,
    input logic texture_valid,
    input logic [31:0] texture_data,
    output logic texture_read_done,
    
    // Interface với ARBITER_WRITE (output color)
    output logic write_req,
    output logic [31:0] write_addr,
    output logic [31:0] write_data,  // Final RGBA color
    output logic [6:0] write_core_id,
    input logic write_valid,
    input logic write_done,
    
    // Control interface
    input logic [6:0] core_id,
    input logic [31:0] addr_diff_tex,
    input logic [31:0] addr_norm_tex,
    input logic [31:0] addr_spec_tex,
    input logic [31:0] addr_framebuffer,
    input logic [31:0] width_framebuffer,
    input logic [31:0] height_framebuffer
);

    // Matrix opcodes
    localparam MATRIX_MODELVIEW = 3'd1;
    localparam MATRIX_LIGHT     = 3'd5;
    
    // 20-Stage Pipeline States (theo document)
    typedef enum logic [4:0] {
        IDLE                = 5'd0,
        
        // Fragment Processing Pipeline (20 stages theo document)
        STAGE_1_SETUP       = 5'd1,   // Setup + 3 pixels đầu
        STAGE_2_6PIXELS     = 5'd2,   // 6 pixels tầng 1
        STAGE_3_6PIXELS     = 5'd3,   // 6 pixels tầng 2
        STAGE_4_4P2P        = 5'd4,   // 4 pixels tầng 2 + 2 pixels tầng 3
        STAGE_5_6PIXELS     = 5'd5,   // 6 pixels tầng 3
        STAGE_6_2P4P        = 5'd6,   // 2 pixels tầng 3 + 4 pixels tầng 4
        STAGE_7_6PIXELS     = 5'd7,   // 6 pixels tầng 4
        STAGE_8_6PIXELS     = 5'd8,   // 6 pixels tầng 5  
        STAGE_9_4P2P        = 5'd9,   // 4 pixels tầng 5 + 2 pixels tầng 6
        STAGE_10_6PIXELS    = 5'd10,  // 6 pixels tầng 6
        STAGE_11_2P4P       = 5'd11,  // 2 pixels tầng 6 + 4 pixels tầng 7
        STAGE_12_6PIXELS    = 5'd12,  // 6 pixels tầng 7
        STAGE_13_6PIXELS    = 5'd13,  // 6 pixels tầng 8
        STAGE_14_4P2P       = 5'd14,  // 4 pixels tầng 8 + 2 pixels tầng 9
        STAGE_15_6PIXELS    = 5'd15,  // 6 pixels tầng 9
        STAGE_16_4P2P       = 5'd16,  // 4 pixels tầng 9 + 2 pixels tầng 10
        STAGE_17_6PIXELS    = 5'd17,  // 6 pixels tầng 10
        STAGE_18_UV_AI      = 5'd18,  // 2 pixels tầng 10 + uv + 5 tầng AI
        STAGE_19_AI_IJ_B    = 5'd19,  // 3 tầng AI + i + j + 3 tầng matrix B
        STAGE_20_FINAL      = 5'd20   // Final computation và output
    } fragment_state_t;
    
    fragment_state_t current_stage, next_stage;
    
    // Pipeline data storage
    logic [31:0] varying_uv_interp[2];     // Interpolated UV coordinates
    logic [31:0] varying_nrm_interp[3];    // Interpolated normals
    
    // AI matrix calculation results (Stage 18-19)
    logic [31:0] AI_matrix[3][3];          // Inverted matrix
    logic [31:0] i_vector[3];              // Tangent vector i
    logic [31:0] j_vector[3];              // Tangent vector j
    logic [31:0] B_matrix[3][3];           // Final transformation matrix
    
    // Texture samples (Stage 20)
    logic [31:0] diffuse_color[4];         // RGBA from diffuse texture
    logic [31:0] normal_color[4];          // RGBA from normal texture  
    logic [31:0] specular_color[4];        // RGBA from specular texture
    
    // Lighting calculation
    logic [31:0] light_dir_view[3];        // Light direction in view space
    logic [31:0] transformed_normal[3];    // Final transformed normal
    logic [31:0] diffuse_intensity;        // Diffuse lighting coefficient
    logic [31:0] specular_intensity;       // Specular lighting coefficient
    
    // Final output
    logic [31:0] final_color[4];           // Final RGBA color
    
    // Arithmetic units
    logic [31:0] mul_a[0:3], mul_b[0:3], mul_z[0:3];
    logic mul_a_stb[0:3], mul_b_stb[0:3], mul_z_stb[0:3];
    logic mul_a_ack[0:3], mul_b_ack[0:3], mul_z_ack[0:3];
    
    logic [31:0] add_a[0:1], add_b[0:1], add_z[0:1];
    logic add_a_stb[0:1], add_b_stb[0:1], add_z_stb[0:1];
    logic add_a_ack[0:1], add_b_ack[0:1], add_z_ack[0:1];
    
    // Conversion units
    logic [31:0] f2i_input_a, f2i_output_z;
    logic f2i_input_a_stb, f2i_input_a_ack;
    logic f2i_output_z_stb, f2i_output_z_ack;
    
    logic [31:0] i2f_input_a, i2f_output_z;
    logic i2f_input_a_stb, i2f_input_a_ack;
    logic i2f_output_z_stb, i2f_output_z_ack;
    
    // FP Comparator
    logic fp_comp_ready, fp_comp_data_valid, fp_comp_calc_done, fp_comp_read_done;
    logic [31:0] fp_comp_a, fp_comp_b;
    logic [2:0] fp_comp_result;
    
    // Specialized units
    logic dot_ready, dot_data_valid, dot_calc_done, dot_read_done;
    logic [31:0] dot_input_a[3], dot_input_b[3], dot_result;
    
    logic matrix_inv_ready, matrix_inv_data_valid, matrix_inv_calc_done, matrix_inv_read_done;
    logic [31:0] matrix_inv_input[9], matrix_inv_output[9];
    
    // Pipeline control
    logic [4:0] pixel_count;
    logic [4:0] max_pixels_per_stage;
    logic stage_complete;
    
    // Texture sampling control
    logic [1:0] texture_sample_state;  // 0=diffuse, 1=normal, 2=specular
    logic [31:0] texture_u_int, texture_v_int;
    
    // Instantiate arithmetic units
    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : gen_multipliers
            multiplier mul_inst (
                .clk(clk), .rst(~rst_n),
                .input_a(mul_a[i]), .input_b(mul_b[i]),
                .input_a_stb(mul_a_stb[i]), .input_b_stb(mul_b_stb[i]),
                .input_a_ack(mul_a_ack[i]), .input_b_ack(mul_b_ack[i]),
                .output_z(mul_z[i]), .output_z_stb(mul_z_stb[i]), .output_z_ack(mul_z_ack[i])
            );
        end
        
        for (i = 0; i < 2; i++) begin : gen_adders
            adder add_inst (
                .clk(clk), .rst(~rst_n),
                .input_a(add_a[i]), .input_b(add_b[i]),
                .input_a_stb(add_a_stb[i]), .input_b_stb(add_b_stb[i]),
                .input_a_ack(add_a_ack[i]), .input_b_ack(add_b_ack[i]),
                .output_z(add_z[i]), .output_z_stb(add_z_stb[i]), .output_z_ack(add_z_ack[i])
            );
        end
    endgenerate
    
    // Conversion units
    float_to_int fragment_f2i (
        .clk(clk), .rst(~rst_n),
        .input_a(f2i_input_a), .input_a_stb(f2i_input_a_stb), .input_a_ack(f2i_input_a_ack),
        .output_z(f2i_output_z), .output_z_stb(f2i_output_z_stb), .output_z_ack(f2i_output_z_ack)
    );
    
    int_to_float fragment_i2f (
        .clk(clk), .rst(~rst_n),
        .input_a(i2f_input_a), .input_a_stb(i2f_input_a_stb), .input_a_ack(i2f_input_a_ack),
        .output_z(i2f_output_z), .output_z_stb(i2f_output_z_stb), .output_z_ack(i2f_output_z_ack)
    );
    
    fp_comparator_32bit fragment_fp_comp (
        .clk(clk), .rst_n(rst_n),
        .ready(fp_comp_ready), .data_valid(fp_comp_data_valid),
        .calc_done(fp_comp_calc_done), .read_done(fp_comp_read_done),
        .a(fp_comp_a), .b(fp_comp_b), .result(fp_comp_result)
    );
    
    dot_product_3x1_wrapper dot_unit (
        .iClk(clk), .iRstn(rst_n),
        .ready(dot_ready), .data_valid(dot_data_valid),
        .input_a(dot_input_a), .input_b(dot_input_b),
        .calc_done(dot_calc_done), .result(dot_result), .read_done(dot_read_done)
    );
    
    matrix_invert_3x3 matrix_inv_unit (
        .clk(clk), .rst_n(rst_n),
        .ready(matrix_inv_ready), .data_valid(matrix_inv_data_valid),
        .data_in(matrix_inv_input), .calc_done(matrix_inv_calc_done),
        .data_out(matrix_inv_output), .read_done(matrix_inv_read_done)
    );
    
    // Max pixels per stage definition
    always_comb begin
        case (current_stage)
            STAGE_1_SETUP:      max_pixels_per_stage = 5'd3;
            STAGE_2_6PIXELS:    max_pixels_per_stage = 5'd6;
            STAGE_3_6PIXELS:    max_pixels_per_stage = 5'd6;
            STAGE_4_4P2P:       max_pixels_per_stage = 5'd6;
            STAGE_5_6PIXELS:    max_pixels_per_stage = 5'd6;
            STAGE_6_2P4P:       max_pixels_per_stage = 5'd6;
            STAGE_7_6PIXELS:    max_pixels_per_stage = 5'd6;
            STAGE_8_6PIXELS:    max_pixels_per_stage = 5'd6;
            STAGE_9_4P2P:       max_pixels_per_stage = 5'd6;
            STAGE_10_6PIXELS:   max_pixels_per_stage = 5'd6;
            STAGE_11_2P4P:      max_pixels_per_stage = 5'd6;
            STAGE_12_6PIXELS:   max_pixels_per_stage = 5'd6;
            STAGE_13_6PIXELS:   max_pixels_per_stage = 5'd6;
            STAGE_14_4P2P:      max_pixels_per_stage = 5'd6;
            STAGE_15_6PIXELS:   max_pixels_per_stage = 5'd6;
            STAGE_16_4P2P:      max_pixels_per_stage = 5'd6;
            STAGE_17_6PIXELS:   max_pixels_per_stage = 5'd6;
            STAGE_18_UV_AI:     max_pixels_per_stage = 5'd8;
            STAGE_19_AI_IJ_B:   max_pixels_per_stage = 5'd7;
            STAGE_20_FINAL:     max_pixels_per_stage = 5'd1;
            default:            max_pixels_per_stage = 5'd6;
        endcase
    end
    
    assign stage_complete = (pixel_count >= max_pixels_per_stage) || 
                           (current_stage == STAGE_18_UV_AI && matrix_inv_calc_done) ||
                           (current_stage == STAGE_20_FINAL && write_done);
    
    // Main pipeline state machine
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            current_stage <= IDLE;
        end else begin
            current_stage <= next_stage;
        end
    end
    
    // Next stage logic
    always_comb begin
        next_stage = current_stage;
        
        case (current_stage)
            IDLE: begin
                if (pixel_valid) next_stage = STAGE_1_SETUP;
            end
            STAGE_1_SETUP: begin
                if (stage_complete) next_stage = STAGE_2_6PIXELS;
            end
            STAGE_2_6PIXELS: begin
                if (stage_complete) next_stage = STAGE_3_6PIXELS;
            end
            STAGE_3_6PIXELS: begin
                if (stage_complete) next_stage = STAGE_4_4P2P;
            end
            STAGE_4_4P2P: begin
                if (stage_complete) next_stage = STAGE_5_6PIXELS;
            end
            STAGE_5_6PIXELS: begin
                if (stage_complete) next_stage = STAGE_6_2P4P;
            end
            STAGE_6_2P4P: begin
                if (stage_complete) next_stage = STAGE_7_6PIXELS;
            end
            STAGE_7_6PIXELS: begin
                if (stage_complete) next_stage = STAGE_8_6PIXELS;
            end
            STAGE_8_6PIXELS: begin
                if (stage_complete) next_stage = STAGE_9_4P2P;
            end
            STAGE_9_4P2P: begin
                if (stage_complete) next_stage = STAGE_10_6PIXELS;
            end
            STAGE_10_6PIXELS: begin
                if (stage_complete) next_stage = STAGE_11_2P4P;
            end
            STAGE_11_2P4P: begin
                if (stage_complete) next_stage = STAGE_12_6PIXELS;
            end
            STAGE_12_6PIXELS: begin
                if (stage_complete) next_stage = STAGE_13_6PIXELS;
            end
            STAGE_13_6PIXELS: begin
                if (stage_complete) next_stage = STAGE_14_4P2P;
            end
            STAGE_14_4P2P: begin
                if (stage_complete) next_stage = STAGE_15_6PIXELS;
            end
            STAGE_15_6PIXELS: begin
                if (stage_complete) next_stage = STAGE_16_4P2P;
            end
            STAGE_16_4P2P: begin
                if (stage_complete) next_stage = STAGE_17_6PIXELS;
            end
            STAGE_17_6PIXELS: begin
                if (stage_complete) next_stage = STAGE_18_UV_AI;
            end
            STAGE_18_UV_AI: begin
                if (stage_complete) next_stage = STAGE_19_AI_IJ_B;
            end
            STAGE_19_AI_IJ_B: begin
                if (stage_complete) next_stage = STAGE_20_FINAL;
            end
            STAGE_20_FINAL: begin
                if (stage_complete) next_stage = IDLE;
            end
        endcase
    end
    
    // Pipeline control
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            pixel_count <= 5'b0;
        end else begin
            if (pixel_valid && current_stage == IDLE) begin
                pixel_count <= 5'd1;
            end else if (!stage_complete) begin
                pixel_count <= pixel_count + 1'b1;
            end else begin
                pixel_count <= 5'b0;
            end
        end
    end
    
    // Input data processing - Stage 1
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 2; i++) varying_uv_interp[i] <= 32'b0;
            for (int i = 0; i < 3; i++) varying_nrm_interp[i] <= 32'b0;
        end else if (current_stage == STAGE_1_SETUP) begin
            // Store interpolated values (simplified)
            varying_uv_interp <= pixel_varying_uv;
            varying_nrm_interp <= pixel_varying_nrm;
        end
    end
    
    // AI Matrix calculation - Stage 18
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            matrix_inv_data_valid <= 1'b0;
            matrix_inv_read_done <= 1'b0;
        end else if (current_stage == STAGE_18_UV_AI) begin
            if (matrix_inv_ready && !matrix_inv_data_valid) begin
                // Setup 3x3 matrix for inversion (simplified)
                matrix_inv_input[0] <= 32'h3F800000;  // 1.0 - identity for demo
                matrix_inv_input[1] <= 32'h00000000;  // 0.0
                matrix_inv_input[2] <= 32'h00000000;  // 0.0
                matrix_inv_input[3] <= 32'h00000000;  // 0.0
                matrix_inv_input[4] <= 32'h3F800000;  // 1.0
                matrix_inv_input[5] <= 32'h00000000;  // 0.0
                matrix_inv_input[6] <= 32'h00000000;  // 0.0
                matrix_inv_input[7] <= 32'h00000000;  // 0.0
                matrix_inv_input[8] <= 32'h3F800000;  // 1.0
                matrix_inv_data_valid <= 1'b1;
            end
            
            if (matrix_inv_calc_done) begin
                for (int i = 0; i < 9; i++) begin
                    AI_matrix[i/3][i%3] <= matrix_inv_output[i];
                end
                matrix_inv_read_done <= 1'b1;
            end
        end else begin
            matrix_inv_data_valid <= 1'b0;
            matrix_inv_read_done <= 1'b0;
        end
    end
    
    // Texture sampling - Stage 20
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            texture_req <= 1'b0;
            texture_sample_state <= 2'b0;
            f2i_input_a_stb <= 1'b0;
            f2i_output_z_ack <= 1'b0;
        end else if (current_stage == STAGE_20_FINAL && texture_sample_state < 3) begin
            
            // Convert UV to integer coordinates
            if (!f2i_input_a_stb) begin
                f2i_input_a <= varying_uv_interp[0] * 256;  // u * texture_width
                f2i_input_a_stb <= 1'b1;
            end
            
            if (f2i_output_z_stb) begin
                texture_u_int <= f2i_output_z;
                f2i_output_z_ack <= 1'b1;
                
                // Request texture sample
                if (!texture_req) begin
                    texture_req <= 1'b1;
                    texture_core_id <= core_id;
                    
                    case (texture_sample_state)
                        2'b00: texture_addr <= addr_diff_tex[23:0] + texture_u_int * 4;
                        2'b01: texture_addr <= addr_norm_tex[23:0] + texture_u_int * 4;
                        2'b10: texture_addr <= addr_spec_tex[23:0] + texture_u_int * 4;
                    endcase
                end
            end
            
            if (texture_valid) begin
                case (texture_sample_state)
                    2'b00: diffuse_color[0] <= texture_data;
                    2'b01: normal_color[0] <= texture_data;
                    2'b10: specular_color[0] <= texture_data;
                endcase
                
                texture_read_done <= 1'b1;
                texture_req <= 1'b0;
                texture_sample_state <= texture_sample_state + 1'b1;
            end
        end else if (current_stage != STAGE_20_FINAL) begin
            texture_sample_state <= 2'b0;
            texture_read_done <= 1'b0;
        end
    end
    
    // Lighting calculation
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            diffuse_intensity <= 32'b0;
            specular_intensity <= 32'b0;
            dot_data_valid <= 1'b0;
            dot_read_done <= 1'b0;
        end else if (current_stage == STAGE_20_FINAL && texture_sample_state >= 3) begin
            
            // Get light direction
            if (!matrix_request) begin
                matrix_request <= 1'b1;
                matrix_opcode <= MATRIX_LIGHT;
            end
            
            if (matrix_valid && target_core_id == core_id) begin
                light_dir_view[0] <= matrix_data;  // Simplified - get first component
                matrix_read_done <= 1'b1;
                matrix_request <= 1'b0;
                
                // Calculate dot product for diffuse lighting
                if (dot_ready && !dot_data_valid) begin
                    dot_input_a <= varying_nrm_interp;  // Normal
                    dot_input_b <= light_dir_view;      // Light direction
                    dot_data_valid <= 1'b1;
                end
                
                if (dot_calc_done) begin
                    // Clamp to positive values using FP comparator
                    if (fp_comp_ready && !fp_comp_data_valid) begin
                        fp_comp_a <= dot_result;
                        fp_comp_b <= 32'h00000000;  // 0.0
                        fp_comp_data_valid <= 1'b1;
                    end
                    
                    if (fp_comp_calc_done) begin
                        diffuse_intensity <= fp_comp_result[2] ? dot_result : 32'h00000000;  // max(0, dot)
                        specular_intensity <= specular_color[0];  // Use specular map
                        fp_comp_read_done <= 1'b1;
                    end
                    
                    dot_read_done <= 1'b1;
                end
            end
        end else begin
            dot_data_valid <= 1'b0;
            dot_read_done <= 1'b0;
            fp_comp_data_valid <= 1'b0;
            fp_comp_read_done <= 1'b0;
        end
    end
    
    // Final color calculation and output
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            write_req <= 1'b0;
            write_addr <= 32'b0;
            write_data <= 32'b0;
            write_core_id <= 7'b0;
        end else if (current_stage == STAGE_20_FINAL && 
                     texture_sample_state >= 3 && 
                     diffuse_intensity != 32'b0) begin
            
            // Calculate final color using multipliers
            if (!mul_a_stb[0]) begin
                mul_a[0] <= diffuse_color[0];    // Base color
                mul_b[0] <= diffuse_intensity;   // Lighting
                mul_a_stb[0] <= 1'b1;
                mul_b_stb[0] <= 1'b1;
            end
            
            if (mul_z_stb[0]) begin
                final_color[0] <= mul_z[0];      // Final red
                final_color[1] <= mul_z[0];      // Simplified: same for all channels
                final_color[2] <= mul_z[0];      
                final_color[3] <= 32'h3F800000;  // Alpha = 1.0
                mul_z_ack[0] <= 1'b1;
                
                // Write to framebuffer
                if (!write_req) begin
                    write_req <= 1'b1;
                    write_addr <= addr_framebuffer + (pixel_screen_y * width_framebuffer + pixel_screen_x) * 4;
                    write_data <= {final_color[3][7:0], final_color[2][7:0], final_color[1][7:0], final_color[0][7:0]};
                    write_core_id <= core_id;
                end
            end
        end else if (write_done) begin
            write_req <= 1'b0;
        end
    end
    
    // Output control
    assign pixel_ready = (current_stage == IDLE);

endmodule

    // Arbitration FSM
    typedef enum logic [2:0] {
        IDLE                = 3'd0,
        FIND_REQUEST        = 3'd1,
        PROCESS_WRITE       = 3'd2,
        WAIT_COMPLETE       = 3'd3,
        SEND_RESPONSE       = 3'd4
    } arb_state_t;
    
    arb_state_t current_state, next_state;
    
    // Priority encoder - tìm core ID nhỏ nhất có write request
    logic [6:0] winning_core;
    logic valid_request_found;
    logic [6:0] processing_core;
    
    // Priority encoder logic
    always_comb begin
        winning_core = 7'd127;      // Invalid value
        valid_request_found = 1'b0;
        
        for (int i = 0; i < 87; i++) begin
            if (write_req[i] && (i < winning_core)) begin
                winning_core = i[6:0];
                valid_request_found = 1'b1;
            end
        end
    end
    
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
                if (valid_request_found) begin
                    next_state = FIND_REQUEST;
                end
            end
            
            FIND_REQUEST: begin
                next_state = PROCESS_WRITE;
            end
            
            PROCESS_WRITE: begin
                next_state = WAIT_COMPLETE;
            end
            
            WAIT_COMPLETE: begin
                if (write_complete) begin
                    next_state = SEND_RESPONSE;
                end
            end
            
            SEND_RESPONSE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Processing core tracking
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            processing_core <= 7'b0;
        end else begin
            if (current_state == FIND_REQUEST) begin
                processing_core <= winning_core;
            end
        end
    end
    
    // Output control signals
    always_comb begin
        start_write = 1'b0;
        write_address = 32'b0;
        write_value = 32'b0;
        requesting_core_id = 7'b0;
        
        if (current_state == PROCESS_WRITE) begin
            start_write = 1'b1;
            write_address = write_addr[processing_core];
            write_value = write_data[processing_core];
            requesting_core_id = processing_core;
        end
    end
    
    // Response signals to cores
    always_comb begin
        write_valid = 87'b0;
        write_done = 87'b0;
        
        if (current_state == PROCESS_WRITE) begin
            write_valid[processing_core] = 1'b1;
        end
        
        if (current_state == SEND_RESPONSE) begin
            write_done[processing_core] = 1'b1;
        end
    end

endmodule