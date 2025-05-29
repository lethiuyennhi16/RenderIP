module RASTERIZER (
    input logic clk,
    input logic rst_n,
    
    // Interface với VERTEX_PROCESSOR 
    input logic vertex_output_valid,
    input logic [31:0] clip_vert[3][4],    // gl_Position từ vertex shader
    input logic [31:0] view_vert[3][3],    // gl_Position_view 
    input logic [31:0] varying_uv[3][2],   // texture coordinates
    input logic [31:0] varying_nrm[3][3],  // transformed normals
    input logic face_valid,                // sau face culling
    output logic vertex_ready,
    
    // Interface với CONTROL_MATRIX (viewport matrix)
    output logic matrix_request,
    output logic [2:0] matrix_opcode, 
    input logic [31:0] matrix_data,
    input logic [6:0] matrix_target_core_id,
    input logic matrix_valid,
    output logic matrix_read_done,
    
    // Interface với ARBITER_TEXTURE (đọc z-buffer)
    output logic texture_req,
    output logic [31:0] texture_addr,
    output logic [6:0] texture_core_id,
    input logic texture_valid,
    input logic [31:0] texture_data,
    output logic texture_read_done,
    
    // Interface với ARBITER_WRITE (ghi z-buffer & fragment)
    output logic write_req,
    output logic [31:0] write_addr,
    output logic [31:0] write_data,
    output logic [6:0] write_core_id,
    input logic write_valid,
    input logic write_done,
    
    // Interface với CONTROL (địa chỉ base)
    input logic [31:0] addr_z_buffer,
    input logic [31:0] addr_framebuffer, 
    
    // Interface với 4 FRAGMENT_PROCESSOR (4 tile processors song song)
    output logic [3:0] fragment_valid,
    output logic [3:0][31:0] fragment_screen_x,
    output logic [3:0][31:0] fragment_screen_y,
    output logic [3:0][31:0] fragment_bc_screen[3],    // barycentric screen coords
    output logic [3:0][31:0] fragment_bc_clip[3],      // barycentric clip coords  
    output logic [3:0][31:0] fragment_frag_depth,      // interpolated depth
    output logic [3:0][31:0] fragment_current_z,       // current z-buffer value
    output logic [3:0][31:0] fragment_varying_uv[2],   // interpolated UV
    output logic [3:0][31:0] fragment_varying_nrm[3],  // interpolated normal
    input logic [3:0] fragment_ready,
    input logic [3:0] fragment_done,
    
    // Control interface
    input logic [6:0] core_id,             // ID của core này (0-86)
    input logic [31:0] width_framebuffer,
    input logic [31:0] height_framebuffer,
    
    // Debug interface
    output logic raster_busy,
    output logic [31:0] debug_triangle_count
);

    // Internal state machine
    typedef enum logic [4:0] {
        IDLE,
        LOAD_VIEWPORT_MATRIX,
        TRANSFORM_TO_SCREEN,
        CALCULATE_BOUNDING_BOX,
        TILE_ITERATION,
        PIXEL_PROCESSING,
        WAIT_FRAGMENTS,
        TRIANGLE_DONE
    } raster_state_t;
    
    raster_state_t current_state, next_state;
    
    // Internal registers
    logic [31:0] viewport_matrix[4][4];    // Viewport transformation matrix
    logic [31:0] screen_pts[3][4];         // Transformed screen coordinates
    logic [31:0] screen_pts2[3][2];        // 2D screen coordinates (pts2)
    logic [31:0] bounding_box[4];          // [min_x, max_x, min_y, max_y]
    
    // Tile iteration control
    logic [31:0] current_tile_x, current_tile_y;
    logic [31:0] tiles_per_row, tiles_per_col;
    logic [31:0] tile_counter;
    logic [31:0] total_tiles;
    
    // Triangle data storage
    logic [31:0] stored_clip_vert[3][4];
    logic [31:0] stored_view_vert[3][3];
    logic [31:0] stored_varying_uv[3][2];
    logic [31:0] stored_varying_nrm[3][3];
    
    // Counters
    logic [4:0] matrix_load_counter;
    logic [31:0] triangle_counter;
    
    // Sub-modules
    logic coord_transform_ready, coord_transform_valid, coord_transform_done, coord_transform_read_done;
    logic bbox_calc_ready, bbox_calc_valid, bbox_calc_done, bbox_calc_read_done;  
    logic tile_check_ready, tile_check_valid, tile_check_done, tile_check_read_done;
    logic bary_calc_ready, bary_calc_valid, bary_calc_done, bary_calc_read_done;
    
    // Tile checker outputs
    logic tile_intersects;
    logic [31:0] tile_pixel_count;
    logic [31:0] tile_pixels_x[16], tile_pixels_y[16];  // Max 16 pixels per tile (4x4)
    
    // Barycentric calculator arrays
    logic [31:0] bary_pts2_input, bary_p_input, bary_output;
    logic bary_input_counter;
    logic [1:0] bary_output_counter;
    logic [31:0] pixel_barycentric[4][3];  // For 4 pixels in parallel
    
    // Pixel processing control
    logic [3:0] pixel_processing_active;
    logic [31:0] pixels_in_current_batch;
    logic [31:0] current_pixel_index;
    
    // Coordinate transformer instance
    coordinate_transformer coord_transformer (
        .clk(clk),
        .rst_n(rst_n),
        .ready(coord_transform_ready),
        .data_valid(coord_transform_valid),
        .calc_done(coord_transform_done),
        .read_done(coord_transform_read_done),
        .clip_coords_in(stored_clip_vert),
        .viewport_matrix(viewport_matrix),
        .screen_coords_out(screen_pts),
        .screen_2d_out(screen_pts2)
    );
    
    // Bounding box calculator instance  
    bounding_box_calc bbox_calculator (
        .clk(clk),
        .rst_n(rst_n),
        .ready(bbox_calc_ready),
        .data_valid(bbox_calc_valid),
        .calc_done(bbox_calc_done),
        .read_done(bbox_calc_read_done),
        .screen_pts(screen_pts2),
        .width(width_framebuffer),
        .height(height_framebuffer),
        .bbox_out(bounding_box)
    );
    
    // Tile intersection checker instance
    tile_checker tile_intersection (
        .clk(clk),
        .rst_n(rst_n),
        .ready(tile_check_ready),
        .data_valid(tile_check_valid),
        .calc_done(tile_check_done),
        .read_done(tile_check_read_done),
        .triangle_pts(screen_pts2),
        .tile_x(current_tile_x),
        .tile_y(current_tile_y),
        .tile_width(32'd4),    // 4x4 tiles
        .tile_height(32'd4),
        .intersects(tile_intersects),
        .pixel_count(tile_pixel_count),
        .pixels_x(tile_pixels_x),
        .pixels_y(tile_pixels_y)
    );
    
    // Barycentric calculator instance
    barycentric bary_calculator (
        .clk(clk),
        .rst_n(rst_n),
        .ready(bary_calc_ready),
        .data_valid(bary_calc_valid),
        .calc_done(bary_calc_done),
        .read_done(bary_calc_read_done),
        .pts2(bary_pts2_input),
        .P(bary_p_input),
        .bary(bary_output)
    );
    
    // State machine
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
                if (vertex_output_valid && face_valid) 
                    next_state = LOAD_VIEWPORT_MATRIX;
            end
            LOAD_VIEWPORT_MATRIX: begin
                if (matrix_load_counter == 16) 
                    next_state = TRANSFORM_TO_SCREEN;
            end
            TRANSFORM_TO_SCREEN: begin  
                if (coord_transform_done)
                    next_state = CALCULATE_BOUNDING_BOX;
            end
            CALCULATE_BOUNDING_BOX: begin
                if (bbox_calc_done)
                    next_state = TILE_ITERATION;
            end
            TILE_ITERATION: begin
                if (tile_check_done) begin
                    if (tile_intersects && tile_pixel_count > 0)
                        next_state = PIXEL_PROCESSING;
                    else if (tile_counter < total_tiles - 1)
                        next_state = TILE_ITERATION;  // Next tile
                    else
                        next_state = TRIANGLE_DONE;
                end
            end
            PIXEL_PROCESSING: begin
                if (pixels_in_current_batch == 0) begin
                    if (tile_counter < total_tiles - 1)
                        next_state = TILE_ITERATION;
                    else
                        next_state = TRIANGLE_DONE;
                end else if (current_pixel_index >= pixels_in_current_batch)
                    next_state = WAIT_FRAGMENTS;
            end
            WAIT_FRAGMENTS: begin
                if (&fragment_done[3:0]) begin  // All 4 fragment processors done
                    if (!bbox_processing_done)
                        next_state = PIXEL_PROCESSING;  // Process next batch
                    else
                        next_state = TRIANGLE_DONE;
                end
            end
            TRIANGLE_DONE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Store triangle data when received -- checked
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 3; i++) begin
                for (int j = 0; j < 4; j++) begin
                    stored_clip_vert[i][j] <= 32'h0;
                end
                for (int j = 0; j < 3; j++) begin
                    stored_view_vert[i][j] <= 32'h0;
                    stored_varying_nrm[i][j] <= 32'h0;
                end
                for (int j = 0; j < 2; j++) begin
                    stored_varying_uv[i][j] <= 32'h0;
                end
            end
        end else if (current_state == IDLE && vertex_output_valid && face_valid) begin
            stored_clip_vert <= clip_vert;
            stored_view_vert <= view_vert;
            stored_varying_uv <= varying_uv;
            stored_varying_nrm <= varying_nrm;
        end
    end
    
    // Load viewport matrix from CONTROL_MATRIX -- checked
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            matrix_load_counter <= 0;
            matrix_request <= 0;
            matrix_opcode <= 3'b010;  // Viewport matrix code
            matrix_read_done <= 0;
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    viewport_matrix[i][j] <= 32'h0;
                end
            end
        end else if (current_state == LOAD_VIEWPORT_MATRIX) begin
            if (matrix_load_counter < 16) begin
                if (!matrix_request) begin
                    matrix_request <= 1;
                end else if (matrix_valid && matrix_target_core_id == core_id) begin
                    viewport_matrix[matrix_load_counter >> 2][matrix_load_counter & 2'b11] <= matrix_data;
                    matrix_load_counter <= matrix_load_counter + 1;
                    matrix_request <= 0;
                    matrix_read_done <= 1;
                end
            end else if (matrix_read_done) begin
                matrix_read_done <= 0;
            end
        end else if (current_state == IDLE) begin
            matrix_load_counter <= 0;
            matrix_request <= 0;
            matrix_read_done <= 0;
        end
    end
    
    // Coordinate transformation control -- module coordinate transformer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            coord_transform_valid <= 0;
            coord_transform_read_done <= 0;
        end else if (current_state == TRANSFORM_TO_SCREEN) begin
            if (coord_transform_ready && !coord_transform_valid) begin
                coord_transform_valid <= 1;
            end else if (coord_transform_done) begin
                coord_transform_read_done <= 1;
                coord_transform_valid <= 0;
            end else if (coord_transform_read_done) begin
                coord_transform_read_done <= 0;
            end
        end else begin
            coord_transform_valid <= 0;
            coord_transform_read_done <= 0;
        end
    end
    
    // Bounding box calculation control
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bbox_calc_valid <= 0;
            bbox_calc_read_done <= 0;
        end else if (current_state == CALCULATE_BOUNDING_BOX) begin
            if (bbox_calc_ready && !bbox_calc_valid) begin
                bbox_calc_valid <= 1;
            end else if (bbox_calc_done) begin
                bbox_calc_read_done <= 1;
                bbox_calc_valid <= 0;
            end else if (bbox_calc_read_done) begin
                bbox_calc_read_done <= 0;
            end
        end else begin
            bbox_calc_valid <= 0;
            bbox_calc_read_done <= 0;
        end
    end
    
    // Tile iteration and checking control
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_tile_x <= 0;
            current_tile_y <= 0;
            tile_counter <= 0;
            total_tiles <= 0;
            tiles_per_row <= 0;
            tiles_per_col <= 0;
            tile_check_valid <= 0;
            tile_check_read_done <= 0;
        end else if (current_state == CALCULATE_BOUNDING_BOX && bbox_calc_done) begin
            // Calculate tile grid dimensions
            tiles_per_row <= ((bounding_box[1] - bounding_box[0] + 3) >> 2);  // Ceiling division by 4
            tiles_per_col <= ((bounding_box[3] - bounding_box[2] + 3) >> 2);
            total_tiles <= ((bounding_box[1] - bounding_box[0] + 3) >> 2) * 
                          ((bounding_box[3] - bounding_box[2] + 3) >> 2);
            current_tile_x <= bounding_box[0] & ~32'h3;  // Align to 4-pixel boundary
            current_tile_y <= bounding_box[2] & ~32'h3;
            tile_counter <= 0;
        end else if (current_state == TILE_ITERATION) begin
            if (tile_check_ready && !tile_check_valid) begin
                tile_check_valid <= 1;
            end else if (tile_check_done) begin
                tile_check_read_done <= 1;
                tile_check_valid <= 0;
                
                // Move to next tile
                if (tile_counter < total_tiles - 1) begin
                    tile_counter <= tile_counter + 1;
                    if (current_tile_x + 4 <= bounding_box[1]) begin
                        current_tile_x <= current_tile_x + 4;
                    end else begin
                        current_tile_x <= bounding_box[0] & ~32'h3;
                        current_tile_y <= current_tile_y + 4;
                    end
                end
            end else if (tile_check_read_done) begin
                tile_check_read_done <= 0;
            end
        end else if (current_state == WAIT_FRAGMENTS && &fragment_done[3:0]) begin
            // Move to next tile after fragments are done
            if (tile_counter < total_tiles - 1) begin
                tile_counter <= tile_counter + 1;
                if (current_tile_x + 4 <= bounding_box[1]) begin
                    current_tile_x <= current_tile_x + 4;
                end else begin
                    current_tile_x <= bounding_box[0] & ~32'h3;
                    current_tile_y <= current_tile_y + 4;
                end
            end
        end else if (current_state == IDLE) begin
            current_tile_x <= 0;
            current_tile_y <= 0;
            tile_counter <= 0;
            total_tiles <= 0;
            tile_check_valid <= 0;
            tile_check_read_done <= 0;
        end
    end
    
    // 4 Pixel Processors song song - mỗi processor xử lý 1 khối liên tục 4x4 pixels
    logic [3:0] pixel_proc_ready, pixel_proc_valid, pixel_proc_done, pixel_proc_read_done;
    
    // Chia tile 4x4 thành 4 sub-blocks 2x2 cho 4 processors
    logic [31:0] sub_block_start_x[4], sub_block_start_y[4];
    logic [31:0] sub_block_width[4], sub_block_height[4];
    
    genvar proc_id;
    generate
        for (proc_id = 0; proc_id < 4; proc_id++) begin : gen_pixel_processors
            pixel_processor_block pixel_proc_inst (
                .clk(clk),
                .rst_n(rst_n),
                .ready(pixel_proc_ready[proc_id]),
                .data_valid(pixel_proc_valid[proc_id]),
                .calc_done(pixel_proc_done[proc_id]),
                .read_done(pixel_proc_read_done[proc_id]),
                
                // Input triangle data
                .triangle_pts(screen_pts2),
                .clip_vertices(stored_clip_vert),
                
                // Sub-block coordinates (2x2 block within 4x4 tile)
                .block_start_x(sub_block_start_x[proc_id]),
                .block_start_y(sub_block_start_y[proc_id]),
                .block_width(sub_block_width[proc_id]),
                .block_height(sub_block_height[proc_id]),
                
                // Output to fragment processor
                .fragment_ready(fragment_ready[proc_id]),
                .fragment_valid(fragment_valid[proc_id]),
                .fragment_screen_x(fragment_screen_x[proc_id]),
                .fragment_screen_y(fragment_screen_y[proc_id]),
                .fragment_bc_screen(fragment_bc_screen[proc_id]),
                .fragment_bc_clip(fragment_bc_clip[proc_id]),
                .fragment_frag_depth(fragment_frag_depth[proc_id]),
                .fragment_varying_uv(fragment_varying_uv[proc_id]),
                .fragment_varying_nrm(fragment_varying_nrm[proc_id]),
                
                // Z-buffer interface (shared bus)
                .zbuffer_addr_out(/* connect to arbiter */),
                .zbuffer_req_out(/* connect to arbiter */),
                .zbuffer_data_in(texture_data),
                .zbuffer_valid_in(texture_valid),
                .zbuffer_read_done_out(/* connect to arbiter */),
                
                // Vertex data for interpolation
                .vertex_uv(stored_varying_uv),
                .vertex_nrm(stored_varying_nrm)
            );
        end
    endgenerate
    
    // Tile processing control (4x4 tiles = 16 pixels each)
    logic [31:0] valid_tiles[4];           // 4 valid tiles for 4 processors
    logic [31:0] valid_tile_count;         // Number of valid tiles found
    logic [31:0] tiles_processed;          // Number of tiles processed so far
    logic [31:0] current_search_tile;      // Current tile being checked
    logic tile_search_done;                // Found 4 valid tiles or searched all
    
    // State machine update for tile-based processing
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (vertex_output_valid && face_valid) 
                    next_state = LOAD_VIEWPORT_MATRIX;
            end
            LOAD_VIEWPORT_MATRIX: begin
                if (matrix_load_counter == 16) 
                    next_state = TRANSFORM_TO_SCREEN;
            end
            TRANSFORM_TO_SCREEN: begin  
                if (coord_transform_done)
                    next_state = CALCULATE_BOUNDING_BOX;
            end
            CALCULATE_BOUNDING_BOX: begin
                if (bbox_calc_done)
                    next_state = TILE_ITERATION;
            end
            TILE_ITERATION: begin
                if (tile_check_done) begin
                    if (valid_tile_count == 4 || tile_search_done)
                        next_state = PIXEL_PROCESSING;
                    // Continue searching for more valid tiles if < 4 found
                end
            end
            PIXEL_PROCESSING: begin
                if (&pixel_proc_done[3:0])
                    next_state = WAIT_FRAGMENTS;
            end
            WAIT_FRAGMENTS: begin
                if (&fragment_done[3:0]) begin
                    if (tiles_processed < total_tiles)
                        next_state = TILE_ITERATION;  // Find next batch of valid tiles
                    else
                        next_state = TRIANGLE_DONE;
                end
            end
            TRIANGLE_DONE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Tile search and validation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_tile_count <= 0;
            current_search_tile <= 0;
            tile_search_done <= 0;
            tiles_processed <= 0;
            for (int i = 0; i < 4; i++) begin
                valid_tiles[i] <= 0;
            end
        end else if (current_state == CALCULATE_BOUNDING_BOX && bbox_calc_done) begin
            // Initialize tile search
            valid_tile_count <= 0;
            current_search_tile <= 0;
            tile_search_done <= 0;
            tiles_processed <= 0;
        end else if (current_state == TILE_ITERATION) begin
            if (tile_check_done) begin
                // Check if current tile is valid
                if (tile_intersects || current_tile_width < 4 || current_tile_height < 4) begin
                    // Valid tile (intersects or small tile)
                    if (valid_tile_count < 4) begin
                        valid_tiles[valid_tile_count] <= current_search_tile;
                        valid_tile_count <= valid_tile_count + 1;
                    end
                end
                
                // Move to next tile
                if (current_search_tile < total_tiles - 1 && valid_tile_count < 4) begin
                    current_search_tile <= current_search_tile + 1;
                    // Update tile coordinates for next search
                    if (current_tile_x + 4 <= bounding_box[1]) begin
                        current_tile_x <= current_tile_x + 4;
                    end else begin
                        current_tile_x <= bounding_box[0] & ~32'h3;
                        current_tile_y <= current_tile_y + 4;
                    end
                end else begin
                    tile_search_done <= 1;  // Found 4 tiles or searched all
                end
            end
        end else if (current_state == WAIT_FRAGMENTS && &fragment_done[3:0]) begin
            // Mark processed tiles and reset for next search
            tiles_processed <= tiles_processed + valid_tile_count;
            valid_tile_count <= 0;
            tile_search_done <= 0;
        end else if (current_state == IDLE) begin
            valid_tile_count <= 0;
            current_search_tile <= 0;
            tile_search_done <= 0;
            tiles_processed <= 0;
        end
    end
    
    // Assign valid tiles to 4 processors
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) begin
                sub_block_start_x[i] <= 0;
                sub_block_start_y[i] <= 0;
                sub_block_width[i] <= 4;
                sub_block_height[i] <= 4;
                pixel_proc_valid[i] <= 0;
                pixel_proc_read_done[i] <= 0;
            end
        end else if (current_state == PIXEL_PROCESSING) begin
            if (current_pixel_index == 0) begin
                // Assign valid tiles to processors
                for (int proc = 0; proc < 4; proc++) begin
                    if (proc < valid_tile_count) begin
                        // Calculate tile coordinates from tile index
                        logic [31:0] tile_idx = valid_tiles[proc];
                        logic [31:0] tiles_per_row = ((bounding_box[1] - bounding_box[0] + 3) >> 2);
                        logic [31:0] tile_x_idx = tile_idx % tiles_per_row;
                        logic [31:0] tile_y_idx = tile_idx / tiles_per_row;
                        
                        sub_block_start_x[proc] <= (bounding_box[0] & ~32'h3) + tile_x_idx * 4;
                        sub_block_start_y[proc] <= (bounding_box[2] & ~32'h3) + tile_y_idx * 4;
                        sub_block_width[proc] <= 4;
                        sub_block_height[proc] <= 4;
                        
                        if (pixel_proc_ready[proc]) begin
                            pixel_proc_valid[proc] <= 1;
                        end
                    end else begin
                        // No tile for this processor
                        pixel_proc_valid[proc] <= 0;
                    end
                end
                current_pixel_index <= 1;
                
                // Start all 4 processors simultaneously
                for (int proc = 0; proc < 4; proc++) begin
                    if (pixel_proc_ready[proc]) begin
                        pixel_proc_valid[proc] <= 1;
                    end
                end
                current_pixel_index <= 1;
                
            end else if (current_pixel_index == 1) begin
                // Wait for all processors to finish their sub-blocks
                if (&pixel_proc_done[3:0]) begin
                    for (int proc = 0; proc < 4; proc++) begin
                        pixel_proc_read_done[proc] <= 1;
                    end
                    current_pixel_index <= 2;
                end
            end else if (current_pixel_index == 2) begin
                // Clear read_done signals
                for (int proc = 0; proc < 4; proc++) begin
                    pixel_proc_read_done[proc] <= 0;
                    pixel_proc_valid[proc] <= 0;
                end
                current_pixel_index <= 3;  // Signal completion
            end
        end else if (current_state == IDLE) begin
            current_pixel_index <= 0;
            for (int i = 0; i < 4; i++) begin
                pixel_proc_valid[i] <= 0;
                pixel_proc_read_done[i] <= 0;
            end
        end
    end
    
    // Output assignments
    assign vertex_ready = (current_state == IDLE);
    assign raster_busy = (current_state != IDLE);
    
    // Triangle counter for debug
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            triangle_counter <= 0;
        end else if (current_state == TRIANGLE_DONE) begin
            triangle_counter <= triangle_counter + 1;
        end
    end
    
    assign debug_triangle_count = triangle_counter;

endmodule

// ===========================
// Module pixel_processor - Xử lý 1 nhóm pixel song song
// ===========================
module pixel_processor (
    input logic clk,
    input logic rst_n,
    
    // Handshake protocol
    output logic ready,
    input logic data_valid,
    output logic calc_done,
    input logic read_done,
    
    // Input triangle data
    input logic [31:0] triangle_pts[3][2],      // Triangle screen coordinates
    input logic [31:0] clip_vertices[3][4],     // Clip space vertices for depth
    input logic [31:0] pixel_coords[4][2],      // Up to 4 pixels to process (x,y)
    input logic [31:0] pixel_count,             // Number of valid pixels
    
    // Vertex data for interpolation
    input logic [31:0] vertex_uv[3][2],         // UV coordinates
    input logic [31:0] vertex_nrm[3][3],        // Normal vectors
    
    // Fragment processor interface
    input logic fragment_ready,
    output logic fragment_valid,
    output logic [31:0] fragment_screen_x,
    output logic [31:0] fragment_screen_y,
    output logic [31:0] fragment_bc_screen[3],
    output logic [31:0] fragment_bc_clip[3],
    output logic [31:0] fragment_frag_depth,
    output logic [31:0] fragment_varying_uv[2],
    output logic [31:0] fragment_varying_nrm[3],
    
    // Z-buffer access
    output logic [31:0] zbuffer_addr,
    output logic zbuffer_req,
    input logic [31:0] zbuffer_data,
    input logic zbuffer_valid,
    output logic zbuffer_read_done
);

    typedef enum logic [3:0] {
        IDLE,
        CALCULATE_BARYCENTRIC,
        CHECK_DEPTH_TEST,
        INTERPOLATE_ATTRIBUTES,
        SEND_TO_FRAGMENT,
        NEXT_PIXEL,
        PROCESSING_DONE
    } pixel_state_t;
    
    pixel_state_t current_state, next_state;
    
    // Internal storage
    logic [31:0] tri_pts[3][2];
    logic [31:0] clip_verts[3][4];
    logic [31:0] pixels[4][2];
    logic [31:0] num_pixels;
    logic [31:0] current_pixel_idx;
    
    // Current pixel being processed
    logic [31:0] current_x, current_y;
    logic [31:0] current_barycentric[3];
    logic [31:0] current_depth;
    logic [31:0] current_z_buffer;
    logic depth_test_pass;
    
    // Interpolated attributes for current pixel
    logic [31:0] interp_uv[2];
    logic [31:0] interp_normal[3];
    logic [31:0] interp_bc_clip[3];
    
    // Sub-modules
    logic bary_ready, bary_valid, bary_done, bary_read_done;
    logic [31:0] bary_pts2_input, bary_p_input, bary_output;
    logic [1:0] bary_input_counter, bary_output_counter;
    
    logic interp_ready, interp_valid, interp_done, interp_read_done;
    logic [31:0] interp_vertex_data[3][8];
    logic [31:0] interp_result[8];
    
    // Barycentric calculator
    barycentric bary_calc (
        .clk(clk),
        .rst_n(rst_n),
        .ready(bary_ready),
        .data_valid(bary_valid),
        .calc_done(bary_done),
        .read_done(bary_read_done),
        .pts2(bary_pts2_input),
        .P(bary_p_input),
        .bary(bary_output)
    );
    
    // Attribute interpolator
    pixel_interpolator attr_interp (
        .clk(clk),
        .rst_n(rst_n),
        .ready(interp_ready),
        .data_valid(interp_valid),
        .calc_done(interp_done),
        .read_done(interp_read_done),
        .barycentric_coords(current_barycentric),
        .vertex_data(interp_vertex_data),
        .attribute_count(3'd5),  // UV(2) + Normal(3) = 5 attributes
        .interpolated_data(interp_result)
    );
    
    // State machine
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
                if (data_valid && pixel_count > 0) 
                    next_state = CALCULATE_BARYCENTRIC;
            end
            CALCULATE_BARYCENTRIC: begin
                if (bary_done) 
                    next_state = CHECK_DEPTH_TEST;
            end
            CHECK_DEPTH_TEST: begin
                if (zbuffer_valid) begin
                    if (depth_test_pass)
                        next_state = INTERPOLATE_ATTRIBUTES;
                    else
                        next_state = NEXT_PIXEL;
                end
            end
            INTERPOLATE_ATTRIBUTES: begin
                if (interp_done)
                    next_state = SEND_TO_FRAGMENT;
            end
            SEND_TO_FRAGMENT: begin
                if (fragment_ready)
                    next_state = NEXT_PIXEL;
            end
            NEXT_PIXEL: begin
                if (current_pixel_idx >= num_pixels - 1)
                    next_state = PROCESSING_DONE;
                else
                    next_state = CALCULATE_BARYCENTRIC;
            end
            PROCESSING_DONE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Store input data
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tri_pts <= '{default: '0};
            clip_verts <= '{default: '0};
            pixels <= '{default: '0};
            num_pixels <= 0;
            current_pixel_idx <= 0;
        end else if (current_state == IDLE && data_valid) begin
            tri_pts <= triangle_pts;
            clip_verts <= clip_vertices;
            pixels <= pixel_coords;
            num_pixels <= pixel_count;
            current_pixel_idx <= 0;
        end else if (current_state == NEXT_PIXEL) begin
            if (current_pixel_idx < num_pixels - 1) begin
                current_pixel_idx <= current_pixel_idx + 1;
            end
        end
    end
    
    // Set current pixel coordinates
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_x <= 0;
            current_y <= 0;
        end else if (current_state == CALCULATE_BARYCENTRIC || current_state == NEXT_PIXEL) begin
            current_x <= pixels[current_pixel_idx][0];
            current_y <= pixels[current_pixel_idx][1];
        end
    end
    
    // Calculate barycentric coordinates
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bary_valid <= 0;
            bary_read_done <= 0;
            bary_input_counter <= 0;
            bary_output_counter <= 0;
            current_barycentric <= '{default: '0};
        end else if (current_state == CALCULATE_BARYCENTRIC) begin
            if (bary_ready && !bary_valid) begin
                bary_valid <= 1;
                bary_input_counter <= 0;
            end else if (bary_valid && bary_input_counter < 8) begin
                // Send triangle points (6 values) + current pixel (2 values)
                case (bary_input_counter)
                    0: bary_pts2_input <= tri_pts[0][0];
                    1: bary_pts2_input <= tri_pts[0][1];
                    2: bary_pts2_input <= tri_pts[1][0];
                    3: bary_pts2_input <= tri_pts[1][1];
                    4: bary_pts2_input <= tri_pts[2][0];
                    5: bary_pts2_input <= tri_pts[2][1];
                    6: bary_p_input <= current_x;
                    7: bary_p_input <= current_y;
                endcase
                bary_input_counter <= bary_input_counter + 1;
                
                if (bary_input_counter == 7) begin
                    bary_valid <= 0;
                end
            end else if (bary_done && bary_output_counter < 3) begin
                // Read barycentric coordinates u, v, w
                current_barycentric[bary_output_counter] <= bary_output;
                bary_output_counter <= bary_output_counter + 1;
                
                if (bary_output_counter == 2) begin
                    bary_read_done <= 1;
                    bary_output_counter <= 0;
                end
            end else if (bary_read_done) begin
                bary_read_done <= 0;
            end
        end else if (current_state == IDLE) begin
            bary_valid <= 0;
            bary_read_done <= 0;
            bary_input_counter <= 0;
            bary_output_counter <= 0;
        end
    end
    
    // Depth test
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zbuffer_req <= 0;
            zbuffer_addr <= 0;
            zbuffer_read_done <= 0;
            current_depth <= 0;
            current_z_buffer <= 0;
            depth_test_pass <= 0;
        end else if (current_state == CHECK_DEPTH_TEST) begin
            if (!zbuffer_req) begin
                // Request z-buffer value at current pixel
                zbuffer_addr <= current_y * 32'd800 + current_x;  // Assuming 800 width
                zbuffer_req <= 1;
                
                // Calculate interpolated depth using barycentric coordinates
                // depth = bc.x * clip_verts[0][2] + bc.y * clip_verts[1][2] + bc.z * clip_verts[2][2]
                // Simplified calculation (should use proper multiplier/adder)
                current_depth <= current_barycentric[0] + current_barycentric[1] + current_barycentric[2]; // Placeholder
                
            end else if (zbuffer_valid) begin
                current_z_buffer <= zbuffer_data;
                zbuffer_req <= 0;
                zbuffer_read_done <= 1;
                
                // Depth test: pass if current_depth < z_buffer_value
                depth_test_pass <= (current_depth < zbuffer_data);
                
            end else if (zbuffer_read_done) begin
                zbuffer_read_done <= 0;
            end
        end else if (current_state == IDLE) begin
            zbuffer_req <= 0;
            zbuffer_read_done <= 0;
            depth_test_pass <= 0;
        end
    end
    
    // Prepare vertex data for interpolation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interp_vertex_data <= '{default: '0};
        end else if (current_state == INTERPOLATE_ATTRIBUTES) begin
            // Pack vertex attributes: UV(2) + Normal(3) = 5 attributes per vertex
            for (int v = 0; v < 3; v++) begin
                interp_vertex_data[v][0] <= vertex_uv[v][0];    // U coordinate
                interp_vertex_data[v][1] <= vertex_uv[v][1];    // V coordinate  
                interp_vertex_data[v][2] <= vertex_nrm[v][0];   // Normal X
                interp_vertex_data[v][3] <= vertex_nrm[v][1];   // Normal Y
                interp_vertex_data[v][4] <= vertex_nrm[v][2];   // Normal Z
            end
        end
    end
    
    // Attribute interpolation control
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interp_valid <= 0;
            interp_read_done <= 0;
            interp_uv <= '{default: '0};
            interp_normal <= '{default: '0};
        end else if (current_state == INTERPOLATE_ATTRIBUTES) begin
            if (interp_ready && !interp_valid) begin
                interp_valid <= 1;
            end else if (interp_done) begin
                // Extract interpolated results
                interp_uv[0] <= interp_result[0];     // U
                interp_uv[1] <= interp_result[1];     // V
                interp_normal[0] <= interp_result[2]; // Normal X
                interp_normal[1] <= interp_result[3]; // Normal Y
                interp_normal[2] <= interp_result[4]; // Normal Z
                
                interp_read_done <= 1;
                interp_valid <= 0;
            end else if (interp_read_done) begin
                interp_read_done <= 0;
            end
        end else if (current_state == IDLE) begin
            interp_valid <= 0;
            interp_read_done <= 0;
        end
    end
    
    // Calculate clip space barycentric coordinates
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interp_bc_clip <= '{default: '0};
        end else if (current_state == INTERPOLATE_ATTRIBUTES) begin
            // Convert screen barycentric to clip barycentric
            // bc_clip = {bc_screen.x/pts[0][3], bc_screen.y/pts[1][3], bc_screen.z/pts[2][3]}
            // bc_clip = bc_clip / (bc_clip.x + bc_clip.y + bc_clip.z)
            // Simplified version (needs proper division)
            interp_bc_clip[0] <= current_barycentric[0];
            interp_bc_clip[1] <= current_barycentric[1];
            interp_bc_clip[2] <= current_barycentric[2];
        end
    end
    
    // Send to fragment processor
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fragment_valid <= 0;
            fragment_screen_x <= 0;
            fragment_screen_y <= 0;
            fragment_bc_screen <= '{default: '0};
            fragment_bc_clip <= '{default: '0};
            fragment_frag_depth <= 0;
            fragment_varying_uv <= '{default: '0};
            fragment_varying_nrm <= '{default: '0};
        end else if (current_state == SEND_TO_FRAGMENT) begin
            if (fragment_ready && !fragment_valid) begin
                fragment_valid <= 1;
                fragment_screen_x <= current_x;
                fragment_screen_y <= current_y;
                fragment_bc_screen <= current_barycentric;
                fragment_bc_clip <= interp_bc_clip;
                fragment_frag_depth <= current_depth;
                fragment_varying_uv <= interp_uv;
                fragment_varying_nrm <= interp_normal;
            end else if (fragment_valid) begin
                fragment_valid <= 0;  // Clear after one cycle
            end
        end else if (current_state == IDLE) begin
            fragment_valid <= 0;
        end
    end
    
    assign ready = (current_state == IDLE);
    assign calc_done = (current_state == PROCESSING_DONE);

endmodule
