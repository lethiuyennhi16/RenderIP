// module mul4x4_4x4_wrapper (
    // input logic iClk,
    // input logic iRstn,
    // output logic ready,
    // input logic data_valid,
    // input logic [31:0] data,
    // output logic calc_done,
    // output logic [31:0] result,
    // input logic read_done
// );

    // // State machine
    // typedef enum logic [3:0] {
        // IDLE,
        // LOAD_MATRIX_A,
        // LOAD_MATRIX_B, 
        // COMPUTE,
        // OUTPUT_RESULT,
        // WAIT_READ_DONE
    // } state_t;
    
    // state_t current_state, next_state;
    
    // // Matrix storage
    // logic [31:0] matrix_a [0:15]; // 4x4 matrix A
    // logic [31:0] matrix_b [0:15]; // 4x4 matrix B
    // logic [31:0] matrix_c [0:15]; // 4x4 result matrix C
    
    // // Counters
    // logic [4:0] load_counter;
    // logic [4:0] output_counter;
    // logic [2:0] compute_row, compute_col;
    
    // // Multiplier instances (4 multipliers)
    // logic [31:0] mul_a [0:3], mul_b [0:3], mul_z [0:3];
    // logic mul_a_stb [0:3], mul_b_stb [0:3], mul_z_stb [0:3];
    // logic mul_a_ack [0:3], mul_b_ack [0:3], mul_z_ack [0:3];
    
    // // Adder instances (3 adders)
    // logic [31:0] add_a [0:2], add_b [0:2], add_z [0:2];
    // logic add_a_stb [0:2], add_b_stb [0:2], add_z_stb [0:2];
    // logic add_a_ack [0:2], add_b_ack [0:2], add_z_ack [0:2];
    
    // // Generate multiplier instances
    // genvar i;
    // generate
        // for (i = 0; i < 4; i++) begin : gen_multipliers
            // multiplier mul_inst (
                // .clk(iClk),
                // .rst(~iRstn),
                // .input_a(mul_a[i]),
                // .input_a_stb(mul_a_stb[i]),
                // .input_a_ack(mul_a_ack[i]),
                // .input_b(mul_b[i]),
                // .input_b_stb(mul_b_stb[i]),
                // .input_b_ack(mul_b_ack[i]),
                // .output_z(mul_z[i]),
                // .output_z_stb(mul_z_stb[i]),
                // .output_z_ack(mul_z_ack[i])
            // );
        // end
    // endgenerate
    
    // // Generate adder instances
    // generate
        // for (i = 0; i < 3; i++) begin : gen_adders
            // adder add_inst (
                // .clk(iClk),
                // .rst(~iRstn),
                // .input_a(add_a[i]),
                // .input_a_stb(add_a_stb[i]),
                // .input_a_ack(add_a_ack[i]),
                // .input_b(add_b[i]),
                // .input_b_stb(add_b_stb[i]),
                // .input_b_ack(add_b_ack[i]),
                // .output_z(add_z[i]),
                // .output_z_stb(add_z_stb[i]),
                // .output_z_ack(add_z_ack[i])
            // );
        // end
    // endgenerate
    
    // // Computation control
    // logic [3:0] compute_stage; // 0-15: handle all mul/add steps
    // logic computation_done;
    
    // // State machine
    // always_ff @(posedge iClk or negedge iRstn) begin
        // if (!iRstn) begin
            // current_state <= IDLE;
        // end else begin
            // current_state <= next_state;
        // end
    // end
    
    // always_comb begin
        // next_state = current_state;
        // case (current_state)
            // IDLE: begin
                // if (data_valid) next_state = LOAD_MATRIX_A;
            // end
            // LOAD_MATRIX_A: begin
                // if (load_counter == 15) next_state = LOAD_MATRIX_B;
            // end
            // LOAD_MATRIX_B: begin
                // if (load_counter == 15) next_state = COMPUTE;
            // end
            // COMPUTE: begin
                // if (computation_done) next_state = OUTPUT_RESULT;
            // end
            // OUTPUT_RESULT: begin
                // if (output_counter == 15) next_state = WAIT_READ_DONE;
            // end
            // WAIT_READ_DONE: begin
                // if (read_done) next_state = IDLE;
            // end
        // endcase
    // end
    
    // // Load counter
    // always_ff @(posedge iClk or negedge iRstn) begin
        // if (!iRstn) begin
            // load_counter <= 0;
        // end else begin
            // case (current_state)
                // LOAD_MATRIX_A: begin
                    // if (data_valid) begin
                        // if (load_counter == 15) begin
                            // load_counter <= 0; // Reset for next matrix
                        // end else begin
                            // load_counter <= load_counter + 1;
                        // end
                    // end
                // end
                // LOAD_MATRIX_B: begin
                    // if (data_valid) begin
                        // if (load_counter == 15) begin
                            // load_counter <= 0; // Reset for output phase
                        // end else begin
                            // load_counter <= load_counter + 1;
                        // end
                    // end
                // end
                // default: load_counter <= 0;
            // endcase
        // end
    // end
    
    // // Matrix loading
    // always_ff @(posedge iClk or negedge iRstn) begin
        // if (!iRstn) begin
            // for (int j = 0; j < 16; j++) begin
                // matrix_a[j] <= 32'h0;
                // matrix_b[j] <= 32'h0;
                // matrix_c[j] <= 32'h0;
            // end
        // end else begin
            // if (current_state == LOAD_MATRIX_A && data_valid) begin
                // matrix_a[load_counter] <= data;
            // end else if (current_state == LOAD_MATRIX_B && data_valid) begin
                // matrix_b[load_counter] <= data;
            // end
        // end
    // end
    
    // // Computation control
    // always_ff @(posedge iClk or negedge iRstn) begin
        // if (!iRstn) begin
            // compute_row <= 0;
            // compute_col <= 0;
            // compute_stage <= 0;
            // computation_done <= 0;
            
            // // Initialize all strobes to 0
            // for (int k = 0; k < 4; k++) begin
                // mul_a_stb[k] <= 0;
                // mul_b_stb[k] <= 0;
                // mul_z_ack[k] <= 0;
            // end
            // for (int k = 0; k < 3; k++) begin
                // add_a_stb[k] <= 0;
                // add_b_stb[k] <= 0;
                // add_z_ack[k] <= 0;
            // end
            
        // end else if (current_state == COMPUTE) begin
            // case (compute_stage)
                // // Send A values to all 4 multipliers
                // 0: begin // mul0 get_a
                    // mul_a_stb[0] <= 1;
                    // if (mul_a_stb[0] && mul_a_ack[0]) begin
                        // mul_a[0] <= matrix_a[compute_row*4 + 0];
                        // mul_a_stb[0] <= 0;
                        // compute_stage <= 1;
                    // end
                // end
                // 1: begin // mul1 get_a  
                    // mul_a_stb[1] <= 1;
                    // if (mul_a_stb[1] && mul_a_ack[1]) begin
                        // mul_a[1] <= matrix_a[compute_row*4 + 1];
                        // mul_a_stb[1] <= 0;
                        // compute_stage <= 2;
                    // end
                // end
                // 2: begin // mul2 get_a
                    // mul_a_stb[2] <= 1;
                    // if (mul_a_stb[2] && mul_a_ack[2]) begin
                        // mul_a[2] <= matrix_a[compute_row*4 + 2];
                        // mul_a_stb[2] <= 0;
                        // compute_stage <= 3;
                    // end
                // end
                // 3: begin // mul3 get_a
                    // mul_a_stb[3] <= 1;
                    // if (mul_a_stb[3] && mul_a_ack[3]) begin
                        // mul_a[3] <= matrix_a[compute_row*4 + 3];
                        // mul_a_stb[3] <= 0;
                        // compute_stage <= 4;
                    // end
                // end
                
                // // Send B values to all 4 multipliers
                // 4: begin // mul0 get_b
                    // mul_b_stb[0] <= 1;
                    // if (mul_b_stb[0] && mul_b_ack[0]) begin
                        // mul_b[0] <= matrix_b[0*4 + compute_col];
                        // mul_b_stb[0] <= 0;
                        // compute_stage <= 5;
                    // end
                // end
                // 5: begin // mul1 get_b
                    // mul_b_stb[1] <= 1;
                    // if (mul_b_stb[1] && mul_b_ack[1]) begin
                        // mul_b[1] <= matrix_b[1*4 + compute_col];
                        // mul_b_stb[1] <= 0;
                        // compute_stage <= 6;
                    // end
                // end
                // 6: begin // mul2 get_b
                    // mul_b_stb[2] <= 1;
                    // if (mul_b_stb[2] && mul_b_ack[2]) begin
                        // mul_b[2] <= matrix_b[2*4 + compute_col];
                        // mul_b_stb[2] <= 0;
                        // compute_stage <= 7;
                    // end
                // end
                // 7: begin // mul3 get_b
                    // mul_b_stb[3] <= 1;
                    // if (mul_b_stb[3] && mul_b_ack[3]) begin
                        // mul_b[3] <= matrix_b[3*4 + compute_col];
                        // mul_b_stb[3] <= 0;
                        // compute_stage <= 8;
                    // end
                // end
                
                // // Wait for all multipliers and start parallel adds
                // 8: begin // Wait for all muls done, start add0 get_a
                    // if (mul_z_stb[0] && mul_z_stb[1] && mul_z_stb[2] && mul_z_stb[3]) begin
                        // add_a_stb[0] <= 1;
                        // if (add_a_stb[0] && add_a_ack[0]) begin
                            // add_a[0] <= mul_z[0];
                            // add_a_stb[0] <= 0;
                            // compute_stage <= 9;
                        // end
                    // end
                // end
                // 9: begin // add0 get_b
                    // add_b_stb[0] <= 1;
                    // if (add_b_stb[0] && add_b_ack[0]) begin
                        // add_b[0] <= mul_z[1];
                        // add_b_stb[0] <= 0;
                        // mul_z_ack[0] <= 1;
                        // mul_z_ack[1] <= 1;
                        // compute_stage <= 10;
                    // end
                // end
                // 10: begin // add1 get_a
                    // add_a_stb[1] <= 1;
                    // if (add_a_stb[1] && add_a_ack[1]) begin
                        // add_a[1] <= mul_z[2];
                        // add_a_stb[1] <= 0;
                        // compute_stage <= 11;
                    // end
                // end
                // 11: begin // add1 get_b
                    // add_b_stb[1] <= 1;
                    // if (add_b_stb[1] && add_b_ack[1]) begin
                        // add_b[1] <= mul_z[3];
                        // add_b_stb[1] <= 0;
                        // mul_z_ack[2] <= 1;
                        // mul_z_ack[3] <= 1;
                        // compute_stage <= 12;
                    // end
                // end
                
                // // Final addition
                // 12: begin // Wait for add0,add1 done, start add2 get_a
                    // if (add_z_stb[0] && add_z_stb[1]) begin
                        // add_a_stb[2] <= 1;
                        // if (add_a_stb[2] && add_a_ack[2]) begin
                            // add_a[2] <= add_z[0];
                            // add_a_stb[2] <= 0;
                            // compute_stage <= 13;
                        // end
                    // end
                // end
                // 13: begin // add2 get_b
                    // add_b_stb[2] <= 1;
                    // if (add_b_stb[2] && add_b_ack[2]) begin
                        // add_b[2] <= add_z[1];
                        // add_b_stb[2] <= 0;
                        // add_z_ack[0] <= 1;
                        // add_z_ack[1] <= 1;
                        // compute_stage <= 14;
                    // end
                // end
                // 14: begin // Wait for final result
                    // if (add_z_stb[2]) begin
                        // matrix_c[compute_row*4 + compute_col] <= add_z[2];
                        // add_z_ack[2] <= 1;
                        // compute_stage <= 15;
                    // end
                // end
                // 15: begin // Move to next element
                    // // Reset all acks
                    // for (int k = 0; k < 4; k++) begin
                        // mul_z_ack[k] <= 0;
                    // end
                    // for (int k = 0; k < 3; k++) begin
                        // add_z_ack[k] <= 0;
                    // end
                    
                    // // Move to next element
                    // if (compute_col == 3) begin
                        // compute_col <= 0;
                        // if (compute_row == 3) begin
                            // computation_done <= 1;
                        // end else begin
                            // compute_row <= compute_row + 1;
                        // end
                    // end else begin
                        // compute_col <= compute_col + 1;
                    // end
                    
                    // compute_stage <= 0;
                // end
            // endcase
            
        // end else if (current_state == IDLE) begin
            // compute_row <= 0;
            // compute_col <= 0;
            // compute_stage <= 0;
            // computation_done <= 0;
            
            // // Reset matrix_c
            // for (int k = 0; k < 16; k++) begin
                // matrix_c[k] <= 32'h0;
            // end
            
            // // Reset all acks and strobes
            // for (int k = 0; k < 4; k++) begin
                // mul_a_stb[k] <= 0;
                // mul_b_stb[k] <= 0;
                // mul_z_ack[k] <= 0;
            // end
            // for (int k = 0; k < 3; k++) begin
                // add_a_stb[k] <= 0;
                // add_b_stb[k] <= 0;
                // add_z_ack[k] <= 0;
            // end
        // end
    // end
    
    // // Output counter and result
    // always_ff @(posedge iClk or negedge iRstn) begin
        // if (!iRstn) begin
            // output_counter <= 0;
        // end else if (current_state == OUTPUT_RESULT) begin
            // output_counter <= output_counter + 1;
        // end else begin
            // output_counter <= 0;
        // end
    // end
    
    // // Output assignments
    // always_comb begin
        // ready = (current_state == IDLE);
        // calc_done = (current_state == OUTPUT_RESULT);
        // result = (current_state == OUTPUT_RESULT) ? matrix_c[output_counter] : 32'h0;
    // end

// endmodule
// module mul4x4_4x4_wrapper (
    // input logic iClk,
    // input logic iRstn,
    // output logic ready,
    // input logic data_valid,
    // input logic [31:0] data,
    // output logic calc_done,
    // output logic [31:0] result,
    // input logic read_done
// );

    // // State machine
    // typedef enum logic [3:0] {
        // IDLE,
        // LOAD_MATRIX_A,
        // LOAD_MATRIX_B, 
        // COMPUTE,
        // OUTPUT_RESULT,
        // WAIT_READ_DONE
    // } state_t;
    
    // state_t current_state, next_state;
    
    // // Matrix storage
    // logic [31:0] matrix_a [0:15];
    // logic [31:0] matrix_b [0:15];
    // logic [31:0] matrix_c [0:15];
    
    // // Counters
    // logic [4:0] load_counter;
    // logic [4:0] output_counter;
    // logic [2:0] compute_row, compute_col;
    
    // // Multiplier instances (4 multipliers)
    // logic [31:0] mul_a [0:3], mul_b [0:3], mul_z [0:3];
    // logic mul_a_stb [0:3], mul_b_stb [0:3], mul_z_stb [0:3];
    // logic mul_a_ack [0:3], mul_b_ack [0:3], mul_z_ack [0:3];
    
    // // Adder instances (3 adders)
    // logic [31:0] add_a [0:2], add_b [0:2], add_z [0:2];
    // logic add_a_stb [0:2], add_b_stb [0:2], add_z_stb [0:2];
    // logic add_a_ack [0:2], add_b_ack [0:2], add_z_ack [0:2];
    
    // // Generate multiplier instances
    // genvar i;
    // generate
        // for (i = 0; i < 4; i++) begin : gen_multipliers
            // multiplier mul_inst (
                // .clk(iClk),
                // .rst(~iRstn),
                // .input_a(mul_a[i]),
                // .input_a_stb(mul_a_stb[i]),
                // .input_a_ack(mul_a_ack[i]),
                // .input_b(mul_b[i]),
                // .input_b_stb(mul_b_stb[i]),
                // .input_b_ack(mul_b_ack[i]),
                // .output_z(mul_z[i]),
                // .output_z_stb(mul_z_stb[i]),
                // .output_z_ack(mul_z_ack[i])
            // );
        // end
    // endgenerate
    
    // // Generate adder instances
    // generate
        // for (i = 0; i < 3; i++) begin : gen_adders
            // adder add_inst (
                // .clk(iClk),
                // .rst(~iRstn),
                // .input_a(add_a[i]),
                // .input_a_stb(add_a_stb[i]),
                // .input_a_ack(add_a_ack[i]),
                // .input_b(add_b[i]),
                // .input_b_stb(add_b_stb[i]),
                // .input_b_ack(add_b_ack[i]),
                // .output_z(add_z[i]),
                // .output_z_stb(add_z_stb[i]),
                // .output_z_ack(add_z_ack[i])
            // );            
        // end
    // endgenerate
    
    // // Computation control
    // logic [3:0] compute_stage;
    // logic computation_done;
    
    // // State machine
    // always_ff @(posedge iClk or negedge iRstn) begin
        // if (!iRstn) begin
            // current_state <= IDLE;
        // end else begin
            // current_state <= next_state;
        // end
    // end
    
    // always_comb begin
        // next_state = current_state;
        // case (current_state)
            // IDLE: begin
                // if (data_valid) next_state = LOAD_MATRIX_A;
            // end
            // LOAD_MATRIX_A: begin
                // if (load_counter == 15) next_state = LOAD_MATRIX_B;
            // end
            // LOAD_MATRIX_B: begin
                // if (load_counter == 15) next_state = COMPUTE;
            // end
            // COMPUTE: begin
                // if (computation_done) next_state = OUTPUT_RESULT;
            // end
            // OUTPUT_RESULT: begin
                // if (output_counter == 15) next_state = WAIT_READ_DONE;
            // end
            // WAIT_READ_DONE: begin
                // if (read_done) next_state = IDLE;
            // end
        // endcase
    // end
    
    // // Load counter
    // always_ff @(posedge iClk or negedge iRstn) begin
        // if (!iRstn) begin
            // load_counter <= 0;
        // end else begin
            // case (current_state)
                // LOAD_MATRIX_A: begin
                    // if (data_valid) begin
                        // if (load_counter == 15) begin
                            // load_counter <= 0;
                        // end else begin
                            // load_counter <= load_counter + 1;
                        // end
                    // end
                // end
                // LOAD_MATRIX_B: begin
                    // if (data_valid) begin
                        // if (load_counter == 15) begin
                            // load_counter <= 0;
                        // end else begin
                            // load_counter <= load_counter + 1;
                        // end
                    // end
                // end
                // default: load_counter <= 0;
            // endcase
        // end
    // end
    
    // // Matrix loading
    // always_ff @(posedge iClk or negedge iRstn) begin
        // if (!iRstn) begin
            // for (int j = 0; j < 16; j++) begin
                // matrix_a[j] <= 32'h0;
                // matrix_b[j] <= 32'h0;
                // matrix_c[j] <= 32'h0;
            // end
        // end else begin
            // if (current_state == LOAD_MATRIX_A && data_valid) begin
                // matrix_a[load_counter] <= data;
            // end else if (current_state == LOAD_MATRIX_B && data_valid) begin
                // matrix_b[load_counter] <= data;
            // end
        // end
    // end
    
    // // Simple parallel computation - just change from 16 sequential to 8 parallel stages
    // always_ff @(posedge iClk or negedge iRstn) begin
        // if (!iRstn) begin
            // compute_row <= 0;
            // compute_col <= 0;
            // compute_stage <= 0;
            // computation_done <= 0;
            
            // for (int k = 0; k < 4; k++) begin
                // mul_a_stb[k] <= 0;
                // mul_b_stb[k] <= 0;
                // mul_z_ack[k] <= 0;
            // end
            // for (int k = 0; k < 3; k++) begin
                // add_a_stb[k] <= 0;
                // add_b_stb[k] <= 0;
                // add_z_ack[k] <= 0;
            // end
            
        // end else if (current_state == COMPUTE) begin
            // case (compute_stage)
                // // Send A to all 4 multipliers in parallel
                // 0: begin 
                    // mul_a_stb[0] <= 1;
                    // mul_a_stb[1] <= 1;
                    // mul_a_stb[2] <= 1;
                    // mul_a_stb[3] <= 1;
                    // if (mul_a_stb[0] && mul_a_ack[0] && 
                        // mul_a_stb[1] && mul_a_ack[1] && 
                        // mul_a_stb[2] && mul_a_ack[2] && 
                        // mul_a_stb[3] && mul_a_ack[3]) begin
                        // mul_a[0] <= matrix_a[compute_row*4 + 0];
                        // mul_a[1] <= matrix_a[compute_row*4 + 1];
                        // mul_a[2] <= matrix_a[compute_row*4 + 2];
                        // mul_a[3] <= matrix_a[compute_row*4 + 3];
                        // mul_a_stb[0] <= 0;
                        // mul_a_stb[1] <= 0;
                        // mul_a_stb[2] <= 0;
                        // mul_a_stb[3] <= 0;
                        // compute_stage <= 1;
                    // end
                // end
                
                // // Send B to all 4 multipliers in parallel  
                // 1: begin
                    // mul_b_stb[0] <= 1;
                    // mul_b_stb[1] <= 1;
                    // mul_b_stb[2] <= 1;
                    // mul_b_stb[3] <= 1;
                    // if (mul_b_stb[0] && mul_b_ack[0] && 
                        // mul_b_stb[1] && mul_b_ack[1] && 
                        // mul_b_stb[2] && mul_b_ack[2] && 
                        // mul_b_stb[3] && mul_b_ack[3]) begin
                        // mul_b[0] <= matrix_b[0*4 + compute_col];
                        // mul_b[1] <= matrix_b[1*4 + compute_col];
                        // mul_b[2] <= matrix_b[2*4 + compute_col];
                        // mul_b[3] <= matrix_b[3*4 + compute_col];
                        // mul_b_stb[0] <= 0;
                        // mul_b_stb[1] <= 0;
                        // mul_b_stb[2] <= 0;
                        // mul_b_stb[3] <= 0;
                        // compute_stage <= 2;
                    // end
                // end
                
                // // Send to first 2 adders in parallel
                // 2: begin
                    // if (mul_z_stb[0] && mul_z_stb[1] && mul_z_stb[2] && mul_z_stb[3]) begin
                        // add_a_stb[0] <= 1;
                        // add_a_stb[1] <= 1;
                        // if (add_a_stb[0] && add_a_ack[0] && add_a_stb[1] && add_a_ack[1]) begin
                            // add_a[0] <= mul_z[0];
                            // add_a[1] <= mul_z[2];
                            // add_a_stb[0] <= 0;
                            // add_a_stb[1] <= 0;
                            // compute_stage <= 3;
                        // end
                    // end
                // end
                
                // 3: begin
                    // add_b_stb[0] <= 1;
                    // add_b_stb[1] <= 1;
                    // if (add_b_stb[0] && add_b_ack[0] && add_b_stb[1] && add_b_ack[1]) begin
                        // add_b[0] <= mul_z[1];
                        // add_b[1] <= mul_z[3];
                        // add_b_stb[0] <= 0;
                        // add_b_stb[1] <= 0;
                        // mul_z_ack[0] <= 1;
                        // mul_z_ack[1] <= 1;
                        // mul_z_ack[2] <= 1;
                        // mul_z_ack[3] <= 1;
                        // compute_stage <= 4;
                    // end
                // end
                
                // // Final adder
                // 4: begin
                    // if (add_z_stb[0] && add_z_stb[1]) begin
                        // add_a_stb[2] <= 1;
                        // if (add_a_stb[2] && add_a_ack[2]) begin
                            // add_a[2] <= add_z[0];
                            // add_a_stb[2] <= 0;
                            // compute_stage <= 5;
                        // end
                    // end
                // end
                
                // 5: begin
                    // add_b_stb[2] <= 1;
                    // if (add_b_stb[2] && add_b_ack[2]) begin
                        // add_b[2] <= add_z[1];
                        // add_b_stb[2] <= 0;
                        // add_z_ack[0] <= 1;
                        // add_z_ack[1] <= 1;
                        // compute_stage <= 6;
                    // end
                // end
                
                // 6: begin
                    // if (add_z_stb[2]) begin
                        // matrix_c[compute_row*4 + compute_col] <= add_z[2];
                        // add_z_ack[2] <= 1;
                        // compute_stage <= 7;
                    // end
                // end
                
                // 7: begin
                    // // Reset acks
                    // mul_z_ack[0] <= 0;
                    // mul_z_ack[1] <= 0;
                    // mul_z_ack[2] <= 0;
                    // mul_z_ack[3] <= 0;
                    // add_z_ack[0] <= 0;
                    // add_z_ack[1] <= 0;
                    // add_z_ack[2] <= 0;
                    
                    // // Next element
                    // if (compute_col == 3) begin
                        // compute_col <= 0;
                        // if (compute_row == 3) begin
                            // computation_done <= 1;
                        // end else begin
                            // compute_row <= compute_row + 1;
                        // end
                    // end else begin
                        // compute_col <= compute_col + 1;
                    // end
                    
                    // compute_stage <= 0;
                // end
            // endcase
            
        // end else if (current_state == IDLE) begin
            // compute_row <= 0;
            // compute_col <= 0;
            // compute_stage <= 0;
            // computation_done <= 0;
            
            // for (int k = 0; k < 16; k++) begin
                // matrix_c[k] <= 32'h0;
            // end
            
            // for (int k = 0; k < 4; k++) begin
                // mul_a_stb[k] <= 0;
                // mul_b_stb[k] <= 0;
                // mul_z_ack[k] <= 0;
            // end
            // for (int k = 0; k < 3; k++) begin
                // add_a_stb[k] <= 0;
                // add_b_stb[k] <= 0;
                // add_z_ack[k] <= 0;
            // end
        // end
    // end
    
    // // Output counter and result
    // always_ff @(posedge iClk or negedge iRstn) begin
        // if (!iRstn) begin
            // output_counter <= 0;
        // end else if (current_state == OUTPUT_RESULT) begin
            // output_counter <= output_counter + 1;
        // end else begin
            // output_counter <= 0;
        // end
    // end
    
    // // Output assignments
    // always_comb begin
        // ready = (current_state == IDLE);
        // calc_done = (current_state == OUTPUT_RESULT);
        // result = (current_state == OUTPUT_RESULT) ? matrix_c[output_counter] : 32'h0;
    // end

// endmodule
module mul4x4_4x4_wrapper (
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
        LOAD_MATRIX_A,
        LOAD_MATRIX_B, 
        COMPUTE,
        OUTPUT_RESULT,
        WAIT_READ_DONE
    } state_t;
    
    state_t current_state, next_state;
    
    // Matrix storage
    logic [31:0] matrix_a [0:15];
    logic [31:0] matrix_b [0:15];
    logic [31:0] matrix_c [0:15];
    
    // Counters
    logic [4:0] load_counter;
    logic [4:0] output_counter;
    logic [2:0] compute_row, compute_col;
    
    // Multiplier instances (4 multipliers)
    logic [31:0] mul_a [0:3], mul_b [0:3], mul_z [0:3];
    logic mul_a_stb [0:3], mul_b_stb [0:3], mul_z_stb [0:3];
    logic mul_a_ack [0:3], mul_b_ack [0:3], mul_z_ack [0:3];
    
    // Adder instances (3 adders)
    logic [31:0] add_a [0:2], add_b [0:2], add_z [0:2];
    logic add_a_stb [0:2], add_b_stb [0:2], add_z_stb [0:2];
    logic add_a_ack [0:2], add_b_ack [0:2], add_z_ack [0:2];
    
    // Generate multiplier instances
    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : gen_multipliers
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
    logic [7:0] wait_counter; // Add wait counter for computation delay
    
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
                if (data_valid) next_state = LOAD_MATRIX_A;
            end
            LOAD_MATRIX_A: begin
                if (load_counter == 15) next_state = LOAD_MATRIX_B;
            end
            LOAD_MATRIX_B: begin
                if (load_counter == 15) next_state = COMPUTE;
            end
            COMPUTE: begin
                if (computation_done) next_state = OUTPUT_RESULT;
            end
            OUTPUT_RESULT: begin
                if (output_counter == 15) next_state = WAIT_READ_DONE;
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
                LOAD_MATRIX_A: begin
                    if (data_valid) begin
                        if (load_counter == 15) begin
                            load_counter <= 0;
                        end else begin
                            load_counter <= load_counter + 1;
                        end
                    end
                end
                LOAD_MATRIX_B: begin
                    if (data_valid) begin
                        if (load_counter == 15) begin
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
    
    // Matrix loading
    always_ff @(posedge iClk or negedge iRstn) begin
        if (!iRstn) begin
            for (int j = 0; j < 16; j++) begin
                matrix_a[j] <= 32'h0;
                matrix_b[j] <= 32'h0;
                matrix_c[j] <= 32'h0;
            end
        end else begin
            if (current_state == LOAD_MATRIX_A && data_valid) begin
                matrix_a[load_counter] <= data;
            end else if (current_state == LOAD_MATRIX_B && data_valid) begin
                matrix_b[load_counter] <= data;
            end
        end
    end
    
    // Simple parallel computation - just change from 16 sequential to 8 parallel stages
    always_ff @(posedge iClk or negedge iRstn) begin
        if (!iRstn) begin
            compute_row <= 0;
            compute_col <= 0;
            compute_stage <= 0;
            computation_done <= 0;
            wait_counter <= 0;
            
            // Initialize multiplier inputs
            for (int k = 0; k < 4; k++) begin
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
                // Send A to all 4 multipliers in parallel
                0: begin 
                    // Set data first, then start handshake
                    mul_a[0] <= matrix_a[compute_row*4 + 0];
                    mul_a[1] <= matrix_a[compute_row*4 + 1];
                    mul_a[2] <= matrix_a[compute_row*4 + 2];
                    mul_a[3] <= matrix_a[compute_row*4 + 3];
                    
                    mul_a_stb[0] <= 1;
                    mul_a_stb[1] <= 1;
                    mul_a_stb[2] <= 1;
                    mul_a_stb[3] <= 1;
                    
                    if (mul_a_stb[0] && mul_a_ack[0] && 
                        mul_a_stb[1] && mul_a_ack[1] && 
                        mul_a_stb[2] && mul_a_ack[2] && 
                        mul_a_stb[3] && mul_a_ack[3]) begin
                        mul_a_stb[0] <= 0;
                        mul_a_stb[1] <= 0;
                        mul_a_stb[2] <= 0;
                        mul_a_stb[3] <= 0;
                        compute_stage <= 1;
                    end
                end
                
                // Send B to all 4 multipliers in parallel  
                1: begin
                    // Set data first, then start handshake
                    mul_b[0] <= matrix_b[0*4 + compute_col];
                    mul_b[1] <= matrix_b[1*4 + compute_col];
                    mul_b[2] <= matrix_b[2*4 + compute_col];
                    mul_b[3] <= matrix_b[3*4 + compute_col];
                    
                    mul_b_stb[0] <= 1;
                    mul_b_stb[1] <= 1;
                    mul_b_stb[2] <= 1;
                    mul_b_stb[3] <= 1;
                    
                    if (mul_b_stb[0] && mul_b_ack[0] && 
                        mul_b_stb[1] && mul_b_ack[1] && 
                        mul_b_stb[2] && mul_b_ack[2] && 
                        mul_b_stb[3] && mul_b_ack[3]) begin
                        mul_b_stb[0] <= 0;
                        mul_b_stb[1] <= 0;
                        mul_b_stb[2] <= 0;
                        mul_b_stb[3] <= 0;
                        wait_counter <= 0;
                        compute_stage <= 2;
                    end
                end
                
                // Wait for multipliers to compute, then send to adders
                2: begin
                    if (mul_z_stb[0] && mul_z_stb[1] && mul_z_stb[2] && mul_z_stb[3]) begin
                        // Set data first, then start handshake
                        add_a[0] <= mul_z[0];
                        add_a[1] <= mul_z[2];
                        
                        add_a_stb[0] <= 1;
                        add_a_stb[1] <= 1;
                        
                        if (add_a_stb[0] && add_a_ack[0] && add_a_stb[1] && add_a_ack[1]) begin
                            add_a_stb[0] <= 0;
                            add_a_stb[1] <= 0;
                            compute_stage <= 3;
                        end
                    end
                end
                
                3: begin
                    // Set data first, then start handshake
                    add_b[0] <= mul_z[1];
                    add_b[1] <= mul_z[3];
                    
                    add_b_stb[0] <= 1;
                    add_b_stb[1] <= 1;
                    
                    if (add_b_stb[0] && add_b_ack[0] && add_b_stb[1] && add_b_ack[1]) begin
                        add_b_stb[0] <= 0;
                        add_b_stb[1] <= 0;
                        mul_z_ack[0] <= 1;
                        mul_z_ack[1] <= 1;
                        mul_z_ack[2] <= 1;
                        mul_z_ack[3] <= 1;
                        wait_counter <= 0;
                        compute_stage <= 4;
                    end
                end
                
                // Wait for first level adders, then final adder
                4: begin
                    if (add_z_stb[0] && add_z_stb[1]) begin
                        // Set data first, then start handshake
                        add_a[2] <= add_z[0];
                        add_a_stb[2] <= 1;
                        
                        if (add_a_stb[2] && add_a_ack[2]) begin
                            add_a_stb[2] <= 0;
                            compute_stage <= 5;
                        end
                    end
                end
                
                5: begin
                    // Set data first, then start handshake
                    add_b[2] <= add_z[1];
                    add_b_stb[2] <= 1;
                    
                    if (add_b_stb[2] && add_b_ack[2]) begin
                        add_b_stb[2] <= 0;
                        add_z_ack[0] <= 1;
                        add_z_ack[1] <= 1;
                        wait_counter <= 0;
                        compute_stage <= 6;
                    end
                end
                
                // Wait for final result
                6: begin
                    if (add_z_stb[2]) begin
                        matrix_c[compute_row*4 + compute_col] <= add_z[2];
                        add_z_ack[2] <= 1;
                        compute_stage <= 7;
                    end
                end
                
                6: begin
                    if (add_z_stb[2]) begin
                        matrix_c[compute_row*4 + compute_col] <= add_z[2];
                        add_z_ack[2] <= 1;
                        compute_stage <= 7;
                    end
                end
                
                7: begin
                    // Reset acks
                    mul_z_ack[0] <= 0;
                    mul_z_ack[1] <= 0;
                    mul_z_ack[2] <= 0;
                    mul_z_ack[3] <= 0;
                    add_z_ack[0] <= 0;
                    add_z_ack[1] <= 0;
                    add_z_ack[2] <= 0;
                    
                    // Next element
                    if (compute_col == 3) begin
                        compute_col <= 0;
                        if (compute_row == 3) begin
                            computation_done <= 1;
                        end else begin
                            compute_row <= compute_row + 1;
                        end
                    end else begin
                        compute_col <= compute_col + 1;
                    end
                    
                    compute_stage <= 0;
                end
            endcase
            
        end else if (current_state == IDLE) begin
            compute_row <= 0;
            compute_col <= 0;
            compute_stage <= 0;
            computation_done <= 0;
            wait_counter <= 0;
            
            for (int k = 0; k < 16; k++) begin
                matrix_c[k] <= 32'h0;
            end
            
            // Reset multiplier inputs
            for (int k = 0; k < 4; k++) begin
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
        result = (current_state == OUTPUT_RESULT) ? matrix_c[output_counter] : 32'h0;
    end

endmodule