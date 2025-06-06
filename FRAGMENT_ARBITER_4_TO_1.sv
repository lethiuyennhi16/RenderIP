module FRAGMENT_ARBITER_4_TO_1 (
    input logic clk,
    input logic rst_n,
    
    // Interface với 4 FRAGMENT cores - Texture requests
    input logic [3:0] frag_texture_req,
    input logic [23:0] frag_texture_addr [3:0],
    input logic [6:0] frag_texture_core_id [3:0],
    output logic [3:0] frag_texture_valid,
    output logic [31:0] frag_texture_data [3:0],
    input logic [3:0] frag_texture_read_done,
    
    // Interface với 4 FRAGMENT cores - Write requests  
    input logic [3:0] frag_write_req,
    input logic [23:0] frag_write_addr [3:0],
    input logic [31:0] frag_write_data [3:0],
    input logic [6:0] frag_write_core_id [3:0],
    output logic [3:0] frag_write_valid,
    output logic [3:0] frag_write_done,
    
    // Unified output interface - Texture
    output logic texture_req_out,
    output logic [23:0] texture_addr_out,
    output logic [6:0] texture_core_id_out,
    input logic texture_valid_in,
    input logic [31:0] texture_data_in,
    output logic texture_read_done_out,
    
    // Unified output interface - Write
    output logic write_req_out,
    output logic [23:0] write_addr_out,
    output logic [31:0] write_data_out,
    output logic [6:0] write_core_id_out,
    input logic write_valid_in,
    input logic write_done_in
);

    // Arbitration states
    typedef enum logic [2:0] {
        IDLE = 3'b000,
        TEXTURE_GRANT = 3'b001,
        TEXTURE_WAIT = 3'b010,
        WRITE_GRANT = 3'b011,
        WRITE_WAIT = 3'b100
    } arbiter_state_t;
    
    arbiter_state_t current_state, next_state;
    
    // Round-robin counters
    logic [1:0] texture_rr_counter;
    logic [1:0] write_rr_counter;
    logic [1:0] current_texture_grant;
    logic [1:0] current_write_grant;
    
    // Fair scheduling between texture and write
    logic prefer_texture;
    logic [3:0] texture_starvation_counter;
    logic [3:0] write_starvation_counter;
    
    // Request detection
    logic texture_pending;
    logic write_pending;
    logic [1:0] next_texture_grant;
    logic [1:0] next_write_grant;
    
    // Priority encoder for round-robin texture arbitration
    always_comb begin
        texture_pending = |frag_texture_req;
        next_texture_grant = 2'b00;
        
        // Round-robin starting from current counter
        for (int i = 0; i < 4; i++) begin
            logic [1:0] check_idx = texture_rr_counter + i[1:0];
            if (frag_texture_req[check_idx]) begin
                next_texture_grant = check_idx;
                break;
            end
        end
    end
    
    // Priority encoder for round-robin write arbitration  
    always_comb begin
        write_pending = |frag_write_req;
        next_write_grant = 2'b00;
        
        // Round-robin starting from current counter
        for (int i = 0; i < 4; i++) begin
            logic [1:0] check_idx = write_rr_counter + i[1:0];
            if (frag_write_req[check_idx]) begin
                next_write_grant = check_idx;
                break;
            end
        end
    end
    
    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next state logic with fair scheduling
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                // Fair scheduling between texture and write with starvation prevention
                if (texture_pending && write_pending) begin
                    // Both have requests - use fair scheduling
                    if (prefer_texture || write_starvation_counter > 4'd8) begin
                        next_state = TEXTURE_GRANT;
                    end else if (texture_starvation_counter > 4'd8) begin
                        next_state = WRITE_GRANT;
                    end else begin
                        next_state = prefer_texture ? TEXTURE_GRANT : WRITE_GRANT;
                    end
                end else if (texture_pending) begin
                    next_state = TEXTURE_GRANT;
                end else if (write_pending) begin
                    next_state = WRITE_GRANT;
                end
            end
            
            TEXTURE_GRANT: begin
                if (texture_req_out) begin
                    next_state = TEXTURE_WAIT;
                end
            end
            
            TEXTURE_WAIT: begin
                if (texture_valid_in && frag_texture_read_done[current_texture_grant]) begin
                    // Check if more requests pending
                    if (texture_pending || write_pending) begin
                        next_state = IDLE;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end
            
            WRITE_GRANT: begin
                if (write_req_out) begin
                    next_state = WRITE_WAIT;
                end
            end
            
            WRITE_WAIT: begin
                if (write_valid_in && write_done_in) begin
                    // Check if more requests pending  
                    if (texture_pending || write_pending) begin
                        next_state = IDLE;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end
        endcase
    end
    
    // Fair scheduling and starvation prevention
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            texture_rr_counter <= 2'b00;
            write_rr_counter <= 2'b00;
            current_texture_grant <= 2'b00;
            current_write_grant <= 2'b00;
            prefer_texture <= 1'b1;  // Start with texture preference
            texture_starvation_counter <= 4'b0;
            write_starvation_counter <= 4'b0;
        end else begin
            // Update starvation counters
            if (current_state == IDLE) begin
                if (texture_pending && !write_pending) begin
                    write_starvation_counter <= 4'b0;  // Reset write starvation
                end else if (!texture_pending && write_pending) begin
                    texture_starvation_counter <= 4'b0;  // Reset texture starvation
                end else if (texture_pending && write_pending) begin
                    // Both pending - increment starvation for non-served type
                    if (next_state == TEXTURE_GRANT) begin
                        write_starvation_counter <= write_starvation_counter + 1'b1;
                        texture_starvation_counter <= 4'b0;
                    end else if (next_state == WRITE_GRANT) begin
                        texture_starvation_counter <= texture_starvation_counter + 1'b1;
                        write_starvation_counter <= 4'b0;
                    end
                end
            end
            
            case (current_state)
                TEXTURE_GRANT: begin
                    current_texture_grant <= next_texture_grant;
                end
                
                TEXTURE_WAIT: begin
                    if (texture_valid_in && frag_texture_read_done[current_texture_grant]) begin
                        texture_rr_counter <= current_texture_grant + 1'b1;
                        prefer_texture <= 1'b0;  // Switch preference to write
                    end
                end
                
                WRITE_GRANT: begin
                    current_write_grant <= next_write_grant;
                end
                
                WRITE_WAIT: begin
                    if (write_valid_in && write_done_in) begin
                        write_rr_counter <= current_write_grant + 1'b1;
                        prefer_texture <= 1'b1;  // Switch preference to texture
                    end
                end
            endcase
        end
    end
    
    // Output muxing - Texture interface
    always_comb begin
        // Default values
        texture_req_out = 1'b0;
        texture_addr_out = 24'h0;
        texture_core_id_out = 7'h0;
        texture_read_done_out = 1'b0;
        
        case (current_state)
            TEXTURE_GRANT, TEXTURE_WAIT: begin
                texture_req_out = frag_texture_req[current_texture_grant];
                texture_addr_out = frag_texture_addr[current_texture_grant];
                texture_core_id_out = frag_texture_core_id[current_texture_grant];
                texture_read_done_out = frag_texture_read_done[current_texture_grant];
            end
        endcase
    end
    
    // Output muxing - Write interface
    always_comb begin
        // Default values
        write_req_out = 1'b0;
        write_addr_out = 24'h0;
        write_data_out = 32'h0;
        write_core_id_out = 7'h0;
        
        case (current_state)
            WRITE_GRANT, WRITE_WAIT: begin
                write_req_out = frag_write_req[current_write_grant];
                write_addr_out = frag_write_addr[current_write_grant][23:0];
                write_data_out = frag_write_data[current_write_grant];
                write_core_id_out = frag_write_core_id[current_write_grant];
            end
        endcase
    end
    
    // Input demuxing - Texture responses
    always_comb begin
        // Default: no grants
        frag_texture_valid = 4'b0000;
        for (int i = 0; i < 4; i++) begin
            frag_texture_data[i] = 32'h0;
        end
        
        // Grant to current texture winner
        if (current_state == TEXTURE_WAIT) begin
            frag_texture_valid[current_texture_grant] = texture_valid_in;
            frag_texture_data[current_texture_grant] = texture_data_in;
        end
    end
    
    // Input demuxing - Write responses
    always_comb begin
        // Default: no grants
        frag_write_valid = 4'b0000;
        frag_write_done = 4'b0000;
        
        // Grant to current write winner
        if (current_state == WRITE_WAIT) begin
            frag_write_valid[current_write_grant] = write_valid_in;
            frag_write_done[current_write_grant] = write_done_in;
        end
    end

endmodule