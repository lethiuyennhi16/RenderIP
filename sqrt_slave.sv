module sqrt_slave(
    input clk,
    input rst_n,
    
    // Handshake signals
    output ready,           // slave báo sẵn sàng nhận dữ liệu
    input data_valid,       // master báo dữ liệu có sẵn
    output calc_done,       // slave báo tính toán xong
    input read_done,        // master báo đã đọc xong kết quả
    
    // Data signals
    input [31:0] data_in,    // dữ liệu đầu vào
    output [31:0] result_out   // kết quả căn bậc 2
);

    // State machine states
    reg [4:0] state;
    parameter IDLE          = 5'd0,
              RECEIVE_DATA  = 5'd1,
              CHECK_SPECIAL = 5'd2,
              INIT_GUESS    = 5'd3,
              NEWTON_ITER   = 5'd4,
              START_DIV     = 5'd5,
              WAIT_DIV      = 5'd6,
              START_ADD     = 5'd7,
              WAIT_ADD      = 5'd8,
              START_MULT    = 5'd9,
              WAIT_MULT     = 5'd10,
              CHECK_CONV    = 5'd11,
              COMPLETE      = 5'd12,
              WAIT_READ     = 5'd13;

    // Internal registers
    reg [31:0] x;              // input value
    reg [31:0] guess;          // current guess
    reg [31:0] prev_guess;     // previous guess for convergence check
    reg [31:0] result;         // final result
    reg [3:0] iter_count;      // iteration counter
    reg s_ready;
    reg s_calc_done;
    
    // FP constants
    wire [31:0] fp_half = 32'h3F000000;  // 0.5 in IEEE 754
    wire [31:0] fp_one  = 32'h3F800000;  // 1.0 in IEEE 754
    wire [31:0] fp_zero = 32'h00000000;  // 0.0 in IEEE 754
    
    // Division unit signals
    reg div_a_stb, div_b_stb;
    wire div_a_ack, div_b_ack;
    wire [31:0] div_result;
    wire div_z_stb;
    reg div_z_ack;
    
    // Addition unit signals  
    reg add_a_stb, add_b_stb;
    wire add_a_ack, add_b_ack;
    wire [31:0] add_result;
    wire add_z_stb;
    reg add_z_ack;
    
    // Multiplication unit signals
    reg mult_a_stb, mult_b_stb;
    wire mult_a_ack, mult_b_ack;
    wire [31:0] mult_result;
    wire mult_z_stb;
    reg mult_z_ack;
    
    // Data for arithmetic operations
    reg [31:0] div_a_data, div_b_data;
    reg [31:0] add_a_data, add_b_data;
    reg [31:0] mult_a_data, mult_b_data;
    
    // Division unit instance
    divider div_unit(
        .input_a(div_a_data),
        .input_b(div_b_data),
        .input_a_stb(div_a_stb),
        .input_b_stb(div_b_stb),
        .output_z_ack(div_z_ack),
        .clk(clk),
        .rst(~rst_n),
        .output_z(div_result),
        .output_z_stb(div_z_stb),
        .input_a_ack(div_a_ack),
        .input_b_ack(div_b_ack)
    );
    
    // Addition unit instance  
    adder add_unit(
        .input_a(add_a_data),
        .input_b(add_b_data),
        .input_a_stb(add_a_stb),
        .input_b_stb(add_b_stb),
        .output_z_ack(add_z_ack),
        .clk(clk),
        .rst(~rst_n),
        .output_z(add_result),
        .output_z_stb(add_z_stb),
        .input_a_ack(add_a_ack),
        .input_b_ack(add_b_ack)
    );
    
    // Multiplication unit instance
    multiplier mult_unit(
        .input_a(mult_a_data),
        .input_b(mult_b_data),
        .input_a_stb(mult_a_stb),
        .input_b_stb(mult_b_stb),
        .output_z_ack(mult_z_ack),
        .clk(clk),
        .rst(~rst_n),
        .output_z(mult_result),
        .output_z_stb(mult_z_stb),
        .input_a_ack(mult_a_ack),
        .input_b_ack(mult_b_ack)
    );
    
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            s_ready <= 1'b1;
            s_calc_done <= 1'b0;
            iter_count <= 4'd0;
            div_a_stb <= 1'b0;
            div_b_stb <= 1'b0;
            div_z_ack <= 1'b0;
            add_a_stb <= 1'b0;
            add_b_stb <= 1'b0;
            add_z_ack <= 1'b0;
            mult_a_stb <= 1'b0;
            mult_b_stb <= 1'b0;
            mult_z_ack <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    s_ready <= 1'b1;
                    s_calc_done <= 1'b0;
                    if (data_valid && s_ready) begin
                        x <= data_in;
                        s_ready <= 1'b0;
                        state <= RECEIVE_DATA;
                    end
                end
                
                RECEIVE_DATA: begin
                    state <= CHECK_SPECIAL;
                end
                
                CHECK_SPECIAL: begin
                    // Kiểm tra các trường hợp đặc biệt
                    if (x[30:0] == 31'b0) begin
                        // x = 0 hoặc -0, sqrt(0) = 0
                        result <= fp_zero;
                        state <= COMPLETE;
                    end else if (x[31] == 1'b1) begin
                        // x < 0, trả về NaN
                        result <= 32'h7FC00000; // NaN
                        state <= COMPLETE;
                    end else if (x[30:23] == 8'hFF) begin
                        if (x[22:0] == 23'b0) begin
                            // x = +infinity, sqrt(inf) = inf
                            result <= x;
                        end else begin
                            // x = NaN, sqrt(NaN) = NaN
                            result <= x;
                        end
                        state <= COMPLETE;
                    end else begin
                        // Trường hợp bình thường, bắt đầu tính toán
                        state <= INIT_GUESS;
                    end
                end
                
                INIT_GUESS: begin
                    // Tạo guess ban đầu bằng cách chia đôi exponent
                    if (x[30:23] == 8'h00) begin
                        // Số denormalized
                        guess <= 32'h3F000000; // 0.5
                    end else begin
                        // Số normalized - chia đôi exponent
                        reg [8:0] exp_temp;
                        exp_temp = (x[30:23] + 127) >> 1;
                        guess <= {1'b0, exp_temp[7:0], 23'h400000}; // Mantissa = 1.0
                    end
                    iter_count <= 4'd0;
                    state <= NEWTON_ITER;
                end
                
                NEWTON_ITER: begin
                    if (iter_count < 4'd6) begin // Tối đa 6 lần lặp
                        prev_guess <= guess;
                        state <= START_DIV;
                    end else begin
                        result <= guess;
                        state <= COMPLETE;
                    end
                end
                
                START_DIV: begin
                    // Bắt đầu phép chia: x / guess
                    div_a_data <= x;
                    div_b_data <= guess;
                    div_a_stb <= 1'b1;
                    div_b_stb <= 1'b1;
                    state <= WAIT_DIV;
                end
                
                WAIT_DIV: begin
                    // Chờ phép chia hoàn thành
                    if (div_a_ack) div_a_stb <= 1'b0;
                    if (div_b_ack) div_b_stb <= 1'b0;
                    
                    if (div_z_stb) begin
                        div_z_ack <= 1'b1;
                        state <= START_ADD;
                    end else begin
                        div_z_ack <= 1'b0;
                    end
                end
                
                START_ADD: begin
                    // Bắt đầu phép cộng: guess + (x/guess)
                    div_z_ack <= 1'b0;
                    add_a_data <= guess;
                    add_b_data <= div_result;
                    add_a_stb <= 1'b1;
                    add_b_stb <= 1'b1;
                    state <= WAIT_ADD;
                end
                
                WAIT_ADD: begin
                    // Chờ phép cộng hoàn thành
                    if (add_a_ack) add_a_stb <= 1'b0;
                    if (add_b_ack) add_b_stb <= 1'b0;
                    
                    if (add_z_stb) begin
                        add_z_ack <= 1'b1;
                        state <= START_MULT;
                    end else begin
                        add_z_ack <= 1'b0;
                    end
                end
                
                START_MULT: begin
                    // Bắt đầu phép nhân: 0.5 * (guess + x/guess)
                    add_z_ack <= 1'b0;
                    mult_a_data <= fp_half;
                    mult_b_data <= add_result;
                    mult_a_stb <= 1'b1;
                    mult_b_stb <= 1'b1;
                    state <= WAIT_MULT;
                end
                
                WAIT_MULT: begin
                    // Chờ phép nhân hoàn thành
                    if (mult_a_ack) mult_a_stb <= 1'b0;
                    if (mult_b_ack) mult_b_stb <= 1'b0;
                    
                    if (mult_z_stb) begin
                        mult_z_ack <= 1'b1;
                        guess <= mult_result;
                        state <= CHECK_CONV;
                    end else begin
                        mult_z_ack <= 1'b0;
                    end
                end
                
                CHECK_CONV: begin
                    mult_z_ack <= 1'b0;
                    iter_count <= iter_count + 1;
                    // Kiểm tra hội tụ - nếu guess gần bằng prev_guess thì dừng
                    // Đơn giản: chỉ kiểm tra số lần lặp
                    state <= NEWTON_ITER;
                end
                
                COMPLETE: begin
                    s_calc_done <= 1'b1;
                    state <= WAIT_READ;
                end
                
                WAIT_READ: begin
                    if (read_done) begin
                        s_calc_done <= 1'b0;
                        state <= IDLE;
                    end
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
    
    // Output assignments
    assign ready = s_ready;
    assign calc_done = s_calc_done;
    assign result_out = result;

endmodule