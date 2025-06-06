module CORE_ARBITER_2_TO_1 (
    input logic clk,
    input logic rst_n,
    
    // Interface từ RASTERIZER - Texture requests
    input logic raster_texture_req,
    input logic [23:0] raster_texture_addr,
    input logic [6:0] raster_texture_core_id,
    output logic raster_texture_valid,
    output logic [31:0] raster_texture_data,
    input logic raster_texture_read_done,
    
    // Interface từ RASTERIZER - Write requests  
    input logic raster_write_req,
    input logic [31:0] raster_write_addr,
    input logic [31:0] raster_write_data,
    input logic [6:0] raster_write_core_id,
    output logic raster_write_valid,
    output logic raster_write_done,
    
    // Interface từ FRAGMENT_ARBITER - Texture requests
    input logic frag_texture_req,
    input logic [23:0] frag_texture_addr,
    input logic [6:0] frag_texture_core_id,
    output logic frag_texture_valid,
    output logic [31:0] frag_texture_data,
    input logic frag_texture_read_done,
    
    // Interface từ FRAGMENT_ARBITER - Write requests
    input logic frag_write_req,
    input logic [23:0] frag_write_addr,
    input logic [31:0] frag_write_data,
    input logic [6:0] frag_write_core_id,
    output logic frag_write_valid,
    output logic frag_write_done,
    
    // External unified interface - Texture
    output logic texture_req_out,
    output logic [23:0] texture_addr_out,
    output logic [6:0] texture_core_id_out,
    input logic texture_valid_in,
    input logic [31:0] texture_data_in,
    output logic texture_read_done_out,
    
    // External unified interface - Write
    output logic write_req_out,
    output logic [31:0] write_addr_out,
    output logic [31:0] write_data_out,
    output logic [6:0] write_core_id_out,
    input logic write_valid_in,
    input logic write_done_in
);

    // Arbitration states
    typedef enum logic [2:0] {
        IDLE = 3'b000,
        RASTER_TEXTURE = 3'b001,
        RASTER_WRITE = 3'b010,
        FRAG_TEXTURE = 3'b011,
        FRAG_WRITE = 3'b100
    } arbiter_state_t;
    
    arbiter_state_t current_state, next_state;
    
    // Fair scheduling state
    logic prefer_raster;
    logic [3:0] raster_starvation_counter;
    logic [3:0] frag_starvation_counter;
    
    // Request detection
    logic raster_pending;
    logic frag_pending;
    logic raster_texture_pending;
    logic raster_write_pending;
    logic frag_texture_pending;
    logic frag_write_pending;
    
    // Request aggregation
    always_comb begin
        raster_texture_pending = raster_texture_req;
        raster_write_pending = raster_write_req;
        frag_texture_pending = frag_texture_req;
        frag_write_pending = frag_write_req;
        
        raster_pending = raster_texture_pending || raster_write_pending;
        frag_pending = frag_texture_pending || frag_write_pending;
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
                if (raster_pending && frag_pending) begin
                    // Both have requests - use fair scheduling with starvation prevention
                    if (raster_starvation_counter > 4'd6) begin
                        // Force RASTER service
                        if (raster_texture_pending) begin
                            next_state = RASTER_TEXTURE;
                        end else begin
                            next_state = RASTER_WRITE;
                        end
                    end else if (frag_starvation_counter > 4'd6) begin
                        // Force FRAGMENT service
                        if (frag_texture_pending) begin
                            next_state = FRAG_TEXTURE;
                        end else begin
                            next_state = FRAG_WRITE;
                        end
                    end else begin
                        // Normal fair scheduling
                        if (prefer_raster) begin
                            if (raster_texture_pending) begin
                                next_state = RASTER_TEXTURE;
                            end else begin
                                next_state = RASTER_WRITE;
                            end
                        end else begin
                            if (frag_texture_pending) begin
                                next_state = FRAG_TEXTURE;
                            end else begin
                                next_state = FRAG_WRITE;
                            end
                        end
                    end
                end else if (raster_pending) begin
                    // Only RASTER has requests
                    if (raster_texture_pending) begin
                        next_state = RASTER_TEXTURE;
                    end else begin
                        next_state = RASTER_WRITE;
                    end
                end else if (frag_pending) begin
                    // Only FRAGMENT has requests
                    if (frag_texture_pending) begin
                        next_state = FRAG_TEXTURE;
                    end else begin
                        next_state = FRAG_WRITE;
                    end
                end
            end
            
            RASTER_TEXTURE: begin
                if (texture_valid_in && raster_texture_read_done) begin
                    next_state = IDLE;
                end
            end
            
            RASTER_WRITE: begin
                if (write_valid_in && write_done_in) begin
                    next_state = IDLE;
                end
            end
            
            FRAG_TEXTURE: begin
                if (texture_valid_in && frag_texture_read_done) begin
                    next_state = IDLE;
                end
            end
            
            FRAG_WRITE: begin
                if (write_valid_in && write_done_in) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    // Fair scheduling and starvation prevention
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prefer_raster <= 1'b1;  // Start with RASTER preference
            raster_starvation_counter <= 4'b0;
            frag_starvation_counter <= 4'b0;
        end else begin
            // Update starvation counters
            if (current_state == IDLE) begin
                if (raster_pending && !frag_pending) begin
                    frag_starvation_counter <= 4'b0;  // Reset FRAG starvation
                end else if (!raster_pending && frag_pending) begin
                    raster_starvation_counter <= 4'b0;  // Reset RASTER starvation
                end else if (raster_pending && frag_pending) begin
                    // Both pending - increment starvation for non-served source
                    if (next_state == RASTER_TEXTURE || next_state == RASTER_WRITE) begin
                        frag_starvation_counter <= frag_starvation_counter + 1'b1;
                        raster_starvation_counter <= 4'b0;
                    end else if (next_state == FRAG_TEXTURE || next_state == FRAG_WRITE) begin
                        raster_starvation_counter <= raster_starvation_counter + 1'b1;
                        frag_starvation_counter <= 4'b0;
                    end
                end
            end
            
            // Update preference after completing a transaction
            case (current_state)
                RASTER_TEXTURE: begin
                    if (texture_valid_in && raster_texture_read_done) begin
                        prefer_raster <= 1'b0;  // Switch preference to FRAGMENT
                    end
                end
                
                RASTER_WRITE: begin
                    if (write_valid_in && write_done_in) begin
                        prefer_raster <= 1'b0;  // Switch preference to FRAGMENT
                    end
                end
                
                FRAG_TEXTURE: begin
                    if (texture_valid_in && frag_texture_read_done) begin
                        prefer_raster <= 1'b1;  // Switch preference to RASTER
                    end
                end
                
                FRAG_WRITE: begin
                    if (write_valid_in && write_done_in) begin
                        prefer_raster <= 1'b1;  // Switch preference to RASTER
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
            RASTER_TEXTURE: begin
                texture_req_out = raster_texture_req;
                texture_addr_out = raster_texture_addr;
                texture_core_id_out = raster_texture_core_id;
                texture_read_done_out = raster_texture_read_done;
            end
            
            FRAG_TEXTURE: begin
                texture_req_out = frag_texture_req;
                texture_addr_out = frag_texture_addr;
                texture_core_id_out = frag_texture_core_id;
                texture_read_done_out = frag_texture_read_done;
            end
        endcase
    end
    
    // Output muxing - Write interface
    always_comb begin
        // Default values
        write_req_out = 1'b0;
        write_addr_out = 32'h0;
        write_data_out = 32'h0;
        write_core_id_out = 7'h0;
        
        case (current_state)
            RASTER_WRITE: begin
                write_req_out = raster_write_req;
                write_addr_out = raster_write_addr;
                write_data_out = raster_write_data;
                write_core_id_out = raster_write_core_id;
            end
            
            FRAG_WRITE: begin
                write_req_out = frag_write_req;
                write_addr_out = {8'h0, frag_write_addr};  // Convert 24-bit to 32-bit
                write_data_out = frag_write_data;
                write_core_id_out = frag_write_core_id;
            end
        endcase
    end
    
    // Input demuxing - Texture responses
    always_comb begin
        // Default: no responses
        raster_texture_valid = 1'b0;
        raster_texture_data = 32'h0;
        frag_texture_valid = 1'b0;
        frag_texture_data = 32'h0;
        
        case (current_state)
            RASTER_TEXTURE: begin
                raster_texture_valid = texture_valid_in;
                raster_texture_data = texture_data_in;
            end
            
            FRAG_TEXTURE: begin
                frag_texture_valid = texture_valid_in;
                frag_texture_data = texture_data_in;
            end
        endcase
    end
    
    // Input demuxing - Write responses
    always_comb begin
        // Default: no responses
        raster_write_valid = 1'b0;
        raster_write_done = 1'b0;
        frag_write_valid = 1'b0;
        frag_write_done = 1'b0;
        
        case (current_state)
            RASTER_WRITE: begin
                raster_write_valid = write_valid_in;
                raster_write_done = write_done_in;
            end
            
            FRAG_WRITE: begin
                frag_write_valid = write_valid_in;
                frag_write_done = write_done_in;
            end
        endcase
    end

endmodule