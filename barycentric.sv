module barycentric (
    input logic clk,
    input logic rst_n,
    
    output logic ready,
    input logic data_valid,
    output logic calc_done,
    input logic read_done,
    input logic [31:0] pts2,   // Đọc tuần tự 6 lần (3 điểm x 2 tọa độ)
    input logic [31:0] P,      // Đọc tuần tự 2 lần (1 điểm x 2 tọa độ)
    output logic [31:0] bary   // Xuất tuần tự 3 lần (u, v, w)
);

    // State machine
    typedef enum logic [3:0] {
        IDLE,
        LOAD_TRIANGLE_POINTS,
        LOAD_POINT_P,
        COMPUTE_DENOMINATOR,
        COMPUTE_BARYCENTRIC,
        OUTPUT_RESULT,
        WAIT_READ_DONE
    } state_t;
    
    state_t current_state, next_state;
    
    // Storage for triangle points A, B, C (each has x, y)
    logic [31:0] A_x, A_y;  // pts2[0], pts2[1]
    logic [31:0] B_x, B_y;  // pts2[2], pts2[3]
    logic [31:0] C_x, C_y;  // pts2[4], pts2[5]
    logic [31:0] P_x, P_y;  // Point P coordinates
    
    // Intermediate calculations
    logic [31:0] denom;     // (B.y - C.y)*(A.x - C.x) + (C.x - B.x)*(A.y - C.y)
    logic [31:0] u, v, w;   // Barycentric coordinates
    
    // Counters
    logic [2:0] load_counter;
    logic [1:0] output_counter;
    logic output_done;
    
    // Multiple arithmetic units for parallel computation
    // 4 subtractors for parallel computation
    logic [31:0] sub_a [0:3], sub_b [0:3], sub_z [0:3];
    logic sub_a_stb [0:3], sub_b_stb [0:3], sub_z_stb [0:3];
    logic sub_a_ack [0:3], sub_b_ack [0:3], sub_z_ack [0:3];
    
    // 4 multipliers for parallel computation
    logic [31:0] mul_a [0:3], mul_b [0:3], mul_z [0:3];
    logic mul_a_stb [0:3], mul_b_stb [0:3], mul_z_stb [0:3];
    logic mul_a_ack [0:3], mul_b_ack [0:3], mul_z_ack [0:3];
    
    // 2 adders
    logic [31:0] add_a [0:1], add_b [0:1], add_z [0:1];
    logic add_a_stb [0:1], add_b_stb [0:1], add_z_stb [0:1];
    logic add_a_ack [0:1], add_b_ack [0:1], add_z_ack [0:1];
    
    // 2 dividers
    logic [31:0] div_a [0:1], div_b [0:1], div_z [0:1];
    logic div_a_stb [0:1], div_b_stb [0:1], div_z_stb [0:1];
    logic div_a_ack [0:1], div_b_ack [0:1], div_z_ack [0:1];
    
    // Generate arithmetic units
    genvar i;
    
    // Generate 4 subtractors
    generate
        for (i = 0; i < 4; i++) begin : gen_subtractors
            subtractor sub_inst (
                .clk(clk),
                .rst(~rst_n),
                .input_a(sub_a[i]),
                .input_a_stb(sub_a_stb[i]),
                .input_a_ack(sub_a_ack[i]),
                .input_b(sub_b[i]),
                .input_b_stb(sub_b_stb[i]),
                .input_b_ack(sub_b_ack[i]),
                .output_z(sub_z[i]),
                .output_z_stb(sub_z_stb[i]),
                .output_z_ack(sub_z_ack[i])
            );
        end
    endgenerate
    
    // Generate 4 multipliers
    generate
        for (i = 0; i < 4; i++) begin : gen_multipliers
            multiplier mul_inst (
                .clk(clk),
                .rst(~rst_n),
                .input_a(mul_a[i]),
                .input_a_stb(mul_a_stb[i]),
                .input_a_ack(mul_a_ack[i]),
                .input_b(mul_b[i]),
                .input_b_stb(mul_b_stb[i]),
                .input_b_ack(mul_b_ack[i]),
                .output_z(mul_z[i]),
                .output_z_stb(mul_z_stb[i]),
                .output_z_ack(mul_z_ack[i])
            );
        end
    endgenerate
    
    // Generate 2 adders
    generate
        for (i = 0; i < 2; i++) begin : gen_adders
            adder add_inst (
                .clk(clk),
                .rst(~rst_n),
                .input_a(add_a[i]),
                .input_a_stb(add_a_stb[i]),
                .input_a_ack(add_a_ack[i]),
                .input_b(add_b[i]),
                .input_b_stb(add_b_stb[i]),
                .input_b_ack(add_b_ack[i]),
                .output_z(add_z[i]),
                .output_z_stb(add_z_stb[i]),
                .output_z_ack(add_z_ack[i])
            );
        end
    endgenerate
    
    // Generate 2 dividers
    generate
        for (i = 0; i < 2; i++) begin : gen_dividers
            divider div_inst (
                .clk(clk),
                .rst(~rst_n),
                .input_a(div_a[i]),
                .input_a_stb(div_a_stb[i]),
                .input_a_ack(div_a_ack[i]),
                .input_b(div_b[i]),
                .input_b_stb(div_b_stb[i]),
                .input_b_ack(div_b_ack[i]),
                .output_z(div_z[i]),
                .output_z_stb(div_z_stb[i]),
                .output_z_ack(div_z_ack[i])
            );
        end
    endgenerate
    
    // Computation control
    logic [5:0] compute_stage;  // Increased to support more stages
    logic denom_done, bary_done;
    
    // Temporary storage for intermediate results
    logic [31:0] temp_diff [0:5];  // Store differences
    logic [31:0] temp_prod [0:3];  // Store products
    logic [31:0] numerator_u, numerator_v;
    
    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (data_valid) next_state = LOAD_TRIANGLE_POINTS;
            end
            LOAD_TRIANGLE_POINTS: begin
                if (load_counter == 5) next_state = LOAD_POINT_P;
            end
            LOAD_POINT_P: begin
                if (load_counter == 1) next_state = COMPUTE_DENOMINATOR;
            end
            COMPUTE_DENOMINATOR: begin
                if (denom_done) begin
                    next_state = COMPUTE_BARYCENTRIC;
                end
            end
            COMPUTE_BARYCENTRIC: begin
                if (bary_done) begin
                    next_state = OUTPUT_RESULT;
                end
            end
            OUTPUT_RESULT: begin
                if (output_done) next_state = WAIT_READ_DONE;
            end
            WAIT_READ_DONE: begin
                if (read_done) next_state = IDLE;
            end
        endcase
    end
    
    // Load counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_counter <= 0;
        end else begin
            case (current_state)
                LOAD_TRIANGLE_POINTS: begin
                    if (data_valid) begin
                        if (load_counter == 5) begin
                            load_counter <= 0;
                        end else begin
                            load_counter <= load_counter + 1;
                        end
                    end
                end
                LOAD_POINT_P: begin
                    if (data_valid) begin
                        if (load_counter == 1) begin
                            load_counter <= 0;
                        end else begin
                            load_counter <= load_counter + 1;
                        end
                    end
                end
                default: load_counter <= 0;
            endcase
        end
    end
    
    // Data loading
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_x <= 32'h0; A_y <= 32'h0;
            B_x <= 32'h0; B_y <= 32'h0;
            C_x <= 32'h0; C_y <= 32'h0;
            P_x <= 32'h0; P_y <= 32'h0;
        end else begin
            if (current_state == LOAD_TRIANGLE_POINTS && data_valid) begin
                case (load_counter)
                    0: A_x <= pts2;
                    1: A_y <= pts2;
                    2: B_x <= pts2;
                    3: B_y <= pts2;
                    4: C_x <= pts2;
                    5: C_y <= pts2;
                endcase
            end else if (current_state == LOAD_POINT_P && data_valid) begin
                case (load_counter)
                    0: P_x <= P;
                    1: P_y <= P;
                endcase
            end
        end
    end
    
    // Compute denominator in parallel: (B.y - C.y)*(A.x - C.x) + (C.x - B.x)*(A.y - C.y)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compute_stage <= 0;
            denom_done <= 0;
            denom <= 32'h0;
            
            // Reset all arithmetic units
            for (int j = 0; j < 4; j++) begin
                sub_a[j] <= 32'h0; sub_b[j] <= 32'h0; 
                sub_a_stb[j] <= 0; sub_b_stb[j] <= 0; sub_z_ack[j] <= 0;
                mul_a[j] <= 32'h0; mul_b[j] <= 32'h0; 
                mul_a_stb[j] <= 0; mul_b_stb[j] <= 0; mul_z_ack[j] <= 0;
            end
            for (int j = 0; j < 2; j++) begin
                add_a[j] <= 32'h0; add_b[j] <= 32'h0; 
                add_a_stb[j] <= 0; add_b_stb[j] <= 0; add_z_ack[j] <= 0;
            end
            for (int j = 0; j < 6; j++) begin
                temp_diff[j] <= 32'h0;
            end
            for (int j = 0; j < 4; j++) begin
                temp_prod[j] <= 32'h0;
            end
            
        end else if (current_state == COMPUTE_DENOMINATOR) begin
            // Reset compute_stage when entering denominator computation
            if (compute_stage == 0 && !denom_done) begin
                // Reset all temp storage at start of denominator computation
                for (int k = 0; k < 6; k++) begin
                    temp_diff[k] <= 32'h0;
                end
                for (int k = 0; k < 4; k++) begin
                    temp_prod[k] <= 32'h0;
                end
            end
            
            case (compute_stage)
                // Parallel computation of all 4 differences needed
                // sub[0]: B.y - C.y, sub[1]: A.x - C.x, sub[2]: C.x - B.x, sub[3]: A.y - C.y
                0: begin
                    sub_a[0] <= B_y; sub_b[0] <= C_y;  // B.y - C.y
                    sub_a[1] <= A_x; sub_b[1] <= C_x;  // A.x f- C.x  
                    sub_a[2] <= C_x; sub_b[2] <= B_x;  // C.x - B.x
                    sub_a[3] <= A_y; sub_b[3] <= C_y;  // A.y - C.y
                    
                    sub_a_stb[0] <= 1; sub_a_stb[1] <= 1; sub_a_stb[2] <= 1; sub_a_stb[3] <= 1;
                    
                    if (sub_a_stb[0] && sub_a_ack[0] && sub_a_stb[1] && sub_a_ack[1] && 
                        sub_a_stb[2] && sub_a_ack[2] && sub_a_stb[3] && sub_a_ack[3]) begin
                        sub_a_stb[0] <= 0; sub_a_stb[1] <= 0; sub_a_stb[2] <= 0; sub_a_stb[3] <= 0;
                        compute_stage <= 1;
                    end
                end
                
                1: begin
                    sub_b_stb[0] <= 1; sub_b_stb[1] <= 1; sub_b_stb[2] <= 1; sub_b_stb[3] <= 1;
                    
                    if (sub_b_stb[0] && sub_b_ack[0] && sub_b_stb[1] && sub_b_ack[1] && 
                        sub_b_stb[2] && sub_b_ack[2] && sub_b_stb[3] && sub_b_ack[3]) begin
                        sub_b_stb[0] <= 0; sub_b_stb[1] <= 0; sub_b_stb[2] <= 0; sub_b_stb[3] <= 0;
                        compute_stage <= 2;
                    end
                end
                
                // Wait for all subtractor results and store
                2: begin
                    if (sub_z_stb[0] && sub_z_stb[1] && sub_z_stb[2] && sub_z_stb[3]) begin
                        temp_diff[0] <= sub_z[0];  // B.y - C.y
                        temp_diff[1] <= sub_z[1];  // A.x - C.x
                        temp_diff[2] <= sub_z[2];  // C.x - B.x
                        temp_diff[3] <= sub_z[3];  // A.y - C.y
                        sub_z_ack[0] <= 1; sub_z_ack[1] <= 1; sub_z_ack[2] <= 1; sub_z_ack[3] <= 1;
                        compute_stage <= 3;
                    end
                end
                
                // Parallel multiplication: mul[0]: (B.y-C.y)*(A.x-C.x), mul[1]: (C.x-B.x)*(A.y-C.y)
                3: begin
                    sub_z_ack[0] <= 0; sub_z_ack[1] <= 0; sub_z_ack[2] <= 0; sub_z_ack[3] <= 0;
                    
                    mul_a[0] <= temp_diff[0]; mul_b[0] <= temp_diff[1];  // (B.y-C.y) * (A.x-C.x)
                    mul_a[1] <= temp_diff[2]; mul_b[1] <= temp_diff[3];  // (C.x-B.x) * (A.y-C.y)
                    
                    mul_a_stb[0] <= 1; mul_a_stb[1] <= 1;
                    
                    if (mul_a_stb[0] && mul_a_ack[0] && mul_a_stb[1] && mul_a_ack[1]) begin
                        mul_a_stb[0] <= 0; mul_a_stb[1] <= 0;
                        compute_stage <= 4;
                    end
                end
                
                4: begin
                    mul_b_stb[0] <= 1; mul_b_stb[1] <= 1;
                    
                    if (mul_b_stb[0] && mul_b_ack[0] && mul_b_stb[1] && mul_b_ack[1]) begin
                        mul_b_stb[0] <= 0; mul_b_stb[1] <= 0;
                        compute_stage <= 5;
                    end
                end
                
                // Wait for multiplier results and add them
                5: begin
                    if (mul_z_stb[0] && mul_z_stb[1]) begin
                        temp_prod[0] <= mul_z[0];  // First term
                        temp_prod[1] <= mul_z[1];  // Second term
                        mul_z_ack[0] <= 1; mul_z_ack[1] <= 1;
                        compute_stage <= 6;
                    end
                end
                
                // Final addition
                6: begin
                    mul_z_ack[0] <= 0; mul_z_ack[1] <= 0;
                    
                    add_a[0] <= temp_prod[0]; add_b[0] <= temp_prod[1];
                    add_a_stb[0] <= 1;
                    
                    if (add_a_stb[0] && add_a_ack[0]) begin
                        add_a_stb[0] <= 0;
                        compute_stage <= 7;
                    end
                end
                
                7: begin
                    add_b_stb[0] <= 1;
                    
                    if (add_b_stb[0] && add_b_ack[0]) begin
                        add_b_stb[0] <= 0;
                        compute_stage <= 8;
                    end
                end
                
                8: begin
                    if (add_z_stb[0]) begin
                        denom <= add_z[0];
                        add_z_ack[0] <= 1;
                        compute_stage <= 9;
                    end
                end
                
                9: begin
                    add_z_ack[0] <= 0;
                    denom_done <= 1;
                end
            endcase
            
        end else if (current_state == IDLE) begin
            compute_stage <= 0;
            denom_done <= 0;
            denom <= 32'h0;
        end else if (current_state == LOAD_POINT_P && next_state == COMPUTE_DENOMINATOR) begin
            // Reset compute_stage when transitioning to denominator computation
            compute_stage <= 0;
        end else if (current_state == COMPUTE_DENOMINATOR && next_state == COMPUTE_BARYCENTRIC) begin
            // Reset compute_stage when transitioning to barycentric computation
            compute_stage <= 0;
        end
    end
    
    // Compute barycentric coordinates u, v, w
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bary_done <= 0;
            u <= 32'h0; v <= 32'h0; w <= 32'h0;
            numerator_u <= 32'h0; numerator_v <= 32'h0;
            
            // Reset dividers
            for (int j = 0; j < 2; j++) begin
                div_a[j] <= 32'h0; div_b[j] <= 32'h0; 
                div_a_stb[j] <= 0; div_b_stb[j] <= 0; div_z_ack[j] <= 0;
            end
            
        end else if (current_state == COMPUTE_BARYCENTRIC) begin
            // Reset compute_stage and temp storage when entering barycentric computation
            // if (compute_stage == 0 && !bary_done) begin
                // // Reset temp storage to avoid using stale values from denominator computation
                // for (int k = 0; k < 6; k++) begin
                    // temp_diff[k] <= 32'h0;
                // end
                // for (int k = 0; k < 4; k++) begin
                    // temp_prod[k] <= 32'h0;
                // end
            // end
            
            case (compute_stage)
                // Compute all needed differences for u and v numerators in parallel
                // For u: (B.y - C.y)*(P.x - C.x) + (C.x - B.x)*(P.y - C.y)
                // For v: (C.y - A.y)*(P.x - C.x) + (A.x - C.x)*(P.y - C.y)
                // We need: P.x - C.x, P.y - C.y, C.y - A.y (we already have B.y-C.y, C.x-B.x, A.x-C.x)
                0: begin
                    sub_a[0] <= P_x; sub_b[0] <= C_x;  // P.x - C.x
                    sub_a[1] <= P_y; sub_b[1] <= C_y;  // P.y - C.y
                    sub_a[2] <= C_y; sub_b[2] <= A_y;  // C.y - A.y
                    
                    sub_a_stb[0] <= 1; sub_a_stb[1] <= 1; sub_a_stb[2] <= 1;
                    
                    if (sub_a_stb[0] && sub_a_ack[0] && sub_a_stb[1] && sub_a_ack[1] && 
                        sub_a_stb[2] && sub_a_ack[2]) begin
                        sub_a_stb[0] <= 0; sub_a_stb[1] <= 0; sub_a_stb[2] <= 0;
                        compute_stage <= 1;
                    end
                end
                
                1: begin
                    sub_b_stb[0] <= 1; sub_b_stb[1] <= 1; sub_b_stb[2] <= 1;
                    
                    if (sub_b_stb[0] && sub_b_ack[0] && sub_b_stb[1] && sub_b_ack[1] && 
                        sub_b_stb[2] && sub_b_ack[2]) begin
                        sub_b_stb[0] <= 0; sub_b_stb[1] <= 0; sub_b_stb[2] <= 0;
                        compute_stage <= 2;
                    end
                end
                
                2: begin
                    if (sub_z_stb[0] && sub_z_stb[1] && sub_z_stb[2]) begin
                        temp_diff[4] <= sub_z[0];  // P.x - C.x (use index 4)
                        temp_diff[5] <= sub_z[1];  // P.y - C.y (use index 5)
                        temp_diff[3] <= sub_z[2];  // C.y - A.y (overwrite index 3 safely)
                        sub_z_ack[0] <= 1; sub_z_ack[1] <= 1; sub_z_ack[2] <= 1;
                        compute_stage <= 3;
                    end
                end
                
                // Parallel multiplication for both numerators
                // mul[0]: (B.y-C.y)*(P.x-C.x), mul[1]: (C.x-B.x)*(P.y-C.y) for numerator_u
                // mul[2]: (C.y-A.y)*(P.x-C.x), mul[3]: (A.x-C.x)*(P.y-C.y) for numerator_v
                // Using: temp_diff[0]=B.y-C.y, temp_diff[1]=A.x-C.x, temp_diff[2]=C.x-B.x
                //        temp_diff[3]=C.y-A.y, temp_diff[4]=P.x-C.x, temp_diff[5]=P.y-C.y
                3: begin
                    sub_z_ack[0] <= 0; sub_z_ack[1] <= 0; sub_z_ack[2] <= 0;
                    
                    mul_a[0] <= temp_diff[0]; mul_b[0] <= temp_diff[4];  // (B.y-C.y) * (P.x-C.x)
                    mul_a[1] <= temp_diff[2]; mul_b[1] <= temp_diff[5];  // (C.x-B.x) * (P.y-C.y)
                    mul_a[2] <= temp_diff[3]; mul_b[2] <= temp_diff[4];  // (C.y-A.y) * (P.x-C.x)
                    mul_a[3] <= temp_diff[1]; mul_b[3] <= temp_diff[5];  // (A.x-C.x) * (P.y-C.y)
                    
                    mul_a_stb[0] <= 1; mul_a_stb[1] <= 1; mul_a_stb[2] <= 1; mul_a_stb[3] <= 1;
                    
                    if (mul_a_stb[0] && mul_a_ack[0] && mul_a_stb[1] && mul_a_ack[1] && 
                        mul_a_stb[2] && mul_a_ack[2] && mul_a_stb[3] && mul_a_ack[3]) begin
                        mul_a_stb[0] <= 0; mul_a_stb[1] <= 0; mul_a_stb[2] <= 0; mul_a_stb[3] <= 0;
                        compute_stage <= 4;
                    end
                end
                
                4: begin
                    mul_b_stb[0] <= 1; mul_b_stb[1] <= 1; mul_b_stb[2] <= 1; mul_b_stb[3] <= 1;
                    
                    if (mul_b_stb[0] && mul_b_ack[0] && mul_b_stb[1] && mul_b_ack[1] && 
                        mul_b_stb[2] && mul_b_ack[2] && mul_b_stb[3] && mul_b_ack[3]) begin
                        mul_b_stb[0] <= 0; mul_b_stb[1] <= 0; mul_b_stb[2] <= 0; mul_b_stb[3] <= 0;
                        compute_stage <= 5;
                    end
                end
                
                // Store multiplication results and add them to get numerators
                5: begin
                    if (mul_z_stb[0] && mul_z_stb[1] && mul_z_stb[2] && mul_z_stb[3]) begin
                        temp_prod[0] <= mul_z[0];  // (B.y-C.y)*(P.x-C.x)
                        temp_prod[1] <= mul_z[1];  // (C.x-B.x)*(P.y-C.y) 
                        temp_prod[2] <= mul_z[2];  // (C.y-A.y)*(P.x-C.x)
                        temp_prod[3] <= mul_z[3];  // (A.x-C.x)*(P.y-C.y)
                        mul_z_ack[0] <= 1; mul_z_ack[1] <= 1; mul_z_ack[2] <= 1; mul_z_ack[3] <= 1;
                        compute_stage <= 6;
                    end
                end
                
                // Parallel addition for both numerators
                // add[0]: temp_prod[0] + temp_prod[1] = numerator_u
                // add[1]: temp_prod[2] + temp_prod[3] = numerator_v
                6: begin
                    mul_z_ack[0] <= 0; mul_z_ack[1] <= 0; mul_z_ack[2] <= 0; mul_z_ack[3] <= 0;
                    
                    add_a[0] <= temp_prod[0]; add_b[0] <= temp_prod[1];  // numerator_u
                    add_a[1] <= temp_prod[2]; add_b[1] <= temp_prod[3];  // numerator_v
                    
                    add_a_stb[0] <= 1; add_a_stb[1] <= 1;
                    
                    if (add_a_stb[0] && add_a_ack[0] && add_a_stb[1] && add_a_ack[1]) begin
                        add_a_stb[0] <= 0; add_a_stb[1] <= 0;
                        compute_stage <= 7;
                    end
                end
                
                7: begin
                    add_b_stb[0] <= 1; add_b_stb[1] <= 1;
                    
                    if (add_b_stb[0] && add_b_ack[0] && add_b_stb[1] && add_b_ack[1]) begin
                        add_b_stb[0] <= 0; add_b_stb[1] <= 0;
                        compute_stage <= 8;
                    end
                end
                
                8: begin
                    if (add_z_stb[0] && add_z_stb[1]) begin
                        numerator_u <= add_z[0];
                        numerator_v <= add_z[1];
                        add_z_ack[0] <= 1; add_z_ack[1] <= 1;
                        compute_stage <= 9;
                    end
                end
                
                // Parallel division: u = numerator_u / denom, v = numerator_v / denom
                9: begin
                    add_z_ack[0] <= 0; add_z_ack[1] <= 0;
                    
                    div_a[0] <= numerator_u; div_b[0] <= denom;  // u calculation
                    div_a[1] <= numerator_v; div_b[1] <= denom;  // v calculation
                    
                    div_a_stb[0] <= 1; div_a_stb[1] <= 1;
                    
                    if (div_a_stb[0] && div_a_ack[0] && div_a_stb[1] && div_a_ack[1]) begin
                        div_a_stb[0] <= 0; div_a_stb[1] <= 0;
                        compute_stage <= 10;
                    end
                end
                
                10: begin
                    div_b_stb[0] <= 1; div_b_stb[1] <= 1;
                    
                    if (div_b_stb[0] && div_b_ack[0] && div_b_stb[1] && div_b_ack[1]) begin
                        div_b_stb[0] <= 0; div_b_stb[1] <= 0;
                        compute_stage <= 11;
                    end
                end
                
                11: begin
                    if (div_z_stb[0] && div_z_stb[1]) begin
                        u <= div_z[0];
                        v <= div_z[1];
                        div_z_ack[0] <= 1; div_z_ack[1] <= 1;
                        compute_stage <= 12;
                    end
                end
                
                // Compute w = 1.0 - u - v using subtractors
                12: begin
                    div_z_ack[0] <= 0; div_z_ack[1] <= 0;
                    
                    // First compute 1.0 - u
                    sub_a[0] <= 32'h3F800000;  // 1.0 in IEEE 754 single precision
                    sub_b[0] <= u;
                    sub_a_stb[0] <= 1;
                    
                    if (sub_a_stb[0] && sub_a_ack[0]) begin
                        sub_a_stb[0] <= 0;
                        compute_stage <= 13;
                    end
                end
                
                13: begin
                    sub_b_stb[0] <= 1;
                    
                    if (sub_b_stb[0] && sub_b_ack[0]) begin
                        sub_b_stb[0] <= 0;
                        compute_stage <= 14;
                    end
                end
                
                14: begin
                    if (sub_z_stb[0]) begin
                        temp_diff[0] <= sub_z[0];  // 1.0 - u
                        sub_z_ack[0] <= 1;
                        compute_stage <= 15;
                    end
                end
                
                // Then compute (1.0 - u) - v = w
                15: begin
                    sub_z_ack[0] <= 0;
                    
                    sub_a[1] <= temp_diff[0];  // 1.0 - u
                    sub_b[1] <= v;
                    sub_a_stb[1] <= 1;
                    
                    if (sub_a_stb[1] && sub_a_ack[1]) begin
                        sub_a_stb[1] <= 0;
                        compute_stage <= 16;
                    end
                end
                
                16: begin
                    sub_b_stb[1] <= 1;
                    
                    if (sub_b_stb[1] && sub_b_ack[1]) begin
                        sub_b_stb[1] <= 0;
                        compute_stage <= 17;
                    end
                end
                
                17: begin
                    if (sub_z_stb[1]) begin
                        w <= sub_z[1];  // Final w = 1.0 - u - v
                        sub_z_ack[1] <= 1;
                        compute_stage <= 18;
                    end
                end
                
                18: begin
                    sub_z_ack[1] <= 0;
                    bary_done <= 1;
                end
            endcase
            
        end else if (current_state == IDLE) begin
            compute_stage <= 0;
            bary_done <= 0;
            u <= 32'h0; v <= 32'h0; w <= 32'h0;
            numerator_u <= 32'h0; numerator_v <= 32'h0;
            
            // Reset all arithmetic units
            for (int j = 0; j < 4; j++) begin
                sub_a[j] <= 32'h0; sub_b[j] <= 32'h0; 
                sub_a_stb[j] <= 0; sub_b_stb[j] <= 0; sub_z_ack[j] <= 0;
                mul_a[j] <= 32'h0; mul_b[j] <= 32'h0; 
                mul_a_stb[j] <= 0; mul_b_stb[j] <= 0; mul_z_ack[j] <= 0;
            end
            for (int j = 0; j < 2; j++) begin
                add_a[j] <= 32'h0; add_b[j] <= 32'h0; 
                add_a_stb[j] <= 0; add_b_stb[j] <= 0; add_z_ack[j] <= 0;
                div_a[j] <= 32'h0; div_b[j] <= 32'h0; 
                div_a_stb[j] <= 0; div_b_stb[j] <= 0; div_z_ack[j] <= 0;
            end
            for (int j = 0; j < 6; j++) begin
                temp_diff[j] <= 32'h0;
            end
            for (int j = 0; j < 4; j++) begin
                temp_prod[j] <= 32'h0;
            end
        end else if (current_state == COMPUTE_DENOMINATOR && next_state == COMPUTE_BARYCENTRIC) begin
            // Reset compute_stage when transitioning to barycentric computation
            compute_stage <= 0;
        end
    end
    
    // Output control
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_counter <= 0;
            output_done <= 0;
        end else if (current_state == OUTPUT_RESULT) begin
            if (output_counter == 2) begin
                output_done <= 1;
            end else begin
                output_counter <= output_counter + 1;
            end
        end else begin
            output_counter <= 0;
            output_done <= 0;
        end
    end
    
    // Output assignments
    always_comb begin
        ready = (current_state == IDLE);
        calc_done = (current_state == OUTPUT_RESULT);
        
        case (output_counter)
            0: bary = u;
            1: bary = v;
            2: bary = w;
            default: bary = 32'h0;
        endcase
    end

endmodule
