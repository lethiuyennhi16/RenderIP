module cross_product_3x1_wrapper (
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
        LOAD_VECTOR_A,
        LOAD_VECTOR_B,
        COMPUTE,
        OUTPUT_RESULT,
        WAIT_READ_DONE
    } state_t;
    
    state_t current_state, next_state;
    
    // Vector storage
    logic [31:0] vector_a [0:2];  // First 3x1 vector [a0, a1, a2]
    logic [31:0] vector_b [0:2];  // Second 3x1 vector [b0, b1, b2]
    logic [31:0] result_c [0:2];  // Cross product result [c0, c1, c2]
    
    // Counters
    logic [1:0] load_counter;
    logic [1:0] output_counter;
    
    // Multiplier instances (6 multipliers for cross product)
    // mul0: a1*b2, mul1: a2*b1, mul2: a2*b0, mul3: a0*b2, mul4: a0*b1, mul5: a1*b0
    logic [31:0] mul_a [0:5], mul_b [0:5], mul_z [0:5];
    logic mul_a_stb [0:5], mul_b_stb [0:5], mul_z_stb [0:5];
    logic mul_a_ack [0:5], mul_b_ack [0:5], mul_z_ack [0:5];
    
    // Adder instances (3 adders for subtraction: a1*b2-a2*b1, a2*b0-a0*b2, a0*b1-a1*b0)
    logic [31:0] add_a [0:2], add_b [0:2], add_z [0:2];
    logic add_a_stb [0:2], add_b_stb [0:2], add_z_stb [0:2];
    logic add_a_ack [0:2], add_b_ack [0:2], add_z_ack [0:2];
    
    // Generate multiplier instances
    genvar i;
    generate
        for (i = 0; i < 6; i++) begin : gen_multipliers
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
    
    // Generate adder instances (used for subtraction)
    generate
        for (i = 0; i < 3; i++) begin : gen_adders
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
                if (data_valid) next_state = LOAD_VECTOR_A;
            end
            LOAD_VECTOR_A: begin
                if (load_counter == 2) next_state = LOAD_VECTOR_B;
            end
            LOAD_VECTOR_B: begin
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
                LOAD_VECTOR_A: begin
                    if (data_valid) begin
                        if (load_counter == 2) begin
                            load_counter <= 0;
                        end else begin
                            load_counter <= load_counter + 1;
                        end
                    end
                end
                LOAD_VECTOR_B: begin
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
    
    // Vector loading
    always_ff @(posedge iClk or negedge iRstn) begin
        if (!iRstn) begin
            for (int j = 0; j < 3; j++) begin
                vector_a[j] <= 32'h0;
                vector_b[j] <= 32'h0;
                result_c[j] <= 32'h0;
            end
        end else begin
            if (current_state == LOAD_VECTOR_A && data_valid) begin
                vector_a[load_counter] <= data;
            end else if (current_state == LOAD_VECTOR_B && data_valid) begin
                vector_b[load_counter] <= data;
            end
        end
    end
    
    // Cross product computation: a × b = [a1*b2-a2*b1, a2*b0-a0*b2, a0*b1-a1*b0]
    always_ff @(posedge iClk or negedge iRstn) begin
        if (!iRstn) begin
            compute_stage <= 0;
            computation_done <= 0;
            
            // Initialize multiplier inputs
            for (int k = 0; k < 6; k++) begin
                mul_a[k] <= 32'h0;
                mul_b[k] <= 32'h0;
                mul_a_stb[k] <= 0;
                mul_b_stb[k] <= 0;
                mul_z_ack[k] <= 0;
            end
            
            // Initialize adder inputs
            for (int k = 0; k < 3; k++) begin
                add_a[k] <= 32'h0;
                add_b[k] <= 32'h0;
                add_a_stb[k] <= 0;
                add_b_stb[k] <= 0;
                add_z_ack[k] <= 0;
            end
            
        end else if (current_state == COMPUTE) begin
            case (compute_stage)
                // Send all 6 multiplication pairs to multipliers
                0: begin 
                    // Set data first for cross product terms
                    // c0 = a1*b2 - a2*b1
                    mul_a[0] <= vector_a[1]; // a1
                    mul_b[0] <= vector_b[2]; // b2
                    mul_a[1] <= vector_a[2]; // a2  
                    mul_b[1] <= vector_b[1]; // b1
                    
                    // c1 = a2*b0 - a0*b2
                    mul_a[2] <= vector_a[2]; // a2
                    mul_b[2] <= vector_b[0]; // b0
                    mul_a[3] <= vector_a[0]; // a0
                    mul_b[3] <= vector_b[2]; // b2
                    
                    // c2 = a0*b1 - a1*b0
                    mul_a[4] <= vector_a[0]; // a0
                    mul_b[4] <= vector_b[1]; // b1
                    mul_a[5] <= vector_a[1]; // a1
                    mul_b[5] <= vector_b[0]; // b0
                    
                    mul_a_stb[0] <= 1;
                    mul_a_stb[1] <= 1;
                    mul_a_stb[2] <= 1;
                    mul_a_stb[3] <= 1;
                    mul_a_stb[4] <= 1;
                    mul_a_stb[5] <= 1;
                    
                    if (mul_a_stb[0] && mul_a_ack[0] && 
                        mul_a_stb[1] && mul_a_ack[1] && 
                        mul_a_stb[2] && mul_a_ack[2] &&
                        mul_a_stb[3] && mul_a_ack[3] &&
                        mul_a_stb[4] && mul_a_ack[4] &&
                        mul_a_stb[5] && mul_a_ack[5]) begin
                        mul_a_stb[0] <= 0;
                        mul_a_stb[1] <= 0;
                        mul_a_stb[2] <= 0;
                        mul_a_stb[3] <= 0;
                        mul_a_stb[4] <= 0;
                        mul_a_stb[5] <= 0;
                        compute_stage <= 1;
                    end
                end
                
                // Send B to all 6 multipliers
                1: begin
                    mul_b_stb[0] <= 1;
                    mul_b_stb[1] <= 1;
                    mul_b_stb[2] <= 1;
                    mul_b_stb[3] <= 1;
                    mul_b_stb[4] <= 1;
                    mul_b_stb[5] <= 1;
                    
                    if (mul_b_stb[0] && mul_b_ack[0] && 
                        mul_b_stb[1] && mul_b_ack[1] && 
                        mul_b_stb[2] && mul_b_ack[2] &&
                        mul_b_stb[3] && mul_b_ack[3] &&
                        mul_b_stb[4] && mul_b_ack[4] &&
                        mul_b_stb[5] && mul_b_ack[5]) begin
                        mul_b_stb[0] <= 0;
                        mul_b_stb[1] <= 0;
                        mul_b_stb[2] <= 0;
                        mul_b_stb[3] <= 0;
                        mul_b_stb[4] <= 0;
                        mul_b_stb[5] <= 0;
                        compute_stage <= 2;
                    end
                end
                
                // Wait for multipliers and perform 3 parallel subtractions
                2: begin
                    if (mul_z_stb[0] && mul_z_stb[1] && mul_z_stb[2] && 
                        mul_z_stb[3] && mul_z_stb[4] && mul_z_stb[5]) begin
                        
                        // Set data first for 3 parallel subtractions
                        // c0 = mul0 - mul1 = a1*b2 - a2*b1
                        add_a[0] <= mul_z[0];
                        add_b[0] <= {~mul_z[1][31], mul_z[1][30:0]}; // Negate mul_z[1] for subtraction
                        
                        // c1 = mul2 - mul3 = a2*b0 - a0*b2  
                        add_a[1] <= mul_z[2];
                        add_b[1] <= {~mul_z[3][31], mul_z[3][30:0]}; // Negate mul_z[3] for subtraction
                        
                        // c2 = mul4 - mul5 = a0*b1 - a1*b0
                        add_a[2] <= mul_z[4]; 
                        add_b[2] <= {~mul_z[5][31], mul_z[5][30:0]}; // Negate mul_z[5] for subtraction
                        
                        add_a_stb[0] <= 1;
                        add_a_stb[1] <= 1;
                        add_a_stb[2] <= 1;
                        
                        if (add_a_stb[0] && add_a_ack[0] && 
                            add_a_stb[1] && add_a_ack[1] && 
                            add_a_stb[2] && add_a_ack[2]) begin
                            add_a_stb[0] <= 0;
                            add_a_stb[1] <= 0;
                            add_a_stb[2] <= 0;
                            compute_stage <= 3;
                        end
                    end
                end
                
                3: begin
                    add_b_stb[0] <= 1;
                    add_b_stb[1] <= 1;
                    add_b_stb[2] <= 1;
                    
                    if (add_b_stb[0] && add_b_ack[0] && 
                        add_b_stb[1] && add_b_ack[1] && 
                        add_b_stb[2] && add_b_ack[2]) begin
                        add_b_stb[0] <= 0;
                        add_b_stb[1] <= 0;
                        add_b_stb[2] <= 0;
                        
                        // Acknowledge multiplier outputs
                        mul_z_ack[0] <= 1;
                        mul_z_ack[1] <= 1;
                        mul_z_ack[2] <= 1;
                        mul_z_ack[3] <= 1;
                        mul_z_ack[4] <= 1;
                        mul_z_ack[5] <= 1;
                        
                        compute_stage <= 4;
                    end
                end
                
                // Store all 3 results simultaneously
                4: begin
                    if (add_z_stb[0] && add_z_stb[1] && add_z_stb[2]) begin
                        result_c[0] <= add_z[0]; // c0 = a1*b2 - a2*b1
                        result_c[1] <= add_z[1]; // c1 = a2*b0 - a0*b2
                        result_c[2] <= add_z[2]; // c2 = a0*b1 - a1*b0
                        
                        add_z_ack[0] <= 1;
                        add_z_ack[1] <= 1;
                        add_z_ack[2] <= 1;
                        
                        compute_stage <= 5;
                    end
                end
                
                5: begin
                    // Reset all acks
                    mul_z_ack[0] <= 0;
                    mul_z_ack[1] <= 0;
                    mul_z_ack[2] <= 0;
                    mul_z_ack[3] <= 0;
                    mul_z_ack[4] <= 0;
                    mul_z_ack[5] <= 0;
                    add_z_ack[0] <= 0;
                    add_z_ack[1] <= 0;
                    add_z_ack[2] <= 0;
                    
                    computation_done <= 1;
                end
            endcase
            
        end else if (current_state == IDLE) begin
            compute_stage <= 0;
            computation_done <= 0;
            
            for (int k = 0; k < 3; k++) begin
                result_c[k] <= 32'h0;
            end
            
            // Reset multiplier inputs
            for (int k = 0; k < 6; k++) begin
                mul_a[k] <= 32'h0;
                mul_b[k] <= 32'h0;
                mul_a_stb[k] <= 0;
                mul_b_stb[k] <= 0;
                mul_z_ack[k] <= 0;
            end
            
            // Reset adder inputs
            for (int k = 0; k < 3; k++) begin
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