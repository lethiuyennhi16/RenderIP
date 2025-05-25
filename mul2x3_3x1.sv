module mul2x3_3x1 (
    input logic iClk,
    input logic iRstn,
    // Giao diện cho 3 bộ nhân
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
    // Giao diện cho 2 bộ cộng
    output logic [31:0] add_data_a, add_data_b,
    output logic add_a_stb, add_b_stb,
    input logic add_a_ack, add_b_ack,
    input logic [31:0] add_result,
    input logic add_z_stb,
    output logic add_z_ack,
    output logic [31:0] add_data_a_1, add_data_b_1,
    output logic add_a_stb_1, add_b_stb_1,
    input logic add_a_ack_1, add_b_ack_1,
    input logic [31:0] add_result_1,
    input logic add_z_stb_1,
    output logic add_z_ack_1,
    // Tín hiệu điều khiển và dữ liệu
    output logic ready,
    input logic data_valid,
    input logic [31:0] data,
    output logic data_done,
    output logic calc_done,
    output logic [31:0] result,
    input logic read_done
);

    // Ma trận A (2x3), B (3x1) và C (2x1)
    logic [31:0] A [0:1][0:2];
    logic [31:0] B [0:2];
    logic [31:0] C [0:1];
    
    // Biến trạng thái và chỉ số
    typedef enum logic [3:0] {
        IDLE,
        LOAD_A,
        LOAD_B,
        MUL,
        ADD_1,
        ADD_2,
        OUTPUT,
        DONE
    } state_t;
    
    state_t state, next_state;
    logic [1:0] row_idx, col_idx; // Chỉ số cho ma trận A
    logic [3:0] data_idx; // Chỉ số cho ma trận C khi xuất
    logic [31:0] mul_results [0:2];
    logic [31:0] add_temp;
    logic load_done;
    logic [3:0] data_count; // Đếm 9 phần tử (6 cho A, 3 cho B)
    
    // Tín hiệu điều khiển nội bộ
    logic mul_start, add_start_1, add_start_2;
    
    // Biến tạm thời cho always_comb
    logic next_ready;
    logic [3:0] next_data_count;
    logic next_load_done;
    logic next_calc_done;

    // Khối tuần tự: Quản lý trạng thái và các biến trạng thái
    always_ff @(posedge iClk or negedge iRstn) begin
        if (!iRstn) begin
            state <= IDLE;
            data_count <= 0;
            row_idx <= 0;
            col_idx <= 0;
            data_idx <= 0;
            load_done <= 0;
            ready <= 1;
            calc_done <= 0;
        end else begin
            state <= next_state;
            ready <= next_ready;
            data_count <= next_data_count;
            load_done <= next_load_done;
            calc_done <= next_calc_done;

            // Nạp dữ liệu cho ma trận A
            if (state == LOAD_A && data_valid) begin
                A[row_idx][col_idx] <= data;
                if (col_idx == 2) begin
                    col_idx <= 0;
                    row_idx <= row_idx + 1;
                end else begin
                    col_idx <= col_idx + 1;
                end
            end

            // Nạp dữ liệu cho ma trận B
            if (state == LOAD_B && data_valid) begin
                B[data_count[1:0]] <= data;
            end
            
            // Lưu kết quả nhân
            if (state == MUL && mul_z_stb_0 && mul_z_stb_1 && mul_z_stb_2) begin
                mul_results[0] <= mul_result_0;
                mul_results[1] <= mul_result_1;
                mul_results[2] <= mul_result_2;
            end
            
            // Lưu kết quả cộng bước 1
            if (state == ADD_1 && add_z_stb) begin
                add_temp <= add_result;
            end
            
            // Lưu kết quả cộng bước 2 và cập nhật ma trận C
            if (state == ADD_2 && add_z_stb_1) begin
                C[row_idx] <= add_result_1;
                if (row_idx == 1) begin
                    row_idx <= 0;
                end else begin
                    row_idx <= row_idx + 1;
                end
            end
            
            // Tăng data_idx tự động trong OUTPUT
            if (state == OUTPUT && calc_done) begin
                data_idx <= data_idx + 1;
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
        mul_start = 0;
        add_start_1 = 0;
        add_start_2 = 0;
        mul_a_stb_0 = 0;
        mul_b_stb_0 = 0;
        mul_a_stb_1 = 0;
        mul_b_stb_1 = 0;
        mul_a_stb_2 = 0;
        mul_b_stb_2 = 0;
        add_a_stb = 0;
        add_b_stb = 0;
        add_a_stb_1 = 0;
        add_b_stb_1 = 0;
        mul_z_ack_0 = 0;
        mul_z_ack_1 = 0;
        mul_z_ack_2 = 0;
        add_z_ack = 0;
        add_z_ack_1 = 0;
        data_done = 0;
        result = C[data_idx[0]]; // Chỉ cần 1 bit vì C có 2 phần tử
        
        case (state)
            IDLE: begin
                if (data_valid) begin
                    next_state = LOAD_A;
                    next_ready = 0;
                    next_data_count = 0;
                    next_load_done = 0;
                    next_calc_done = 0;
                end
            end
            
            LOAD_A: begin
                data_done = data_valid;
                if (data_valid) begin
                    next_data_count = data_count + 1;
                    if (data_count == 5) begin // 6 phần tử cho A
                        next_state = LOAD_B;
                        next_load_done = 1;
                        next_data_count = 0;
                    end
                end
            end
            
            LOAD_B: begin
                data_done = data_valid;
                if (data_valid) begin
                    next_data_count = data_count + 1;
                    if (data_count == 2) begin // 3 phần tử cho B
                        next_state = MUL;
                        next_load_done = 1;
                        next_data_count = 0;
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
                mul_data_a_0 = A[row_idx][0];
                mul_data_b_0 = B[0];
                mul_data_a_1 = A[row_idx][1];
                mul_data_b_1 = B[1];
                mul_data_a_2 = A[row_idx][2];
                mul_data_b_2 = B[2];
                
                if (mul_a_ack_0 && mul_b_ack_0 && mul_a_ack_1 && mul_b_ack_1 &&
                    mul_a_ack_2 && mul_b_ack_2) begin
                    mul_start = 1;
                end
                
                if (mul_z_stb_0 && mul_z_stb_1 && mul_z_stb_2) begin
                    mul_z_ack_0 = 1;
                    mul_z_ack_1 = 1;
                    mul_z_ack_2 = 1;
                    next_state = ADD_1;
                end
            end
            
            ADD_1: begin
                add_a_stb = 1;
                add_b_stb = 1;
                add_data_a = mul_results[0];
                add_data_b = mul_results[1];
                
                if (add_a_ack && add_b_ack) begin
                    add_start_1 = 1;
                end
                
                if (add_z_stb) begin
                    add_z_ack = 1;
                    next_state = ADD_2;
                end
            end
            
            ADD_2: begin
                add_a_stb_1 = 1;
                add_b_stb_1 = 1;
                add_data_a_1 = add_temp;
                add_data_b_1 = mul_results[2];
                
                if (add_a_ack_1 && add_b_ack_1) begin
                    add_start_2 = 1;
                end
                
                if (add_z_stb_1) begin
                    add_z_ack_1 = 1;
                    if (row_idx == 1) begin
                        next_state = OUTPUT;
                        next_calc_done = 1;
                    end else begin
                        next_state = MUL;
                    end
                end
            end
            
            OUTPUT: begin
                if (data_idx == 1) begin // 2 phần tử cho C
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
                end
            end
        endcase
    end
    
endmodule