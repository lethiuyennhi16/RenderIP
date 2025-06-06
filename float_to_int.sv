// //IEEE Floating Point to Integer Converter (Single Precision)
// //Copyright (C) Jonathan P Dawson 2013
// //2013-12-12
// module float_to_int(
        // input_a,
        // input_a_stb,
        // output_z_ack,
        // clk,
        // rst,
        // output_z,
        // output_z_stb,
        // input_a_ack);

  // input     clk;
  // input     rst;

  // input     [31:0] input_a;
  // input     input_a_stb;
  // output    input_a_ack;

  // output    [31:0] output_z;
  // output    output_z_stb;
  // input     output_z_ack;

  // reg       s_output_z_stb;
  // reg       [31:0] s_output_z;
  // reg       s_input_a_ack;

  // reg       [2:0] state;
  // parameter get_a         = 3'd0,
            // special_cases = 3'd1,
            // unpack        = 3'd2,
            // convert       = 3'd3,
            // put_z         = 3'd4;

  // reg [31:0] a_m, a, z;
  // reg [8:0] a_e;
  // reg a_s;

  // always @(posedge clk)
  // begin

    // case(state)

      // get_a:
      // begin
        // s_input_a_ack <= 1;
        // if (s_input_a_ack && input_a_stb) begin
          // a <= input_a;
          // s_input_a_ack <= 0;
          // state <= unpack;
        // end
      // end

      // unpack:
      // begin
        // a_m[31:8] <= {1'b1, a[22 : 0]};
        // a_m[7:0] <= 0;
        // a_e <= a[30 : 23] - 127;
        // a_s <= a[31];
        // state <= special_cases;
      // end

      // special_cases:
      // begin
        // if ($signed(a_e) == -127) begin
          // z <= 0;
          // state <= put_z;
        // end else if ($signed(a_e) > 31) begin
          // z <= 32'h80000000;
          // state <= put_z;
        // end else begin
          // state <= convert;
        // end
      // end

      // convert:
      // begin
        // if ($signed(a_e) < 31 && a_m) begin
          // a_e <= a_e + 1;
          // a_m <= a_m >> 1;
        // end else begin
          // if (a_m[31]) begin
            // z <= 32'h80000000;
          // end else begin
            // z <= a_s ? -a_m : a_m;
          // end
          // state <= put_z;
        // end
      // end

      // put_z:
      // begin
        // s_output_z_stb <= 1;
        // s_output_z <= z;
        // if (s_output_z_stb && output_z_ack) begin
          // s_output_z_stb <= 0;
          // state <= get_a;
        // end
      // end

    // endcase

    // if (rst == 1) begin
      // state <= get_a;
      // s_input_a_ack <= 0;
      // s_output_z_stb <= 0;
    // end

  // end
  // assign input_a_ack = s_input_a_ack;
  // assign output_z_stb = s_output_z_stb;
  // assign output_z = s_output_z;

// endmodule
module float_to_int (
    input clk,
    input rst,
    input [31:0] input_a,
    input input_a_stb,
    output input_a_ack,
    output [31:0] output_z,
    output output_z_stb,
    input output_z_ack
);

    reg [2:0] state;
    parameter get_a = 3'd0, unpack = 3'd1, special_cases = 3'd2, convert = 3'd3, put_z = 3'd4;

    reg s_output_z_stb;
    reg [31:0] s_output_z;
    reg s_input_a_ack;
    reg [47:0] a_m;
    reg [31:0] a, z;
    reg [8:0] a_e;
    reg a_s;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= get_a;
            s_input_a_ack <= 0;
            s_output_z_stb <= 0;
            a_m <= 0;
            a <= 0;
            z <= 0;
            a_e <= 0;
            a_s <= 0;
        end else begin
            case (state)
                get_a: begin
                    s_input_a_ack <= 1;
                    if (s_input_a_ack && input_a_stb) begin
                        a <= input_a;
                        s_input_a_ack <= 0;
                        state <= unpack;
                    end
                end
                unpack: begin
                    a_m[47:24] <= {1'b1, a[22:0]};
                    a_m[23:0] <= 0;
                    a_e <= a[30:23] - 127;
                    a_s <= a[31];
                    state <= special_cases;
                end
                special_cases: begin
                    if (a[30:23] == 8'h00 && a[22:0] == 23'h0) begin // Số 0
                        z <= 0;
                        state <= put_z;
                    end else if (a[30:23] == 8'hFF) begin // NaN/Inf
                        z <= 32'h80000000;
                        state <= put_z;
                    end else if (a_s) begin // Số âm
                        z <= 32'h80000000;
                        state <= put_z;
                    end else if ($signed(a_e) > 31) begin // Quá lớn
                        z <= 32'h7FFFFFFF;
                        state <= put_z;
                    end else begin
                        state <= convert;
                    end
                end
                convert: begin
                    if ($signed(a_e) < 16) begin
                        a_e <= a_e + 1;
                        a_m <= a_m << 1; // Dịch trái để đạt 2^16
                    end else if ($signed(a_e) > 16) begin
                        a_e <= a_e - 1;
                        a_m <= a_m >> 1; // Dịch phải nếu cần
                    end else begin
                        z <= a_m[47:16];
                        state <= put_z;
                    end
                end
                put_z: begin
                    s_output_z_stb <= 1;
                    s_output_z <= z;
                    if (s_output_z_stb && output_z_ack) begin
                        s_output_z_stb <= 0;
                        state <= get_a;
                    end
                end
            endcase
        end
    end

    assign input_a_ack = s_input_a_ack;
    assign output_z_stb = s_output_z_stb;
    assign output_z = s_output_z;

endmodule