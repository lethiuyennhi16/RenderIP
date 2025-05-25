module mul4x4_4x1_wrapper (
    input iClk,
    input iRstn,
    output logic ready,
    input logic data_valid,
    input logic [31:0] data,
    output logic data_done,
    output logic calc_done,
    output logic [31:0] result,
    input logic read_done
);

    // Tín hiệu kết nối với module mul4x4_4x1
    logic [31:0] mul_data_a_0, mul_data_b_0;
    logic mul_a_stb_0, mul_b_stb_0;
    logic mul_a_ack_0, mul_b_ack_0;
    logic [31:0] mul_result_0;
    logic mul_z_stb_0;
    logic mul_z_ack_0;

    logic [31:0] mul_data_a_1, mul_data_b_1;
    logic mul_a_stb_1, mul_b_stb_1;
    logic mul_a_ack_1, mul_b_ack_1;
    logic [31:0] mul_result_1;
    logic mul_z_stb_1;
    logic mul_z_ack_1;

    logic [31:0] mul_data_a_2, mul_data_b_2;
    logic mul_a_stb_2, mul_b_stb_2;
    logic mul_a_ack_2, mul_b_ack_2;
    logic [31:0] mul_result_2;
    logic mul_z_stb_2;
    logic mul_z_ack_2;

    logic [31:0] mul_data_a_3, mul_data_b_3;
    logic mul_a_stb_3, mul_b_stb_3;
    logic mul_a_ack_3, mul_b_ack_3;
    logic [31:0] mul_result_3;
    logic mul_z_stb_3;
    logic mul_z_ack_3;

    logic [31:0] add_data_a, add_data_b;
    logic add_a_stb, add_b_stb;
    logic add_a_ack, add_b_ack;
    logic [31:0] add_result;
    logic add_z_stb;
    logic add_z_ack;

    logic [31:0] add_data_a_1, add_data_b_1;
    logic add_a_stb_1, add_b_stb_1;
    logic add_a_ack_1, add_b_ack_1;
    logic [31:0] add_result_1;
    logic add_z_stb_1;
    logic add_z_ack_1;

    logic [31:0] add_data_a_2, add_data_b_2;
    logic add_a_stb_2, add_b_stb_2;
    logic add_a_ack_2, add_b_ack_2;
    logic [31:0] add_result_2;
    logic add_z_stb_2;
    logic add_z_ack_2;

    // Khởi tạo module mul4x4_4x1
    mul4x4_4x1 mul4x1_inst (
        .iClk(iClk),
        .iRstn(iRstn),
        .mul_data_a_0(mul_data_a_0),
        .mul_data_b_0(mul_data_b_0),
        .mul_a_stb_0(mul_a_stb_0),
        .mul_b_stb_0(mul_b_stb_0),
        .mul_a_ack_0(mul_a_ack_0),
        .mul_b_ack_0(mul_b_ack_0),
        .mul_result_0(mul_result_0),
        .mul_z_stb_0(mul_z_stb_0),
        .mul_z_ack_0(mul_z_ack_0),
        .mul_data_a_1(mul_data_a_1),
        .mul_data_b_1(mul_data_b_1),
        .mul_a_stb_1(mul_a_stb_1),
        .mul_b_stb_1(mul_b_stb_1),
        .mul_a_ack_1(mul_a_ack_1),
        .mul_b_ack_1(mul_b_ack_1),
        .mul_result_1(mul_result_1),
        .mul_z_stb_1(mul_z_stb_1),
        .mul_z_ack_1(mul_z_ack_1),
        .mul_data_a_2(mul_data_a_2),
        .mul_data_b_2(mul_data_b_2),
        .mul_a_stb_2(mul_a_stb_2),
        .mul_b_stb_2(mul_b_stb_2),
        .mul_a_ack_2(mul_a_ack_2),
        .mul_b_ack_2(mul_b_ack_2),
        .mul_result_2(mul_result_2),
        .mul_z_stb_2(mul_z_stb_2),
        .mul_z_ack_2(mul_z_ack_2),
        .mul_data_a_3(mul_data_a_3),
        .mul_data_b_3(mul_data_b_3),
        .mul_a_stb_3(mul_a_stb_3),
        .mul_b_stb_3(mul_b_stb_3),
        .mul_a_ack_3(mul_a_ack_3),
        .mul_b_ack_3(mul_b_ack_3),
        .mul_result_3(mul_result_3),
        .mul_z_stb_3(mul_z_stb_3),
        .mul_z_ack_3(mul_z_ack_3),
        .add_data_a(add_data_a),
        .add_data_b(add_data_b),
        .add_a_stb(add_a_stb),
        .add_b_stb(add_b_stb),
        .add_a_ack(add_a_ack),
        .add_b_ack(add_b_ack),
        .add_result(add_result),
        .add_z_stb(add_z_stb),
        .add_z_ack(add_z_ack),
        .add_data_a_1(add_data_a_1),
        .add_data_b_1(add_data_b_1),
        .add_a_stb_1(add_a_stb_1),
        .add_b_stb_1(add_b_stb_1),
        .add_a_ack_1(add_a_ack_1),
        .add_b_ack_1(add_b_ack_1),
        .add_result_1(add_result_1),
        .add_z_stb_1(add_z_stb_1),
        .add_z_ack_1(add_z_ack_1),
        .add_data_a_2(add_data_a_2),
        .add_data_b_2(add_data_b_2),
        .add_a_stb_2(add_a_stb_2),
        .add_b_stb_2(add_b_stb_2),
        .add_a_ack_2(add_a_ack_2),
        .add_b_ack_2(add_b_ack_2),
        .add_result_2(add_result_2),
        .add_z_stb_2(add_z_stb_2),
        .add_z_ack_2(add_z_ack_2),
        .ready(ready),
        .data_valid(data_valid),
        .data(data),
        .data_done(data_done),
        .calc_done(calc_done),
        .result(result),
        .read_done(read_done)
    );

    // Khởi tạo 4 multiplier
    multiplier mul0 (
        .clk(iClk),
        .rst(~iRstn), // Active high reset
        .input_a(mul_data_a_0),
        .input_b(mul_data_b_0),
        .input_a_stb(mul_a_stb_0),
        .input_b_stb(mul_b_stb_0),
        .output_z_ack(mul_z_ack_0),
        .output_z(mul_result_0),
        .output_z_stb(mul_z_stb_0),
        .input_a_ack(mul_a_ack_0),
        .input_b_ack(mul_b_ack_0)
    );

    multiplier mul1 (
        .clk(iClk),
        .rst(~iRstn),
        .input_a(mul_data_a_1),
        .input_b(mul_data_b_1),
        .input_a_stb(mul_a_stb_1),
        .input_b_stb(mul_b_stb_1),
        .output_z_ack(mul_z_ack_1),
        .output_z(mul_result_1),
        .output_z_stb(mul_z_stb_1),
        .input_a_ack(mul_a_ack_1),
        .input_b_ack(mul_b_ack_1)
    );

    multiplier mul2 (
        .clk(iClk),
        .rst(~iRstn),
        .input_a(mul_data_a_2),
        .input_b(mul_data_b_2),
        .input_a_stb(mul_a_stb_2),
        .input_b_stb(mul_b_stb_2),
        .output_z_ack(mul_z_ack_2),
        .output_z(mul_result_2),
        .output_z_stb(mul_z_stb_2),
        .input_a_ack(mul_a_ack_2),
        .input_b_ack(mul_b_ack_2)
    );

    multiplier mul3 (
        .clk(iClk),
        .rst(~iRstn),
        .input_a(mul_data_a_3),
        .input_b(mul_data_b_3),
        .input_a_stb(mul_a_stb_3),
        .input_b_stb(mul_b_stb_3),
        .output_z_ack(mul_z_ack_3),
        .output_z(mul_result_3),
        .output_z_stb(mul_z_stb_3),
        .input_a_ack(mul_a_ack_3),
        .input_b_ack(mul_b_ack_3)
    );

    // Khởi tạo 3 adder
    adder add0 (
        .clk(iClk),
        .rst(~iRstn),
        .input_a(add_data_a),
        .input_b(add_data_b),
        .input_a_stb(add_a_stb),
        .input_b_stb(add_b_stb),
        .output_z_ack(add_z_ack),
        .output_z(add_result),
        .output_z_stb(add_z_stb),
        .input_a_ack(add_a_ack),
        .input_b_ack(add_b_ack)
    );

    adder add1 (
        .clk(iClk),
        .rst(~iRstn),
        .input_a(add_data_a_1),
        .input_b(add_data_b_1),
        .input_a_stb(add_a_stb_1),
        .input_b_stb(add_b_stb_1),
        .output_z_ack(add_z_ack_1),
        .output_z(add_result_1),
        .output_z_stb(add_z_stb_1),
        .input_a_ack(add_a_ack_1),
        .input_b_ack(add_b_ack_1)
    );

    adder add2 (
        .clk(iClk),
        .rst(~iRstn),
        .input_a(add_data_a_2),
        .input_b(add_data_b_2),
        .input_a_stb(add_a_stb_2),
        .input_b_stb(add_b_stb_2),
        .output_z_ack(add_z_ack_2),
        .output_z(add_result_2),
        .output_z_stb(add_z_stb_2),
        .input_a_ack(add_a_ack_2),
        .input_b_ack(add_b_ack_2)
    );

endmodule