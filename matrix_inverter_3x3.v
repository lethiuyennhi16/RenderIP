// IEEE 754 Single Precision 3x3 Matrix Inverter
// Uses Gauss-Jordan elimination method
// Includes all arithmetic units internally
// Copyright (C) 2025

module matrix_inverter_3x3(
    input clk,
    input rst_n,
    
    // Handshake protocol with master
    output reg ready,           // Signal to master that module is ready
    input data_valid,          // Master signals data is available
    output reg calc_done,      // Signal when calculation is complete
    input read_done,           // Master signals it has read all results
    
    // Data interface
    input [31:0] data_in,      // Input data (one float at a time)
    output reg [31:0] data_out // Output data (one float at a time)
);

    // Internal arithmetic unit signals
    // Adder
    wire [31:0] add_a, add_b, add_result;
    reg add_a_stb, add_b_stb, add_result_ack;
    wire add_a_ack, add_b_ack, add_result_stb;
    
    // Subtractor  
    wire [31:0] sub_a, sub_b, sub_result;
    reg sub_a_stb, sub_b_stb, sub_result_ack;
    wire sub_a_ack, sub_b_ack, sub_result_stb;
    
    // Multiplier
    wire [31:0] mul_a, mul_b, mul_result;
    reg mul_a_stb, mul_b_stb, mul_result_ack;
    wire mul_a_ack, mul_b_ack, mul_result_stb;
    
    // Divider
    wire [31:0] div_a, div_b, div_result;
    reg div_a_stb, div_b_stb, div_result_ack;
    wire div_a_ack, div_b_ack, div_result_stb;

    // Instantiate arithmetic units
    adder add_unit (
        .clk(clk),
        .rst(~rst_n),
        .input_a(add_a),
        .input_b(add_b),
        .input_a_stb(add_a_stb),
        .input_b_stb(add_b_stb),
        .input_a_ack(add_a_ack),
        .input_b_ack(add_b_ack),
        .output_z(add_result),
        .output_z_stb(add_result_stb),
        .output_z_ack(add_result_ack)
    );
    
    subtractor sub_unit (
        .clk(clk),
        .rst(~rst_n),
        .input_a(sub_a),
        .input_b(sub_b),
        .input_a_stb(sub_a_stb),
        .input_b_stb(sub_b_stb),
        .input_a_ack(sub_a_ack),
        .input_b_ack(sub_b_ack),
        .output_z(sub_result),
        .output_z_stb(sub_result_stb),
        .output_z_ack(sub_result_ack)
    );
    
    multiplier mul_unit (
        .clk(clk),
        .rst(~rst_n),
        .input_a(mul_a),
        .input_b(mul_b),
        .input_a_stb(mul_a_stb),
        .input_b_stb(mul_b_stb),
        .input_a_ack(mul_a_ack),
        .input_b_ack(mul_b_ack),
        .output_z(mul_result),
        .output_z_stb(mul_result_stb),
        .output_z_ack(mul_result_ack)
    );
    
    divider div_unit (
        .clk(clk),
        .rst(~rst_n),
        .input_a(div_a),
        .input_b(div_b),
        .input_a_stb(div_a_stb),
        .input_b_stb(div_b_stb),
        .input_a_ack(div_a_ack),
        .input_b_ack(div_b_ack),
        .output_z(div_result),
        .output_z_stb(div_result_stb),
        .output_z_ack(div_result_ack)
    );

    // State machine states
    reg [5:0] state;
    parameter IDLE            = 6'd0,
              READ_MATRIX     = 6'd1,
              INIT_IDENTITY   = 6'd2,
              GAUSS_JORDAN    = 6'd3,
              FIND_PIVOT      = 6'd4,
              SCALE_PIVOT     = 6'd5,
              SCALE_PIVOT_WAIT = 6'd6,
              ELIMINATE       = 6'd7,
              ELIMINATE_CALC  = 6'd8,
              ELIMINATE_WAIT  = 6'd9,
              OUTPUT_RESULT   = 6'd10,
              WAIT_READ       = 6'd11;

    // Matrix storage: 3x3 input matrix and 3x3 identity matrix (augmented)
    reg [31:0] matrix [0:2][0:5]; // 3x6 augmented matrix
    
    // Control variables
    reg [3:0] read_count;      // Counter for reading input (0-8)
    reg [3:0] output_count;    // Counter for outputting result (0-8)
    reg [2:0] current_row;     // Current row being processed (0-2)
    reg [2:0] current_col;     // Current column being processed (0-2)
    reg [2:0] pivot_row;       // Row with pivot element
    reg [2:0] elim_row;        // Row being eliminated
    reg [2:0] elim_col;        // Column being eliminated
    
    // Index mapping for 3x3 matrix
    reg [1:0] read_row, read_col;
    reg [1:0] output_row, output_col;
    
    // Temporary storage for arithmetic operations
    reg [31:0] pivot_element;
    reg [31:0] factor;
    reg [31:0] temp_result;
    
    // Operation control
    reg [2:0] operation_step;  // Step within current operation
    reg [5:0] return_state;    // State to return to after arithmetic
    
    // Constants
    wire [31:0] ZERO = 32'h00000000;
    wire [31:0] ONE  = 32'h3F800000;  // 1.0 in IEEE 754
    
    // Arithmetic unit input assignments
    reg [31:0] arith_a, arith_b;
    
    assign add_a = arith_a;
    assign add_b = arith_b;
    assign sub_a = arith_a;
    assign sub_b = arith_b;
    assign mul_a = arith_a;
    assign mul_b = arith_b;
    assign div_a = arith_a;
    assign div_b = arith_b;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            ready <= 1'b1;
            calc_done <= 1'b0;
            read_count <= 4'd0;
            output_count <= 4'd0;
            current_row <= 3'd0;
            current_col <= 3'd0;
            elim_row <= 3'd0;
            elim_col <= 3'd0;
            operation_step <= 3'd0;
            
            // Reset all arithmetic unit strobes
            add_a_stb <= 1'b0;
            add_b_stb <= 1'b0;
            add_result_ack <= 1'b0;
            sub_a_stb <= 1'b0;
            sub_b_stb <= 1'b0;
            sub_result_ack <= 1'b0;
            mul_a_stb <= 1'b0;
            mul_b_stb <= 1'b0;
            mul_result_ack <= 1'b0;
            div_a_stb <= 1'b0;
            div_b_stb <= 1'b0;
            div_result_ack <= 1'b0;
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
                        // Calculate row and column indices for 3x3 matrix
                        case (read_count)
                            4'd0: begin read_row = 2'd0; read_col = 2'd0; end
                            4'd1: begin read_row = 2'd0; read_col = 2'd1; end
                            4'd2: begin read_row = 2'd0; read_col = 2'd2; end
                            4'd3: begin read_row = 2'd1; read_col = 2'd0; end
                            4'd4: begin read_row = 2'd1; read_col = 2'd1; end
                            4'd5: begin read_row = 2'd1; read_col = 2'd2; end
                            4'd6: begin read_row = 2'd2; read_col = 2'd0; end
                            4'd7: begin read_row = 2'd2; read_col = 2'd1; end
                            4'd8: begin read_row = 2'd2; read_col = 2'd2; end
                            default: begin read_row = 2'd0; read_col = 2'd0; end
                        endcase
                        
                        // Store input data in row-major order
                        matrix[read_row][read_col] <= data_in;
                        read_count <= read_count + 1;
                        
                        if (read_count == 4'd8) begin
                            state <= INIT_IDENTITY;
                            current_row <= 3'd0;
                            current_col <= 3'd0;
                        end
                    end
                end
                
                INIT_IDENTITY: begin
                    // Initialize identity matrix in columns 3-5
                    if (current_row < 3) begin
                        if (current_col < 3) begin
                            if (current_row == current_col)
                                matrix[current_row][current_col + 3] <= ONE;
                            else
                                matrix[current_row][current_col + 3] <= ZERO;
                            
                            current_col <= current_col + 1;
                        end
                        else begin
                            current_col <= 3'd0;
                            current_row <= current_row + 1;
                        end
                    end
                    else begin
                        current_row <= 3'd0;
                        current_col <= 3'd0;
                        state <= GAUSS_JORDAN;
                    end
                end
                
                GAUSS_JORDAN: begin
                    if (current_col < 3) begin
                        state <= FIND_PIVOT;
                    end
                    else begin
                        state <= OUTPUT_RESULT;
                        output_count <= 4'd0;
                    end
                end
                
                FIND_PIVOT: begin
                    // Use diagonal element as pivot
                    pivot_element <= matrix[current_col][current_col];
                    
                    // Check if pivot is zero (singular matrix)
                    if (matrix[current_col][current_col] == ZERO) begin
                        // Matrix is singular, return to idle
                        state <= IDLE;
                        ready <= 1'b1;
                    end
                    else begin
                        elim_col <= 3'd0;
                        state <= SCALE_PIVOT;
                    end
                end
                
                SCALE_PIVOT: begin
                    if (elim_col < 6) begin
                        // Divide matrix[current_col][elim_col] by pivot_element
                        arith_a <= matrix[current_col][elim_col];
                        arith_b <= pivot_element;
                        div_a_stb <= 1'b1;
                        operation_step <= 3'd0;
                        state <= SCALE_PIVOT_WAIT;
                    end
                    else begin
                        // Start elimination for other rows
                        elim_row <= 3'd0;
                        state <= ELIMINATE;
                    end
                end
                
                SCALE_PIVOT_WAIT: begin
                    case (operation_step)
                        3'd0: begin
                            if (div_a_stb && div_a_ack) begin
                                div_a_stb <= 1'b0;
                                div_b_stb <= 1'b1;
                                operation_step <= 3'd1;
                            end
                        end
                        3'd1: begin
                            if (div_b_stb && div_b_ack) begin
                                div_b_stb <= 1'b0;
                                operation_step <= 3'd2;
                            end
                        end
                        3'd2: begin
                            if (div_result_stb) begin
                                div_result_ack <= 1'b1;
                                matrix[current_col][elim_col] <= div_result;
                                operation_step <= 3'd3;
                            end
                        end
                        3'd3: begin
                            if (div_result_ack && div_result_stb) begin
                                div_result_ack <= 1'b0;
                                elim_col <= elim_col + 1;
                                state <= SCALE_PIVOT;
                                operation_step <= 3'd0;
                            end
                        end
                    endcase
                end
                
                ELIMINATE: begin
                    if (elim_row < 3) begin
                        if (elim_row != current_col) begin
                            // Get factor = matrix[elim_row][current_col]
                            factor <= matrix[elim_row][current_col];
                            elim_col <= 3'd0;
                            state <= ELIMINATE_CALC;
                        end
                        else begin
                            elim_row <= elim_row + 1;
                        end
                    end
                    else begin
                        current_col <= current_col + 1;
                        state <= GAUSS_JORDAN;
                    end
                end
                
                ELIMINATE_CALC: begin
                    if (elim_col < 6) begin
                        // Calculate factor * matrix[current_col][elim_col]
                        arith_a <= factor;
                        arith_b <= matrix[current_col][elim_col];
                        mul_a_stb <= 1'b1;
                        operation_step <= 3'd0;
                        state <= ELIMINATE_WAIT;
                    end
                    else begin
                        elim_row <= elim_row + 1;
                        state <= ELIMINATE;
                    end
                end
                
                ELIMINATE_WAIT: begin
                    case (operation_step)
                        3'd0: begin // Start multiplication
                            if (mul_a_stb && mul_a_ack) begin
                                mul_a_stb <= 1'b0;
                                mul_b_stb <= 1'b1;
                                operation_step <= 3'd1;
                            end
                        end
                        3'd1: begin
                            if (mul_b_stb && mul_b_ack) begin
                                mul_b_stb <= 1'b0;
                                operation_step <= 3'd2;
                            end
                        end
                        3'd2: begin
                            if (mul_result_stb) begin
                                mul_result_ack <= 1'b1;
                                temp_result <= mul_result;
                                operation_step <= 3'd3;
                            end
                        end
                        3'd3: begin
                            if (mul_result_ack && mul_result_stb) begin
                                mul_result_ack <= 1'b0;
                                // Now subtract: matrix[elim_row][elim_col] - temp_result
                                arith_a <= matrix[elim_row][elim_col];
                                arith_b <= temp_result;
                                sub_a_stb <= 1'b1;
                                operation_step <= 3'd4;
                            end
                        end
                        3'd4: begin // Start subtraction
                            if (sub_a_stb && sub_a_ack) begin
                                sub_a_stb <= 1'b0;
                                sub_b_stb <= 1'b1;
                                operation_step <= 3'd5;
                            end
                        end
                        3'd5: begin
                            if (sub_b_stb && sub_b_ack) begin
                                sub_b_stb <= 1'b0;
                                operation_step <= 3'd6;
                            end
                        end
                        3'd6: begin
                            if (sub_result_stb) begin
                                sub_result_ack <= 1'b1;
                                matrix[elim_row][elim_col] <= sub_result;
                                operation_step <= 3'd7;
                            end
                        end
                        3'd7: begin
                            if (sub_result_ack && sub_result_stb) begin
                                sub_result_ack <= 1'b0;
                                elim_col <= elim_col + 1;
                                state <= ELIMINATE_CALC;
                                operation_step <= 3'd0;
                            end
                        end
                    endcase
                end
                
                OUTPUT_RESULT: begin
                    calc_done <= 1'b1;
                    if (output_count < 9) begin
                        // Calculate row and column indices for 3x3 matrix
                        case (output_count)
                            4'd0: begin output_row = 2'd0; output_col = 2'd0; end
                            4'd1: begin output_row = 2'd0; output_col = 2'd1; end
                            4'd2: begin output_row = 2'd0; output_col = 2'd2; end
                            4'd3: begin output_row = 2'd1; output_col = 2'd0; end
                            4'd4: begin output_row = 2'd1; output_col = 2'd1; end
                            4'd5: begin output_row = 2'd1; output_col = 2'd2; end
                            4'd6: begin output_row = 2'd2; output_col = 2'd0; end
                            4'd7: begin output_row = 2'd2; output_col = 2'd1; end
                            4'd8: begin output_row = 2'd2; output_col = 2'd2; end
                            default: begin output_row = 2'd0; output_col = 2'd0; end
                        endcase
                        
                        // Output the inverse matrix (columns 3-5) in row-major order
                        data_out <= matrix[output_row][output_col + 3];
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

endmodule