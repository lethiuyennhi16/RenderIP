module tile_checker (
    input logic clk,
    input logic rst_n,
    
    // Handshake protocol
    output logic ready,
    input logic data_valid,
    output logic calc_done,
    input logic read_done,
    
    // Input data
    input logic [31:0] triangle_pts[3][2],  // Triangle vertices
    input logic [31:0] tile_x,
    input logic [31:0] tile_y,
    input logic [31:0] tile_width,
    input logic [31:0] tile_height,
    
    // Output data
    output logic intersects,
    output logic [31:0] pixel_count,
    output logic [31:0] pixels_x[16],       // Max 16 pixels (4x4 tile)
    output logic [31:0] pixels_y[16]
);

    typedef enum logic [3:0] {
        IDLE,
        CHECK_TILE_CORNERS,
        SCAN_PIXELS_IF_NEEDED,
        COUNT_VALID_PIXELS,
        OUTPUT_RESULTS,
        WAIT_READ
    } tile_state_t;
    
    tile_state_t current_state, next_state;
    
    // Internal storage
    logic [31:0] tri_pts[3][2];
    logic [31:0] tile_corners[4][2];  // 4 corners of the tile
    logic [3:0] corners_inside;       // Which corners are inside triangle
    logic tile_small;                 // True if tile < 4x4
    
    // Pixel scanning
    logic [31:0] scan_x, scan_y;
    logic [31:0] valid_pixels;
    logic [4:0] scan_counter;
    
    // Barycentric calculation for corner/pixel checking
    logic bary_ready, bary_valid, bary_done, bary_read_done;
    logic [31:0] bary_pts2_input, bary_p_input, bary_result;
    logic [1:0] bary_input_counter, bary_output_counter;
    logic [2:0] corner_check_counter;
    logic [31:0] pixel_bary_coords[3];
    
    // Barycentric calculator instance
    barycentric corner_bary_calc (
        .clk(clk),
        .rst_n(rst_n),
        .ready(bary_ready),
        .data_valid(bary_valid),
        .calc_done(bary_done),
        .read_done(bary_read_done),
        .pts2(bary_pts2_input),
        .P(bary_p_input),
        .bary(bary_result)
    );
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (data_valid) next_state = CHECK_TILE_CORNERS;
            end
            CHECK_TILE_CORNERS: begin
                if (corner_check_counter == 4) begin
                    if (tile_small || (corners_inside == 4'b0000))
                        next_state = SCAN_PIXELS_IF_NEEDED;
                    else
                        next_state = COUNT_VALID_PIXELS;  // All corners inside
                end
            end
            SCAN_PIXELS_IF_NEEDED: begin
                if (scan_counter >= tile_width * tile_height)
                    next_state = COUNT_VALID_PIXELS;
            end
            COUNT_VALID_PIXELS: begin
                next_state = OUTPUT_RESULTS;
            end
            OUTPUT_RESULTS: begin
                next_state = WAIT_READ;
            end
            WAIT_READ: begin
                if (read_done) next_state = IDLE;
            end
        endcase
    end
    
    // Store input data and calculate tile corners
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tri_pts <= '{default: '0};
            tile_corners <= '{default: '0};
            tile_small <= 0;
        end else if (current_state == IDLE && data_valid) begin
            tri_pts <= triangle_pts;
            tile_small <= (tile_width < 4 || tile_height < 4);
            
            // Calculate 4 corners of the tile
            tile_corners[0][0] <= tile_x;           // Top-left
            tile_corners[0][1] <= tile_y;
            tile_corners[1][0] <= tile_x + tile_width - 1;  // Top-right
            tile_corners[1][1] <= tile_y;
            tile_corners[2][0] <= tile_x;           // Bottom-left
            tile_corners[2][1] <= tile_y + tile_height - 1;
            tile_corners[3][0] <= tile_x + tile_width - 1;  // Bottom-right
            tile_corners[3][1] <= tile_y + tile_height - 1;
        end
    end
    
    // Check which corners are inside the triangle
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            corners_inside <= 4'b0000;
            corner_check_counter <= 0;
            bary_valid <= 0;
            bary_read_done <= 0;
            bary_input_counter <= 0;
            bary_output_counter <= 0;
        end else if (current_state == CHECK_TILE_CORNERS) begin
            if (corner_check_counter < 4) begin
                // Send triangle points and current corner to barycentric calculator
                if (bary_ready && !bary_valid) begin
                    bary_valid <= 1;
                    bary_input_counter <= 0;
                end else if (bary_valid && bary_input_counter < 8) begin
                    // Send triangle points (6 values) + corner point (2 values)
                    case (bary_input_counter)
                        0: bary_pts2_input <= tri_pts[0][0];
                        1: bary_pts2_input <= tri_pts[0][1];
                        2: bary_pts2_input <= tri_pts[1][0];
                        3: bary_pts2_input <= tri_pts[1][1];
                        4: bary_pts2_input <= tri_pts[2][0];
                        5: bary_pts2_input <= tri_pts[2][1];
                        6: bary_p_input <= tile_corners[corner_check_counter][0];
                        7: bary_p_input <= tile_corners[corner_check_counter][1];
                    endcase
                    bary_input_counter <= bary_input_counter + 1;
                    
                    if (bary_input_counter == 7) begin
                        bary_valid <= 0;
                    end
                end else if (bary_done && bary_output_counter < 3) begin
                    // Read barycentric coordinates
                    pixel_bary_coords[bary_output_counter] <= bary_result;
                    bary_output_counter <= bary_output_counter + 1;
                    
                    if (bary_output_counter == 2) begin
                        // Check if all coordinates are >= 0 (inside triangle)
                        if (pixel_bary_coords[0] >= 32'h0 && 
                            pixel_bary_coords[1] >= 32'h0 && 
                            bary_result >= 32'h0) begin
                            corners_inside[corner_check_counter] <= 1;
                        end
                        
                        bary_read_done <= 1;
                        bary_output_counter <= 0;
                        corner_check_counter <= corner_check_counter + 1;
                    end
                end else if (bary_read_done) begin
                    bary_read_done <= 0;
                end
            end
        end else if (current_state == IDLE) begin
            corners_inside <= 4'b0000;
            corner_check_counter <= 0;
            bary_valid <= 0;
            bary_read_done <= 0;
            bary_input_counter <= 0;
            bary_output_counter <= 0;
        end
    end
    
    // Scan individual pixels if needed
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_x <= 0;
            scan_y <= 0;
            scan_counter <= 0;
            valid_pixels <= 0;
        end else if (current_state == SCAN_PIXELS_IF_NEEDED) begin
            if (scan_counter < tile_width * tile_height) begin
                // Calculate current pixel position
                scan_x <= tile_x + (scan_counter % tile_width);
                scan_y <= tile_y + (scan_counter / tile_width);
                
                // TODO: Check if pixel is inside triangle using barycentric
                // For now, simplified check
                scan_counter <= scan_counter + 1;
                
                // Store valid pixel coordinates
                if (scan_counter < 16) begin  // Max 16 pixels
                    pixels_x[valid_pixels] <= scan_x;
                    pixels_y[valid_pixels] <= scan_y;
                    valid_pixels <= valid_pixels + 1;
                end
            end
        end else if (current_state == IDLE) begin
            scan_x <= 0;
            scan_y <= 0;
            scan_counter <= 0;
            valid_pixels <= 0;
        end
    end
    
    // Count valid pixels and determine intersection
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            intersects <= 0;
            pixel_count <= 0;
        end else if (current_state == COUNT_VALID_PIXELS) begin
            if (corners_inside != 4'b0000 || valid_pixels > 0) begin
                intersects <= 1;
                if (corners_inside == 4'b1111) begin
                    // All corners inside - tile fully covered
                    pixel_count <= tile_width * tile_height;
                    // Fill all pixel positions for full tile
                    for (int i = 0; i < 16; i++) begin
                        if (i < tile_width * tile_height) begin
                            pixels_x[i] <= tile_x + (i % tile_width);
                            pixels_y[i] <= tile_y + (i / tile_width);
                        end
                    end
                end else begin
                    // Partial coverage - use scanned pixels
                    pixel_count <= valid_pixels;
                end
            end else begin
                intersects <= 0;
                pixel_count <= 0;
            end
        end else if (current_state == IDLE) begin
            intersects <= 0;
            pixel_count <= 0;
        end
    end
    
    assign ready = (current_state == IDLE);
    assign calc_done = (current_state == OUTPUT_RESULTS);

endmodule
