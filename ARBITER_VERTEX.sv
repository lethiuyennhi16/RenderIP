module ARBITER_VERTEX (
    input logic clk,
    input logic rst_n,
    
    // Interface với FIFO_VERTEX (đọc vertex data)
    input logic FF_vertex_empty,
    output logic FF_vertex_readrequest,
    input logic [31:0] FF_vertex_q,
    
    // Interface với 87 RENDER_CORE (shared bus)
    output logic [31:0] vertex_data,          // Shared data bus
    output logic [6:0] target_core_id,        // Target core (0-86)
    output logic vertex_valid,                // Valid signal
    input logic [86:0] vertex_request,        // Core request signals  
    input logic [86:0] vertex_read_done       // Core completed face (24 words)
);

    // Internal signals - không cần FIFO internal
    // ARBITER chỉ đọc từ FIFO_VERTEX có sẵn
    
    // FSM states
    typedef enum logic [2:0] {
        IDLE                = 3'b000,
        INITIAL_DISTRIBUTION = 3'b001,
        SEND_DATA           = 3'b010,
        WAIT_COMPLETE       = 3'b011,
        ON_DEMAND           = 3'b100
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [6:0] current_core;           // Core hiện tại đang gửi data
    logic [6:0] next_available_core;    // Core tiếp theo trong round-robin
    logic [4:0] word_count;             // Đếm words đã gửi cho core hiện tại (0-23)
    logic [6:0] cores_initialized;      // Số cores đã được khởi tạo trong phase đầu
    logic initial_phase_done;           // Flag báo đã xong phase khởi tạo
    
    // Priority encoder để tìm core request
    logic [6:0] requesting_core;
    logic valid_request_found;
    
    always_comb begin
        requesting_core = 7'd127;       // Invalid value
        valid_request_found = 1'b0;
        
        for (int i = 0; i < 87; i++) begin
            if (vertex_request[i] && (i < requesting_core)) begin
                requesting_core = i[6:0];
                valid_request_found = 1'b1;
            end
        end
    end
    
    // State machine update
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (!FF_vertex_empty && !initial_phase_done) begin
                    next_state = INITIAL_DISTRIBUTION;
                end else if (!FF_vertex_empty && valid_request_found) begin
                    next_state = ON_DEMAND;
                end
            end
            
            INITIAL_DISTRIBUTION: begin
                if (!FF_vertex_empty) begin
                    next_state = SEND_DATA;
                end
            end
            
            SEND_DATA: begin
                if (!FF_vertex_empty) begin
                    next_state = WAIT_COMPLETE;
                end
            end
            
            WAIT_COMPLETE: begin
                if (vertex_read_done[current_core]) begin
                    if (!initial_phase_done) begin
                        if (cores_initialized >= 86) begin
                            next_state = IDLE;  // Chuyển sang on-demand mode
                        end else begin
                            next_state = INITIAL_DISTRIBUTION;  // Tiếp tục round-robin
                        end
                    end else begin
                        next_state = IDLE;  // Về chế độ on-demand
                    end
                end
            end
            
            ON_DEMAND: begin
                if (!FF_vertex_empty && valid_request_found) begin
                    next_state = SEND_DATA;
                end else begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    // Internal registers update
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            current_core <= 7'b0;
            next_available_core <= 7'b0;
            word_count <= 5'b0;
            cores_initialized <= 7'b0;
            initial_phase_done <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    word_count <= 5'b0;
                    if (!initial_phase_done && cores_initialized >= 86) begin
                        initial_phase_done <= 1'b1;
                    end
                end
                
                INITIAL_DISTRIBUTION: begin
                    current_core <= next_available_core;
                    word_count <= 5'b0;
                end
                
                SEND_DATA: begin
                    if (!FF_vertex_empty) begin
                        word_count <= word_count + 1'b1;
                    end
                end
                
                WAIT_COMPLETE: begin
                    if (vertex_read_done[current_core]) begin
                        word_count <= 5'b0;
                        if (!initial_phase_done) begin
                            // Update cho round-robin tiếp theo
                            if (next_available_core >= 86) begin
                                next_available_core <= 7'b0;
                            end else begin
                                next_available_core <= next_available_core + 1'b1;
                            end
                            cores_initialized <= cores_initialized + 1'b1;
                        end
                    end
                end
                
                ON_DEMAND: begin
                    if (valid_request_found) begin
                        current_core <= requesting_core;
                        word_count <= 5'b0;
                    end
                end
            endcase
        end
    end
    
    // Output logic
    assign FF_vertex_readrequest = ((current_state == SEND_DATA) && !FF_vertex_empty);
    
    always_comb begin
        vertex_data = 32'b0;
        target_core_id = 7'b0;
        vertex_valid = 1'b0;
        
        if (current_state == SEND_DATA && !FF_vertex_empty) begin
            vertex_data = FF_vertex_q;
            target_core_id = current_core;
            vertex_valid = 1'b1;
        end
    end

endmodule