module ARBITER_TEXTURE (
    input logic clk,
    input logic rst_n,
    
    // Interface với 87 RENDER_CORE
    input logic [86:0] texture_req,           // Request signals từ cores
    input logic [86:0][23:0] texture_addr,    // Addresses từ cores  
    input logic [86:0][6:0] core_id,          // Core IDs (mỗi core gửi ID riêng)
    
    output logic [86:0] texture_valid,        // Valid signals tới cores
    output logic [31:0] texture_data,         // Data broadcast tới all cores
    input logic [86:0] read_done,             // Cores báo đã nhận xong data
    
    // Interface với FIFO_TEXTURE (ghi request)
    input logic FF_texture_almostfull,
    output logic FF_texture_writerequest,
    output logic [31:0] FF_texture_data,      // [31:24]=core_id, [23:0]=address
    
    // Interface với FIFO_RGB (đọc response)  
    input logic FF_rgb_empty,
    output logic FF_rgb_readrequest,
    input logic [31:0] FF_rgb_q              // Data hoặc Core ID
);

    // Internal FSM
    typedef enum logic [2:0] {
        IDLE            = 3'b000,
        FIND_REQUEST    = 3'b001,
        WRITE_FIFO      = 3'b010,
        READ_RESPONSE   = 3'b011,
        WAIT_DATA       = 3'b100,
        SEND_DATA       = 3'b101,
        WAIT_ACK        = 3'b110
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [6:0] winning_core;
    logic [6:0] response_core_id;
    logic [31:0] response_data;
    logic response_phase;       // 0=data phase, 1=ID phase
    logic valid_request_found;
    
    // Priority encoder để tìm core ID nhỏ nhất có request
    always_comb begin
        winning_core = 7'd127;      // Invalid value
        valid_request_found = 1'b0;
        
        for (int i = 0; i < 87; i++) begin
            if (texture_req[i] && (i < winning_core)) begin
                winning_core = i[6:0];
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
                if (valid_request_found && !FF_texture_almostfull) begin
                    next_state = WRITE_FIFO;
                end else if (!FF_rgb_empty) begin
                    next_state = READ_RESPONSE;
                end
            end
            
            WRITE_FIFO: begin
                if (!FF_texture_almostfull) begin
                    next_state = IDLE;  // Quay lại check requests khác
                end
            end
            
            READ_RESPONSE: begin
                if (!FF_rgb_empty) begin
                    next_state = WAIT_DATA;
                end
            end
            
            WAIT_DATA: begin
                if (!FF_rgb_empty) begin
                    next_state = SEND_DATA;
                end
            end
            
            SEND_DATA: begin
                next_state = WAIT_ACK;
            end
            
            WAIT_ACK: begin
                if (read_done[response_core_id]) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    // Internal registers update
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            response_core_id <= 7'b0;
            response_data <= 32'b0;
            response_phase <= 1'b0;
        end else begin
            case (current_state)
                READ_RESPONSE: begin
                    if (!FF_rgb_empty) begin
                        response_data <= FF_rgb_q;  // First read = texture data
                        response_phase <= 1'b0;     // Data phase
                    end
                end
                
                WAIT_DATA: begin
                    if (!FF_rgb_empty) begin
                        response_core_id <= FF_rgb_q[6:0];  // Second read = core ID
                        response_phase <= 1'b1;             // ID phase  
                    end
                end
            endcase
        end
    end
    
    // Output logic
    
    // FIFO_TEXTURE interface
    assign FF_texture_writerequest = (current_state == WRITE_FIFO) && !FF_texture_almostfull;
    assign FF_texture_data = {1'b0, winning_core, texture_addr[winning_core]};  // [31:24]=core_id, [23:0]=addr
    
    // FIFO_RGB interface  
    assign FF_rgb_readrequest = ((current_state == READ_RESPONSE) || (current_state == WAIT_DATA)) && !FF_rgb_empty;
    
    // RENDER_CORE interface
    always_comb begin
        texture_valid = 87'b0;
        texture_data = 32'b0;
        
        if (current_state == SEND_DATA) begin
            texture_valid[response_core_id] = 1'b1;
            texture_data = response_data;
        end
    end

endmodule