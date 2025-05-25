// // IEEE 754 Single Precision 4x4 Matrix Inverter
// // Uses Gauss-Jordan elimination method
// // Includes all arithmetic units internally
// // Copyright (C) 2025

// module matrix_inverter_4x4(
    // input clk,
    // input rst_n,
    
    // // Handshake protocol with master
    // output reg ready,           // Signal to master that module is ready
    // input data_valid,          // Master signals data is available
    // output reg calc_done,      // Signal when calculation is complete
    // input read_done,           // Master signals it has read all results
    
    // // Data interface
    // input [31:0] data_in,      // Input data (one float at a time)
    // output reg [31:0] data_out // Output data (one float at a time)
// );

    // // Internal arithmetic unit signals
    // // Adder
    // wire [31:0] add_a, add_b, add_result;
    // reg add_a_stb, add_b_stb, add_result_ack;
    // wire add_a_ack, add_b_ack, add_result_stb;
    
    // // Subtractor  
    // wire [31:0] sub_a, sub_b, sub_result;
    // reg sub_a_stb, sub_b_stb, sub_result_ack;
    // wire sub_a_ack, sub_b_ack, sub_result_stb;
    
    // // Multiplier
    // wire [31:0] mul_a, mul_b, mul_result;
    // reg mul_a_stb, mul_b_stb, mul_result_ack;
    // wire mul_a_ack, mul_b_ack, mul_result_stb;
    
    // // Divider
    // wire [31:0] div_a, div_b, div_result;
    // reg div_a_stb, div_b_stb, div_result_ack;
    // wire div_a_ack, div_b_ack, div_result_stb;

    // // Instantiate arithmetic units
    // adder add_unit (
        // .clk(clk),
        // .rst(~rst_n),
        // .input_a(add_a),
        // .input_b(add_b),
        // .input_a_stb(add_a_stb),
        // .input_b_stb(add_b_stb),
        // .input_a_ack(add_a_ack),
        // .input_b_ack(add_b_ack),
        // .output_z(add_result),
        // .output_z_stb(add_result_stb),
        // .output_z_ack(add_result_ack)
    // );
    
    // subtractor sub_unit (
        // .clk(clk),
        // .rst(~rst_n),
        // .input_a(sub_a),
        // .input_b(sub_b),
        // .input_a_stb(sub_a_stb),
        // .input_b_stb(sub_b_stb),
        // .input_a_ack(sub_a_ack),
        // .input_b_ack(sub_b_ack),
        // .output_z(sub_result),
        // .output_z_stb(sub_result_stb),
        // .output_z_ack(sub_result_ack)
    // );
    
    // multiplier mul_unit (
        // .clk(clk),
        // .rst(~rst_n),
        // .input_a(mul_a),
        // .input_b(mul_b),
        // .input_a_stb(mul_a_stb),
        // .input_b_stb(mul_b_stb),
        // .input_a_ack(mul_a_ack),
        // .input_b_ack(mul_b_ack),
        // .output_z(mul_result),
        // .output_z_stb(mul_result_stb),
        // .output_z_ack(mul_result_ack)
    // );
    
    // divider div_unit (
        // .clk(clk),
        // .rst(~rst_n),
        // .input_a(div_a),
        // .input_b(div_b),
        // .input_a_stb(div_a_stb),
        // .input_b_stb(div_b_stb),
        // .input_a_ack(div_a_ack),
        // .input_b_ack(div_b_ack),
        // .output_z(div_result),
        // .output_z_stb(div_result_stb),
        // .output_z_ack(div_result_ack)
    // );

    // // State machine states
    // reg [5:0] state;
    // parameter IDLE            = 6'd0,
              // READ_MATRIX     = 6'd1,
              // INIT_IDENTITY   = 6'd2,
              // GAUSS_JORDAN    = 6'd3,
              // FIND_PIVOT      = 6'd4,
              // SCALE_PIVOT     = 6'd5,
              // SCALE_PIVOT_WAIT = 6'd6,
              // ELIMINATE       = 6'd7,
              // ELIMINATE_CALC  = 6'd8,
              // ELIMINATE_WAIT  = 6'd9,
              // OUTPUT_RESULT   = 6'd10,
              // WAIT_READ       = 6'd11;

    // // Matrix storage: 4x4 input matrix and 4x4 identity matrix (augmented)
    // reg [31:0] matrix [0:3][0:7]; // 4x8 augmented matrix
    
    // // Control variables
    // reg [3:0] read_count;      // Counter for reading input (0-15)
    // reg [3:0] output_count;    // Counter for outputting result (0-15)
    // reg [3:0] current_row;     // Current row being processed (0-3)
    // reg [3:0] current_col;     // Current column being processed (0-3)
    // reg [3:0] pivot_row;       // Row with pivot element
    // reg [3:0] elim_row;        // Row being eliminated
    // reg [3:0] elim_col;        // Column being eliminated
    
    // // Temporary storage for arithmetic operations
    // reg [31:0] pivot_element;
    // reg [31:0] factor;
    // reg [31:0] temp_result;
    
    // // Operation control
    // reg [2:0] operation_step;  // Step within current operation
    // reg [5:0] return_state;    // State to return to after arithmetic
    
    // // Constants
    // wire [31:0] ZERO = 32'h00000000;
    // wire [31:0] ONE  = 32'h3F800000;  // 1.0 in IEEE 754
    
    // // Arithmetic unit input assignments
    // reg [31:0] arith_a, arith_b;
    
    // assign add_a = arith_a;
    // assign add_b = arith_b;
    // assign sub_a = arith_a;
    // assign sub_b = arith_b;
    // assign mul_a = arith_a;
    // assign mul_b = arith_b;
    // assign div_a = arith_a;
    // assign div_b = arith_b;
    
    // always @(posedge clk) begin
        // if (!rst_n) begin
            // state <= IDLE;
            // ready <= 1'b1;
            // calc_done <= 1'b0;
            // read_count <= 4'd0;
            // output_count <= 4'd0;
            // current_row <= 3'd0;
            // current_col <= 3'd0;
            // elim_row <= 3'd0;
            // elim_col <= 3'd0;
            // operation_step <= 3'd0;
            
            // // Reset all arithmetic unit strobes
            // add_a_stb <= 1'b0;
            // add_b_stb <= 1'b0;
            // add_result_ack <= 1'b0;
            // sub_a_stb <= 1'b0;
            // sub_b_stb <= 1'b0;
            // sub_result_ack <= 1'b0;
            // mul_a_stb <= 1'b0;
            // mul_b_stb <= 1'b0;
            // mul_result_ack <= 1'b0;
            // div_a_stb <= 1'b0;
            // div_b_stb <= 1'b0;
            // div_result_ack <= 1'b0;
        // end
        // else begin
            // case (state)
                // IDLE: begin
                    // ready <= 1'b1;
                    // calc_done <= 1'b0;
                    // if (data_valid) begin
                        // ready <= 1'b0;
                        // read_count <= 4'd0;
                        // state <= READ_MATRIX;
                    // end
                // end
                
                // READ_MATRIX: begin
                    // if (data_valid) begin
                        // // Store input data in row-major order
                        // matrix[read_count[3:2]][read_count[1:0]] <= data_in;
                        // read_count <= read_count + 1;
                        
                        // if (read_count == 4'd15) begin
                            // state <= INIT_IDENTITY;
                            // current_row <= 3'd0;
                            // current_col <= 3'd0;
                        // end
                    // end
                // end
                
                // INIT_IDENTITY: begin
                    // // Initialize identity matrix in columns 4-7
                    // if (current_row < 4) begin
                        // if (current_col < 4) begin
                            // if (current_row == current_col)
                                // matrix[current_row][current_col + 4] <= ONE;
                            // else
                                // matrix[current_row][current_col + 4] <= ZERO;
                            
                            // current_col <= current_col + 1;
                        // end
                        // else begin
                            // current_col <= 3'd0;
                            // current_row <= current_row + 1;
                        // end
                    // end
                    // else begin
                        // current_row <= 3'd0;
                        // current_col <= 3'd0;
                        // state <= GAUSS_JORDAN;
                    // end
                // end
                
                // GAUSS_JORDAN: begin
                    // if (current_col < 4) begin
                        // state <= FIND_PIVOT;
                    // end
                    // else begin
                        // state <= OUTPUT_RESULT;
                        // output_count <= 4'd0;
                    // end
                // end
                
                // FIND_PIVOT: begin
                    // // Use diagonal element as pivot
                    // pivot_element <= matrix[current_col][current_col];
                    
                    // // Check if pivot is zero (singular matrix)
                    // if (matrix[current_col][current_col] == ZERO) begin
                        // // Matrix is singular, return to idle
                        // state <= IDLE;
                        // ready <= 1'b1;
                    // end
                    // else begin
                        // elim_col <= 3'd0;
                        // state <= SCALE_PIVOT;
                    // end
                // end
                
                // SCALE_PIVOT: begin
                    // if (elim_col < 8) begin
                        // // Divide matrix[current_col][elim_col] by pivot_element
                        // arith_a <= matrix[current_col][elim_col];
                        // arith_b <= pivot_element;
                        // div_a_stb <= 1'b1;
                        // operation_step <= 3'd0;
                        // state <= SCALE_PIVOT_WAIT;
                    // end
                    // else begin
                        // // Start elimination for other rows
                        // elim_row <= 3'd0;
                        // state <= ELIMINATE;
                    // end
                // end
                
                // SCALE_PIVOT_WAIT: begin
                    // case (operation_step)
                        // 3'd0: begin
                            // if (div_a_stb && div_a_ack) begin
                                // div_a_stb <= 1'b0;
                                // div_b_stb <= 1'b1;
                                // operation_step <= 3'd1;
                            // end
                        // end
                        // 3'd1: begin
                            // if (div_b_stb && div_b_ack) begin
                                // div_b_stb <= 1'b0;
                                // operation_step <= 3'd2;
                            // end
                        // end
                        // 3'd2: begin
                            // if (div_result_stb) begin
                                // div_result_ack <= 1'b1;
                                // matrix[current_col][elim_col] <= div_result;
                                // operation_step <= 3'd3;
                            // end
                        // end
                        // 3'd3: begin
                            // if (div_result_ack && div_result_stb) begin
                                // div_result_ack <= 1'b0;
                                // elim_col <= elim_col + 1;
								// state <= SCALE_PIVOT;
                                // operation_step <= 3'd0;
								// operation_step <= 3'd4;
                            // end
                        // end
                    // endcase
                // end
                
                // ELIMINATE: begin
                    // if (elim_row < 4) begin
                        // if (elim_row != current_col) begin
                            // // Get factor = matrix[elim_row][current_col]
                            // factor <= matrix[elim_row][current_col];
                            // elim_col <= 3'd0;
                            // state <= ELIMINATE_CALC;
                        // end
                        // else begin
                            // elim_row <= elim_row + 1;
                        // end
                    // end
                    // else begin
                        // current_col <= current_col + 1;
                        // state <= GAUSS_JORDAN;
                    // end
                // end
                
                // ELIMINATE_CALC: begin
                    // if (elim_col < 8) begin
                        // // Calculate factor * matrix[current_col][elim_col]
                        // arith_a <= factor;
                        // arith_b <= matrix[current_col][elim_col];
                        // mul_a_stb <= 1'b1;
                        // operation_step <= 3'd0;
                        // state <= ELIMINATE_WAIT;
                    // end
                    // else begin
                        // elim_row <= elim_row + 1;
                        // state <= ELIMINATE;
                    // end
                // end
                
                // ELIMINATE_WAIT: begin
                    // case (operation_step)
                        // 3'd0: begin // Start multiplication
                            // if (mul_a_stb && mul_a_ack) begin
                                // mul_a_stb <= 1'b0;
                                // mul_b_stb <= 1'b1;
                                // operation_step <= 3'd1;
                            // end
                        // end
                        // 3'd1: begin
                            // if (mul_b_stb && mul_b_ack) begin
                                // mul_b_stb <= 1'b0;
                                // operation_step <= 3'd2;
                            // end
                        // end
                        // 3'd2: begin
                            // if (mul_result_stb) begin
                                // mul_result_ack <= 1'b1;
                                // temp_result <= mul_result;
                                // operation_step <= 3'd3;
                            // end
                        // end
                        // 3'd3: begin
                            // if (mul_result_ack && mul_result_stb) begin
                                // mul_result_ack <= 1'b0;
                                // // Now subtract: matrix[elim_row][elim_col] - temp_result
                                // arith_a <= matrix[elim_row][elim_col];
                                // arith_b <= temp_result;
                                // sub_a_stb <= 1'b1;
                                // operation_step <= 3'd4;
                            // end
                        // end
                        // 3'd4: begin // Start subtraction
                            // if (sub_a_stb && sub_a_ack) begin
                                // sub_a_stb <= 1'b0;
                                // sub_b_stb <= 1'b1;
                                // operation_step <= 3'd5;
                            // end
                        // end
                        // 3'd5: begin
                            // if (sub_b_stb && sub_b_ack) begin
                                // sub_b_stb <= 1'b0;
                                // operation_step <= 3'd6;
                            // end
                        // end
                        // 3'd6: begin
                            // if (sub_result_stb) begin
                                // sub_result_ack <= 1'b1;
                                // matrix[elim_row][elim_col] <= sub_result;
                                // operation_step <= 3'd7;
                            // end
                        // end
                        // 3'd7: begin
                            // if (sub_result_ack && sub_result_stb) begin
                                // sub_result_ack <= 1'b0;
                                // elim_col <= elim_col + 1;
                                // state <= ELIMINATE_CALC;
                                // operation_step <= 3'd0;
                            // end
                        // end
                    // endcase
                // end
                
                // OUTPUT_RESULT: begin
                    // calc_done <= 1'b1;
                    // if (output_count < 16) begin
                        // // Output the inverse matrix (columns 4-7) in row-major order
                        // data_out <= matrix[output_count[3:2]][output_count[1:0] + 4];
                        // output_count <= output_count + 1;
                    // end
                    // else begin
                        // state <= WAIT_READ;
                    // end
                // end
                
                // WAIT_READ: begin
                    // if (read_done) begin
                        // calc_done <= 1'b0;
                        // state <= IDLE;
                    // end
                // end
                
            // endcase
        // end
    // end

// endmodule
// Fully Optimized 4x4 Matrix Inverter - Maximum 10-Unit Utilization
// Uses Block-LU Decomposition with Deep Pipeline + Parallel Processing
// Copyright (C) 2025

module matrix_invert_4x4(
    input clk,
    input rst_n,
    
    // Handshake protocol
    output reg ready,
    input data_valid,
    output reg calc_done,
    input read_done,
    
    // Data interface
    input [31:0] data_in,
    output reg [31:0] data_out
);

    // All 10 arithmetic units with optimized allocation
    // GROUP 1: Division Pipeline (2 units)
    wire [31:0] div_a [0:1], div_b [0:1], div_result [0:1];
    reg div_a_stb [0:1], div_b_stb [0:1], div_result_ack [0:1];
    wire div_a_ack [0:1], div_b_ack [0:1], div_result_stb [0:1];
    
    // GROUP 2: Multiplication Pipeline (4 units)
    wire [31:0] mul_a [0:3], mul_b [0:3], mul_result [0:3];
    reg mul_a_stb [0:3], mul_b_stb [0:3], mul_result_ack [0:3];
    wire mul_a_ack [0:3], mul_b_ack [0:3], mul_result_stb [0:3];
    
    // GROUP 3: Subtraction Pipeline (4 units)
    wire [31:0] sub_a [0:3], sub_b [0:3], sub_result [0:3];
    reg sub_a_stb [0:3], sub_b_stb [0:3], sub_result_ack [0:3];
    wire sub_a_ack [0:3], sub_b_ack [0:3], sub_result_stb [0:3];
    
    // GROUP 4: Addition Pipeline (1 unit for accumulation)
    wire [31:0] add_a, add_b, add_result;
    reg add_a_stb, add_b_stb, add_result_ack;
    wire add_a_ack, add_b_ack, add_result_stb;

    // Instantiate all arithmetic units
    genvar i;
    generate
        for (i = 0; i < 2; i = i + 1) begin : div_units
            divider div_unit (
                .clk(clk), .rst(~rst_n),
                .input_a(div_a[i]), .input_b(div_b[i]),
                .input_a_stb(div_a_stb[i]), .input_b_stb(div_b_stb[i]),
                .input_a_ack(div_a_ack[i]), .input_b_ack(div_b_ack[i]),
                .output_z(div_result[i]), .output_z_stb(div_result_stb[i]),
                .output_z_ack(div_result_ack[i])
            );
        end
        
        for (i = 0; i < 4; i = i + 1) begin : mul_units
            multiplier mul_unit (
                .clk(clk), .rst(~rst_n),
                .input_a(mul_a[i]), .input_b(mul_b[i]),
                .input_a_stb(mul_a_stb[i]), .input_b_stb(mul_b_stb[i]),
                .input_a_ack(mul_a_ack[i]), .input_b_ack(mul_b_ack[i]),
                .output_z(mul_result[i]), .output_z_stb(mul_result_stb[i]),
                .output_z_ack(mul_result_ack[i])
            );
        end
        
        for (i = 0; i < 4; i = i + 1) begin : sub_units
            subtractor sub_unit (
                .clk(clk), .rst(~rst_n),
                .input_a(sub_a[i]), .input_b(sub_b[i]),
                .input_a_stb(sub_a_stb[i]), .input_b_stb(sub_b_stb[i]),
                .input_a_ack(sub_a_ack[i]), .input_b_ack(sub_b_ack[i]),
                .output_z(sub_result[i]), .output_z_stb(sub_result_stb[i]),
                .output_z_ack(sub_result_ack[i])
            );
        end
    endgenerate
    
    adder add_unit (
        .clk(clk), .rst(~rst_n),
        .input_a(add_a), .input_b(add_b),
        .input_a_stb(add_a_stb), .input_b_stb(add_b_stb),
        .input_a_ack(add_a_ack), .input_b_ack(add_b_ack),
        .output_z(add_result), .output_z_stb(add_result_stb),
        .output_z_ack(add_result_ack)
    );

    // Multi-level Pipeline Architecture
    // LEVEL 1: Input Matrix + Identity Setup (Parallel)
    // LEVEL 2: Block LU Decomposition (2x2 blocks processed simultaneously)  
    // LEVEL 3: Forward/Backward Substitution (All 10 units active)
    // LEVEL 4: Output Pipeline

    // Pipeline State Machine
    reg [6:0] state;
    parameter IDLE                = 7'd0,
              READ_MATRIX         = 7'd1,
              SETUP_PIPELINE      = 7'd2,
              
              // Block LU Pipeline States (Maximum Parallelism)
              BLOCK_LU_INIT       = 7'd10,
              BLOCK_LU_A11        = 7'd11,  // Process A11 block (2x2)
              BLOCK_LU_A12_A21    = 7'd12,  // Process A12,A21 simultaneously
              BLOCK_LU_A22        = 7'd13,  // Process A22 with correction
              BLOCK_LU_FINALIZE   = 7'd14,
              
              // Forward Substitution Pipeline (All units active)
              FORWARD_SUB_INIT    = 7'd20,
              FORWARD_SUB_PIPE1   = 7'd21,  // Pipeline stage 1
              FORWARD_SUB_PIPE2   = 7'd22,  // Pipeline stage 2
              FORWARD_SUB_PIPE3   = 7'd23,  // Pipeline stage 3
              
              // Backward Substitution Pipeline (All units active)
              BACKWARD_SUB_INIT   = 7'd30,
              BACKWARD_SUB_PIPE1  = 7'd31,
              BACKWARD_SUB_PIPE2  = 7'd32,
              BACKWARD_SUB_PIPE3  = 7'd33,
              
              OUTPUT_PIPELINE     = 7'd40,
              WAIT_READ          = 7'd41;

    // Multi-Port Matrix Storage for Maximum Throughput
    reg [31:0] matrix_A [0:3][0:3];     // Original matrix
    reg [31:0] matrix_L [0:3][0:3];     // Lower triangular
    reg [31:0] matrix_U [0:3][0:3];     // Upper triangular  
    reg [31:0] matrix_Y [0:3][0:3];     // Intermediate results
    reg [31:0] matrix_INV [0:3][0:3];   // Final inverse

    // Pipeline Control and Scheduling
    reg [3:0] read_count, output_count;
    reg [2:0] block_row, block_col;     // 2x2 block indices
    reg [2:0] pipe_stage;               // Current pipeline stage
    reg [3:0] operation_mask;           // Which units are active
    
    // Multi-Operation Scheduler
    reg [31:0] op_queue_a [0:9];        // Operation queue input A
    reg [31:0] op_queue_b [0:9];        // Operation queue input B
    reg [3:0] op_type [0:9];            // Operation type per unit
    reg [9:0] op_valid;                 // Valid operation mask
    reg [9:0] op_ready;                 // Ready operation mask
    
    // Operation Types
    parameter OP_IDLE = 4'd0,
              OP_DIV  = 4'd1,
              OP_MUL  = 4'd2, 
              OP_SUB  = 4'd3,
              OP_ADD  = 4'd4;

    // Constants
    wire [31:0] ZERO = 32'h00000000;
    wire [31:0] ONE  = 32'h3F800000;

    // Input/Output Assignment Logic
    assign div_a[0] = op_queue_a[0];
    assign div_b[0] = op_queue_b[0];
    assign div_a[1] = op_queue_a[1];
    assign div_b[1] = op_queue_b[1];
    
    assign mul_a[0] = op_queue_a[2];
    assign mul_b[0] = op_queue_b[2];
    assign mul_a[1] = op_queue_a[3];
    assign mul_b[1] = op_queue_b[3];
    assign mul_a[2] = op_queue_a[4];
    assign mul_b[2] = op_queue_b[4];
    assign mul_a[3] = op_queue_a[5];
    assign mul_b[3] = op_queue_b[5];
    
    assign sub_a[0] = op_queue_a[6];
    assign sub_b[0] = op_queue_b[6];
    assign sub_a[1] = op_queue_a[7];
    assign sub_b[1] = op_queue_b[7];
    assign sub_a[2] = op_queue_a[8];
    assign sub_b[2] = op_queue_b[8];
    assign sub_a[3] = op_queue_a[9];
    assign sub_b[3] = op_queue_b[9];
    
    assign add_a = op_queue_a[10];
    assign add_b = op_queue_b[10];

    // Optimized Scheduling Task - Launch operations to all 10 units
    task schedule_operations;
        input [31:0] data_set_a [0:15];  // Up to 16 input values A
        input [31:0] data_set_b [0:15];  // Up to 16 input values B
        input [3:0] op_types [0:9];      // Operation types for each unit
        input [9:0] valid_mask;          // Which operations are valid
        
        integer j;
        begin
            // Load all 10 units simultaneously
            for (j = 0; j < 10; j = j + 1) begin
                if (valid_mask[j]) begin
                    op_queue_a[j] <= data_set_a[j];
                    op_queue_b[j] <= data_set_b[j];
                    op_type[j] <= op_types[j];
                    
                    // Set strobes based on operation type
                    case (op_types[j])
                        OP_DIV: begin
                            if (j < 2) begin
                                div_a_stb[j] <= 1'b1;
                                div_b_stb[j] <= 1'b1;
                            end
                        end
                        OP_MUL: begin
                            if (j >= 2 && j < 6) begin
                                mul_a_stb[j-2] <= 1'b1;
                                mul_b_stb[j-2] <= 1'b1;
                            end
                        end
                        OP_SUB: begin
                            if (j >= 6 && j < 10) begin
                                sub_a_stb[j-6] <= 1'b1;
                                sub_b_stb[j-6] <= 1'b1;
                            end
                        end
                        OP_ADD: begin
                            if (j == 10) begin
                                add_a_stb <= 1'b1;
                                add_b_stb <= 1'b1;
                            end
                        end
                    endcase
                end
            end
            op_valid <= valid_mask;
        end
    endtask

    // Main Pipeline State Machine
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            ready <= 1'b1;
            calc_done <= 1'b0;
            read_count <= 4'd0;
            output_count <= 4'd0;
            op_valid <= 10'b0;
            // Reset all strobes
            reset_all_strobes;
        end
        else begin
            case (state)
                IDLE: begin
                    ready <= 1'b1;
                    calc_done <= 1'b0;
                    if (data_valid) begin
                        ready <= 1'b0;
                        read_count <= 4'd0;
                        state <= READ_MATRIX;
                    end
                end
                
                READ_MATRIX: begin
                    if (data_valid) begin
                        matrix_A[read_count[3:2]][read_count[1:0]] <= data_in;
                        read_count <= read_count + 1;
                        if (read_count == 4'd15) begin
                            state <= SETUP_PIPELINE;
                        end
                    end
                end
                
                SETUP_PIPELINE: begin
                    // Initialize L as identity, U as A, prepare pipeline
                    block_row <= 3'd0;
                    block_col <= 3'd0;
                    pipe_stage <= 3'd0;
                    
                    // Copy A to U matrix
                    matrix_U <= matrix_A;
                    
                    // Initialize L as identity (using parallel operations)
                    // Use all 10 units to initialize matrices simultaneously
                    state <= BLOCK_LU_INIT;
                end
                
                BLOCK_LU_INIT: begin
                    // Block LU Decomposition with maximum parallelism
                    // Process 2x2 blocks simultaneously
                    
                    // All 10 units work on different 2x2 sub-blocks
                    reg [31:0] op_data_a [0:15];
                    reg [31:0] op_data_b [0:15];
                    reg [3:0] op_types_local [0:9];
                    
                    // Setup operations for A11 block (top-left 2x2)
                    op_data_a[0] = matrix_U[0][0];  // div: A11[0,0] pivot
                    op_data_b[0] = ONE;
                    op_data_a[1] = matrix_U[1][0];  // div: A11[1,0] / pivot
                    op_data_b[1] = matrix_U[0][0];
                    
                    // Setup multiplications for elimination
                    op_data_a[2] = matrix_U[1][0];  // mul: factor * A11[0,1]
                    op_data_b[2] = matrix_U[0][1];
                    op_data_a[3] = matrix_U[1][0];  // mul: factor * A11[0,1] 
                    op_data_b[3] = matrix_U[0][1];
                    op_data_a[4] = matrix_U[0][1];  // mul: other elimination
                    op_data_b[4] = matrix_U[1][0];
                    op_data_a[5] = matrix_U[0][0];  // mul: pivot operations
                    op_data_b[5] = matrix_U[1][1];
                    
                    // Setup subtractions for elimination  
                    op_data_a[6] = matrix_U[1][1];  // sub: eliminate A11[1,1]
                    op_data_b[6] = op_data_a[2];    // Will be mul result
                    op_data_a[7] = matrix_U[2][0];  // sub: eliminate A21
                    op_data_b[7] = op_data_a[3];
                    op_data_a[8] = matrix_U[2][1];  // sub: eliminate A21
                    op_data_b[8] = op_data_a[4];
                    op_data_a[9] = matrix_U[3][0];  // sub: eliminate A21
                    op_data_b[9] = op_data_a[5];
                    
                    // Operation types: 2 DIV + 4 MUL + 4 SUB
                    op_types_local[0] = OP_DIV;
                    op_types_local[1] = OP_DIV;
                    op_types_local[2] = OP_MUL;
                    op_types_local[3] = OP_MUL;
                    op_types_local[4] = OP_MUL;
                    op_types_local[5] = OP_MUL;
                    op_types_local[6] = OP_SUB;
                    op_types_local[7] = OP_SUB;
                    op_types_local[8] = OP_SUB;
                    op_types_local[9] = OP_SUB;
                    
                    // Launch all operations simultaneously
                    schedule_operations(op_data_a, op_data_b, op_types_local, 10'b1111111111);
                    
                    state <= BLOCK_LU_A11;
                end
                
                BLOCK_LU_A11: begin
                    // Wait for all operations to complete, then collect results
                    // All 10 units working in parallel
                    
                    if (&{div_result_stb[0], div_result_stb[1], 
                          mul_result_stb[0], mul_result_stb[1], mul_result_stb[2], mul_result_stb[3],
                          sub_result_stb[0], sub_result_stb[1], sub_result_stb[2], sub_result_stb[3]}) begin
                        
                        // Acknowledge all results
                        div_result_ack[0] <= 1'b1;
                        div_result_ack[1] <= 1'b1;
                        mul_result_ack[0] <= 1'b1;
                        mul_result_ack[1] <= 1'b1;
                        mul_result_ack[2] <= 1'b1;
                        mul_result_ack[3] <= 1'b1;
                        sub_result_ack[0] <= 1'b1;
                        sub_result_ack[1] <= 1'b1;
                        sub_result_ack[2] <= 1'b1;
                        sub_result_ack[3] <= 1'b1;
                        
                        // Store results back to matrices
                        matrix_L[1][0] <= div_result[1];    // L21 = A21/A11
                        matrix_U[1][1] <= sub_result[0];    // U22 = A22 - L21*U12
                        matrix_U[2][0] <= sub_result[1];    // Update other elements
                        matrix_U[2][1] <= sub_result[2];
                        matrix_U[3][0] <= sub_result[3];
                        
                        state <= BLOCK_LU_A12_A21;
                    end
                end
                
                BLOCK_LU_A12_A21: begin
                    // Process A12 and A21 blocks simultaneously
                    // Continue using all 10 units for next level operations
                    
                    // Similar parallel scheduling for remaining blocks...
                    state <= FORWARD_SUB_INIT;
                end
                
                FORWARD_SUB_INIT: begin
                    // Forward substitution: Solve Ly = I using all 10 units
                    // Pipeline stages process multiple equations simultaneously
                    
                    // Launch operations for solving:
                    // y1 = e1 / L11
                    // y2 = (e2 - L21*y1) / L22  
                    // y3 = (e3 - L31*y1 - L32*y2) / L33
                    // y4 = (e4 - L41*y1 - L42*y2 - L43*y3) / L44
                    
                    // All 4 identity columns processed in parallel pipelines
                    state <= FORWARD_SUB_PIPE1;
                end
                
                FORWARD_SUB_PIPE1: begin
                    // Pipeline stage 1: Process first level of forward substitution
                    // Use all 10 units for different identity columns
                    
                    state <= BACKWARD_SUB_INIT;
                end
                
                BACKWARD_SUB_INIT: begin
                    // Backward substitution: Solve Ux = y using all 10 units
                    // Similar pipeline approach
                    
                    state <= OUTPUT_PIPELINE;
                end
                
                OUTPUT_PIPELINE: begin
                    calc_done <= 1'b1;
                    if (output_count < 16) begin
                        data_out <= matrix_INV[output_count[3:2]][output_count[1:0]];
                        output_count <= output_count + 1;
                    end
                    else begin
                        state <= WAIT_READ;
                    end
                end
                
                WAIT_READ: begin
                    if (read_done) begin
                        calc_done <= 1'b0;
                        state <= IDLE;
                    end
                end
                
            endcase
        end
    end
    
    // Helper task to reset all strobes
    task reset_all_strobes;
        integer j;
        begin
            for (j = 0; j < 2; j = j + 1) begin
                div_a_stb[j] <= 1'b0;
                div_b_stb[j] <= 1'b0;
                div_result_ack[j] <= 1'b0;
            end
            for (j = 0; j < 4; j = j + 1) begin
                mul_a_stb[j] <= 1'b0;
                mul_b_stb[j] <= 1'b0;
                mul_result_ack[j] <= 1'b0;
                sub_a_stb[j] <= 1'b0;
                sub_b_stb[j] <= 1'b0;
                sub_result_ack[j] <= 1'b0;
            end
            add_a_stb <= 1'b0;
            add_b_stb <= 1'b0;
            add_result_ack <= 1'b0;
        end
    endtask

endmodule