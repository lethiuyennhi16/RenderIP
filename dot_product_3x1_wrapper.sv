module dot_product_3x1_wrapper (
    input logic iClk,
    input logic iRstn,
    output logic ready,
    input logic data_valid,
    input logic [31:0] data,
    output logic data_done,
    output logic calc_done,
    output logic [31:0] result,
    input logic read_done
);

    // Tín hiệu nội bộ cho giao diện nhân
    logic [31:0] mul_input_a_0, mul_input_b_0;
    logic mul_input_a_stb_0, mul_input_b_stb_0, mul_input_a_ack_0, mul_input_b_ack_0;
    logic [31:0] mul_output_z_0;
    logic mul_output_z_stb_0, mul_output_z_ack_0;
    logic [31:0] mul_input_a_1, mul_input_b_1;
    logic mul_input_a_stb_1, mul_input_b_stb_1, mul_input_a_ack_1, mul_input_b_ack_1;
    logic [31:0] mul_output_z_1;
    logic mul_output_z_stb_1, mul_output_z_ack_1;
    logic [31:0] mul_input_a_2, mul_input_b_2;
    logic mul_input_a_stb_2, mul_input_b_stb_2, mul_input_a_ack_2, mul_input_b_ack_2;
    logic [31:0] mul_output_z_2;
    logic mul_output_z_stb_2, mul_output_z_ack_2;

    // Tín hiệu nội bộ cho giao diện cộng
    logic [31:0] add_input_a_0, add_input_b_0;
    logic add_input_a_stb_0, add_input_b_stb_0, add_input_a_ack_0, add_input_b_ack_0;
    logic [31:0] add_output_z_0;
    logic add_output_z_stb_0, add_output_z_ack_0;
    logic [31:0] add_input_a_1, add_input_b_1;
    logic add_input_a_stb_1, add_input_b_stb_1, add_input_a_ack_1, add_input_b_ack_1;
    logic [31:0] add_output_z_1;
    logic add_output_z_stb_1, add_output_z_ack_1;

    // Chuyển đổi reset tích cực thấp (iRstn) thành tích cực cao (rst)
    logic rst;
    assign rst = ~iRstn;

    // Instantiate module dot_product_3x1
    dot_product_3x1 dot_product_inst (
        .iClk(iClk),
        .iRstn(iRstn),
        .mul_data_a_0(mul_input_a_0),
        .mul_data_b_0(mul_input_b_0),
        .mul_a_stb_0(mul_input_a_stb_0),
        .mul_b_stb_0(mul_input_b_stb_0),
        .mul_a_ack_0(mul_input_a_ack_0),
        .mul_b_ack_0(mul_input_b_ack_0),
        .mul_result_0(mul_output_z_0),
        .mul_z_stb_0(mul_output_z_stb_0),
        .mul_z_ack_0(mul_output_z_ack_0),
        .mul_data_a_1(mul_input_a_1),
        .mul_data_b_1(mul_input_b_1),
        .mul_a_stb_1(mul_input_a_stb_1),
        .mul_b_stb_1(mul_input_b_stb_1),
        .mul_a_ack_1(mul_input_a_ack_1),
        .mul_b_ack_1(mul_input_b_ack_1),
        .mul_result_1(mul_output_z_1),
        .mul_z_stb_1(mul_output_z_stb_1),
        .mul_z_ack_1(mul_output_z_ack_1),
        .mul_data_a_2(mul_input_a_2),
        .mul_data_b_2(mul_input_b_2),
        .mul_a_stb_2(mul_input_a_stb_2),
        .mul_b_stb_2(mul_input_b_stb_2),
        .mul_a_ack_2(mul_input_a_ack_2),
        .mul_b_ack_2(mul_input_b_ack_2),
        .mul_result_2(mul_output_z_2),
        .mul_z_stb_2(mul_output_z_stb_2),
        .mul_z_ack_2(mul_output_z_ack_2),
        .add_data_a(add_input_a_0),
        .add_data_b(add_input_b_0),
        .add_a_stb(add_input_a_stb_0),
        .add_b_stb(add_input_b_stb_0),
        .add_a_ack(add_input_a_ack_0),
        .add_b_ack(add_input_b_ack_0),
        .add_result(add_output_z_0),
        .add_z_stb(add_output_z_stb_0),
        .add_z_ack(add_output_z_ack_0),
        .add_data_a_1(add_input_a_1),
        .add_data_b_1(add_input_b_1),
        .add_a_stb_1(add_input_a_stb_1),
        .add_b_stb_1(add_input_b_stb_1),
        .add_a_ack_1(add_input_a_ack_1),
        .add_b_ack_1(add_input_b_ack_1),
        .add_result_1(add_output_z_1),
        .add_z_stb_1(add_output_z_stb_1),
        .add_z_ack_1(add_output_z_ack_1),
        .ready(ready),
        .data_valid(data_valid),
        .data(data),
        .data_done(data_done),
        .calc_done(calc_done),
        .result(result),
        .read_done(read_done)
    );

    // Instantiate 3 multipliers
    multiplier mul_0 (
        .clk(iClk),
        .rst(rst),
        .input_a(mul_input_a_0),
        .input_b(mul_input_b_0),
        .input_a_stb(mul_input_a_stb_0),
        .input_b_stb(mul_input_b_stb_0),
        .input_a_ack(mul_input_a_ack_0),
        .input_b_ack(mul_input_b_ack_0),
        .output_z(mul_output_z_0),
        .output_z_stb(mul_output_z_stb_0),
        .output_z_ack(mul_output_z_ack_0)
    );

    multiplier mul_1 (
        .clk(iClk),
        .rst(rst),
        .input_a(mul_input_a_1),
        .input_b(mul_input_b_1),
        .input_a_stb(mul_input_a_stb_1),
        .input_b_stb(mul_input_b_stb_1),
        .input_a_ack(mul_input_a_ack_1),
        .input_b_ack(mul_input_b_ack_1),
        .output_z(mul_output_z_1),
        .output_z_stb(mul_output_z_stb_1),
        .output_z_ack(mul_output_z_ack_1)
    );

    multiplier mul_2 (
        .clk(iClk),
        .rst(rst),
        .input_a(mul_input_a_2),
        .input_b(mul_input_b_2),
        .input_a_stb(mul_input_a_stb_2),
        .input_b_stb(mul_input_b_stb_2),
        .input_a_ack(mul_input_a_ack_2),
        .input_b_ack(mul_input_b_ack_2),
        .output_z(mul_output_z_2),
        .output_z_stb(mul_output_z_stb_2),
        .output_z_ack(mul_output_z_ack_2)
    );

    // Instantiate 2 adders
    adder add_0 (
        .clk(iClk),
        .rst(rst),
        .input_a(add_input_a_0),
        .input_b(add_input_b_0),
        .input_a_stb(add_input_a_stb_0),
        .input_b_stb(add_input_b_stb_0),
        .input_a_ack(add_input_a_ack_0),
        .input_b_ack(add_input_b_ack_0),
        .output_z(add_output_z_0),
        .output_z_stb(add_output_z_stb_0),
        .output_z_ack(add_output_z_ack_0)
    );

    adder add_1 (
        .clk(iClk),
        .rst(rst),
        .input_a(add_input_a_1),
        .input_b(add_input_b_1),
        .input_a_stb(add_input_a_stb_1),
        .input_b_stb(add_input_b_stb_1),
        .input_a_ack(add_input_a_ack_1),
        .input_b_ack(add_input_b_ack_1),
        .output_z(add_output_z_1),
        .output_z_stb(add_output_z_stb_1),
        .output_z_ack(add_output_z_ack_1)
    );

endmodule