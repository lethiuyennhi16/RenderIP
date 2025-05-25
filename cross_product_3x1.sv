module cross_product_3x1 (
    input logic iClk,
    input logic iRstn,
    // Giao diện cho 6 bộ nhân
    output logic [31:0] mul_data_a_0, mul_data_b_0,
    output logic mul_a_stb_0, mul_b_stb_0,
    input logic mul_a_ack_0, mul_b_ack_0,
    input logic [31:0] mul_result_0,
    input logic mul_z_stb_0,
    output logic mul_z_ack_0,
    output logic [31:0] mul_data_a_1, mul_data_b_1,
    output logic mul_a_stb_1, mul_b_stb_1,
    input logic mul_a_ack_1, mul_b_ack_1,
    input logic [31:0] mul_result_1,
    input logic mul_z_stb_1,
    output logic mul_z_ack_1,
    output logic [31:0] mul_data_a_2, mul_data_b_2,
    output logic mul_a_stb_2, mul_b_stb_2,
    input logic mul_a_ack_2, mul_b_ack_2,
    input logic [31:0] mul_result_2,
    input logic mul_z_stb_2,
    output logic mul_z_ack_2,
    output logic [31:0] mul_data_a_3, mul_data_b_3,
    output logic mul_a_stb_3, mul_b_stb_3,
    input logic mul_a_ack_3, mul_b_ack_3,
    input logic [31:0] mul_result_3,
    input logic mul_z_stb_3,
    output logic mul_z_ack_3,
    output logic [31:0] mul_data_a_4, mul_data_b_4,
    output logic mul_a_stb_4, mul_b_stb_4,
    input logic mul_a_ack_4, mul_b_ack_4,
    input logic [31:0] mul_result_4,
    input logic mul_z_stb_4,
    output logic mul_z_ack_4,
    output logic [31:0] mul_data_a_5, mul_data_b_5,
    output logic mul_a_stb_5, mul_b_stb_5,
    input logic mul_a_ack_5, mul_b_ack_5,
    input logic [31:0] mul_result_5,
    input logic mul_z_stb_5,
    output logic mul_z_ack_5,
    // Giao diện cho 3 bộ trừ
    output logic [31:0] sub_data_a_0, sub_data_b_0,
    output logic sub_a_stb_0, sub_b_stb_0,
    input logic sub_a_ack_0, sub_b_ack_0,
    input logic [31:0] sub_result_0,
    input logic sub_z_stb_0,
    output logic sub_z_ack_0,
    output logic [31:0] sub_data_a_1, sub_data_b_1,
    output logic sub_a_stb_1, sub_b_stb_1,
    input logic sub_a_ack_1, sub_b_ack_1,
    input logic [31:0] sub_result_1,
    input logic sub_z_stb_1,
    output logic sub_z_ack_1,
    output logic [31:0] sub_data_a_2, sub_data_b_2,
    output logic sub_a_stb_2, sub_b_stb_2,
    input logic sub_a_ack_2, sub_b_ack_2,
    input logic [31:0] sub_result_2,
    input logic sub_z_stb_2,
    output logic sub_z_ack_2,
    // Tín hiệu điều khiển và dữ liệu
    output logic ready,
    input logic data_valid,
    input logic [31:0] data,
    output logic data_done,
    output logic calc_done,
    output logic [31:0] result,
    input logic read_done
);

    // Vector A (3x1), B (3x1) và C (3x1)
    logic [31:0] A [0:2];
    logic [31:0] B [0:2];
    logic [31:0] C [0:2];
    
    // Biến trạng thái và chỉ số
    typedef enum logic [2:0] {
        IDLE,
        LOAD_A,
        LOAD_B,
        MUL,
        SUB,
        OUTPUT,
        DONE
    } state_t;
    
    state_t state, next_state;
    logic [1:0] idx_a; // Chỉ số cho A
    logic [1:0] idx_b; // Chỉ số cho B
    logic [1:0] idx_c; // Chỉ số cho C
    logic [3:0] data_count; // Đếm 6 phần tử (3 cho A, 3 cho B)
    logic [31:0] mul_results [0:5];
    logic load_done;
    
    // Tín hiệu điều khiển nội bộ
    logic mul_start, sub_start;
    logic data_load_complete; // Biến theo dõi trạng thái nạp dữ liệu xong
    
    // Biến tạm thời cho always_comb
    logic next_ready;
    logic [3:0] next_data_count;
    logic next_load_done;
    logic next_calc_done;
    logic next_data_load_complete;

    // Khối tuần tự: Quản lý trạng thái và các biến trạng thái
    always_ff @(posedge iClk or negedge iRstn) begin
        if (!iRstn) begin
            state <= IDLE;
            data_count <= 0;
            idx_a <= 0;
            idx_b <= 0;
            idx_c <= 0;
            load_done <= 0;
            ready <= 1;
            calc_done <= 0;
            data_load_complete <= 0;
            data_done <= 0;
        end else begin
            state <= next_state;
            ready <= next_ready;
            data_count <= next_data_count;
            load_done <= next_load_done;
            calc_done <= next_calc_done;
            data_load_complete <= next_data_load_complete;

            // Nạp dữ liệu cho vector A
            if (state == LOAD_A && data_valid) begin
                A[idx_a] <= data;
                idx_a <= idx_a + 1;
            end

            // Nạp dữ liệu cho vector B
            if (state == LOAD_B && data_valid) begin
                B[idx_b] <= data;
                idx_b <= idx_b + 1;
            end
            
            // Đặt lại idx_a khi chuyển từ LOAD_A sang LOAD_B
            if (state == LOAD_A && data_valid && data_count == 2) begin
                idx_a <= 0;
                idx_b <= 0; // Đặt lại idx_b để chuẩn bị cho LOAD_B
            end
            
            // Lưu kết quả nhân
            if (state == MUL && mul_z_stb_0 && mul_z_stb_1 && mul_z_stb_2 &&
                mul_z_stb_3 && mul_z_stb_4 && mul_z_stb_5) begin
                mul_results[0] <= mul_result_0; // A[1]*B[2]
                mul_results[1] <= mul_result_1; // A[2]*B[1]
                mul_results[2] <= mul_result_2; // A[2]*B[0]
                mul_results[3] <= mul_result_3; // A[0]*B[2]
                mul_results[4] <= mul_result_4; // A[0]*B[1]
                mul_results[5] <= mul_result_5; // A[1]*B[0]
            end
            
            // Lưu kết quả trừ cho C[0], C[1], C[2]
            if (state == SUB) begin
                if (sub_z_stb_0) begin
                    C[0] <= sub_result_0; // A[1]*B[2] - A[2]*B[1]
                end
                if (sub_z_stb_1) begin
                    C[1] <= sub_result_1; // A[2]*B[0] - A[0]*B[2]
                end
                if (sub_z_stb_2) begin
                    C[2] <= sub_result_2; // A[0]*B[1] - A[1]*B[0]
                end
            end
            
            // Tăng idx_c tự động trong OUTPUT
            if (state == OUTPUT && calc_done) begin
                idx_c <= idx_c + 1;
            end
            
            // Đặt lại idx_c khi chuyển từ SUB sang OUTPUT
            if (state == SUB && sub_z_stb_0 && sub_z_stb_1 && sub_z_stb_2) begin
                idx_c <= 0;
            end
            
            // Đặt data_done
            if (state == LOAD_B && data_valid && data_count == 2) begin
                data_done <= 1;
            end else if (state == MUL || state == IDLE) begin
                data_done <= 0;
            end
        end
    end
    
    // Khối kết hợp: Tính toán logic điều khiển
    always_comb begin
        // Giá trị mặc định
        next_state = state;
        next_ready = ready;
        next_data_count = data_count;
        next_load_done = load_done;
        next_calc_done = calc_done;
        next_data_load_complete = data_load_complete;
        mul_start = 0;
        sub_start = 0;
        mul_a_stb_0 = 0;
        mul_b_stb_0 = 0;
        mul_a_stb_1 = 0;
        mul_b_stb_1 = 0;
        mul_a_stb_2 = 0;
        mul_b_stb_2 = 0;
        mul_a_stb_3 = 0;
        mul_b_stb_3 = 0;
        mul_a_stb_4 = 0;
        mul_b_stb_4 = 0;
        mul_a_stb_5 = 0;
        mul_b_stb_5 = 0;
        sub_a_stb_0 = 0;
        sub_b_stb_0 = 0;
        sub_a_stb_1 = 0;
        sub_b_stb_1 = 0;
        sub_a_stb_2 = 0;
        sub_b_stb_2 = 0;
        mul_z_ack_0 = 0;
        mul_z_ack_1 = 0;
        mul_z_ack_2 = 0;
        mul_z_ack_3 = 0;
        mul_z_ack_4 = 0;
        mul_z_ack_5 = 0;
        sub_z_ack_0 = 0;
        sub_z_ack_1 = 0;
        sub_z_ack_2 = 0;
        result = C[idx_c];
        
        case (state)
            IDLE: begin
                if (data_valid) begin
                    next_state = LOAD_A;
                    next_ready = 0;
                    next_data_count = 0;
                    next_load_done = 0;
                    next_calc_done = 0;
                    next_data_load_complete = 0;
                end
            end
            
            LOAD_A: begin
                if (data_valid) begin
                    next_data_count = data_count + 1;
                    if (data_count == 2) begin // 3 phần tử cho A
                        next_state = LOAD_B;
                        next_load_done = 1;
                        next_data_count = 0;
                    end
                end
            end
            
            LOAD_B: begin
                if (data_valid) begin
                    next_data_count = data_count + 1;
                    if (data_count == 2) begin // 3 phần tử cho B
                        next_state = MUL;
                        next_load_done = 1;
                        next_data_count = 0;
                        next_data_load_complete = 1;
                    end
                end
            end
            
            MUL: begin
                mul_a_stb_0 = 1;
                mul_b_stb_0 = 1;
                mul_a_stb_1 = 1;
                mul_b_stb_1 = 1;
                mul_a_stb_2 = 1;
                mul_b_stb_2 = 1;
                mul_a_stb_3 = 1;
                mul_b_stb_3 = 1;
                mul_a_stb_4 = 1;
                mul_b_stb_4 = 1;
                mul_a_stb_5 = 1;
                mul_b_stb_5 = 1;
                mul_data_a_0 = A[1];
                mul_data_b_0 = B[2]; // A[1]*B[2]
                mul_data_a_1 = A[2];
                mul_data_b_1 = B[1]; // A[2]*B[1]
                mul_data_a_2 = A[2];
                mul_data_b_2 = B[0]; // A[2]*B[0]
                mul_data_a_3 = A[0];
                mul_data_b_3 = B[2]; // A[0]*B[2]
                mul_data_a_4 = A[0];
                mul_data_b_4 = B[1]; // A[0]*B[1]
                mul_data_a_5 = A[1];
                mul_data_b_5 = B[0]; // A[1]*B[0]
                
                if (mul_a_ack_0 && mul_b_ack_0 && mul_a_ack_1 && mul_b_ack_1 &&
                    mul_a_ack_2 && mul_b_ack_2 && mul_a_ack_3 && mul_b_ack_3 &&
                    mul_a_ack_4 && mul_b_ack_4 && mul_a_ack_5 && mul_b_ack_5) begin
                    mul_start = 1;
                end
                
                if (mul_z_stb_0 && mul_z_stb_1 && mul_z_stb_2 &&
                    mul_z_stb_3 && mul_z_stb_4 && mul_z_stb_5) begin
                    mul_z_ack_0 = 1;
                    mul_z_ack_1 = 1;
                    mul_z_ack_2 = 1;
                    mul_z_ack_3 = 1;
                    mul_z_ack_4 = 1;
                    mul_z_ack_5 = 1;
                    next_state = SUB;
                end
            end
            
            SUB: begin
                sub_a_stb_0 = 1;
                sub_b_stb_0 = 1;
                sub_data_a_0 = mul_results[0]; // A[1]*B[2]
                sub_data_b_0 = mul_results[1]; // A[2]*B[1]
                sub_a_stb_1 = 1;
                sub_b_stb_1 = 1;
                sub_data_a_1 = mul_results[2]; // A[2]*B[0]
                sub_data_b_1 = mul_results[3]; // A[0]*B[2]
                sub_a_stb_2 = 1;
                sub_b_stb_2 = 1;
                sub_data_a_2 = mul_results[4]; // A[0]*B[1]
                sub_data_b_2 = mul_results[5]; // A[1]*B[0]
                
                if (sub_a_ack_0 && sub_b_ack_0 && sub_a_ack_1 && sub_b_ack_1 &&
                    sub_a_ack_2 && sub_b_ack_2) begin
                    sub_start = 1;
                end
                
                if (sub_z_stb_0 && sub_z_stb_1 && sub_z_stb_2) begin
                    sub_z_ack_0 = 1;
                    sub_z_ack_1 = 1;
                    sub_z_ack_2 = 1;
                    next_state = OUTPUT;
                    next_calc_done = 1;
                end
            end
            
            OUTPUT: begin
                if (idx_c == 2) begin
                    next_state = DONE;
                    next_calc_done = 0;
                end
            end
            
            DONE: begin
                if (read_done) begin
                    next_state = IDLE;
                    next_ready = 1;
                    next_data_count = 0;
                    next_load_done = 0;
                    next_calc_done = 0;
                    next_data_load_complete = 0;
                end
            end
        endcase
    end
    
endmodule