module mul3x3_3x1_wrapper (
    input logic iClk,
    input logic iRstn,
    output logic ready,
    input logic data_valid,
    input logic [31:0] data,
    output logic calc_done,
    output logic [31:0] result,
    input logic read_done
);

    // State machine
    typedef enum logic [3:0] {
        IDLE,
        LOAD_MATRIX,
        LOAD_VECTOR,
        COMPUTE,
        OUTPUT_RESULT,
        WAIT_READ_DONE
    } state_t;
    
    state_t current_state, next_state;
    
    // Matrix and vector storage
    logic [31:0] matrix_a [0:8];  // 3x3 matrix (9 elements)
    logic [31:0] vector_b [0:2];  // 3x1 vector (3 elements)
    logic [31:0] result_c [0:2];  // 3x1 result (3 elements)
    
    // Counters
    logic [3:0] load_counter;
    logic [1:0] output_counter;
    logic [1:0] compute_row; // Only 3 rows (0-2)
    
    // Multiplier instances (3 multipliers for 3x3)
    logic [31:0] mul_a [0:2], mul_b [0:2], mul_z [0:2];
    logic mul_a_stb [0:2], mul_b_stb [0:2], mul_z_stb [0:2];
    logic mul_a_ack [0:2], mul_b_ack [0:2], mul_z_ack [0:2];
    
    // Adder instances (2 adders for 3 terms)
    logic [31:0] add_a [0:1], add_b [0:1], add_z [0:1];
    logic add_a_stb [0:1], add_b_stb [0:1], add_z_stb [0:1];
    logic add_a_ack [0:1], add_b_ack [0:1], add_z_ack [0:1];
    
    // Generate multiplier instances
    genvar i;
    generate
        for (i = 0; i < 3; i++) begin : gen_multipliers
            multiplier mul_inst (
                .clk(iClk),
                .rst(~iRstn),
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
    
    // Generate adder instances
    generate
        for (i = 0; i < 2; i++) begin : gen_adders
            adder add_inst (
                .clk(iClk),
                .rst(~iRstn),
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
    
    // Computation control
    logic [3:0] compute_stage;
    logic computation_done;
    
    // State machine
    always_ff @(posedge iClk or negedge iRstn) begin
        if (!iRstn) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (data_valid) next_state = LOAD_MATRIX;
            end
            LOAD_MATRIX: begin
                if (load_counter == 8) next_state = LOAD_VECTOR;
            end
            LOAD_VECTOR: begin
                if (load_counter == 2) next_state = COMPUTE;
            end
            COMPUTE: begin
                if (computation_done) next_state = OUTPUT_RESULT;
            end
            OUTPUT_RESULT: begin
                if (output_counter == 2) next_state = WAIT_READ_DONE;
            end
            WAIT_READ_DONE: begin
                if (read_done) next_state = IDLE;
            end
        endcase
    end
    
    // Load counter
    always_ff @(posedge iClk or negedge iRstn) begin
        if (!iRstn) begin
            load_counter <= 0;
        end else begin
            case (current_state)
                LOAD_MATRIX: begin
                    if (data_valid) begin
                        if (load_counter == 8) begin
                            load_counter <= 0;
                        end else begin
                            load_counter <= load_counter + 1;
                        end
                    end
                end
                LOAD_VECTOR: begin
                    if (data_valid) begin
                        if (load_counter == 2) begin
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
    
    // Matrix and vector loading
    always_ff @(posedge iClk or negedge iRstn) begin
        if (!iRstn) begin
            for (int j = 0; j < 9; j++) begin
                matrix_a[j] <= 32'h0;
            end
            for (int j = 0; j < 3; j++) begin
                vector_b[j] <= 32'h0;
                result_c[j] <= 32'h0;
            end
        end else begin
            if (current_state == LOAD_MATRIX && data_valid) begin
                matrix_a[load_counter] <= data;
            end else if (current_state == LOAD_VECTOR && data_valid) begin
                vector_b[load_counter] <= data;
            end
        end
    end
    
    // Matrix-Vector multiplication computation (3x3 * 3x1)
    always_ff @(posedge iClk or negedge iRstn) begin
        if (!iRstn) begin
            compute_row <= 0;
            compute_stage <= 0;
            computation_done <= 0;
            
            // Initialize multiplier inputs
            for (int k = 0; k < 3; k++) begin
                mul_a[k] <= 32'h0;
                mul_b[k] <= 32'h0;
                mul_a_stb[k] <= 0;
                mul_b_stb[k] <= 0;
                mul_z_ack[k] <= 0;
            end
            
            // Initialize adder inputs
            for (int k = 0; k < 2; k++) begin
                add_a[k] <= 32'h0;
                add_b[k] <= 32'h0;
                add_a_stb[k] <= 0;
                add_b_stb[k] <= 0;
                add_z_ack[k] <= 0;
            end
            
        end else if (current_state == COMPUTE) begin
            case (compute_stage)
                // Send matrix row and vector to all 3 multipliers
                0: begin 
                    // Set data first: matrix[row][j] * vector[j] for j=0..2
                    mul_a[0] <= matrix_a[compute_row*3 + 0]; // matrix[row][0]
                    mul_a[1] <= matrix_a[compute_row*3 + 1]; // matrix[row][1]
                    mul_a[2] <= matrix_a[compute_row*3 + 2]; // matrix[row][2]
                    
                    mul_b[0] <= vector_b[0];
                    mul_b[1] <= vector_b[1];
                    mul_b[2] <= vector_b[2];
                    
                    mul_a_stb[0] <= 1;
                    mul_a_stb[1] <= 1;
                    mul_a_stb[2] <= 1;
                    
                    if (mul_a_stb[0] && mul_a_ack[0] && 
                        mul_a_stb[1] && mul_a_ack[1] && 
                        mul_a_stb[2] && mul_a_ack[2]) begin
                        mul_a_stb[0] <= 0;
                        mul_a_stb[1] <= 0;
                        mul_a_stb[2] <= 0;
                        compute_stage <= 1;
                    end
                end
                
                // Send B to all 3 multipliers
                1: begin
                    mul_b_stb[0] <= 1;
                    mul_b_stb[1] <= 1;
                    mul_b_stb[2] <= 1;
                    
                    if (mul_b_stb[0] && mul_b_ack[0] && 
                        mul_b_stb[1] && mul_b_ack[1] && 
                        mul_b_stb[2] && mul_b_ack[2]) begin
                        mul_b_stb[0] <= 0;
                        mul_b_stb[1] <= 0;
                        mul_b_stb[2] <= 0;
                        compute_stage <= 2;
                    end
                end
                
                // Wait for multipliers and send to first adder
                2: begin
                    if (mul_z_stb[0] && mul_z_stb[1] && mul_z_stb[2]) begin
                        // Set data first: add first two terms (mul0+mul1)
                        add_a[0] <= mul_z[0];
                        add_a_stb[0] <= 1;
                        
                        if (add_a_stb[0] && add_a_ack[0]) begin
                            add_a_stb[0] <= 0;
                            compute_stage <= 3;
                        end
                    end
                end
                
                3: begin
                    // Set data first
                    add_b[0] <= mul_z[1];
                    add_b_stb[0] <= 1;
                    
                    if (add_b_stb[0] && add_b_ack[0]) begin
                        add_b_stb[0] <= 0;
                        mul_z_ack[0] <= 1;
                        mul_z_ack[1] <= 1;
                        compute_stage <= 4;
                    end
                end
                
                // Final addition: (mul0+mul1) + mul2
                4: begin
                    if (add_z_stb[0]) begin
                        // Set data first: result of first add + third multiplier
                        add_a[1] <= add_z[0];
                        add_a_stb[1] <= 1;
                        
                        if (add_a_stb[1] && add_a_ack[1]) begin
                            add_a_stb[1] <= 0;
                            compute_stage <= 5;
                        end
                    end
                end
                
                5: begin
                    // Set data first
                    add_b[1] <= mul_z[2];
                    add_b_stb[1] <= 1;
                    
                    if (add_b_stb[1] && add_b_ack[1]) begin
                        add_b_stb[1] <= 0;
                        add_z_ack[0] <= 1;
                        mul_z_ack[2] <= 1;
                        compute_stage <= 6;
                    end
                end
                
                // Store result for current row
                6: begin
                    if (add_z_stb[1]) begin
                        result_c[compute_row] <= add_z[1];
                        add_z_ack[1] <= 1;
                        compute_stage <= 7;
                    end
                end
                
                7: begin
                    // Reset acks
                    mul_z_ack[0] <= 0;
                    mul_z_ack[1] <= 0;
                    mul_z_ack[2] <= 0;
                    add_z_ack[0] <= 0;
                    add_z_ack[1] <= 0;
                    
                    // Next row
                    if (compute_row == 2) begin
                        computation_done <= 1;
                    end else begin
                        compute_row <= compute_row + 1;
                        compute_stage <= 0;
                    end
                end
            endcase
            
        end else if (current_state == IDLE) begin
            compute_row <= 0;
            compute_stage <= 0;
            computation_done <= 0;
            
            for (int k = 0; k < 3; k++) begin
                result_c[k] <= 32'h0;
            end
            
            // Reset multiplier inputs
            for (int k = 0; k < 3; k++) begin
                mul_a[k] <= 32'h0;
                mul_b[k] <= 32'h0;
                mul_a_stb[k] <= 0;
                mul_b_stb[k] <= 0;
                mul_z_ack[k] <= 0;
            end
            
            // Reset adder inputs
            for (int k = 0; k < 2; k++) begin
                add_a[k] <= 32'h0;
                add_b[k] <= 32'h0;
                add_a_stb[k] <= 0;
                add_b_stb[k] <= 0;
                add_z_ack[k] <= 0;
            end
        end
    end
    
    // Output counter and result
    always_ff @(posedge iClk or negedge iRstn) begin
        if (!iRstn) begin
            output_counter <= 0;
        end else if (current_state == OUTPUT_RESULT) begin
            output_counter <= output_counter + 1;
        end else begin
            output_counter <= 0;
        end
    end
    
    // Output assignments
    always_comb begin
        ready = (current_state == IDLE);
        calc_done = (current_state == OUTPUT_RESULT);
        result = (current_state == OUTPUT_RESULT) ? result_c[output_counter] : 32'h0;
    end

endmodule