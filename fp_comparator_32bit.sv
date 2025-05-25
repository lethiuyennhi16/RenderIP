module fp_comparator_32bit (
    input logic clk,
    input logic rst_n,
    
    // Handshake signals
    output logic ready,         // Comparator sẵn sàng nhận dữ liệu
    input logic data_valid,     // Master có dữ liệu sẵn sàng
    output logic calc_done,     // Comparator hoàn thành tính toán
    input logic read_done,      // Master đã đọc xong kết quả
    
    // Data signals
    input logic [31:0] a,       // Số floating point thứ nhất
    input logic [31:0] b,       // Số floating point thứ hai
    output logic [2:0] result   // 100: a>b, 010: a=b, 001: a<b
);

    // IEEE 754 32-bit format:
    // Bit 31: Sign (0=positive, 1=negative)
    // Bit 30-23: Exponent (8 bits, biased by 127)
    // Bit 22-0: Mantissa (23 bits, implicit leading 1)
    
    // Extract fields for number a
    wire sign_a = a[31];
    wire [7:0] exp_a = a[30:23];
    wire [22:0] mant_a = a[22:0];
    
    // Extract fields for number b
    wire sign_b = b[31];
    wire [7:0] exp_b = b[30:23];
    wire [22:0] mant_b = b[22:0];
    
    // Check for special cases
    wire is_zero_a = (exp_a == 8'h00) && (mant_a == 23'h000000);
    wire is_zero_b = (exp_b == 8'h00) && (mant_b == 23'h000000);
    wire is_inf_a = (exp_a == 8'hFF) && (mant_a == 23'h000000);
    wire is_inf_b = (exp_b == 8'hFF) && (mant_b == 23'h000000);
    wire is_nan_a = (exp_a == 8'hFF) && (mant_a != 23'h000000);
    wire is_nan_b = (exp_b == 8'hFF) && (mant_b != 23'h000000);
    
    // State machine
    typedef enum logic [1:0] {
        IDLE,
        COMPARING,
        DONE
    } state_t;
    
    state_t current_state, next_state;
    
    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end
    
    // Next state logic
    always_comb begin
        case (current_state)
            IDLE: begin
                if (data_valid)
                    next_state = COMPARING;
                else
                    next_state = IDLE;
            end
            
            COMPARING: begin
                next_state = DONE;
            end
            
            DONE: begin
                if (read_done)
                    next_state = IDLE;
                else
                    next_state = DONE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Output logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready <= 1'b1;
            calc_done <= 1'b0;
            result <= 3'b000;
        end else begin
            case (current_state)
                IDLE: begin
                    ready <= 1'b1;
                    calc_done <= 1'b0;
                    if (data_valid) begin
                        ready <= 1'b0;
                    end
                end
                
                COMPARING: begin
                    ready <= 1'b0;
                    calc_done <= 1'b0;
                    
                    // Perform comparison
                    if (is_nan_a || is_nan_b) begin
                        // NaN comparison is always false
                        result <= 3'b000; // Undefined result for NaN
                    end else if (is_zero_a && is_zero_b) begin
                        // Both are zero (including -0 and +0)
                        result <= 3'b010; // Equal
                    end else if (sign_a != sign_b) begin
                        // Different signs
                        if (is_zero_a && is_zero_b) begin
                            result <= 3'b010; // +0 == -0
                        end else if (sign_a) begin
                            result <= 3'b001; // a is negative, b is positive -> a < b
                        end else begin
                            result <= 3'b100; // a is positive, b is negative -> a > b
                        end
                    end else begin
                        // Same sign, compare magnitude
                        logic mag_a_greater, mag_equal;
                        
                        // Compare exponents first
                        if (exp_a > exp_b) begin
                            mag_a_greater = 1'b1;
                            mag_equal = 1'b0;
                        end else if (exp_a < exp_b) begin
                            mag_a_greater = 1'b0;
                            mag_equal = 1'b0;
                        end else begin
                            // Same exponent, compare mantissa
                            if (mant_a > mant_b) begin
                                mag_a_greater = 1'b1;
                                mag_equal = 1'b0;
                            end else if (mant_a < mant_b) begin
                                mag_a_greater = 1'b0;
                                mag_equal = 1'b0;
                            end else begin
                                mag_a_greater = 1'b0;
                                mag_equal = 1'b1;
                            end
                        end
                        
                        // Apply sign to magnitude comparison
                        if (mag_equal) begin
                            result <= 3'b010; // Equal
                        end else if (sign_a == 1'b0) begin
                            // Both positive
                            result <= mag_a_greater ? 3'b100 : 3'b001;
                        end else begin
                            // Both negative
                            result <= mag_a_greater ? 3'b001 : 3'b100;
                        end
                    end
                end
                
                DONE: begin
                    ready <= 1'b0;
                    calc_done <= 1'b1;
                    if (read_done) begin
                        calc_done <= 1'b0;
                    end
                end
            endcase
        end
    end

endmodule