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
    
    // Interface với ARBITER_TEXTURE (đọc z-buffer) - through internal arbiter
    output logic texture_req,
    output logic [31:0] texture_addr,
    output logic [6:0] texture_core_id,
    input logic texture_valid,
    input logic [31:0] texture_data,
    output logic texture_read_done,
    
    // Interface với ARBITER_WRITE (ghi z-buffer & fragment) - through internal arbiter
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
        CONVERT_TO_INTEGER,
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
    logic [31:0] screen_pts2[3][2];        // 2D screen coordinates (float)
    logic [31:0] screen_pts2_int[3][2];    // 2D screen coordinates (integer)
    logic [31:0] bounding_box[4];          // [min_x, max_x, min_y, max_y] - direct from module
    logic [31:0] stored_bounding_box[4];   // Stored bounding box results
    
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
    
    // Coordinate transformer signals và outputs
    logic coord_transform_ready, coord_transform_valid, coord_transform_done, coord_transform_read_done;
    logic [31:0] coord_screen_coords_out[3][4];
    logic [31:0] coord_screen_2d_out[3][2];
    
    // Float-to-int conversion signals
    logic [2:0][1:0] f2i_ready, f2i_valid, f2i_done;
    logic all_conversions_done;
    
    // Bounding box calculator signals
    logic bbox_calc_ready, bbox_calc_valid, bbox_calc_done, bbox_calc_read_done;
    
    // Tile checker signals và outputs
    logic tile_check_ready, tile_check_valid, tile_check_done, tile_check_read_done;
    logic tile_intersects;
    logic [31:0] tile_pixel_count;
    logic [31:0] tile_pixels_x[16], tile_pixels_y[16];  // Max 16 pixels per tile (4x4)
    
    // Pixel processing control
    logic [3:0] pixel_processing_active;
    logic [31:0] pixels_in_current_batch;
    logic [31:0] current_pixel_index;
    
    // Tile processing control (4x4 tiles = 16 pixels each)
    logic [31:0] valid_tiles[4];           // 4 valid tiles for 4 processors
    logic [31:0] valid_tile_count;         // Number of valid tiles found
    logic [31:0] tiles_processed;          // Number of tiles processed so far
    logic [31:0] current_search_tile;      // Current tile being checked
    logic tile_search_done;                // Found 4 valid tiles or searched all
    
    // 4 Pixel Processors song song
    logic [3:0] pixel_proc_ready, pixel_proc_valid, pixel_proc_done, pixel_proc_read_done;
    logic [31:0] sub_block_start_x[4], sub_block_start_y[4];
    logic [31:0] sub_block_width[4], sub_block_height[4];
    
    // Internal Z-buffer arbiter signals
    logic [3:0] proc_zbuffer_req;
    logic [3:0][31:0] proc_zbuffer_addr;
    logic [3:0][31:0] proc_zbuffer_write_data;
    logic [3:0] proc_zbuffer_write_enable;
    logic [3:0] proc_zbuffer_valid;
    logic [3:0][31:0] proc_zbuffer_data;
    logic [3:0] proc_zbuffer_read_done;
    
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
        .screen_coords_out(coord_screen_coords_out),
        .screen_2d_out(coord_screen_2d_out)
    );
    
    // Generate 6 float-to-int converters (3 vertices x 2 coordinates)
    genvar i, j;
    generate
        for (i = 0; i < 3; i++) begin : gen_vertices
            for (j = 0; j < 2; j++) begin : gen_coords
                float_to_int f2i_conv (
                    .clk(clk), 
                    .rst(~rst_n),
                    .input_a(screen_pts2[i][j]),
                    .input_a_stb(f2i_valid[i][j]),
                    .input_a_ack(f2i_ready[i][j]),
                    .output_z(screen_pts2_int[i][j]),
                    .output_z_stb(f2i_done[i][j]),
                    .output_z_ack(1'b1)
                );
            end
        end
    endgenerate
    
    // Bounding box calculator instance  
    bounding_box_calc bbox_calculator (
        .clk(clk),
        .rst_n(rst_n),
        .ready(bbox_calc_ready),
        .data_valid(bbox_calc_valid),
        .calc_done(bbox_calc_done),
        .read_done(bbox_calc_read_done),
        .screen_pts(screen_pts2_int),    // Integer coordinates
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
        .triangle_pts(screen_pts2_int),    // Integer coordinates
        .tile_x(current_tile_x),
        .tile_y(current_tile_y),
        .tile_width(32'd4),    // 4x4 tiles
        .tile_height(32'd4),
        .intersects(tile_intersects),
        .pixel_count(tile_pixel_count),
        .pixels_x(tile_pixels_x),
        .pixels_y(tile_pixels_y)
    );
    
    // Internal Z-buffer arbiter instance
    INTERNAL_ZBUFFER_ARBITER zbuffer_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        
        // Interface với 4 pixel processors
        .proc_zbuffer_req(proc_zbuffer_req),
        .proc_zbuffer_addr(proc_zbuffer_addr),
        .proc_zbuffer_write_data(proc_zbuffer_write_data),
        .proc_zbuffer_write_enable(proc_zbuffer_write_enable),
        .proc_zbuffer_valid(proc_zbuffer_valid),
        .proc_zbuffer_data(proc_zbuffer_data),
        .proc_zbuffer_read_done(proc_zbuffer_read_done),
        
        // Interface với external arbiters
        .ext_texture_req(texture_req),
        .ext_texture_addr(texture_addr),
        .ext_texture_core_id(texture_core_id),
        .ext_texture_valid(texture_valid),
        .ext_texture_data(texture_data),
        .ext_texture_read_done(texture_read_done),
        
        .ext_write_req(write_req),
        .ext_write_addr(write_addr),
        .ext_write_data(write_data),
        .ext_write_core_id(write_core_id),
        .ext_write_valid(write_valid),
        .ext_write_done(write_done),
        
        .core_id(core_id)
    );
    
    // Generate 4 pixel processor blocks
    generate
        for (genvar proc_id = 0; proc_id < 4; proc_id++) begin : gen_pixel_processors
            pixel_processor_block pixel_proc_inst (
                .clk(clk),
                .rst_n(rst_n),
                .ready(pixel_proc_ready[proc_id]),
                .data_valid(pixel_proc_valid[proc_id]),
                .calc_done(pixel_proc_done[proc_id]),
                .read_done(pixel_proc_read_done[proc_id]),
                
                // Input triangle data
                .triangle_pts(screen_pts2_int),    // Integer coordinates
                .clip_vertices(stored_clip_vert),
                
                // Sub-block coordinates (tile assignment)
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
                .fragment_current_z(fragment_current_z[proc_id]),     // ✅ FIXED: Added missing signal
                .fragment_varying_uv(fragment_varying_uv[proc_id]),
                .fragment_varying_nrm(fragment_varying_nrm[proc_id]),
                
                // Z-buffer interface - connect to internal arbiter
                .zbuffer_addr_out(proc_zbuffer_addr[proc_id]),
                .zbuffer_req_out(proc_zbuffer_req[proc_id]),
                .zbuffer_write_data_out(proc_zbuffer_write_data[proc_id]),
                .zbuffer_write_enable_out(proc_zbuffer_write_enable[proc_id]),
                .zbuffer_data_in(proc_zbuffer_data[proc_id]),
                .zbuffer_valid_in(proc_zbuffer_valid[proc_id]),
                .zbuffer_read_done_out(proc_zbuffer_read_done[proc_id]),
                
                // Vertex data for interpolation
                .vertex_uv(stored_varying_uv),
                .vertex_nrm(stored_varying_nrm)
            );
        end
    endgenerate
    
    // Check if all float-to-int conversions are done
    always_comb begin
        all_conversions_done = 1'b1;
        for (int v = 0; v < 3; v++) begin
            for (int c = 0; c < 2; c++) begin
                if (!f2i_done[v][c]) begin
                    all_conversions_done = 1'b0;
                end
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
    
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (vertex_output_valid && face_valid) 
                    next_state = LOAD_VIEWPORT_MATRIX;
            end
            LOAD_VIEWPORT_MATRIX: begin
                if (matrix_load_counter >= 16) 
                    next_state = TRANSFORM_TO_SCREEN;
            end
            TRANSFORM_TO_SCREEN: begin  
                if (coord_transform_done)
                    next_state = CONVERT_TO_INTEGER;
            end
            CONVERT_TO_INTEGER: begin
                if (all_conversions_done)
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
    
    // Store triangle data when received
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
    
    // Load viewport matrix from CONTROL_MATRIX
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            matrix_load_counter <= 0;
            matrix_request <= 0;
            matrix_opcode <= 3'b011;  // Viewport matrix code  
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
    
    // Coordinate transformation control
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            coord_transform_valid <= 0;
            coord_transform_read_done <= 0;
            screen_pts <= '{default: '0};
            screen_pts2 <= '{default: '0};
        end else if (current_state == TRANSFORM_TO_SCREEN) begin
            if (coord_transform_ready && !coord_transform_valid) begin
                coord_transform_valid <= 1;
            end else if (coord_transform_done) begin
                // ✅ Đọc dữ liệu từ coordinate_transformer
                screen_pts <= coord_screen_coords_out;
                screen_pts2 <= coord_screen_2d_out;
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
    
    // Float-to-int conversion control
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int v = 0; v < 3; v++) begin
                for (int c = 0; c < 2; c++) begin
                    f2i_valid[v][c] <= 1'b0;
                end
            end
        end else if (current_state == CONVERT_TO_INTEGER) begin
            // Start all 6 conversions simultaneously
            for (int v = 0; v < 3; v++) begin
                for (int c = 0; c < 2; c++) begin
                    if (f2i_ready[v][c] && !f2i_valid[v][c]) begin
                        f2i_valid[v][c] <= 1'b1;
                    end else if (f2i_valid[v][c] && f2i_ready[v][c]) begin
                        f2i_valid[v][c] <= 1'b0;
                    end
                end
            end
        end else if (current_state == IDLE) begin
            // Reset conversion signals
            for (int v = 0; v < 3; v++) begin
                for (int c = 0; c < 2; c++) begin
                    f2i_valid[v][c] <= 1'b0;
                end
            end
        end
    end
    
    // Bounding box calculation control
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bbox_calc_valid <= 0;
            bbox_calc_read_done <= 0;
            stored_bounding_box <= '{default: '0};
        end else if (current_state == CALCULATE_BOUNDING_BOX) begin
            if (bbox_calc_ready && !bbox_calc_valid) begin
                bbox_calc_valid <= 1;
            end else if (bbox_calc_done) begin
                // ✅ ĐỌC và LƯU kết quả từ bounding_box_calc
                stored_bounding_box <= bounding_box;
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
    
    // Tile search and validation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_tile_count <= 0;
            current_search_tile <= 0;
            tile_search_done <= 0;
            tiles_processed <= 0;
            current_tile_x <= 0;
            current_tile_y <= 0;
            tile_counter <= 0;
            total_tiles <= 0;
            tiles_per_row <= 0;
            tiles_per_col <= 0;
            tile_check_valid <= 0;
            tile_check_read_done <= 0;
            for (int i = 0; i < 4; i++) begin
                valid_tiles[i] <= 0;
            end
        end else if (current_state == CALCULATE_BOUNDING_BOX && bbox_calc_done) begin
            // ✅ Initialize tile search using STORED bounding_box results
            valid_tile_count <= 0;
            current_search_tile <= 0;
            tile_search_done <= 0;
            tiles_processed <= 0;
            
            // Calculate tile grid dimensions using STORED bounding_box data
            tiles_per_row <= ((stored_bounding_box[1] - stored_bounding_box[0] + 3) >> 2);
            tiles_per_col <= ((stored_bounding_box[3] - stored_bounding_box[2] + 3) >> 2);
            total_tiles <= ((stored_bounding_box[1] - stored_bounding_box[0] + 3) >> 2) * 
                          ((stored_bounding_box[3] - stored_bounding_box[2] + 3) >> 2);
            current_tile_x <= stored_bounding_box[0] & ~32'h3;  // Align to 4-pixel boundary
            current_tile_y <= stored_bounding_box[2] & ~32'h3;
            tile_counter <= 0;
        end else if (current_state == TILE_ITERATION) begin
            if (tile_check_ready && !tile_check_valid) begin
                tile_check_valid <= 1;
            end else if (tile_check_done) begin
                tile_check_read_done <= 1;
                tile_check_valid <= 0;
                
                // ✅ Check if current tile is valid using tile_checker results
                if (tile_intersects) begin
                    // Valid tile (intersects)
                    if (valid_tile_count < 4) begin
                        valid_tiles[valid_tile_count] <= current_search_tile;
                        valid_tile_count <= valid_tile_count + 1;
                    end
                end
                
                // Move to next tile
                if (current_search_tile < total_tiles - 1 && valid_tile_count < 4) begin
                    current_search_tile <= current_search_tile + 1;
                    // Update tile coordinates for next search
                    if (current_tile_x + 4 <= stored_bounding_box[1]) begin
                        current_tile_x <= current_tile_x + 4;
                    end else begin
                        current_tile_x <= stored_bounding_box[0] & ~32'h3;
                        current_tile_y <= current_tile_y + 4;
                    end
                end else begin
                    tile_search_done <= 1;  // Found 4 tiles or searched all
                end
            end else if (tile_check_read_done) begin
                tile_check_read_done <= 0;
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
            tile_check_valid <= 0;
            tile_check_read_done <= 0;
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
            current_pixel_index <= 0;
        end else if (current_state == PIXEL_PROCESSING) begin
            if (current_pixel_index == 0) begin
                // ✅ Assign valid tiles to processors
                for (int proc = 0; proc < 4; proc++) begin
                    if (proc < valid_tile_count) begin
                        // Calculate tile coordinates from tile index
                        logic [31:0] tile_idx = valid_tiles[proc];
                        logic [31:0] tiles_per_row_local = ((stored_bounding_box[1] - stored_bounding_box[0] + 3) >> 2);
                        logic [31:0] tile_x_idx = tile_idx % tiles_per_row_local;
                        logic [31:0] tile_y_idx = tile_idx / tiles_per_row_local;
                        
                        sub_block_start_x[proc] <= (stored_bounding_box[0] & ~32'h3) + tile_x_idx * 4;
                        sub_block_start_y[proc] <= (stored_bounding_box[2] & ~32'h3) + tile_y_idx * 4;
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