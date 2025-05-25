// IEEE Floating Point Subtractor (Single Precision)
// Modified from Adder by Jonathan P Dawson (2013)
// Modified for subtraction by [Your Name] 2025

module subtractor(
    input  logic        clk,
    input  logic        rst,
    
    input  logic [31:0] input_a,
    input  logic        input_a_stb,
    output logic        input_a_ack,
    
    input  logic [31:0] input_b,
    input  logic        input_b_stb,
    output logic        input_b_ack,
    
    output logic [31:0] output_z,
    output logic        output_z_stb,
    input  logic        output_z_ack
);

    // Tín hiệu nội bộ
    logic       s_output_z_stb;
    logic [31:0] s_output_z;
    logic       s_input_a_ack;
    logic       s_input_b_ack;

    // Trạng thái FSM
    logic [3:0] state;
    parameter get_a         = 4'd0,
              get_b         = 4'd1,
              unpack        = 4'd2,
              special_cases = 4'd3,
              align         = 4'd4,
              add_0         = 4'd5,
              add_1         = 4'd6,
              normalise_1   = 4'd7,
              normalise_2   = 4'd8,
              round         = 4'd9,
              pack          = 4'd10,
              put_z         = 4'd11;

    // Biến lưu trữ
    logic [31:0] a, b, z;
    logic [26:0] a_m, b_m;
    logic [23:0] z_m;
    logic [9:0]  a_e, b_e, z_e;
    logic        a_s, b_s, z_s;
    logic        guard, round_bit, sticky;
    logic [27:0] sum;

    always @(posedge clk) begin
        case (state)
            get_a: begin
                s_input_a_ack <= 1;
                if (s_input_a_ack && input_a_stb) begin
                    a <= input_a;
                    s_input_a_ack <= 0;
                    state <= get_b;
                end
            end

            get_b: begin
                s_input_b_ack <= 1;
                if (s_input_b_ack && input_b_stb) begin
                    b <= input_b;
                    s_input_b_ack <= 0;
                    state <= unpack;
                end
            end

            unpack: begin
                a_m <= {a[22:0], 3'd0};
                b_m <= {b[22:0], 3'd0};
                a_e <= a[30:23] - 127;
                b_e <= b[30:23] - 127;
                a_s <= a[31];
                b_s <= ~b[31]; // Đảo dấu của input_b để thực hiện a - b
                state <= special_cases;
            end

            special_cases: begin
                // Nếu a hoặc b là NaN, trả về NaN
                if ((a_e == 128 && a_m != 0) || (b_e == 128 && b_m != 0)) begin
                    z[31] <= 1;
                    z[30:23] <= 255;
                    z[22] <= 1;
                    z[21:0] <= 0;
                    state <= put_z;
                // Nếu a là vô cực, trả về vô cực với dấu của a
                end else if (a_e == 128) begin
                    z[31] <= a_s;
                    z[30:23] <= 255;
                    z[22:0] <= 0;
                    // Nếu b cũng là vô cực và dấu khác nhau, trả về NaN
                    if (b_e == 128 && a_s != b_s) begin
                        z[31] <= 1;
                        z[30:23] <= 255;
                        z[22] <= 1;
                        z[21:0] <= 0;
                    end
                    state <= put_z;
                // Nếu b là vô cực, trả về vô cực với dấu đảo của b
                end else if (b_e == 128) begin
                    z[31] <= b_s; // Dấu đã đảo trong unpack
                    z[30:23] <= 255;
                    z[22:0] <= 0;
                    state <= put_z;
                // Nếu cả a và b là zero, trả về zero
                end else if (($signed(a_e) == -127 && a_m == 0) && ($signed(b_e) == -127 && b_m == 0)) begin
                    z[31] <= a_s & b_s; // Dấu của +0 hoặc -0
                    z[30:23] <= 0;
                    z[22:0] <= 0;
                    state <= put_z;
                // Nếu a là zero, trả về -b
                end else if ($signed(a_e) == -127 && a_m == 0) begin
                    z[31] <= b_s; // Dấu đã đảo
                    z[30:23] <= b_e[7:0] + 127;
                    z[22:0] <= b_m[26:3];
                    state <= put_z;
                // Nếu b là zero, trả về a
                end else if ($signed(b_e) == -127 && b_m == 0) begin
                    z[31] <= a_s;
                    z[30:23] <= a_e[7:0] + 127;
                    z[22:0] <= a_m[26:3];
                    state <= put_z;
                end else begin
                    // Xử lý số không chuẩn hóa (denormalized)
                    if ($signed(a_e) == -127) begin
                        a_e <= -126;
                    end else begin
                        a_m[26] <= 1;
                    end
                    if ($signed(b_e) == -127) begin
                        b_e <= -126;
                    end else begin
                        b_m[26] <= 1;
                    end
                    state <= align;
                end
            end

            align: begin
                if ($signed(a_e) > $signed(b_e)) begin
                    b_e <= b_e + 1;
                    b_m <= b_m >> 1;
                    b_m[0] <= b_m[0] | b_m[1];
                end else if ($signed(a_e) < $signed(b_e)) begin
                    a_e <= a_e + 1;
                    a_m <= a_m >> 1;
                    a_m[0] <= a_m[0] | a_m[1];
                end else begin
                    state <= add_0;
                end
            end

            add_0: begin
                z_e <= a_e;
                if (a_s == b_s) begin
                    sum <= a_m + b_m; // Cộng nếu dấu giống nhau
                    z_s <= a_s;
                end else begin
                    if (a_m >= b_m) begin
                        sum <= a_m - b_m; // Trừ nếu dấu khác nhau
                        z_s <= a_s;
                    end else begin
                        sum <= b_m - a_m;
                        z_s <= b_s;
                    end
                end
                state <= add_1;
            end

            add_1: begin
                if (sum[27]) begin
                    z_m <= sum[27:4];
                    guard <= sum[3];
                    round_bit <= sum[2];
                    sticky <= sum[1] | sum[0];
                    z_e <= z_e + 1;
                end else begin
                    z_m <= sum[26:3];
                    guard <= sum[2];
                    round_bit <= sum[1];
                    sticky <= sum[0];
                end
                state <= normalise_1;
            end

            normalise_1: begin
                if (z_m[23] == 0 && $signed(z_e) > -126) begin
                    z_e <= z_e - 1;
                    z_m <= z_m << 1;
                    z_m[0] <= guard;
                    guard <= round_bit;
                    round_bit <= 0;
                end else begin
                    state <= normalise_2;
                end
            end

            normalise_2: begin
                if ($signed(z_e) < -126) begin
                    z_e <= z_e + 1;
                    z_m <= z_m >> 1;
                    guard <= z_m[0];
                    round_bit <= guard;
                    sticky <= sticky | round_bit;
                end else begin
                    state <= round;
                end
            end

            round: begin
                if (guard && (round_bit | sticky | z_m[0])) begin
                    z_m <= z_m + 1;
                    if (z_m == 24'hffffff) begin
                        z_e <= z_e + 1;
                    end
                end
                state <= pack;
            end

            pack: begin
                z[22:0] <= z_m[22:0];
                z[30:23] <= z_e[7:0] + 127;
                z[31] <= z_s;
                if ($signed(z_e) == -126 && z_m[23] == 0) begin
                    z[30:23] <= 0;
                end
                if ($signed(z_e) == -126 && z_m[23:0] == 24'h0) begin
                    z[31] <= 1'b0; // Sửa lỗi dấu: a - a = +0
                end
                // Xử lý tràn (overflow)
                if ($signed(z_e) > 127) begin
                    z[22:0] <= 0;
                    z[30:23] <= 255;
                    z[31] <= z_s;
                end
                state <= put_z;
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

        if (rst == 1) begin
            state <= get_a;
            s_input_a_ack <= 0;
            s_input_b_ack <= 0;
            s_output_z_stb <= 0;
        end
    end

    // Gán tín hiệu đầu ra
    assign input_a_ack = s_input_a_ack;
    assign input_b_ack = s_input_b_ack;
    assign output_z_stb = s_output_z_stb;
    assign output_z = s_output_z;
endmodule