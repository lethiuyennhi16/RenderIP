module small_arbiter_zbuffer #(
    parameter CORE_ID = 0
)(
    input logic clk,
    input logic rst_n,
    
    // Interface với 4 fragdepth - Read requests
    input logic [3:0] frag_request_zbuffer_cp,
    input logic [23:0] frag_addr_zbuffer_cp [3:0],
    output logic [31:0] frag_zbuffer_cp [3:0],
    output logic [3:0] frag_zbuffer_valid_cp,
    input logic [3:0] frag_received_zbuffer_cp,
    
    // Interface với 4 fragdepth - Write requests  
    input logic [3:0] frag_request_zbuffer_ud,
    input logic [23:0] frag_addr_zbuffer_ud [3:0],
    input logic [31:0] frag_zbuffer_ud [3:0],
    output logic [3:0] frag_zbuffer_valid_ud,
    input logic [3:0] frag_received_zbuffer_ud,
    
    // Interface với ARBITER_TEXTURE (đọc z-buffer)
    output logic texture_req,
    output logic [31:0] texture_addr,
    output logic [6:0] texture_core_id,
    input logic texture_valid,
    input logic [31:0] texture_data,
    output logic texture_read_done,
    
    // Interface với ARBITER_WRITE (ghi z-buffer)
    output logic write_req,
    output logic [31:0] write_addr,
    output logic [31:0] write_data,
    output logic [6:0] write_core_id,
    input logic write_valid,
    input logic write_done
);

    typedef enum logic [2:0] {
        ARB_IDLE,
        ARB_READ_REQ,
        ARB_READ_WAIT,
        ARB_READ_DONE,
        ARB_WRITE_REQ,
        ARB_WRITE_WAIT,
        ARB_WRITE_DONE
    } arbiter_state_t;
    
    arbiter_state_t current_state, next_state;
    
    // Round-robin counters
    logic [1:0] read_rr_counter;   // 0-3 cho 4 fragdepth
    logic [1:0] write_rr_counter;  // 0-3 cho 4 fragdepth
    
    // Current serving
    logic [1:0] current_read_frag;
    logic [1:0] current_write_frag;
    
    // Request tracking
    logic [3:0] pending_read_reqs;
    logic [3:0] pending_write_reqs;
    logic has_read_req, has_write_req;
    
    // Priority: Read requests có priority cao hơn write để tránh pipeline stall
    assign has_read_req = |pending_read_reqs;
    assign has_write_req = |pending_write_reqs;
    
    // Track pending requests
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_read_reqs <= 4'b0;
            pending_write_reqs <= 4'b0;
        end else begin
            // Update read requests
            for (int i = 0; i < 4; i++) begin
                if (frag_request_zbuffer_cp[i] && !pending_read_reqs[i]) begin
                    pending_read_reqs[i] <= 1'b1;
                end else if (frag_received_zbuffer_cp[i] && pending_read_reqs[i]) begin
                    pending_read_reqs[i] <= 1'b0;
                end
            end
            
            // Update write requests  
            for (int i = 0; i < 4; i++) begin
                if (frag_request_zbuffer_ud[i] && !pending_write_reqs[i]) begin
                    pending_write_reqs[i] <= 1'b1;
                end else if (frag_received_zbuffer_ud[i] && pending_write_reqs[i]) begin
                    pending_write_reqs[i] <= 1'b0;
                end
            end
        end
    end
    
    // Round-robin selection
    logic [1:0] next_read_frag, next_write_frag;
    
    always_comb begin
        // Find next read request using round-robin
        next_read_frag = read_rr_counter;
        for (int i = 0; i < 4; i++) begin
            logic [1:0] check_idx = (read_rr_counter + i) % 4;
            if (pending_read_reqs[check_idx]) begin
                next_read_frag = check_idx;
                break;
            end
        end
        
        // Find next write request using round-robin
        next_write_frag = write_rr_counter;
        for (int i = 0; i < 4; i++) begin
            logic [1:0] check_idx = (write_rr_counter + i) % 4;
            if (pending_write_reqs[check_idx]) begin
                next_write_frag = check_idx;
                break;
            end
        end
    end
    
    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= ARB_IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            ARB_IDLE: begin
                if (has_read_req) begin
                    next_state = ARB_READ_REQ;
                end else if (has_write_req) begin
                    next_state = ARB_WRITE_REQ;
                end
            end
            
            ARB_READ_REQ: begin
                next_state = ARB_READ_WAIT;
            end
            
            ARB_READ_WAIT: begin
                if (texture_valid) begin
                    next_state = ARB_READ_DONE;
                end
            end
            
            ARB_READ_DONE: begin
                next_state = ARB_IDLE;
            end
            
            ARB_WRITE_REQ: begin
                next_state = ARB_WRITE_WAIT;
            end
            
            ARB_WRITE_WAIT: begin
                if (write_valid) begin
                    next_state = ARB_WRITE_DONE;
                end
            end
            
            ARB_WRITE_DONE: begin
                next_state = ARB_IDLE;
            end
        endcase
    end
    
    // Main control logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset outputs
            texture_req <= 1'b0;
            texture_addr <= 32'h0;
            texture_core_id <= CORE_ID;
            texture_read_done <= 1'b0;
            
            write_req <= 1'b0;
            write_addr <= 32'h0;
            write_data <= 32'h0;
            write_core_id <= CORE_ID;
            
            // Reset counters
            read_rr_counter <= 2'b0;
            write_rr_counter <= 2'b0;
            current_read_frag <= 2'b0;
            current_write_frag <= 2'b0;
            
            // Reset fragdepth outputs
            frag_zbuffer_cp <= '{default: '0};
            frag_zbuffer_valid_cp <= 4'b0;
            frag_zbuffer_valid_ud <= 4'b0;
            
        end else begin
            // Default values
            texture_req <= 1'b0;
            texture_read_done <= 1'b0;
            write_req <= 1'b0;
            frag_zbuffer_valid_cp <= 4'b0;
            frag_zbuffer_valid_ud <= 4'b0;
            
            case (current_state)
                ARB_IDLE: begin
                    if (has_read_req) begin
                        current_read_frag <= next_read_frag;
                    end else if (has_write_req) begin
                        current_write_frag <= next_write_frag;
                    end
                end
                
                ARB_READ_REQ: begin
                    // Send read request to big arbiter
                    texture_req <= 1'b1;
                    texture_addr <= {8'h0, frag_addr_zbuffer_cp[current_read_frag]}; // Extend to 32-bit
                    texture_core_id <= CORE_ID;
                end
                
                ARB_READ_WAIT: begin
                    // Wait for read response
                    if (texture_valid) begin
                        // Forward data to requesting fragdepth
                        frag_zbuffer_cp[current_read_frag] <= texture_data;
                        frag_zbuffer_valid_cp[current_read_frag] <= 1'b1;
                        texture_read_done <= 1'b1;
                    end
                end
                
                ARB_READ_DONE: begin
                    // Update round-robin counter for next read
                    read_rr_counter <= (current_read_frag + 1) % 4;
                end
                
                ARB_WRITE_REQ: begin
                    // Send write request to big arbiter
                    write_req <= 1'b1;
                    write_addr <= {8'h0, frag_addr_zbuffer_ud[current_write_frag]}; // Extend to 32-bit
                    write_data <= frag_zbuffer_ud[current_write_frag];
                    write_core_id <= CORE_ID;
                end
                
                ARB_WRITE_WAIT: begin
                    // Wait for write completion
                    if (write_valid) begin
                        // Signal completion to requesting fragdepth
                        frag_zbuffer_valid_ud[current_write_frag] <= 1'b1;
                    end
                end
                
                ARB_WRITE_DONE: begin
                    // Update round-robin counter for next write
                    write_rr_counter <= (current_write_frag + 1) % 4;
                end
            endcase
        end
    end
    
    // Debug/monitoring signals (optional)
    logic [3:0] debug_read_queue_depth;
    logic [3:0] debug_write_queue_depth;
    
    always_comb begin
        debug_read_queue_depth = pending_read_reqs[0] + pending_read_reqs[1] + 
                                pending_read_reqs[2] + pending_read_reqs[3];
        debug_write_queue_depth = pending_write_reqs[0] + pending_write_reqs[1] + 
                                 pending_write_reqs[2] + pending_write_reqs[3];
    end

endmodule