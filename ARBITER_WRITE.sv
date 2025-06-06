module ARBITER_WRITE (
    input logic clk,
    input logic rst_n,
    
    // Interface với 87 RENDER_CORE (unified write interface)
    input logic [86:0] write_req,           // Write request signals từ cores
    input logic [86:0][31:0] write_addr,    // Write addresses từ cores  
    input logic [86:0][31:0] write_data,    // Write data từ cores
    input logic [86:0][6:0] write_core_id,  // Core IDs (mỗi core gửi ID riêng)
    
    output logic [86:0] write_valid,        // Valid signals tới cores
    output logic [86:0] write_done,         // Write completed signals
    
    // Interface với FIFO
    output logic FF_writerequest,
    input logic FF_almostfull,
    output logic [31:0] FF_data
);

    // FSM states
    typedef enum logic [2:0] {
        IDLE            = 3'b000,
        WAIT_FIFO_SPACE = 3'b001,
        SEND_ADDR       = 3'b010,
        SEND_DATA       = 3'b011,
        COMPLETE        = 3'b100
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [6:0] current_serving_core;      // Core hiện tại đang được serve
    logic [6:0] winning_core_id;           // Core ID của winner
    logic [31:0] current_addr;             // Address được lưu
    logic [31:0] current_data;             // Data được lưu
    logic addr_sent;                       // Flag đã gửi address
    
    // Priority encoder - First Come First Serve (tìm core có index thấp nhất)
    logic [6:0] requesting_core;
    logic valid_request_found;
    
    always_comb begin
        requesting_core = 7'd127;       // Invalid value
        valid_request_found = 1'b0;
        
        // Tìm core có index thấp nhất đang request (FCFS)
        for (int i = 0; i < 87; i++) begin
            if (write_req[i] && !valid_request_found) begin
                requesting_core = i[6:0];
                valid_request_found = 1'b1;
            end
        end
    end
    
    // State machine update
    always_ff @(posedge clk or negedge rst_n) begin
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
                if (valid_request_found) begin
                    if (FF_almostfull) begin
                        next_state = WAIT_FIFO_SPACE;
                    end else begin
                        next_state = SEND_ADDR;
                    end
                end
            end
            
            WAIT_FIFO_SPACE: begin
                if (!FF_almostfull) begin
                    next_state = SEND_ADDR;
                end
            end
            
            SEND_ADDR: begin
                if (!FF_almostfull) begin
                    next_state = SEND_DATA;
                end else begin
                    next_state = WAIT_FIFO_SPACE;
                end
            end
            
            SEND_DATA: begin
                if (!FF_almostfull) begin
                    next_state = COMPLETE;
                end else begin
                    next_state = WAIT_FIFO_SPACE;
                end
            end
            
            COMPLETE: begin
                next_state = IDLE;  // Hoàn thành transaction, quay về IDLE
            end
        endcase
    end
    
    // Internal registers update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_serving_core <= 7'b0;
            winning_core_id <= 7'b0;
            current_addr <= 32'b0;
            current_data <= 32'b0;
            addr_sent <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    addr_sent <= 1'b0;
                    if (valid_request_found) begin
                        // Lưu thông tin của winning core
                        current_serving_core <= requesting_core;
                        winning_core_id <= write_core_id[requesting_core];
                        current_addr <= write_addr[requesting_core];
                        current_data <= write_data[requesting_core];
                    end
                end
                
                WAIT_FIFO_SPACE: begin
                    // Chờ FIFO có space, không làm gì
                end
                
                SEND_ADDR: begin
                    if (!FF_almostfull) begin
                        addr_sent <= 1'b1;
                    end
                end
                
                SEND_DATA: begin
                    // Data đã được gửi, chuẩn bị complete
                end
                
                COMPLETE: begin
                    // Reset cho transaction tiếp theo
                    current_serving_core <= 7'b0;
                    winning_core_id <= 7'b0;
                    current_addr <= 32'b0;
                    current_data <= 32'b0;
                    addr_sent <= 1'b0;
                end
            endcase
        end
    end
    
    // FIFO interface logic
    always_comb begin
        FF_writerequest = 1'b0;
        FF_data = 32'b0;
        
        case (current_state)
            SEND_ADDR: begin
                if (!FF_almostfull) begin
                    FF_writerequest = 1'b1;
                    FF_data = {9'b0, current_addr[22:0]};  // Address (23-bit) with padding
                end
            end
            
            SEND_DATA: begin
                if (!FF_almostfull && addr_sent) begin
                    FF_writerequest = 1'b1;
                    FF_data = current_data;  // Data (32-bit)
                end
            end
        endcase
    end
    
    // Output logic to cores
    always_comb begin
        // Default: no responses
        write_valid = 87'b0;
        write_done = 87'b0;
        
        case (current_state)
            SEND_ADDR: begin
                if (!FF_almostfull) begin
                    write_valid[current_serving_core] = 1'b1;
                end
            end
            
            SEND_DATA: begin
                if (!FF_almostfull && addr_sent) begin
                    write_valid[current_serving_core] = 1'b1;
                end
            end
            
            COMPLETE: begin
                // Signal write completion to the served core
                write_done[current_serving_core] = 1'b1;
            end
        endcase
    end

endmodule
