module vector_normalize_3d(
    input clk,
    input rst_n,
    
    // Handshake signals
    output ready,           // module báo sẵn sàng nhận dữ liệu
    input data_valid,       // master báo dữ liệu có sẵn (đủ 3 chiều)
    output calc_done,       // module báo tính toán xong
    input read_done,        // master báo đã đọc xong kết quả (đọc xong cả 3 chiều)
    
    // Data signals - nhận cùng lúc 3 chiều
    input [31:0] x_in,      // thành phần x
    input [31:0] y_in,      // thành phần y  
    input [31:0] z_in,      // thành phần z
    output [31:0] x_out,    // x_norm
    output [31:0] y_out,    // y_norm
    output [31:0] z_out     // z_norm
);

    // State machine states
    reg [5:0] state;
    parameter IDLE           = 6'd0,
              RECEIVE_DATA   = 6'd1,
              CHECK_ZERO     = 6'd2,
              CALC_X_SQUARE  = 6'd3,
              WAIT_X_SQUARE  = 6'd4,
              CALC_Y_SQUARE  = 6'd5,
              WAIT_Y_SQUARE  = 6'd6,
              CALC_Z_SQUARE  = 6'd7,
              WAIT_Z_SQUARE  = 6'd8,
              ADD_XY_SQUARE  = 6'd9,
              WAIT_ADD_XY    = 6'd10,
              ADD_Z_SQUARE   = 6'd11,
              WAIT_ADD_Z     = 6'd12,
              CALC_SQRT      = 6'd13,
              WAIT_SQRT      = 6'd14,
              DIV_X          = 6'd15,
              WAIT_DIV_X     = 6'd16,
              DIV_Y          = 6'd17,
              WAIT_DIV_Y     = 6'd18,
              DIV_Z          = 6'd19,
              WAIT_DIV_Z     = 6'd20,
              OUTPUT_READY   = 6'd21;

    // Internal registers
    reg [31:0] x, y, z;           // vector components
    reg [31:0] x_norm, y_norm, z_norm; // normalized components
    reg [31:0] x_square, y_square, z_square; // squared components
    reg [31:0] magnitude_square;   // x² + y² + z²
    reg [31:0] magnitude;         // sqrt(x² + y² + z²)
    reg s_ready;
    reg s_calc_done;
    
    // FP constants
    wire [31:0] fp_zero = 32'h00000000;  // 0.0 in IEEE 754
    
    // Multiplier signals
    reg mult_a_stb, mult_b_stb;
    wire mult_a_ack, mult_b_ack;
    wire [31:0] mult_result;
    wire mult_z_stb;
    reg mult_z_ack;
    reg [31:0] mult_a_data, mult_b_data;
    
    // Adder signals  
    reg add_a_stb, add_b_stb;
    wire add_a_ack, add_b_ack;
    wire [31:0] add_result;
    wire add_z_stb;
    reg add_z_ack;
    reg [31:0] add_a_data, add_b_data;
    
    // Divider signals
    reg div_a_stb, div_b_stb;
    wire div_a_ack, div_b_ack;
    wire [31:0] div_result;
    wire div_z_stb;
    reg div_z_ack;
    reg [31:0] div_a_data, div_b_data;
    
    // Square root signals
    reg sqrt_data_valid;
    wire sqrt_ready, sqrt_calc_done;
    reg sqrt_read_done;
    reg [31:0] sqrt_data_in;
    wire [31:0] sqrt_result;
    
    // Multiplier instance
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
    
    // Adder instance  
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
    
    // Divider instance
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
    
    // Square root instance
    sqrt_slave sqrt_unit(
        .clk(clk),
        .rst_n(rst_n),
        .ready(sqrt_ready),
        .data_valid(sqrt_data_valid),
        .calc_done(sqrt_calc_done),
        .read_done(sqrt_read_done),
        .data_in(sqrt_data_in),
        .result_out(sqrt_result)
    );
    
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            s_ready <= 1'b1;
            s_calc_done <= 1'b0;
            
            // Reset all handshake signals
            mult_a_stb <= 1'b0;
            mult_b_stb <= 1'b0;
            mult_z_ack <= 1'b0;
            add_a_stb <= 1'b0;
            add_b_stb <= 1'b0;
            add_z_ack <= 1'b0;
            div_a_stb <= 1'b0;
            div_b_stb <= 1'b0;
            div_z_ack <= 1'b0;
            sqrt_data_valid <= 1'b0;
            sqrt_read_done <= 1'b0;
            
        end else begin
            case (state)
                IDLE: begin
                    s_ready <= 1'b1;
                    s_calc_done <= 1'b0;
                    if (data_valid && s_ready) begin
                        s_ready <= 1'b0;  // Không sẵn sàng nhận dữ liệu mới
                        state <= RECEIVE_DATA;
                    end
                end
                
                RECEIVE_DATA: begin
                    // Nhận tất cả 3 thành phần cùng lúc
                    x <= x_in;
                    y <= y_in;
                    z <= z_in;
                    state <= CHECK_ZERO;
                end
                
                CHECK_ZERO: begin
                    // Kiểm tra vector không (0,0,0)
                    if ((x[30:0] == 31'b0) && (y[30:0] == 31'b0) && (z[30:0] == 31'b0)) begin
                        // Vector không, trả về (0,0,0)
                        x_norm <= fp_zero;
                        y_norm <= fp_zero;
                        z_norm <= fp_zero;
                        state <= OUTPUT_READY;
                    end else begin
                        // Bắt đầu tính x²
                        state <= CALC_X_SQUARE;
                    end
                end
                
                CALC_X_SQUARE: begin
                    // Tính x² = x * x
                    mult_a_data <= x;
                    mult_b_data <= x;
                    mult_a_stb <= 1'b1;
                    mult_b_stb <= 1'b1;
                    state <= WAIT_X_SQUARE;
                end
                
                WAIT_X_SQUARE: begin
                    if (mult_a_ack) mult_a_stb <= 1'b0;
                    if (mult_b_ack) mult_b_stb <= 1'b0;
                    
                    if (mult_z_stb) begin
                        mult_z_ack <= 1'b1;
                        x_square <= mult_result;
                        state <= CALC_Y_SQUARE;
                    end else begin
                        mult_z_ack <= 1'b0;
                    end
                end
                
                CALC_Y_SQUARE: begin
                    // Tính y² = y * y
                    mult_z_ack <= 1'b0;
                    mult_a_data <= y;
                    mult_b_data <= y;
                    mult_a_stb <= 1'b1;
                    mult_b_stb <= 1'b1;
                    state <= WAIT_Y_SQUARE;
                end
                
                WAIT_Y_SQUARE: begin
                    if (mult_a_ack) mult_a_stb <= 1'b0;
                    if (mult_b_ack) mult_b_stb <= 1'b0;
                    
                    if (mult_z_stb) begin
                        mult_z_ack <= 1'b1;
                        y_square <= mult_result;
                        state <= CALC_Z_SQUARE;
                    end else begin
                        mult_z_ack <= 1'b0;
                    end
                end
                
                CALC_Z_SQUARE: begin
                    // Tính z² = z * z
                    mult_z_ack <= 1'b0;
                    mult_a_data <= z;
                    mult_b_data <= z;
                    mult_a_stb <= 1'b1;
                    mult_b_stb <= 1'b1;
                    state <= WAIT_Z_SQUARE;
                end
                
                WAIT_Z_SQUARE: begin
                    if (mult_a_ack) mult_a_stb <= 1'b0;
                    if (mult_b_ack) mult_b_stb <= 1'b0;
                    
                    if (mult_z_stb) begin
                        mult_z_ack <= 1'b1;
                        z_square <= mult_result;
                        state <= ADD_XY_SQUARE;
                    end else begin
                        mult_z_ack <= 1'b0;
                    end
                end
                
                ADD_XY_SQUARE: begin
                    // Tính x² + y²
                    mult_z_ack <= 1'b0;
                    add_a_data <= x_square;
                    add_b_data <= y_square;
                    add_a_stb <= 1'b1;
                    add_b_stb <= 1'b1;
                    state <= WAIT_ADD_XY;
                end
                
                WAIT_ADD_XY: begin
                    if (add_a_ack) add_a_stb <= 1'b0;
                    if (add_b_ack) add_b_stb <= 1'b0;
                    
                    if (add_z_stb) begin
                        add_z_ack <= 1'b1;
                        state <= ADD_Z_SQUARE;
                    end else begin
                        add_z_ack <= 1'b0;
                    end
                end
                
                ADD_Z_SQUARE: begin
                    // Tính (x² + y²) + z² = x² + y² + z²
                    add_z_ack <= 1'b0;
                    add_a_data <= add_result;
                    add_b_data <= z_square;
                    add_a_stb <= 1'b1;
                    add_b_stb <= 1'b1;
                    state <= WAIT_ADD_Z;
                end
                
                WAIT_ADD_Z: begin
                    if (add_a_ack) add_a_stb <= 1'b0;
                    if (add_b_ack) add_b_stb <= 1'b0;
                    
                    if (add_z_stb) begin
                        add_z_ack <= 1'b1;
                        magnitude_square <= add_result;
                        state <= CALC_SQRT;
                    end else begin
                        add_z_ack <= 1'b0;
                    end
                end
                
                CALC_SQRT: begin
                    // Tính sqrt(x² + y² + z²)
                    add_z_ack <= 1'b0;
                    if (sqrt_ready) begin
                        sqrt_data_in <= magnitude_square;
                        sqrt_data_valid <= 1'b1;
                        state <= WAIT_SQRT;
                    end
                end
                
                WAIT_SQRT: begin
                    sqrt_data_valid <= 1'b0;
                    if (sqrt_calc_done) begin
                        magnitude <= sqrt_result;
                        sqrt_read_done <= 1'b1;
                        state <= DIV_X;
                    end else begin
                        sqrt_read_done <= 1'b0;
                    end
                end
                
                DIV_X: begin
                    // Tính x_norm = x / magnitude
                    sqrt_read_done <= 1'b0;
                    div_a_data <= x;
                    div_b_data <= magnitude;
                    div_a_stb <= 1'b1;
                    div_b_stb <= 1'b1;
                    state <= WAIT_DIV_X;
                end
                
                WAIT_DIV_X: begin
                    if (div_a_ack) div_a_stb <= 1'b0;
                    if (div_b_ack) div_b_stb <= 1'b0;
                    
                    if (div_z_stb) begin
                        div_z_ack <= 1'b1;
                        x_norm <= div_result;
                        state <= DIV_Y;
                    end else begin
                        div_z_ack <= 1'b0;
                    end
                end
                
                DIV_Y: begin
                    // Tính y_norm = y / magnitude
                    div_z_ack <= 1'b0;
                    div_a_data <= y;
                    div_b_data <= magnitude;
                    div_a_stb <= 1'b1;
                    div_b_stb <= 1'b1;
                    state <= WAIT_DIV_Y;
                end
                
                WAIT_DIV_Y: begin
                    if (div_a_ack) div_a_stb <= 1'b0;
                    if (div_b_ack) div_b_stb <= 1'b0;
                    
                    if (div_z_stb) begin
                        div_z_ack <= 1'b1;
                        y_norm <= div_result;
                        state <= DIV_Z;
                    end else begin
                        div_z_ack <= 1'b0;
                    end
                end
                
                DIV_Z: begin
                    // Tính z_norm = z / magnitude
                    div_z_ack <= 1'b0;
                    div_a_data <= z;
                    div_b_data <= magnitude;
                    div_a_stb <= 1'b1;
                    div_b_stb <= 1'b1;
                    state <= WAIT_DIV_Z;
                end
                
                WAIT_DIV_Z: begin
                    if (div_a_ack) div_a_stb <= 1'b0;
                    if (div_b_ack) div_b_stb <= 1'b0;
                    
                    if (div_z_stb) begin
                        div_z_ack <= 1'b1;
                        z_norm <= div_result;
                        state <= OUTPUT_READY;
                    end else begin
                        div_z_ack <= 1'b0;
                    end
                end
                
                OUTPUT_READY: begin
                    // Tính toán hoàn thành, chờ master đọc xong
                    div_z_ack <= 1'b0;
                    s_calc_done <= 1'b1;
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
    
    // Output cả 3 chiều cùng lúc
    assign x_out = x_norm;
    assign y_out = y_norm;
    assign z_out = z_norm;

endmodule
// module vector_normalize_3d(
    // input clk,
    // input rst_n,
    
    // // Handshake signals
    // output ready,           
    // input data_valid,       
    // output calc_done,       
    // input read_done,        
    
    // // Data signals
    // input [31:0] x_in,      
    // input [31:0] y_in,      
    // input [31:0] z_in,      
    // output [31:0] x_out,    
    // output [31:0] y_out,    
    // output [31:0] z_out     
// );

    // // State machine states - ít states hơn nhờ song song
    // reg [4:0] state;
    // parameter IDLE           = 5'd0,
              // RECEIVE_DATA   = 5'd1,
              // CHECK_ZERO     = 5'd2,
              // CALC_SQUARES   = 5'd3,  // Tính 3 bình phương song song
              // WAIT_SQUARES   = 5'd4,
              // ADD_XY_SQUARE  = 5'd5,
              // WAIT_ADD_XY    = 5'd6,
              // ADD_Z_SQUARE   = 5'd7,
              // WAIT_ADD_Z     = 5'd8,
              // CALC_SQRT      = 5'd9,
              // WAIT_SQRT      = 5'd10,
              // DIV_X          = 5'd11, // Chia tuần tự nhưng nhanh hơn
              // WAIT_DIV_X     = 5'd12,
              // DIV_Y          = 5'd13,
              // WAIT_DIV_Y     = 5'd14,
              // DIV_Z          = 5'd15,
              // WAIT_DIV_Z     = 5'd16,
              // OUTPUT_READY   = 5'd17;

    // // Internal registers
    // reg [31:0] x, y, z;           
    // reg [31:0] x_norm, y_norm, z_norm; 
    // reg [31:0] x_square, y_square, z_square; 
    // reg [31:0] magnitude_square;   
    // reg [31:0] magnitude;         
    // reg s_ready;
    // reg s_calc_done;
    
    // // FP constants
    // wire [31:0] fp_zero = 32'h00000000;
    
    // // 3 Multipliers cho song song
    // reg mult_x_a_stb, mult_x_b_stb;
    // wire mult_x_a_ack, mult_x_b_ack;
    // wire [31:0] mult_x_result;
    // wire mult_x_z_stb;
    // reg mult_x_z_ack;
    // reg [31:0] mult_x_a_data, mult_x_b_data;
    
    // reg mult_y_a_stb, mult_y_b_stb;
    // wire mult_y_a_ack, mult_y_b_ack;
    // wire [31:0] mult_y_result;
    // wire mult_y_z_stb;
    // reg mult_y_z_ack;
    // reg [31:0] mult_y_a_data, mult_y_b_data;
    
    // reg mult_z_a_stb, mult_z_b_stb;
    // wire mult_z_a_ack, mult_z_b_ack;
    // wire [31:0] mult_z_result;
    // wire mult_z_z_stb;
    // reg mult_z_z_ack;
    // reg [31:0] mult_z_a_data, mult_z_b_data;
    
    // // 2 Adders cho tree addition
    // reg add1_a_stb, add1_b_stb;
    // wire add1_a_ack, add1_b_ack;
    // wire [31:0] add1_result;
    // wire add1_z_stb;
    // reg add1_z_ack;
    // reg [31:0] add1_a_data, add1_b_data;
    
    // reg add2_a_stb, add2_b_stb;
    // wire add2_a_ack, add2_b_ack;
    // wire [31:0] add2_result;
    // wire add2_z_stb;
    // reg add2_z_ack;
    // reg [31:0] add2_a_data, add2_b_data;
    
    // // 1 Divider (reuse)
    // reg div_a_stb, div_b_stb;
    // wire div_a_ack, div_b_ack;
    // wire [31:0] div_result;
    // wire div_z_stb;
    // reg div_z_ack;
    // reg [31:0] div_a_data, div_b_data;
    
    // // Square root signals
    // reg sqrt_data_valid;
    // wire sqrt_ready, sqrt_calc_done;
    // reg sqrt_read_done;
    // reg [31:0] sqrt_data_in;
    // wire [31:0] sqrt_result;
    
    // // Status tracking cho 3 multipliers
    // reg mult_x_done, mult_y_done, mult_z_done;
    // wire all_squares_done = mult_x_done & mult_y_done & mult_z_done;
    
    // // 3 Multiplier instances
    // multiplier mult_x_unit(
        // .input_a(mult_x_a_data), .input_b(mult_x_b_data),
        // .input_a_stb(mult_x_a_stb), .input_b_stb(mult_x_b_stb),
        // .output_z_ack(mult_x_z_ack), .clk(clk), .rst(~rst_n),
        // .output_z(mult_x_result), .output_z_stb(mult_x_z_stb),
        // .input_a_ack(mult_x_a_ack), .input_b_ack(mult_x_b_ack)
    // );
    
    // multiplier mult_y_unit(
        // .input_a(mult_y_a_data), .input_b(mult_y_b_data),
        // .input_a_stb(mult_y_a_stb), .input_b_stb(mult_y_b_stb),
        // .output_z_ack(mult_y_z_ack), .clk(clk), .rst(~rst_n),
        // .output_z(mult_y_result), .output_z_stb(mult_y_z_stb),
        // .input_a_ack(mult_y_a_ack), .input_b_ack(mult_y_b_ack)
    // );
    
    // multiplier mult_z_unit(
        // .input_a(mult_z_a_data), .input_b(mult_z_b_data),
        // .input_a_stb(mult_z_a_stb), .input_b_stb(mult_z_b_stb),
        // .output_z_ack(mult_z_z_ack), .clk(clk), .rst(~rst_n),
        // .output_z(mult_z_result), .output_z_stb(mult_z_z_stb),
        // .input_a_ack(mult_z_a_ack), .input_b_ack(mult_z_b_ack)
    // );
    
    // // 2 Adder instances
    // adder add1_unit(
        // .input_a(add1_a_data), .input_b(add1_b_data),
        // .input_a_stb(add1_a_stb), .input_b_stb(add1_b_stb),
        // .output_z_ack(add1_z_ack), .clk(clk), .rst(~rst_n),
        // .output_z(add1_result), .output_z_stb(add1_z_stb),
        // .input_a_ack(add1_a_ack), .input_b_ack(add1_b_ack)
    // );
    
    // adder add2_unit(
        // .input_a(add2_a_data), .input_b(add2_b_data),
        // .input_a_stb(add2_a_stb), .input_b_stb(add2_b_stb),
        // .output_z_ack(add2_z_ack), .clk(clk), .rst(~rst_n),
        // .output_z(add2_result), .output_z_stb(add2_z_stb),
        // .input_a_ack(add2_a_ack), .input_b_ack(add2_b_ack)
    // );
    
    // // 1 Divider instance
    // divider div_unit(
        // .input_a(div_a_data), .input_b(div_b_data),
        // .input_a_stb(div_a_stb), .input_b_stb(div_b_stb),
        // .output_z_ack(div_z_ack), .clk(clk), .rst(~rst_n),
        // .output_z(div_result), .output_z_stb(div_z_stb),
        // .input_a_ack(div_a_ack), .input_b_ack(div_b_ack)
    // );
    
    // // Square root instance
    // sqrt_slave sqrt_unit(
        // .clk(clk), .rst_n(rst_n),
        // .ready(sqrt_ready), .data_valid(sqrt_data_valid),
        // .calc_done(sqrt_calc_done), .read_done(sqrt_read_done),
        // .data_in(sqrt_data_in), .result_out(sqrt_result)
    // );
    
    // always @(posedge clk) begin
        // if (!rst_n) begin
            // state <= IDLE;
            // s_ready <= 1'b1;
            // s_calc_done <= 1'b0;
            
            // // Reset all multiplier signals
            // mult_x_a_stb <= 1'b0; mult_x_b_stb <= 1'b0; mult_x_z_ack <= 1'b0;
            // mult_y_a_stb <= 1'b0; mult_y_b_stb <= 1'b0; mult_y_z_ack <= 1'b0;
            // mult_z_a_stb <= 1'b0; mult_z_b_stb <= 1'b0; mult_z_z_ack <= 1'b0;
            
            // // Reset adder signals
            // add1_a_stb <= 1'b0; add1_b_stb <= 1'b0; add1_z_ack <= 1'b0;
            // add2_a_stb <= 1'b0; add2_b_stb <= 1'b0; add2_z_ack <= 1'b0;
            
            // // Reset divider signals
            // div_a_stb <= 1'b0; div_b_stb <= 1'b0; div_z_ack <= 1'b0;
            
            // sqrt_data_valid <= 1'b0; sqrt_read_done <= 1'b0;
            
            // mult_x_done <= 1'b0; mult_y_done <= 1'b0; mult_z_done <= 1'b0;
            
        // end else begin
            // case (state)
                // IDLE: begin
                    // s_ready <= 1'b1;
                    // s_calc_done <= 1'b0;
                    // if (data_valid && s_ready) begin
                        // s_ready <= 1'b0;
                        // state <= RECEIVE_DATA;
                    // end
                // end
                
                // RECEIVE_DATA: begin
                    // x <= x_in; y <= y_in; z <= z_in;
                    // state <= CHECK_ZERO;
                // end
                
                // CHECK_ZERO: begin
                    // if ((x[30:0] == 31'b0) && (y[30:0] == 31'b0) && (z[30:0] == 31'b0)) begin
                        // x_norm <= fp_zero; y_norm <= fp_zero; z_norm <= fp_zero;
                        // state <= OUTPUT_READY;
                    // end else begin
                        // state <= CALC_SQUARES;
                    // end
                // end
                
                // CALC_SQUARES: begin
                    // // Khởi động 3 multipliers song song
                    // mult_x_a_data <= x; mult_x_b_data <= x;
                    // mult_x_a_stb <= 1'b1; mult_x_b_stb <= 1'b1;
                    
                    // mult_y_a_data <= y; mult_y_b_data <= y;
                    // mult_y_a_stb <= 1'b1; mult_y_b_stb <= 1'b1;
                    
                    // mult_z_a_data <= z; mult_z_b_data <= z;
                    // mult_z_a_stb <= 1'b1; mult_z_b_stb <= 1'b1;
                    
                    // mult_x_done <= 1'b0; mult_y_done <= 1'b0; mult_z_done <= 1'b0;
                    // state <= WAIT_SQUARES;
                // end
                
                // WAIT_SQUARES: begin
                    // // Xử lý mult_x
                    // if (mult_x_a_ack) mult_x_a_stb <= 1'b0;
                    // if (mult_x_b_ack) mult_x_b_stb <= 1'b0;
                    // if (mult_x_z_stb && !mult_x_done) begin
                        // mult_x_z_ack <= 1'b1;
                        // x_square <= mult_x_result;
                        // mult_x_done <= 1'b1;
                    // end else if (mult_x_done) begin
                        // mult_x_z_ack <= 1'b0;
                    // end
                    
                    // // Xử lý mult_y
                    // if (mult_y_a_ack) mult_y_a_stb <= 1'b0;
                    // if (mult_y_b_ack) mult_y_b_stb <= 1'b0;
                    // if (mult_y_z_stb && !mult_y_done) begin
                        // mult_y_z_ack <= 1'b1;
                        // y_square <= mult_y_result;
                        // mult_y_done <= 1'b1;
                    // end else if (mult_y_done) begin
                        // mult_y_z_ack <= 1'b0;
                    // end
                    
                    // // Xử lý mult_z
                    // if (mult_z_a_ack) mult_z_a_stb <= 1'b0;
                    // if (mult_z_b_ack) mult_z_b_stb <= 1'b0;
                    // if (mult_z_z_stb && !mult_z_done) begin
                        // mult_z_z_ack <= 1'b1;
                        // z_square <= mult_z_result;
                        // mult_z_done <= 1'b1;
                    // end else if (mult_z_done) begin
                        // mult_z_z_ack <= 1'b0;
                    // end
                    
                    // // Chuyển state khi tất cả xong
                    // if (all_squares_done) begin
                        // state <= ADD_XY_SQUARE;
                    // end
                // end
                
                // ADD_XY_SQUARE: begin
                    // // Tính x² + y² với add1
                    // add1_a_data <= x_square;
                    // add1_b_data <= y_square;
                    // add1_a_stb <= 1'b1;
                    // add1_b_stb <= 1'b1;
                    // state <= WAIT_ADD_XY;
                // end
                
                // WAIT_ADD_XY: begin
                    // if (add1_a_ack) add1_a_stb <= 1'b0;
                    // if (add1_b_ack) add1_b_stb <= 1'b0;
                    
                    // if (add1_z_stb) begin
                        // add1_z_ack <= 1'b1;
                        // state <= ADD_Z_SQUARE;
                    // end else begin
                        // add1_z_ack <= 1'b0;
                    // end
                // end
                
                // ADD_Z_SQUARE: begin
                    // // Tính (x² + y²) + z² với add2
                    // add1_z_ack <= 1'b0;
                    // add2_a_data <= add1_result;
                    // add2_b_data <= z_square;
                    // add2_a_stb <= 1'b1;
                    // add2_b_stb <= 1'b1;
                    // state <= WAIT_ADD_Z;
                // end
                
                // WAIT_ADD_Z: begin
                    // if (add2_a_ack) add2_a_stb <= 1'b0;
                    // if (add2_b_ack) add2_b_stb <= 1'b0;
                    
                    // if (add2_z_stb) begin
                        // add2_z_ack <= 1'b1;
                        // magnitude_square <= add2_result;
                        // state <= CALC_SQRT;
                    // end else begin
                        // add2_z_ack <= 1'b0;
                    // end
                // end
                
                // CALC_SQRT: begin
                    // add2_z_ack <= 1'b0;
                    // if (sqrt_ready) begin
                        // sqrt_data_in <= magnitude_square;
                        // sqrt_data_valid <= 1'b1;
                        // state <= WAIT_SQRT;
                    // end
                // end
                
                // WAIT_SQRT: begin
                    // sqrt_data_valid <= 1'b0;
                    // if (sqrt_calc_done) begin
                        // magnitude <= sqrt_result;
                        // sqrt_read_done <= 1'b1;
                        // state <= DIV_X;
                    // end else begin
                        // sqrt_read_done <= 1'b0;
                    // end
                // end
                
                // // 3 phép chia tuần tự với 1 divider
                // DIV_X: begin
                    // sqrt_read_done <= 1'b0;
                    // div_a_data <= x;
                    // div_b_data <= magnitude;
                    // div_a_stb <= 1'b1;
                    // div_b_stb <= 1'b1;
                    // state <= WAIT_DIV_X;
                // end
                
                // WAIT_DIV_X: begin
                    // if (div_a_ack) div_a_stb <= 1'b0;
                    // if (div_b_ack) div_b_stb <= 1'b0;
                    
                    // if (div_z_stb) begin
                        // div_z_ack <= 1'b1;
                        // x_norm <= div_result;
                        // state <= DIV_Y;
                    // end else begin
                        // div_z_ack <= 1'b0;
                    // end
                // end
                
                // DIV_Y: begin
                    // div_z_ack <= 1'b0;
                    // div_a_data <= y;
                    // div_b_data <= magnitude;
                    // div_a_stb <= 1'b1;
                    // div_b_stb <= 1'b1;
                    // state <= WAIT_DIV_Y;
                // end
                
                // WAIT_DIV_Y: begin
                    // if (div_a_ack) div_a_stb <= 1'b0;
                    // if (div_b_ack) div_b_stb <= 1'b0;
                    
                    // if (div_z_stb) begin
                        // div_z_ack <= 1'b1;
                        // y_norm <= div_result;
                        // state <= DIV_Z;
                    // end else begin
                        // div_z_ack <= 1'b0;
                    // end
                // end
                
                // DIV_Z: begin
                    // div_z_ack <= 1'b0;
                    // div_a_data <= z;
                    // div_b_data <= magnitude;
                    // div_a_stb <= 1'b1;
                    // div_b_stb <= 1'b1;
                    // state <= WAIT_DIV_Z;
                // end
                
                // WAIT_DIV_Z: begin
                    // if (div_a_ack) div_a_stb <= 1'b0;
                    // if (div_b_ack) div_b_stb <= 1'b0;
                    
                    // if (div_z_stb) begin
                        // div_z_ack <= 1'b1;
                        // z_norm <= div_result;
                        // state <= OUTPUT_READY;
                    // end else begin
                        // div_z_ack <= 1'b0;
                    // end
                // end
                
                // OUTPUT_READY: begin
                    // div_z_ack <= 1'b0;
                    // s_calc_done <= 1'b1;
                    // if (read_done) begin
                        // s_calc_done <= 1'b0;
                        // state <= IDLE;
                    // end
                // end
                
                // default: begin
                    // state <= IDLE;
                // end
            // endcase
        // end
    // end
    
    // // Output assignments
    // assign ready = s_ready;
    // assign calc_done = s_calc_done;
    // assign x_out = x_norm;
    // assign y_out = y_norm;
    // assign z_out = z_norm;

// endmodule