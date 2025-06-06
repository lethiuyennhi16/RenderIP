module RASTERIZER#(
    parameter CORE_ID = 0
)(
	input logic clk, 
	input logic rst_n,
	
	// Interface với VERTEX_PROCESSOR 
   input logic vertex_output_valid,
   input logic [31:0] clip_vert[3][4],    // gl_Position từ vertex shader
   input logic [31:0] view_vert[3][3],    // gl_Position_view 
   input logic [31:0] varying_uv[3][2],   // texture coordinates
   input logic [31:0] varying_nrm[3][3],  // transformed normals
   input logic face_valid,                // sau face culling
	output logic start_stage1,
	 
	// Interface với CONTROL_MATRIX (viewport matrix + light)
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
	 
	 // Interface với ARBITER_WRITE (ghi z-buffer) 
    output logic write_req,
    output logic [31:0] write_addr,
    output logic [31:0] write_data,
    output logic [6:0] write_core_id,
    input logic write_valid,
    input logic write_done,
	 
	 // Interface với CONTROL (địa chỉ base)
    input logic [31:0] addr_z_buffer,
    
	 // Interface với 4 FIFO riêng biệt
    output logic [3:0] FF_writerequest,
	 input logic [3:0] FF_almostfull,
	 output logic [31:0] FF_q [3:0], //-1, uniform_l, varying_nrm, varying_uv, view_tri, pixel_x, pixel_y, bar, pixel_x, pixel_y, bar,... -1 
	 
	 // Control interface
    input logic [31:0] width_framebuffer,
    input logic [31:0] height_framebuffer
);

	typedef enum logic [4:0] {
        IDLE,
        LOAD_VIEWPORT_MATRIX,
		  LOAD_LIGHT,
        TRANSFORM_TO_SCREEN,
        CONVERT_TO_INTEGER,
        CALCULATE_BOUNDING_BOX,
        TILE_ITERATION,
        PIXEL_PROCESSING,
        WAIT_FRAGMENTS,
        TRIANGLE_DONE
    } raster_state_t;
	 raster_state_t current_state, next_state;
	 
	 logic [31:0] viewport_matrix[4][4];    // Viewport transformation matrix
    logic [31:0] screen_pts[3][4];         // Transformed screen coordinates
    logic [31:0] screen_pts2[3][2];        // 2D screen coordinates (float)
    logic [31:0] screen_pts2_int[3][2];    // 2D screen coordinates (integer)
    logic [31:0] bounding_box[4];          // [min_x, max_x, min_y, max_y] - direct from module
    logic [31:0] stored_bounding_box[4];   // Stored bounding box results
	 logic [31:0] light_vector[3];          // Light vector storage
	 
	 // Triangle data storage
    logic [31:0] stored_clip_vert[3][4];
    logic [31:0] stored_view_vert[3][3];
    logic [31:0] stored_varying_uv[3][2];
    logic [31:0] stored_varying_nrm[3][3];
	 
	  // Counters
    logic [4:0] matrix_load_counter;
    logic [4:0] light_load_counter;
    logic [31:0] triangle_counter;
	 
	 // Tile checker signals
	logic tile_checker_ready;
	logic tile_checker_data_valid;
	logic tile_checker_calc_done;
	logic tile_checker_read_done;
	logic [31:0] tile_checker_triangle_pts[3][2];
   logic [31:0] tile_checker_xmin_bbox;
	logic [31:0] tile_checker_xmax_bbox;
	logic [31:0] tile_checker_ymin_bbox;
	logic [31:0] tile_checker_ymax_bbox;
	logic [31:0] tile_checker_corner_valid[4][2];
   logic [31:0] tile_checker_triangle_pts_out[3][2];
	logic [3:0] tile_checker_received;
	logic [3:0] tile_checker_request;
	logic [3:0] tile_checker_start;
	logic tile_checker_tile_finished;
	
	// 4 Pixel processor signals
	logic [3:0] pixel_proc_request;
	logic [31:0] pixel_proc_corner_valid[3:0][4][2];  // 4 processors, each with 4 corners
	logic [3:0] pixel_proc_start;
	logic [3:0] pixel_proc_received;
	logic [3:0] pixel_proc_tile_finished;
	logic [3:0] pixel_proc_done_processor;
	
	// Pixel output từ 4 processor
	logic [31:0] pixel_proc_pixel_x[3:0];
	logic [31:0] pixel_proc_pixel_y[3:0];
	logic [31:0] pixel_proc_barycentric_u[3:0];
	logic [31:0] pixel_proc_barycentric_v[3:0];
	logic [31:0] pixel_proc_barycentric_w[3:0];
	logic [3:0] pixel_proc_ready;
	logic [3:0] pixel_proc_data_valid;
	logic [3:0] pixel_proc_received_pixel;
	
	// Triangle points cho tất cả pixel processor
	logic [31:0] shared_triangle_pts[3][2];
	
	// Triangle data interface cho 4 fragdepth
	logic triangle_data_ready;
	logic [3:0] triangle_data_received;
	
	// 4 Fragdepth signals cho Z-buffer interface  
	logic [31:0] frag_zbuffer_cp[3:0];
	logic [3:0] frag_request_zbuffer_cp;
	logic [3:0] frag_zbuffer_valid_cp;
	logic [3:0] frag_received_zbuffer_cp;
	logic [23:0] frag_addr_zbuffer_cp[3:0];
	
	logic [31:0] frag_zbuffer_ud[3:0];
	logic [3:0] frag_request_zbuffer_ud;
	logic [3:0] frag_zbuffer_valid_ud;
	logic [3:0] frag_received_zbuffer_ud;
	logic [23:0] frag_addr_zbuffer_ud[3:0];
	
	// Coordinate transformer signals
    logic coord_transform_ready, coord_transform_valid, coord_transform_done, coord_transform_read_done;
    logic [31:0] coord_screen_coords_out[3][4];
    logic [31:0] coord_screen_2d_out[3][2];
	
	// Bounding box calculator signals
	logic bbox_calc_ready, bbox_calc_valid, bbox_calc_done, bbox_calc_read_done;
	
	// Float to int conversion signals
	logic [31:0] f2i_input[3][2];
	logic f2i_valid[3][2];
	logic f2i_ready[3][2];
	logic [31:0] f2i_result[3][2];
	logic f2i_done[3][2];
	logic f2i_read_done[3][2];
	logic all_conversions_done;
	
	// Conversion done logic
	assign all_conversions_done = &f2i_done;
	
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
	 
	 // Bounding box calculator instance 
	  bounding_box_calc bbox_calculator (
        .clk(clk),
        .rst_n(rst_n),
        .ready(bbox_calc_ready),
        .data_valid(bbox_calc_valid),
        .calc_done(bbox_calc_done),
        .read_done(bbox_calc_read_done),
        .screen_pts(screen_pts2_int),    
        .width(width_framebuffer),
        .height(height_framebuffer),
        .bbox_out(bounding_box)
    );
	 
	 // Tile intersection checker instance 
    tile_checker u_tile_checker (
		.clk(clk),
		.rst_n(rst_n),
		.ready(tile_checker_ready),
		.data_valid(tile_checker_data_valid),
		.calc_done(tile_checker_calc_done),
		.read_done(tile_checker_read_done),
		.triangle_pts(tile_checker_triangle_pts),
		.xmin_bbox(tile_checker_xmin_bbox),
		.xmax_bbox(tile_checker_xmax_bbox),
		.ymin_bbox(tile_checker_ymin_bbox),
		.ymax_bbox(tile_checker_ymax_bbox),
		.tile_width(32'd4),
		.tile_height(32'd4),
		.corner_valid(tile_checker_corner_valid),
		.triangle_pts_out(tile_checker_triangle_pts_out),
		.received(tile_checker_received),
		.request(tile_checker_request),
		.start(tile_checker_start),
		.tile_finished(tile_checker_tile_finished)
	 );
	 
	 // Small arbiter cho Z-buffer access
	 small_arbiter_zbuffer #(
		.CORE_ID(CORE_ID)
	 ) u_small_arbiter (
		.clk(clk),
		.rst_n(rst_n),
		// Interface với 4 fragdepth - Read requests
		.frag_request_zbuffer_cp(frag_request_zbuffer_cp),
		.frag_addr_zbuffer_cp(frag_addr_zbuffer_cp),
		.frag_zbuffer_cp(frag_zbuffer_cp),
		.frag_zbuffer_valid_cp(frag_zbuffer_valid_cp),
		.frag_received_zbuffer_cp(frag_received_zbuffer_cp),
		// Interface với 4 fragdepth - Write requests
		.frag_request_zbuffer_ud(frag_request_zbuffer_ud),
		.frag_addr_zbuffer_ud(frag_addr_zbuffer_ud),
		.frag_zbuffer_ud(frag_zbuffer_ud),
		.frag_zbuffer_valid_ud(frag_zbuffer_valid_ud),
		.frag_received_zbuffer_ud(frag_received_zbuffer_ud),
		// Interface với ARBITER_TEXTURE (đọc z-buffer)
		.texture_req(texture_req),
		.texture_addr(texture_addr),
		.texture_core_id(texture_core_id),
		.texture_valid(texture_valid),
		.texture_data(texture_data),
		.texture_read_done(texture_read_done),
		// Interface với ARBITER_WRITE (ghi z-buffer)
		.write_req(write_req),
		.write_addr(write_addr),
		.write_data(write_data),
		.write_core_id(write_core_id),
		.write_valid(write_valid),
		.write_done(write_done)
	 );
	 
	 // 4 Pixel processor và 4 Fragdepth instances
	 genvar p;
	 generate
		for (p = 0; p < 4; p++) begin : gen_pixel_processors
			pixel_processor u_pixel_processor (
				.clk(clk),
				.rst_n(rst_n),
				.request(pixel_proc_request[p]),
				.corner_valid(pixel_proc_corner_valid[p]),
				.start(pixel_proc_start[p]),
				.received(pixel_proc_received[p]),
				.tile_finished(pixel_proc_tile_finished[p]),
				.done_processor(pixel_proc_done_processor[p]),
				.pixel_x(pixel_proc_pixel_x[p]),
				.pixel_y(pixel_proc_pixel_y[p]),
				.barycentric_u(pixel_proc_barycentric_u[p]),
				.barycentric_v(pixel_proc_barycentric_v[p]),
				.barycentric_w(pixel_proc_barycentric_w[p]),
				.ready(pixel_proc_ready[p]),
				.data_valid(pixel_proc_data_valid[p]),
				.received_pixel(pixel_proc_received_pixel[p]),
				.triangle_pts(shared_triangle_pts)
			);
			
			fragdepth u_fragdepth (
				.clk(clk),
				.rst_n(rst_n),
				// Pixel processor interface
				.pixel_x(pixel_proc_pixel_x[p]),
				.pixel_y(pixel_proc_pixel_y[p]),
				.barycentric_u(pixel_proc_barycentric_u[p]),
				.barycentric_v(pixel_proc_barycentric_v[p]),
				.barycentric_w(pixel_proc_barycentric_w[p]),
				.ready_pixel(pixel_proc_ready[p]),
				.data_valid_pixel(pixel_proc_data_valid[p]),
				.received_pixel(pixel_proc_received_pixel[p]),
				// Triangle data interface
				.triangle_data_ready(triangle_data_ready),
				.light_vector(light_vector),
				.varying_nrm(stored_varying_nrm),
				.varying_uv(stored_varying_uv),
				.view_vert(stored_view_vert),
				.triangle_data_received(triangle_data_received[p]),
				// Z-buffer interface
				.zbuffer_cp(frag_zbuffer_cp[p]),
				.request_zbuffer_cp(frag_request_zbuffer_cp[p]),
				.zbuffer_valid_cp(frag_zbuffer_valid_cp[p]),
				.received_zbuffer_cp(frag_received_zbuffer_cp[p]),
				.addr_zbuffer_cp(frag_addr_zbuffer_cp[p]),
				.zbuffer_ud(frag_zbuffer_ud[p]),
				.request_zbuffer_ud(frag_request_zbuffer_ud[p]),
				.zbuffer_valid_ud(frag_zbuffer_valid_ud[p]),
				.received_zbuffer_ud(frag_received_zbuffer_ud[p]),
				.addr_zbuffer_ud(frag_addr_zbuffer_ud[p]),
				// FIFO interface
				.FF_writerequest(FF_writerequest[p]),
				.FF_almostfull(FF_almostfull[p]),
				.FF_q(FF_q[p]),
				// Screen data
				.image_width(width_framebuffer),
				.screen_pts(coord_screen_coords_out)
			);
		end
	 endgenerate
	
	 genvar i, j;
    generate
        for (i = 0; i < 3; i++) begin : gen_vertices
            for (j = 0; j < 2; j++) begin : gen_coords
                float_to_int f2i_conv (
                    .clk(clk), 
                    .rst(~rst_n),
                    .input_a(f2i_input[i][j]),
                    .input_a_stb(f2i_valid[i][j]),
                    .input_a_ack(f2i_ready[i][j]),
                    .output_z(f2i_result[i][j]),
                    .output_z_stb(f2i_done[i][j]),
                    .output_z_ack(f2i_read_done[i][j])
                );
            end
        end
    endgenerate
	 
	 // Logic kết nối giữa tile_checker và pixel_processor
	 always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			pixel_proc_request <= 4'b0;
			pixel_proc_start <= 4'b0;
			pixel_proc_tile_finished <= 4'b0;
			tile_checker_received <= 4'b0;
			shared_triangle_pts <= '{default: '0};
			for (int p = 0; p < 4; p++) begin
				for (int c = 0; c < 4; c++) begin
					for (int d = 0; d < 2; d++) begin
						pixel_proc_corner_valid[p][c][d] <= 32'h0;
					end
				end
			end
		end else begin
			start_stage1 <= 1'b0;  // Default: not signaling next triangle
			// Chuyển dữ liệu từ tile_checker sang pixel_processor
			shared_triangle_pts <= tile_checker_triangle_pts_out;
			
			// Xử lý từng processor riêng biệt
			for (int p = 0; p < 4; p++) begin
				// Kiểm tra xem processor này có được request không
				if (tile_checker_start[p]) begin
					pixel_proc_request[p] <= tile_checker_request[p];
					pixel_proc_corner_valid[p] <= tile_checker_corner_valid;
					pixel_proc_start[p] <= 1'b1;
					pixel_proc_tile_finished[p] <= tile_checker_tile_finished;
				end else if (pixel_proc_received[p]) begin
					pixel_proc_start[p] <= 1'b0;
				end
				
				// Feedback từ pixel_processor về tile_checker
				tile_checker_received[p] <= pixel_proc_received[p];
			end
		end
	 end
	 
	 // Triangle data control cho fragdepth
	 always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			triangle_data_ready <= 1'b0;
		end else begin
			// Signal triangle data ready khi bắt đầu TILE_ITERATION
			if (current_state == TILE_ITERATION && tile_checker_data_valid && !triangle_data_ready) begin
				triangle_data_ready <= 1'b1;
			end else if (&triangle_data_received) begin
				// Tất cả 4 fragdepth đã nhận triangle data
				triangle_data_ready <= 1'b0;
			end
		end
	 end
	 
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
                    next_state = LOAD_LIGHT;
            end
				LOAD_LIGHT: begin
					 if (light_load_counter >= 3)
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
                if (tile_checker_calc_done)
                    next_state = PIXEL_PROCESSING;
            end
            PIXEL_PROCESSING: begin
                if (&pixel_proc_done_processor)  // Tất cả 4 processor hoàn thành
                    next_state = WAIT_FRAGMENTS;
            end
            WAIT_FRAGMENTS: begin
                if (tile_checker_tile_finished && (&triangle_data_received))
                    next_state = TRIANGLE_DONE;
            end
            TRIANGLE_DONE: begin
                start_stage1 <= 1'b1;  // Signal VERTEX_PROCESSOR to continue
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
                end else if (matrix_valid && matrix_target_core_id == CORE_ID) begin
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
	 
	 // Load light vector from CONTROL_MATRIX
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            light_load_counter <= 0;
            for (int i = 0; i < 3; i++) begin
                light_vector[i] <= 32'h0;
            end
        end else if (current_state == LOAD_LIGHT) begin
            if (light_load_counter < 3) begin
                if (!matrix_request) begin
                    matrix_request <= 1;
                    matrix_opcode <= 3'b100;  // Light vector code
                end else if (matrix_valid && matrix_target_core_id == CORE_ID) begin
                    light_vector[light_load_counter] <= matrix_data;
                    light_load_counter <= light_load_counter + 1;
                    matrix_request <= 0;
                    matrix_read_done <= 1;
                end
            end else if (matrix_read_done) begin
                matrix_read_done <= 0;
            end
        end else if (current_state == IDLE) begin
            light_load_counter <= 0;
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
                    f2i_read_done[v][c] <= 1'b0;
                end
            end
        end else if (current_state == CONVERT_TO_INTEGER) begin
            for (int v = 0; v < 3; v++) begin
                for (int c = 0; c < 2; c++) begin
                    if (f2i_ready[v][c] && !f2i_valid[v][c]) begin
                        f2i_input[v][c] <= screen_pts2[v][c];
                        f2i_valid[v][c] <= 1'b1;
                    end else if (f2i_done[v][c] && !f2i_read_done[v][c]) begin
                        screen_pts2_int[v][c] <= f2i_result[v][c];
                        f2i_valid[v][c] <= 1'b0;
                        f2i_read_done[v][c] <= 1'b1;
                    end else if (f2i_read_done[v][c]) begin
                        f2i_read_done[v][c] <= 1'b0;
                    end
                end
            end
        end else if (current_state == IDLE) begin
            for (int v = 0; v < 3; v++) begin
                for (int c = 0; c < 2; c++) begin
                    f2i_valid[v][c] <= 1'b0;
                    f2i_read_done[v][c] <= 1'b0;
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
	 
	 // Tile checker control
	 always_ff @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			tile_checker_data_valid <= 1'b0;
			tile_checker_read_done <= 1'b0;
			tile_checker_triangle_pts <= '{default: '0};
			tile_checker_xmin_bbox <= 32'd0;
			tile_checker_xmax_bbox <= 32'd0;
			tile_checker_ymin_bbox <= 32'd0;
			tile_checker_ymax_bbox <= 32'd0;
		end else if (current_state == TILE_ITERATION) begin
			if (tile_checker_ready && !tile_checker_data_valid) begin
				tile_checker_triangle_pts <= screen_pts2;
				tile_checker_xmin_bbox <= stored_bounding_box[0];
				tile_checker_xmax_bbox <= stored_bounding_box[1];
				tile_checker_ymin_bbox <= stored_bounding_box[2];
				tile_checker_ymax_bbox <= stored_bounding_box[3];
				tile_checker_data_valid <= 1'b1;
			end else if (tile_checker_calc_done) begin
				tile_checker_read_done <= 1'b1;
				tile_checker_data_valid <= 1'b0;
			end else if (tile_checker_read_done) begin
				tile_checker_read_done <= 1'b0;
			end
		end else begin
			tile_checker_data_valid <= 1'b0;
			tile_checker_read_done <= 1'b0;
		end
	 end

endmodule