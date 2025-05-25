module cross_product_3x1_wrapper (
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
    logic [31:0] mul_input_a_3, mul_input_b_3;
    logic mul_input_a_stb_3, mul_input_b_stb_3, mul_input_a_ack_3, mul_input_b_ack_3;
    logic [31:0] mul_output_z_3;
    logic mul_output_z_stb_3, mul_output_z_ack_3;
    logic [31:0] mul_input_a_4, mul_input_b_4;
    logic mul_input_a_stb_4, mul_input_b_stb_4, mul_input_a_ack_4, mul_input_b_ack_4;
    logic [31:0] mul_output_z_4;
    logic mul_output_z_stb_4, mul_output_z_ack_4;
    logic [31:0] mul_input_a_5, mul_input_b_5;
    logic mul_input_a_stb_5, mul_input_b_stb_5, mul_input_a_ack_5, mul_input_b_ack_5;
    logic [31:0] mul_output_z_5;
    logic mul_output_z_stb_5, mul_output_z_ack_5;

    // Tín hiệu nội bộ cho giao diện trừ
    logic [31:0] sub_input_a_0, sub_input_b_0;
    logic sub_input_a_stb_0, sub_input_b_stb_0, sub_input_a_ack_0, sub_input_b_ack_0;
    logic [31:0] sub_output_z_0;
    logic sub_output_z_stb_0, sub_output_z_ack_0;
    logic [31:0] sub_input_a_1, sub_input_b_1;
    logic sub_input_a_stb_1, sub_input_b_stb_1, sub_input_a_ack_1, sub_input_b_ack_1;
    logic [31:0] sub_output_z_1;
    logic sub_output_z_stb_1, sub_output_z_ack_1;
    logic [31:0] sub_input_a_2, sub_input_b_2;
    logic sub_input_a_stb_2, sub_input_b_stb_2, sub_input_a_ack_2, sub_input_b_ack_2;
    logic [31:0] sub_output_z_2;
    logic sub_output_z_stb_2, sub_output_z_ack_2;

    // Chuyển đổi reset tích cực thấp (iRstn) thành tích cực cao (rst)
    logic rst;
    assign rst = ~iRstn;

    // Instantiate module cross_product_3x1
    cross_product_3x1 cross_product_inst (
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
        .mul_data_a_3(mul_input_a_3),
        .mul_data_b_3(mul_input_b_3),
        .mul_a_stb_3(mul_input_a_stb_3),
        .mul_b_stb_3(mul_input_b_stb_3),
        .mul_a_ack_3(mul_input_a_ack_3),
        .mul_b_ack_3(mul_input_b_ack_3),
        .mul_result_3(mul_output_z_3),
        .mul_z_stb_3(mul_output_z_stb_3),
        .mul_z_ack_3(mul_output_z_ack_3),
        .mul_data_a_4(mul_input_a_4),
        .mul_data_b_4(mul_input_b_4),
        .mul_a_stb_4(mul_input_a_stb_4),
        .mul_b_stb_4(mul_input_b_stb_4),
        .mul_a_ack_4(mul_input_a_ack_4),
        .mul_b_ack_4(mul_input_b_ack_4),
        .mul_result_4(mul_output_z_4),
        .mul_z_stb_4(mul_output_z_stb_4),
        .mul_z_ack_4(mul_output_z_ack_4),
        .mul_data_a_5(mul_input_a_5),
        .mul_data_b_5(mul_input_b_5),
        .mul_a_stb_5(mul_input_a_stb_5),
        .mul_b_stb_5(mul_input_b_stb_5),
        .mul_a_ack_5(mul_input_a_ack_5),
        .mul_b_ack_5(mul_input_b_ack_5),
        .mul_result_5(mul_output_z_5),
        .mul_z_stb_5(mul_output_z_stb_5),
        .mul_z_ack_5(mul_output_z_ack_5),
        .sub_data_a_0(sub_input_a_0),
        .sub_data_b_0(sub_input_b_0),
        .sub_a_stb_0(sub_input_a_stb_0),
        .sub_b_stb_0(sub_input_b_stb_0),
        .sub_a_ack_0(sub_input_a_ack_0),
        .sub_b_ack_0(sub_input_b_ack_0),
        .sub_result_0(sub_output_z_0),
        .sub_z_stb_0(sub_output_z_stb_0),
        .sub_z_ack_0(sub_output_z_ack_0),
        .sub_data_a_1(sub_input_a_1),
        .sub_data_b_1(sub_input_b_1),
        .sub_a_stb_1(sub_input_a_stb_1),
        .sub_b_stb_1(sub_input_b_stb_1),
        .sub_a_ack_1(sub_input_a_ack_1),
        .sub_b_ack_1(sub_input_b_ack_1),
        .sub_result_1(sub_output_z_1),
        .sub_z_stb_1(sub_output_z_stb_1),
        .sub_z_ack_1(sub_output_z_ack_1),
        .sub_data_a_2(sub_input_a_2),
        .sub_data_b_2(sub_input_b_2),
        .sub_a_stb_2(sub_input_a_stb_2),
        .sub_b_stb_2(sub_input_b_stb_2),
        .sub_a_ack_2(sub_input_a_ack_2),
        .sub_b_ack_2(sub_input_b_ack_2),
        .sub_result_2(sub_output_z_2),
        .sub_z_stb_2(sub_output_z_stb_2),
        .sub_z_ack_2(sub_output_z_ack_2),
        .ready(ready),
        .data_valid(data_valid),
        .data(data),
        .data_done(data_done),
        .calc_done(calc_done),
        .result(result),
        .read_done(read_done)
    );

    // Instantiate 6 multipliers
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

    multiplier mul_3 (
        .clk(iClk),
        .rst(rst),
        .input_a(mul_input_a_3),
        .input_b(mul_input_b_3),
        .input_a_stb(mul_input_a_stb_3),
        .input_b_stb(mul_input_b_stb_3),
        .input_a_ack(mul_input_a_ack_3),
        .input_b_ack(mul_input_b_ack_3),
        .output_z(mul_output_z_3),
        .output_z_stb(mul_output_z_stb_3),
        .output_z_ack(mul_output_z_ack_3)
    );

    multiplier mul_4 (
        .clk(iClk),
        .rst(rst),
        .input_a(mul_input_a_4),
        .input_b(mul_input_b_4),
        .input_a_stb(mul_input_a_stb_4),
        .input_b_stb(mul_input_b_stb_4),
        .input_a_ack(mul_input_a_ack_4),
        .input_b_ack(mul_input_b_ack_4),
        .output_z(mul_output_z_4),
        .output_z_stb(mul_output_z_stb_4),
        .output_z_ack(mul_output_z_ack_4)
    );

    multiplier mul_5 (
        .clk(iClk),
        .rst(rst),
        .input_a(mul_input_a_5),
        .input_b(mul_input_b_5),
        .input_a_stb(mul_input_a_stb_5),
        .input_b_stb(mul_input_b_stb_5),
        .input_a_ack(mul_input_a_ack_5),
        .input_b_ack(mul_input_b_ack_5),
        .output_z(mul_output_z_5),
        .output_z_stb(mul_output_z_stb_5),
        .output_z_ack(mul_output_z_ack_5)
    );

    // Instantiate 3 subtractors
    subtractor sub_0 (
        .clk(iClk),
        .rst(rst),
        .input_a(sub_input_a_0),
        .input_b(sub_input_b_0),
        .input_a_stb(sub_input_a_stb_0),
        .input_b_stb(sub_input_b_stb_0),
        .input_a_ack(sub_input_a_ack_0),
        .input_b_ack(sub_input_b_ack_0),
        .output_z(sub_output_z_0),
        .output_z_stb(sub_output_z_stb_0),
        .output_z_ack(sub_output_z_ack_0)
    );

    subtractor sub_1 (
        .clk(iClk),
        .rst(rst),
        .input_a(sub_input_a_1),
        .input_b(sub_input_b_1),
        .input_a_stb(sub_input_a_stb_1),
        .input_b_stb(sub_input_b_stb_1),
        .input_a_ack(sub_input_a_ack_1),
        .input_b_ack(sub_input_b_ack_1),
        .output_z(sub_output_z_1),
        .output_z_stb(sub_output_z_stb_1),
        .output_z_ack(sub_output_z_ack_1)
    );

    subtractor sub_2 (
        .clk(iClk),
        .rst(rst),
        .input_a(sub_input_a_2),
        .input_b(sub_input_b_2),
        .input_a_stb(sub_input_a_stb_2),
        .input_b_stb(sub_input_b_stb_2),
        .input_a_ack(sub_input_a_ack_2),
        .input_b_ack(sub_input_b_ack_2),
        .output_z(sub_output_z_2),
        .output_z_stb(sub_output_z_stb_2),
        .output_z_ack(sub_output_z_ack_2)
    );

endmodule