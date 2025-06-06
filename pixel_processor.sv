module pixel_processor (
	input logic clk,
	input logic rst_n,
	
	//interface tile_checker
	output logic request,
	input logic [31:0] corner_valid[4][2], //integer
	input logic start,
	output logic received,
	input logic tile_finished,
	
	output logic done_processor, 
	
	//interface fragdepth
	output logic [31:0] pixel_x, pixel_y, //integer
	output logic [31:0] barycentric_u, barycentric_v, barycentric_w, //3 coordinates
	input logic ready,
	output logic data_valid,
	input logic received_pixel,
	
	// Triangle points (from tile_checker - floating-point)
	input logic [31:0] triangle_pts[3][2]
);

	typedef enum logic [3:0] {
		IDLE,
		REQUEST_TILE,
		RECEIVE_TILE,
		CONVERT_TRIANGLE,
		PROCESS_PIXELS,
		CONVERT_PIXEL,
		CALC_BARYCENTRIC,
		SEND_PIXEL,
		WAIT_FRAGDEPTH,
		NEXT_PIXEL,
		DONE
	} pixel_state_t;
	
	pixel_state_t current_state, next_state;
	
	// Tile information
	logic [31:0] tile_x, tile_y, tile_width, tile_height;
	logic [31:0] current_x, current_y;
	logic [31:0] total_pixels, processed_pixels;
	
	// Triangle points (floating-point, no conversion needed)
	logic [31:0] tri_pts_float[3][2];
	
	// Current pixel coordinates (int -> float conversion)
	logic [31:0] pixel_coords_int[2];   // [x, y]
	logic [31:0] pixel_coords_float[2]; // [x, y] in float
	
	// Int-to-Float conversion
	logic [7:0] int2float_ready, int2float_valid, int2float_done, int2float_ack;
	logic [31:0] int2float_input[8];
	logic [31:0] int2float_output[8];
	logic [2:0] convert_counter;
	
	// Barycentric calculation
	logic bary_ready, bary_valid, bary_done, bary_read_done;
	logic [31:0] bary_pts2_input, bary_p_input, bary_result;
	logic [1:0] bary_input_counter, bary_output_counter;
	logic [31:0] pixel_bary_coords[3];
	
	// Flags
	logic triangle_converted;
	logic pixel_converted;
	logic pixel_inside;
	logic last_pixel;
	logic all_pixels_sent;
	
	// Int-to-Float converter instances
	genvar i;
	generate 
		for (i = 0; i < 8; i++) begin : int2float_gen
			int_to_float u_int2float (
				.clk(clk),
				.rst(~rst_n),
				.input_a(int2float_input[i]),
				.input_a_stb(int2float_valid[i]),
				.input_a_ack(int2float_ready[i]),
				.output_z(int2float_output[i]),
				.output_z_stb(int2float_done[i]),
				.output_z_ack(int2float_ack[i])
			);
		end
	endgenerate
	
	// Barycentric calculator instance
	barycentric pixel_bary_calc (
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
	
	// State machine
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
				if (!tile_finished) next_state = REQUEST_TILE;
			end
			
			REQUEST_TILE: begin
				if (start) next_state = RECEIVE_TILE;
			end
			
			RECEIVE_TILE: begin
				next_state = PROCESS_PIXELS; // Skip CONVERT_TRIANGLE
			end
			
			CONVERT_TRIANGLE: begin
				// Not used anymore - triangle already in float
				next_state = PROCESS_PIXELS;
			end
			
			PROCESS_PIXELS: begin
				if (current_x < tile_x + tile_width && current_y < tile_y + tile_height) begin
					next_state = CONVERT_PIXEL;
				end else begin
					// All pixels in current tile processed
					if (tile_finished && all_pixels_sent) begin
						next_state = DONE;
					end else begin
						next_state = IDLE; // Request next tile
					end
				end
			end
			
			CONVERT_PIXEL: begin
				if (pixel_converted) next_state = CALC_BARYCENTRIC;
			end
			
			CALC_BARYCENTRIC: begin
				if (bary_output_counter >= 3) begin
					if (pixel_inside) begin
						next_state = SEND_PIXEL;
					end else begin
						next_state = NEXT_PIXEL;
					end
				end
			end
			
			SEND_PIXEL: begin
				if (ready) next_state = WAIT_FRAGDEPTH;
			end
			
			WAIT_FRAGDEPTH: begin
				if (received_pixel) next_state = NEXT_PIXEL;
			end
			
			NEXT_PIXEL: begin
				next_state = PROCESS_PIXELS;
			end
			
			DONE: begin
				next_state = DONE; // Stay in done state
			end
		endcase
	end
	
	// Main logic
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			request <= 0;
			received <= 0;
			done_processor <= 0;
			pixel_x <= 0;
			pixel_y <= 0;
			barycentric_u <= 0;
			barycentric_v <= 0;
			barycentric_w <= 0;
			data_valid <= 0;
			
			tile_x <= 0;
			tile_y <= 0;
			tile_width <= 0;
			tile_height <= 0;
			current_x <= 0;
			current_y <= 0;
			processed_pixels <= 0;
			
			triangle_converted <= 0;
			pixel_converted <= 0;
			pixel_inside <= 0;
			all_pixels_sent <= 0;
			
			convert_counter <= 0;
			bary_valid <= 0;
			bary_read_done <= 0;
			bary_input_counter <= 0;
			bary_output_counter <= 0;
			
			int2float_valid <= 8'h00;
			int2float_ack <= 8'h00;
			
		end else begin
			case (current_state)
				IDLE: begin
					request <= 0;
					received <= 0;
					data_valid <= 0;
					triangle_converted <= 0;
					pixel_converted <= 0;
					convert_counter <= 0;
					
					if (!tile_finished) begin
						request <= 1;
					end
				end
				
				REQUEST_TILE: begin
					if (start) begin
						request <= 0;
						received <= 1;
					end
				end
				
				RECEIVE_TILE: begin
					received <= 0;
					
					// Store triangle points (already in float)
					tri_pts_float <= triangle_pts;
					
					// Calculate tile bounds from corners
					tile_x <= corner_valid[0][0];      // Top-left X
					tile_y <= corner_valid[0][1];      // Top-left Y
					tile_width <= corner_valid[1][0] - corner_valid[0][0] + 1;   // Width
					tile_height <= corner_valid[2][1] - corner_valid[0][1] + 1;  // Height
					
					// Initialize pixel scanning
					current_x <= corner_valid[0][0];
					current_y <= corner_valid[0][1];
					processed_pixels <= 0;
					all_pixels_sent <= 0;
				end
				
				CONVERT_TRIANGLE: begin
					// Skip - triangle already in floating-point format
				end
				
				PROCESS_PIXELS: begin
					// Check if we have more pixels to process
					if (current_x >= tile_x + tile_width) begin
						current_x <= tile_x;
						current_y <= current_y + 1;
						
						if (current_y >= tile_y + tile_height) begin
							// All pixels in tile processed
							all_pixels_sent <= 1;
						end
					end
					
					// Store current pixel coordinates
					pixel_coords_int[0] <= current_x;
					pixel_coords_int[1] <= current_y;
					convert_counter <= 0;
					pixel_converted <= 0;
				end
				
				CONVERT_PIXEL: begin
					// Convert current pixel coordinates from int to float
					if (convert_counter < 2) begin
						if (int2float_ready[convert_counter]) begin
							case (convert_counter)
								0: int2float_input[0] <= pixel_coords_int[0];
								1: int2float_input[1] <= pixel_coords_int[1];
							endcase
							int2float_valid[convert_counter] <= 1;
						end
						
						if (int2float_done[convert_counter]) begin
							case (convert_counter)
								0: pixel_coords_float[0] <= int2float_output[0];
								1: pixel_coords_float[1] <= int2float_output[1];
							endcase
							int2float_ack[convert_counter] <= 1;
							int2float_valid[convert_counter] <= 0;
							convert_counter <= convert_counter + 1;
							
							if (convert_counter == 1) begin
								pixel_converted <= 1;
								bary_input_counter <= 0;
								bary_output_counter <= 0;
							end
						end
					end
				end
				
				CALC_BARYCENTRIC: begin
					// Send triangle points and pixel to barycentric calculator
					if (bary_ready && !bary_valid) begin
						bary_valid <= 1;
						bary_input_counter <= 0;
					end else if (bary_valid && bary_input_counter < 8) begin
						case (bary_input_counter)
							0: bary_pts2_input <= tri_pts_float[0][0];
							1: bary_pts2_input <= tri_pts_float[0][1];
							2: bary_pts2_input <= tri_pts_float[1][0];
							3: bary_pts2_input <= tri_pts_float[1][1];
							4: bary_pts2_input <= tri_pts_float[2][0];
							5: bary_pts2_input <= tri_pts_float[2][1];
							6: bary_p_input <= pixel_coords_float[0];
							7: bary_p_input <= pixel_coords_float[1];
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
							// Check if pixel is inside triangle (all coordinates >= 0)
							// Note: This is simplified - should use FP comparator for accuracy
							wire coord0_positive = (pixel_bary_coords[0][31] == 0);
							wire coord1_positive = (pixel_bary_coords[1][31] == 0);
							wire coord2_positive = (bary_result[31] == 0);
							
							pixel_inside <= coord0_positive && coord1_positive && coord2_positive;
							bary_read_done <= 1;
						end
					end else if (bary_read_done) begin
						bary_read_done <= 0;
					end
				end
				
				SEND_PIXEL: begin
					if (ready) begin
						pixel_x <= current_x;
						pixel_y <= current_y;
						barycentric_u <= pixel_bary_coords[0]; // First coordinate (u)
						barycentric_v <= pixel_bary_coords[1]; // Second coordinate (v)  
						barycentric_w <= pixel_bary_coords[2]; // Third coordinate (w)
						data_valid <= 1;
					end
				end
				
				WAIT_FRAGDEPTH: begin
					if (received_pixel) begin
						data_valid <= 0;
						processed_pixels <= processed_pixels + 1;
					end
				end
				
				NEXT_PIXEL: begin
					// Move to next pixel
					current_x <= current_x + 1;
					pixel_inside <= 0;
				end
				
				DONE: begin
					done_processor <= 1;
				end
			endcase
		end
	end

endmodule