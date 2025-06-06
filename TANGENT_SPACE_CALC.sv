module TANGENT_SPACE_CALC (
    input logic clk,
    input logic rst_n,
    
    // Handshake protocol
    output logic ready,
    input logic data_valid,
    output logic calc_done,
    input logic read_done,
    
    // Input data
    input logic [31:0] view_tri [0:8],      // 3x3 matrix (col0, col1, col2) row major
    input logic [31:0] varying_uv [0:5],    // 2x3 matrix (u0,v0,u1,v1,u2,v2)
    input logic [31:0] bn_x, bn_y, bn_z,    // normalized barycentric normal
    
    // Output tangent space matrix B (3x3, row major)
    output logic [31:0] matrix_B [0:8]
);

    // State machine
    typedef enum logic [5:0] {
        IDLE,
        
        // Step 1: Calculate edge vectors (view_tri.col(1) - view_tri.col(0), view_tri.col(2) - view_tri.col(0))
        CALC_EDGE1, WAIT_EDGE1,      // edge1 = col1 - col0
        CALC_EDGE2, WAIT_EDGE2,      // edge2 = col2 - col0
        
        // Step 2: Calculate UV differences  
        CALC_DUV1, WAIT_DUV1,        // duv1 = (u1-u0, v1-v0)
        CALC_DUV2, WAIT_DUV2,        // duv2 = (u2-u0, v2-v0)
        
        // Step 3: Build matrix AI and invert it
        BUILD_AI,                    // Build AI matrix from edge vectors and bn
        INVERT_AI, WAIT_INVERT_AI,   // Invert AI matrix
        
        // Step 4: Calculate tangent vectors i and j
        CALC_I, WAIT_I,              // i = AI * (du1, du2, 0)
        CALC_J, WAIT_J,              // j = AI * (dv1, dv2, 0)
        
        // Step 5: Normalize i and j
        NORMALIZE_I, WAIT_NORMALIZE_I,
        NORMALIZE_J, WAIT_NORMALIZE_J,
        
        // Step 6: Build final matrix B and transpose
        BUILD_B,
        TRANSPOSE_B,
        
        OUTPUT_READY
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal storage
    logic [31:0] edge1 [0:2];       // view_tri.col(1) - view_tri.col(0)
    logic [31:0] edge2 [0:2];       // view_tri.col(2) - view_tri.col(0)
    logic [31:0] du1, dv1;          // u1-u0, v1-v0
    logic [31:0] du2, dv2;          // u2-u0, v2-v0
    logic [31:0] AI_matrix [0:8];   // Matrix AI (3x3)
    logic [31:0] AI_inv [0:8];      // Inverted AI (3x3)
    logic [31:0] i_vec [0:2];       // Tangent vector i
    logic [31:0] j_vec [0:2];       // Tangent vector j
    logic [31:0] i_norm [0:2];      // Normalized i
    logic [31:0] j_norm [0:2];      // Normalized j
    logic [31:0] B_temp [0:8];      // Temporary B matrix
    
    // Subtractor instances (3 for parallel vector subtraction)
    logic sub_a_stb [0:2], sub_b_stb [0:2];
    logic sub_a_ack [0:2], sub_b_ack [0:2];
    logic [31:0] sub_a_data [0:2], sub_b_data [0:2];
    logic [31:0] sub_result [0:2];
    logic sub_z_stb [0:2];
    logic sub_z_ack [0:2];
    
    // Matrix inverter
    logic inv_ready, inv_data_valid, inv_calc_done, inv_read_done;
    logic [31:0] inv_data_in, inv_data_out;
    
    // Matrix multiplier wrappers (for AI * vector operations)
    logic mul_ready, mul_data_valid, mul_calc_done, mul_read_done;
    logic [31:0] mul_data_in, mul_data_out;
    
    // Vector normalizers
    logic norm_i_ready, norm_i_data_valid, norm_i_calc_done, norm_i_read_done;
    logic [31:0] norm_i_x_in, norm_i_y_in, norm_i_z_in;
    logic [31:0] norm_i_x_out, norm_i_y_out, norm_i_z_out;
    
    logic norm_j_ready, norm_j_data_valid, norm_j_calc_done, norm_j_read_done;
    logic [31:0] norm_j_x_in, norm_j_y_in, norm_j_z_in;
    logic [31:0] norm_j_x_out, norm_j_y_out, norm_j_z_out;
    
    // Control signals
    logic [2:0] sub_counter;
    logic [3:0] inv_send_counter, inv_receive_counter;
    logic [3:0] mul_send_counter, mul_receive_counter;
    logic inv_sending, inv_receiving;
    logic mul_sending, mul_receiving;
    
    // Generate 3 subtractor instances
    genvar i;
    generate
        for (i = 0; i < 3; i++) begin : gen_subtractors
            subtractor sub_inst (
                .clk(clk),
                .rst(~rst_n),
                .input_a(sub_a_data[i]),
                .input_a_stb(sub_a_stb[i]),
                .input_a_ack(sub_a_ack[i]),
                .input_b(sub_b_data[i]),
                .input_b_stb(sub_b_stb[i]),
                .input_b_ack(sub_b_ack[i]),
                .output_z(sub_result[i]),
                .output_z_stb(sub_z_stb[i]),
                .output_z_ack(sub_z_ack[i])
            );
        end
    endgenerate
    
    // Matrix inverter instance
    matrix_inverter_3x3 matrix_inv (
        .clk(clk),
        .rst_n(rst_n),
        .ready(inv_ready),
        .data_valid(inv_data_valid),
        .calc_done(inv_calc_done),
        .read_done(inv_read_done),
        .data_in(inv_data_in),
        .data_out(inv_data_out)
    );
    
    // Matrix multiplier instance (reuse for both i and j calculations)
    mul3x3_3x1_wrapper matrix_mul (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(mul_ready),
        .data_valid(mul_data_valid),
        .calc_done(mul_calc_done),
        .read_done(mul_read_done),
        .data(mul_data_in),
        .result(mul_data_out)
    );
    
    // Vector normalizer instances
    vector_normalize_3d norm_i_inst (
        .clk(clk),
        .rst_n(rst_n),
        .ready(norm_i_ready),
        .data_valid(norm_i_data_valid),
        .calc_done(norm_i_calc_done),
        .read_done(norm_i_read_done),
        .x_in(norm_i_x_in),
        .y_in(norm_i_y_in),
        .z_in(norm_i_z_in),
        .x_out(norm_i_x_out),
        .y_out(norm_i_y_out),
        .z_out(norm_i_z_out)
    );
    
    vector_normalize_3d norm_j_inst (
        .clk(clk),
        .rst_n(rst_n),
        .ready(norm_j_ready),
        .data_valid(norm_j_data_valid),
        .calc_done(norm_j_calc_done),
        .read_done(norm_j_read_done),
        .x_in(norm_j_x_in),
        .y_in(norm_j_y_in),
        .z_in(norm_j_z_in),
        .x_out(norm_j_x_out),
        .y_out(norm_j_y_out),
        .z_out(norm_j_z_out)
    );
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (data_valid) next_state = CALC_EDGE1;
            end
            
            CALC_EDGE1: begin
                if (sub_z_stb[0] && sub_z_stb[1] && sub_z_stb[2]) begin
                    next_state = WAIT_EDGE1;
                end
            end
            
            WAIT_EDGE1: begin
                next_state = CALC_EDGE2;
            end
            
            CALC_EDGE2: begin
                if (sub_z_stb[0] && sub_z_stb[1] && sub_z_stb[2]) begin
                    next_state = WAIT_EDGE2;
                end
            end
            
            WAIT_EDGE2: begin
                next_state = CALC_DUV1;
            end
            
            CALC_DUV1: begin
                if (sub_z_stb[0] && sub_z_stb[1]) begin
                    next_state = WAIT_DUV1;
                end
            end
            
            WAIT_DUV1: begin
                next_state = CALC_DUV2;
            end
            
            CALC_DUV2: begin
                if (sub_z_stb[0] && sub_z_stb[1]) begin
                    next_state = WAIT_DUV2;
                end
            end
            
            WAIT_DUV2: begin
                next_state = BUILD_AI;
            end
            
            BUILD_AI: begin
                next_state = INVERT_AI;
            end
            
            INVERT_AI: begin
                if (inv_sending && inv_send_counter == 8) begin
                    next_state = WAIT_INVERT_AI;
                end
            end
            
            WAIT_INVERT_AI: begin
                if (inv_calc_done && inv_receiving && inv_receive_counter == 8) begin
                    next_state = CALC_I;
                end
            end
            
            CALC_I: begin
                if (mul_sending && mul_send_counter == 11) begin // 9 matrix + 3 vector - 1
                    next_state = WAIT_I;
                end
            end
            
            WAIT_I: begin
                if (mul_calc_done && mul_receiving && mul_receive_counter == 2) begin
                    next_state = CALC_J;
                end
            end
            
            CALC_J: begin
                if (mul_sending && mul_send_counter == 11) begin
                    next_state = WAIT_J;
                end
            end
            
            WAIT_J: begin
                if (mul_calc_done && mul_receiving && mul_receive_counter == 2) begin
                    next_state = NORMALIZE_I;
                end
            end
            
            NORMALIZE_I: begin
                if (norm_i_data_valid) begin
                    next_state = WAIT_NORMALIZE_I;
                end
            end
            
            WAIT_NORMALIZE_I: begin
                if (norm_i_calc_done) begin
                    next_state = NORMALIZE_J;
                end
            end
            
            NORMALIZE_J: begin
                if (norm_j_data_valid) begin
                    next_state = WAIT_NORMALIZE_J;
                end
            end
            
            WAIT_NORMALIZE_J: begin
                if (norm_j_calc_done) begin
                    next_state = BUILD_B;
                end
            end
            
            BUILD_B: begin
                next_state = TRANSPOSE_B;
            end
            
            TRANSPOSE_B: begin
                next_state = OUTPUT_READY;
            end
            
            OUTPUT_READY: begin
                if (read_done) next_state = IDLE;
            end
        endcase
    end
    
    // Sequential logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            current_state <= IDLE;
            
            // Reset subtractor signals
            for (int k = 0; k < 3; k++) begin
                sub_a_stb[k] <= 1'b0;
                sub_b_stb[k] <= 1'b0;
                sub_z_ack[k] <= 1'b0;
            end
            
            // Reset other control signals
            sub_counter <= 3'b0;
            inv_data_valid <= 1'b0;
            inv_read_done <= 1'b0;
            inv_send_counter <= 4'b0;
            inv_receive_counter <= 4'b0;
            inv_sending <= 1'b0;
            inv_receiving <= 1'b0;
            
            mul_data_valid <= 1'b0;
            mul_read_done <= 1'b0;
            mul_send_counter <= 4'b0;
            mul_receive_counter <= 4'b0;
            mul_sending <= 1'b0;
            mul_receiving <= 1'b0;
            
            norm_i_data_valid <= 1'b0;
            norm_i_read_done <= 1'b0;
            norm_j_data_valid <= 1'b0;
            norm_j_read_done <= 1'b0;
            
        end else begin
            current_state <= next_state;
            
            case (current_state)
                IDLE: begin
                    if (data_valid) begin
                        // Reset all control signals for new calculation
                        sub_counter <= 3'b0;
                        inv_sending <= 1'b0;
                        inv_receiving <= 1'b0;
                        mul_sending <= 1'b0;
                        mul_receiving <= 1'b0;
                    end
                end
                
                // === STEP 1: Calculate edge vectors ===
                CALC_EDGE1: begin
                    // Calculate edge1 = view_tri.col(1) - view_tri.col(0)
                    // view_tri stored as [col0_x,col0_y,col0_z,col1_x,col1_y,col1_z,col2_x,col2_y,col2_z]
                    
                    // Start subtraction for all 3 components - SEND A FIRST
                    sub_a_data[0] <= view_tri[3]; // col1_x 
                    sub_a_data[1] <= view_tri[4]; // col1_y   
                    sub_a_data[2] <= view_tri[5]; // col1_z
                    
                    // Store B data for later
                    sub_b_data[0] <= view_tri[0]; // col0_x
                    sub_b_data[1] <= view_tri[1]; // col0_y
                    sub_b_data[2] <= view_tri[2]; // col0_z
                    
                    for (int k = 0; k < 3; k++) begin
                        sub_a_stb[k] <= 1'b1;  // Only send A first
                        sub_b_stb[k] <= 1'b0;  // B will be sent after A ack
                    end
                end
                
                WAIT_EDGE1: begin
                    // Handle subtractor handshake and store results
                    for (int k = 0; k < 3; k++) begin
                        // Handle A input
                        if (sub_a_ack[k] && sub_a_stb[k]) begin
                            sub_a_stb[k] <= 1'b0;
                            sub_b_stb[k] <= 1'b1;  // Send B after A is acknowledged
                        end
                        
                        // Handle B input  
                        if (sub_b_ack[k] && sub_b_stb[k]) begin
                            sub_b_stb[k] <= 1'b0;
                        end
                        
                        // Handle result
                        if (sub_z_stb[k]) begin
                            sub_z_ack[k] <= 1'b1;
                            edge1[k] <= sub_result[k];
                        end else begin
                            sub_z_ack[k] <= 1'b0;
                        end
                    end
                end
                
                CALC_EDGE2: begin
                    // Calculate edge2 = view_tri.col(2) - view_tri.col(0)
                    sub_a_data[0] <= view_tri[6]; // col2_x
                    sub_a_data[1] <= view_tri[7]; // col2_y
                    sub_a_data[2] <= view_tri[8]; // col2_z
                    
                    sub_b_data[0] <= view_tri[0]; // col0_x
                    sub_b_data[1] <= view_tri[1]; // col0_y
                    sub_b_data[2] <= view_tri[2]; // col0_z
                    
                    for (int k = 0; k < 3; k++) begin
                        sub_a_stb[k] <= 1'b1;  // Only A first
                        sub_b_stb[k] <= 1'b0;
                    end
                end
                
                WAIT_EDGE2: begin
                    for (int k = 0; k < 3; k++) begin
                        if (sub_a_ack[k] && sub_a_stb[k]) begin
                            sub_a_stb[k] <= 1'b0;
                            sub_b_stb[k] <= 1'b1;  // Send B after A ack
                        end
                        
                        if (sub_b_ack[k] && sub_b_stb[k]) begin
                            sub_b_stb[k] <= 1'b0;
                        end
                        
                        if (sub_z_stb[k]) begin
                            sub_z_ack[k] <= 1'b1;
                            edge2[k] <= sub_result[k];
                        end else begin
                            sub_z_ack[k] <= 1'b0;
                        end
                    end
                end
                
                // === STEP 2: Calculate UV differences ===
                CALC_DUV1: begin
                    // Calculate du1 = u1 - u0, dv1 = v1 - v0
                    // varying_uv: [u0,v0,u1,v1,u2,v2]
                    sub_a_data[0] <= varying_uv[2]; // u1
                    sub_a_data[1] <= varying_uv[3]; // v1
                    
                    sub_b_data[0] <= varying_uv[0]; // u0  
                    sub_b_data[1] <= varying_uv[1]; // v0
                    
                    sub_a_stb[0] <= 1'b1;
                    sub_a_stb[1] <= 1'b1;
                    sub_b_stb[0] <= 1'b0;
                    sub_b_stb[1] <= 1'b0;
                end
                
                WAIT_DUV1: begin
                    // Handle A input
                    if (sub_a_ack[0] && sub_a_stb[0]) begin
                        sub_a_stb[0] <= 1'b0;
                        sub_b_stb[0] <= 1'b1;
                    end
                    if (sub_a_ack[1] && sub_a_stb[1]) begin
                        sub_a_stb[1] <= 1'b0;
                        sub_b_stb[1] <= 1'b1;
                    end
                    
                    // Handle B input
                    if (sub_b_ack[0] && sub_b_stb[0]) begin
                        sub_b_stb[0] <= 1'b0;
                    end
                    if (sub_b_ack[1] && sub_b_stb[1]) begin
                        sub_b_stb[1] <= 1'b0;
                    end
                    
                    // Handle results
                    if (sub_z_stb[0]) begin
                        sub_z_ack[0] <= 1'b1;
                        du1 <= sub_result[0];
                    end else begin
                        sub_z_ack[0] <= 1'b0;
                    end
                    
                    if (sub_z_stb[1]) begin
                        sub_z_ack[1] <= 1'b1;
                        dv1 <= sub_result[1];
                    end else begin
                        sub_z_ack[1] <= 1'b0;
                    end
                end
                
                CALC_DUV2: begin
                    // Calculate du2 = u2 - u0, dv2 = v2 - v0
                    sub_a_data[0] <= varying_uv[4]; // u2
                    sub_a_data[1] <= varying_uv[5]; // v2
                    
                    sub_b_data[0] <= varying_uv[0]; // u0
                    sub_b_data[1] <= varying_uv[1]; // v0
                    
                    sub_a_stb[0] <= 1'b1;
                    sub_a_stb[1] <= 1'b1;
                    sub_b_stb[0] <= 1'b0;
                    sub_b_stb[1] <= 1'b0;
                end
                
                WAIT_DUV2: begin
                    // Handle A input
                    if (sub_a_ack[0] && sub_a_stb[0]) begin
                        sub_a_stb[0] <= 1'b0;
                        sub_b_stb[0] <= 1'b1;
                    end
                    if (sub_a_ack[1] && sub_a_stb[1]) begin
                        sub_a_stb[1] <= 1'b0;
                        sub_b_stb[1] <= 1'b1;
                    end
                    
                    // Handle B input
                    if (sub_b_ack[0] && sub_b_stb[0]) begin
                        sub_b_stb[0] <= 1'b0;
                    end
                    if (sub_b_ack[1] && sub_b_stb[1]) begin
                        sub_b_stb[1] <= 1'b0;
                    end
                    
                    // Handle results
                    if (sub_z_stb[0]) begin
                        sub_z_ack[0] <= 1'b1;
                        du2 <= sub_result[0];
                    end else begin
                        sub_z_ack[0] <= 1'b0;
                    end
                    
                    if (sub_z_stb[1]) begin
                        sub_z_ack[1] <= 1'b1;
                        dv2 <= sub_result[1];
                    end else begin
                        sub_z_ack[1] <= 1'b0;
                    end
                end
                
                // === STEP 3: Build and invert AI matrix ===
                BUILD_AI: begin
                    // Build AI matrix: [edge1, edge2, bn] (3x3, column major)
                    AI_matrix[0] <= edge1[0]; AI_matrix[1] <= edge1[1]; AI_matrix[2] <= edge1[2];
                    AI_matrix[3] <= edge2[0]; AI_matrix[4] <= edge2[1]; AI_matrix[5] <= edge2[2];
                    AI_matrix[6] <= bn_x;     AI_matrix[7] <= bn_y;     AI_matrix[8] <= bn_z;
                    
                    inv_send_counter <= 4'b0;
                    inv_sending <= 1'b1;
                end
                
                INVERT_AI: begin
                    if (inv_ready && inv_sending) begin
                        inv_data_in <= AI_matrix[inv_send_counter];
                        inv_data_valid <= 1'b1;
                        inv_send_counter <= inv_send_counter + 1;
                        
                        if (inv_send_counter == 8) begin
                            inv_sending <= 1'b0;
                            inv_data_valid <= 1'b0;
                        end
                    end else begin
                        inv_data_valid <= 1'b0;
                    end
                end
                
                WAIT_INVERT_AI: begin
                    if (inv_calc_done && !inv_receiving) begin
                        inv_receiving <= 1'b1;
                        inv_receive_counter <= 4'b0;
                    end
                    
                    if (inv_receiving && inv_calc_done) begin
                        AI_inv[inv_receive_counter] <= inv_data_out;
                        inv_receive_counter <= inv_receive_counter + 1;
                        
                        if (inv_receive_counter == 8) begin
                            inv_receiving <= 1'b0;
                            inv_read_done <= 1'b1;
                        end
                    end
                    
                    if (inv_read_done) begin
                        inv_read_done <= 1'b0;
                    end
                end
                
                // === STEP 4: Calculate tangent vectors ===
                CALC_I: begin
                    // Calculate i = AI_inv * [du1, du2, 0]
                    if (mul_ready && !mul_sending) begin
                        mul_sending <= 1'b1;
                        mul_send_counter <= 4'b0;
                    end
                    
                    if (mul_sending) begin
                        if (mul_send_counter < 9) begin
                            // Send AI_inv matrix
                            mul_data_in <= AI_inv[mul_send_counter];
                        end else begin
                            // Send vector [du1, du2, 0]
                            case (mul_send_counter - 9)
                                0: mul_data_in <= du1;
                                1: mul_data_in <= du2;
                                2: mul_data_in <= 32'h00000000; // 0.0
                            endcase
                        end
                        
                        mul_data_valid <= 1'b1;
                        mul_send_counter <= mul_send_counter + 1;
                        
                        if (mul_send_counter == 11) begin
                            mul_sending <= 1'b0;
                            mul_data_valid <= 1'b0;
                        end
                    end else begin
                        mul_data_valid <= 1'b0;
                    end
                end
                
                WAIT_I: begin
                    if (mul_calc_done && !mul_receiving) begin
                        mul_receiving <= 1'b1;
                        mul_receive_counter <= 4'b0;
                    end
                    
                    if (mul_receiving && mul_calc_done) begin
                        i_vec[mul_receive_counter] <= mul_data_out;
                        mul_receive_counter <= mul_receive_counter + 1;
                        
                        if (mul_receive_counter == 2) begin
                            mul_receiving <= 1'b0;
                            mul_read_done <= 1'b1;
                        end
                    end
                    
                    if (mul_read_done) begin
                        mul_read_done <= 1'b0;
                        mul_send_counter <= 4'b0;
                        mul_sending <= 1'b1;
                    end
                end
                
                CALC_J: begin
                    // Calculate j = AI_inv * [dv1, dv2, 0]
                    if (mul_sending) begin
                        if (mul_send_counter < 9) begin
                            // Send AI_inv matrix (reuse)
                            mul_data_in <= AI_inv[mul_send_counter];
                        end else begin
                            // Send vector [dv1, dv2, 0]
                            case (mul_send_counter - 9)
                                0: mul_data_in <= dv1;
                                1: mul_data_in <= dv2;
                                2: mul_data_in <= 32'h00000000; // 0.0
                            endcase
                        end
                        
                        mul_data_valid <= 1'b1;
                        mul_send_counter <= mul_send_counter + 1;
                        
                        if (mul_send_counter == 11) begin
                            mul_sending <= 1'b0;
                            mul_data_valid <= 1'b0;
                        end
                    end else begin
                        mul_data_valid <= 1'b0;
                    end
                end
                
                WAIT_J: begin
                    if (mul_calc_done && !mul_receiving) begin
                        mul_receiving <= 1'b1;
                        mul_receive_counter <= 4'b0;
                    end
                    
                    if (mul_receiving && mul_calc_done) begin
                        j_vec[mul_receive_counter] <= mul_data_out;
                        mul_receive_counter <= mul_receive_counter + 1;
                        
                        if (mul_receive_counter == 2) begin
                            mul_receiving <= 1'b0;
                            mul_read_done <= 1'b1;
                        end
                    end
                    
                    if (mul_read_done) begin
                        mul_read_done <= 1'b0;
                    end
                end
                
                // === STEP 5: Normalize tangent vectors ===
                NORMALIZE_I: begin
                    if (norm_i_ready) begin
                        norm_i_x_in <= i_vec[0];
                        norm_i_y_in <= i_vec[1];
                        norm_i_z_in <= i_vec[2];
                        norm_i_data_valid <= 1'b1;
                    end
                end
                
                WAIT_NORMALIZE_I: begin
                    norm_i_data_valid <= 1'b0;
                    
                    if (norm_i_calc_done) begin
                        i_norm[0] <= norm_i_x_out;
                        i_norm[1] <= norm_i_y_out;
                        i_norm[2] <= norm_i_z_out;
                        norm_i_read_done <= 1'b1;
                    end
                    
                    if (norm_i_read_done) begin
                        norm_i_read_done <= 1'b0;
                    end
                end
                
                NORMALIZE_J: begin
                    if (norm_j_ready) begin
                        norm_j_x_in <= j_vec[0];
                        norm_j_y_in <= j_vec[1];
                        norm_j_z_in <= j_vec[2];
                        norm_j_data_valid <= 1'b1;
                    end
                end
                
                WAIT_NORMALIZE_J: begin
                    norm_j_data_valid <= 1'b0;
                    
                    if (norm_j_calc_done) begin
                        j_norm[0] <= norm_j_x_out;
                        j_norm[1] <= norm_j_y_out;
                        j_norm[2] <= norm_j_z_out;
                        norm_j_read_done <= 1'b1;
                    end
                    
                    if (norm_j_read_done) begin
                        norm_j_read_done <= 1'b0;
                    end
                end
                
                // === STEP 6: Build and transpose matrix B ===
                BUILD_B: begin
                    // Build matrix B = [i_norm, j_norm, bn] (column major)
                    B_temp[0] <= i_norm[0]; B_temp[1] <= i_norm[1]; B_temp[2] <= i_norm[2];  // i column
                    B_temp[3] <= j_norm[0]; B_temp[4] <= j_norm[1]; B_temp[5] <= j_norm[2];  // j column  
                    B_temp[6] <= bn_x;      B_temp[7] <= bn_y;      B_temp[8] <= bn_z;       // bn column
                end
                
                TRANSPOSE_B: begin
                    // Transpose B_temp to get final matrix_B (row major)
                    // B_temp (column major) -> matrix_B (row major)
                    matrix_B[0] <= B_temp[0]; matrix_B[1] <= B_temp[3]; matrix_B[2] <= B_temp[6];  // row 0
                    matrix_B[3] <= B_temp[1]; matrix_B[4] <= B_temp[4]; matrix_B[5] <= B_temp[7];  // row 1
                    matrix_B[6] <= B_temp[2]; matrix_B[7] <= B_temp[5]; matrix_B[8] <= B_temp[8];  // row 2
                end
                
                OUTPUT_READY: begin
                    // Matrix B is ready for output
                    // Results available in matrix_B[0..8]
                end
            endcase
        end
    end
    
    // Output assignments
    always_comb begin
        ready = (current_state == IDLE);
        calc_done = (current_state == OUTPUT_READY);
    end

endmodule