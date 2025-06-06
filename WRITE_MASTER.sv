module WRITE_MASTER (
    input logic clk,
    input logic rst_n,
    
    // Interface CONTROL
    input logic start,
    input logic [31:0] length,
    input logic [31:0] start_address,
    output logic WM_done,
    output logic render_done,
    
    // Interface FIFO
    output logic FF_readrequest,
    input logic FF_empty,
    input logic [31:0] FF_q,
    
    // Interface Avalon MM Write Master
    input logic iWM_waitrequest,
    output logic oWM_write,
    output logic [31:0] oWM_writeaddress,
    output logic [31:0] oWM_writedata
);

    // FSM states
    typedef enum logic [2:0] {
        IDLE         = 3'b000,
        READ_ADDR    = 3'b001,
        READ_DATA    = 3'b010,
        WRITE_MEMORY = 3'b011,
        WAIT_WRITE   = 3'b100,
        CHECK_DONE   = 3'b101,
        DONE         = 3'b110
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [31:0] current_address;
    logic [31:0] current_data;
    logic [31:0] bytes_written;
    logic [31:0] total_length;
    logic [31:0] base_address;
    logic is_framebuffer_write;  // From address bit 24
    
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
                if (start) begin
                    next_state = READ_ADDR;
                end
            end
            
            READ_ADDR: begin
                if (!FF_empty) begin
                    next_state = READ_DATA;
                end
            end
            
            READ_DATA: begin
                if (!FF_empty) begin
                    next_state = WRITE_MEMORY;
                end
            end
            
            WRITE_MEMORY: begin
                next_state = WAIT_WRITE;
            end
            
            WAIT_WRITE: begin
                if (!iWM_waitrequest) begin
                    next_state = CHECK_DONE;
                end
            end
            
            CHECK_DONE: begin
                if (bytes_written >= total_length || FF_empty) begin
                    next_state = DONE;
                end else begin
                    next_state = READ_ADDR;  // Next addr+data pair
                end
            end
            
            DONE: begin
                if (!start) begin  // Wait for start deassertion
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    // Internal registers update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_address <= 32'b0;
            current_data <= 32'b0;
            bytes_written <= 32'b0;
            total_length <= 32'b0;
            base_address <= 32'b0;
            is_framebuffer_write <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    if (start) begin
                        bytes_written <= 32'b0;
                        total_length <= length;
                        base_address <= start_address;
                    end
                end
                
                READ_ADDR: begin
                    if (!FF_empty) begin
                        // Extract type flag and address
                        is_framebuffer_write <= FF_q[24];  // Type bit
                        current_address <= base_address + {8'b0, FF_q[23:0]};  // Real address
                    end
                end
                
                READ_DATA: begin
                    if (!FF_empty) begin
                        current_data <= FF_q;  // Either RGBA or Z-value (both 32-bit)
                    end
                end
                
                WAIT_WRITE: begin
                    if (!iWM_waitrequest) begin
                        bytes_written <= bytes_written + 32'd4;  // Each write = 4 bytes
                    end
                end
            endcase
        end
    end
    
    // FIFO read control
    always_comb begin
        FF_readrequest = 1'b0;
        
        case (current_state)
            READ_ADDR, READ_DATA: begin
                FF_readrequest = !FF_empty;
            end
        endcase
    end
    
    // Avalon MM Write Master control
    always_comb begin
        oWM_write = 1'b0;
        oWM_writeaddress = 32'b0;
        oWM_writedata = 32'b0;
        
        case (current_state)
            WRITE_MEMORY, WAIT_WRITE: begin
                oWM_write = 1'b1;
                oWM_writeaddress = current_address;
                oWM_writedata = current_data;
            end
        endcase
    end
    
    // Output control
    always_comb begin
        WM_done = (current_state == DONE);
        render_done = (current_state == DONE);
    end

endmodule