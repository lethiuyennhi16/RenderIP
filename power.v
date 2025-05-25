module power(
    input clk,
    input rst_n,
    
    // Handshake protocol
    output reg ready,
    input data_valid,
    output reg calc_done,
    input read_done,
    
    // Data interface
    input [31:0] base_a,        // IEEE 754 floating point base
    input [31:0] exponent_n,    // Integer exponent (as 32-bit signed)
    output reg [31:0] result    // IEEE 754 floating point result
);

    reg [4:0] state;
    parameter IDLE           = 5'd0,
              SPECIAL_CASES  = 5'd1,
              INIT_CALC      = 5'd2,
              SQUARE_BASE    = 5'd3,
              WAIT_SQUARE    = 5'd4,
              MULT_RESULT    = 5'd5,
              WAIT_MULT      = 5'd6,
              FINALIZE       = 5'd7,
              HANDLE_NEG_EXP = 5'd8,
              WAIT_DIV       = 5'd9,
              OUTPUT_RESULT  = 5'd10,
              WAIT_READ      = 5'd11;

    // Working registers
    reg [31:0] current_base;     // Current base being squared
    reg [31:0] current_result;   // Accumulating result
    reg [31:0] work_exponent;    // Working copy of exponent
    reg negative_exponent;       // Flag for negative exponent
    reg calculation_active;

    // FPU interface signals
    reg [31:0] fpu_a, fpu_b;
    reg fpu_a_stb, fpu_b_stb;
    reg fpu_result_ack;
    reg [31:0] fpu_result;
    reg fpu_result_stb;
    reg fpu_a_ack, fpu_b_ack;

    // Control signals for FPU operations
    reg use_multiplier, use_divider;

    // Constants in IEEE 754 format
    parameter CONST_1      = 32'h3f800000; // 1.0
    parameter CONST_0      = 32'h00000000; // 0.0
    parameter NAN_VALUE    = 32'h7fc00000; // NaN  
    parameter INF_POS      = 32'h7f800000; // +Infinity
    parameter INF_NEG      = 32'hff800000; // -Infinity

    // Multiplier instance
    wire [31:0] mult_result;
    wire mult_result_stb;
    wire mult_a_ack, mult_b_ack;
    
    multiplier mult_inst (
        .input_a(fpu_a),
        .input_b(fpu_b),
        .input_a_stb(fpu_a_stb & use_multiplier),
        .input_b_stb(fpu_b_stb & use_multiplier),
        .output_z_ack(fpu_result_ack & use_multiplier),
        .clk(clk),
        .rst(~rst_n),
        .output_z(mult_result),
        .output_z_stb(mult_result_stb),
        .input_a_ack(mult_a_ack),
        .input_b_ack(mult_b_ack)
    );

    // Divider instance (for negative exponents: 1/result)
    wire [31:0] div_result;
    wire div_result_stb;
    wire div_a_ack, div_b_ack;
    
    divider div_inst (
        .input_a(fpu_a),
        .input_b(fpu_b),
        .input_a_stb(fpu_a_stb & use_divider),
        .input_b_stb(fpu_b_stb & use_divider),
        .output_z_ack(fpu_result_ack & use_divider),
        .clk(clk),
        .rst(~rst_n),
        .output_z(div_result),
        .output_z_stb(div_result_stb),
        .input_a_ack(div_a_ack),
        .input_b_ack(div_b_ack)
    );

    // Multiplexer for FPU results
    always @(*) begin
        case ({use_multiplier, use_divider})
            2'b10: begin
                fpu_result = mult_result;
                fpu_result_stb = mult_result_stb;
                fpu_a_ack = mult_a_ack;
                fpu_b_ack = mult_b_ack;
            end
            2'b01: begin
                fpu_result = div_result;
                fpu_result_stb = div_result_stb;
                fpu_a_ack = div_a_ack;
                fpu_b_ack = div_b_ack;
            end
            default: begin
                fpu_result = 32'h0;
                fpu_result_stb = 1'b0;
                fpu_a_ack = 1'b0;
                fpu_b_ack = 1'b0;
            end
        endcase
    end

    // Reset FPU control signals
    task reset_fpu_signals;
        begin
            fpu_a_stb <= 1'b0;
            fpu_b_stb <= 1'b0;
            fpu_result_ack <= 1'b0;
            use_multiplier <= 1'b0;
            use_divider <= 1'b0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            ready <= 1'b1;
            calc_done <= 1'b0;
            result <= 32'b0;
            current_base <= 32'b0;
            current_result <= 32'b0;
            work_exponent <= 32'b0;
            negative_exponent <= 1'b0;
            calculation_active <= 1'b0;
            reset_fpu_signals();
        end else begin
            case (state)
                
                IDLE: begin
                    if (!ready) ready <= 1'b1;  // Ensure ready is high
                    if (calc_done) calc_done <= 1'b0;  // Clear any leftover calc_done
                    calculation_active <= 1'b0;
                    reset_fpu_signals();
                    if (data_valid && ready) begin
                        ready <= 1'b0;
                        state <= SPECIAL_CASES;
                    end
                end
                
                SPECIAL_CASES: begin
                    // Handle special cases
                    if (exponent_n == 32'b0) begin
                        // a^0 = 1 (except 0^0 which we'll define as 1)
                        result <= CONST_1;
                        state <= OUTPUT_RESULT;
                    end else if (base_a == CONST_1) begin
                        // 1^n = 1
                        result <= CONST_1;
                        state <= OUTPUT_RESULT;
                    end else if (base_a == CONST_0) begin
                        if (exponent_n[31]) begin
                            // 0^(-n) = infinity
                            result <= INF_POS;
                        end else begin
                            // 0^n = 0 (for n > 0)
                            result <= CONST_0;
                        end
                        state <= OUTPUT_RESULT;
                    end else if (base_a[30:23] == 8'hFF) begin
                        // Handle infinity/NaN in base
                        result <= NAN_VALUE;
                        state <= OUTPUT_RESULT;
                    end else if (exponent_n == 32'h00000001) begin
                        // a^1 = a
                        result <= base_a;
                        state <= OUTPUT_RESULT;
                    end else begin
                        // Normal case: use exponentiation by squaring
                        state <= INIT_CALC;
                    end
                end
                
                INIT_CALC: begin
                    current_base <= base_a;
                    current_result <= CONST_1; // Start with 1.0
                    
                    // Handle negative exponent
                    if (exponent_n[31]) begin
                        // Negative exponent: work with positive value, then take reciprocal
                        work_exponent <= (~exponent_n) + 1; // Two's complement negation
                        negative_exponent <= 1'b1;
                    end else begin
                        work_exponent <= exponent_n;
                        negative_exponent <= 1'b0;
                    end
                    
                    calculation_active <= 1'b1;
                    state <= SQUARE_BASE;
                end
                
                SQUARE_BASE: begin
                    if (work_exponent == 32'b0) begin
                        // Done with exponentiation
                        state <= FINALIZE;
                    end else if (work_exponent[0]) begin
                        // Odd exponent: multiply result by current base
                        reset_fpu_signals();
                        fpu_a <= current_result;
                        fpu_b <= current_base;
                        fpu_a_stb <= 1'b1;
                        fpu_b_stb <= 1'b1;
                        use_multiplier <= 1'b1;
                        state <= WAIT_MULT;
                    end else begin
                        // Even exponent: just square the base
                        reset_fpu_signals();
                        fpu_a <= current_base;
                        fpu_b <= current_base;
                        fpu_a_stb <= 1'b1;
                        fpu_b_stb <= 1'b1;
                        use_multiplier <= 1'b1;
                        state <= WAIT_SQUARE;
                    end
                end
                
                WAIT_SQUARE: begin
                    if (fpu_result_stb) begin
                        fpu_result_ack <= 1'b1;
                        current_base <= fpu_result; // base = base^2
                        work_exponent <= work_exponent >> 1; // exponent = exponent / 2
                        state <= SQUARE_BASE;
                    end
                end
                
                WAIT_MULT: begin
                    if (fpu_result_stb) begin
                        fpu_result_ack <= 1'b1;
                        current_result <= fpu_result; // result = result * base
                        work_exponent <= work_exponent - 1; // exponent = exponent - 1
                        state <= SQUARE_BASE;
                    end
                end
                
                FINALIZE: begin
                    reset_fpu_signals();
                    if (negative_exponent) begin
                        // Calculate 1 / current_result for negative exponent
                        fpu_a <= CONST_1;
                        fpu_b <= current_result;
                        fpu_a_stb <= 1'b1;
                        fpu_b_stb <= 1'b1;
                        use_divider <= 1'b1;
                        state <= WAIT_DIV;
                    end else begin
                        result <= current_result;
                        state <= OUTPUT_RESULT;
                    end
                end
                
                WAIT_DIV: begin
                    if (fpu_result_stb) begin
                        fpu_result_ack <= 1'b1;
                        result <= fpu_result;
                        state <= OUTPUT_RESULT;
                    end
                end
                
                OUTPUT_RESULT: begin
                    reset_fpu_signals();
                    calc_done <= 1'b1;
                    state <= WAIT_READ;
                end
                
                WAIT_READ: begin
                    if (read_done) begin
                        calc_done <= 1'b0;
                        ready <= 1'b1;  // Set ready for next calculation
                        // Don't reset result immediately, let it stay for debugging
                        current_base <= 32'b0;
                        current_result <= 32'b0;
                        work_exponent <= 32'b0;
                        negative_exponent <= 1'b0;
                        calculation_active <= 1'b0;
                        reset_fpu_signals();
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule