module tile_checker (
	input logic clk,
   input logic rst_n,
    
   // Handshake protocol
   output logic ready,
   input logic data_valid,
   output logic calc_done,
   input logic read_done,
    
   // Input data
   input logic [31:0] triangle_pts[3][2],  // Triangle vertices (floating-point)
   input logic [31:0] xmin_bbox,
	input logic [31:0] xmax_bbox,
	input logic [31:0] ymin_bbox,
	input logic [31:0] ymax_bbox,
   input logic [31:0] tile_width,
   input logic [31:0] tile_height,
    
    //Interface 4 khoi pixel processor
   output logic [31:0] corner_valid[4][2], // 4 corners (integers)
   output logic [31:0] triangle_pts_out[3][2], // Triangle vertices for processors (floating-point)
	input logic  [3:0] received,
	input logic  [3:0] request,
	output logic [3:0] start,
	output logic tile_finished
);

	typedef enum logic [3:0] {
        IDLE,
        CALCULATE_TILES,
        CONVERT_TRIANGLE,
        PROCESS_TILE,
        CONVERT_CORNERS,
        CHECK_CORNERS,
        OUTPUT_TILE,
        NEXT_TILE,
        ALL_DONE,
        WAIT_READ
    } tile_state_t;
    
    tile_state_t current_state, next_state;
    
    // Tile iteration
    logic [31:0] bbox_width, bbox_height;
    logic [31:0] tiles_x, tiles_y, total_tiles;
    logic [31:0] current_tile_idx;
    logic [31:0] current_x, current_y;
    logic [31:0] tile_x_idx, tile_y_idx;
    
    // Current tile corners (integers)
    logic [31:0] tile_corners_int[4][2];
    // Triangle points (floating-point, no conversion needed)
    logic [31:0] tri_pts_float[3][2];
    
    // Int-to-Float conversion signals (chỉ cho tile corners)
    logic [7:0] int2float_ready, int2float_valid, int2float_done, int2float_ack;
    logic [31:0] int2float_input[8];
    logic [31:0] int2float_output[8];
    logic [2:0] convert_counter;
    
    // Barycentric and comparison (same as before)
    typedef enum logic [2:0] {
		 COMP_IDLE,
		 COMP_SEND_DATA,
		 COMP_WAIT_CALC,
		 COMP_READ_RESULT,
		 COMP_PROCESS
	} comp_state_t;
	
	comp_state_t comp_state, comp_next_state;
	
	typedef enum logic [1:0] {
		 OUTPUT_IDLE,
		 ARBITRATE,
		 SEND_DATA,
		 WAIT_RECEIVED
	} output_state_t;

	output_state_t output_state, output_next_state;
    
    logic bary_ready, bary_valid, bary_done, bary_read_done;
    logic [31:0] bary_pts2_input, bary_p_input, bary_result;
    logic [1:0] bary_input_counter, bary_output_counter;
    logic [2:0] corner_check_counter;
    logic [31:0] pixel_bary_coords[3];
    logic [3:0] corners_inside;
    logic tile_small;
    
    // FP Comparator signals  
	logic comp_ready_0, comp_ready_1, comp_ready_2;
	logic comp_data_valid_0, comp_data_valid_1, comp_data_valid_2;
	logic comp_calc_done_0, comp_calc_done_1, comp_calc_done_2;
	logic comp_read_done_0, comp_read_done_1, comp_read_done_2;
	logic [2:0] comp_result_0, comp_result_1, comp_result_2;
	logic [31:0] comp_a_0, comp_b_0, comp_a_1, comp_b_1, comp_a_2, comp_b_2;
	
	// Arbiter signals
	logic [1:0] selected_processor;
	logic [3:0] pending_requests;
	logic arbitration_valid;
	logic [31:0] corner_data_float[4][2];  // Floating-point for internal use
	logic [31:0] corner_data_int[4][2];    // Integer for output
    
    // Int-to-Float converter instances (8 converters for efficiency)
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
    
    // FP Comparator instances (same as before)
	fp_comparator_32bit u_comp0 (
		 .clk(clk), .rst_n(rst_n),
		 .ready(comp_ready_0), .data_valid(comp_data_valid_0),
		 .calc_done(comp_calc_done_0), .read_done(comp_read_done_0),
		 .a(comp_a_0), .b(comp_b_0), .result(comp_result_0)
	);

	fp_comparator_32bit u_comp1 (
		 .clk(clk), .rst_n(rst_n),
		 .ready(comp_ready_1), .data_valid(comp_data_valid_1),
		 .calc_done(comp_calc_done_1), .read_done(comp_read_done_1),
		 .a(comp_a_1), .b(comp_b_1), .result(comp_result_1)
	);

	fp_comparator_32bit u_comp2 (
		 .clk(clk), .rst_n(rst_n),
		 .ready(comp_ready_2), .data_valid(comp_data_valid_2),
		 .calc_done(comp_calc_done_2), .read_done(comp_read_done_2),
		 .a(comp_a_2), .b(comp_b_2), .result(comp_result_2)
	);
    
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
    
    // State machines
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            comp_state <= COMP_IDLE;
            output_state <= OUTPUT_IDLE;
        end else begin
            current_state <= next_state;
            comp_state <= comp_next_state;
            output_state <= output_next_state;
        end
    end
    
    // Main state machine
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (data_valid) next_state = CALCULATE_TILES;
            end
            CALCULATE_TILES: begin
                next_state = PROCESS_TILE; // Skip CONVERT_TRIANGLE
            end
            CONVERT_TRIANGLE: begin
                // Not used anymore - triangle already in float
                next_state = PROCESS_TILE;
            end
            PROCESS_TILE: begin
                next_state = CONVERT_CORNERS;
            end
            CONVERT_CORNERS: begin
                if (convert_counter >= 8) next_state = CHECK_CORNERS;
            end
            CHECK_CORNERS: begin
                if (tile_small || corner_check_counter >= 4) next_state = OUTPUT_TILE;
            end
            OUTPUT_TILE: begin
                next_state = NEXT_TILE;
            end
            NEXT_TILE: begin
                if (current_tile_idx >= total_tiles - 1) begin
                    next_state = ALL_DONE;
                end else begin
                    next_state = PROCESS_TILE;
                end
            end
            ALL_DONE: begin
                next_state = WAIT_READ;
            end
            WAIT_READ: begin
                if (read_done) next_state = IDLE;
            end
        endcase
    end
    
    // Comparator state machine (same logic as before)
    always_comb begin
		 case (comp_state)
			  COMP_IDLE: begin
					if (bary_output_counter == 2 && current_state == CHECK_CORNERS && !tile_small)
						 comp_next_state = COMP_SEND_DATA;
					else
						 comp_next_state = COMP_IDLE;
			  end
			  COMP_SEND_DATA: begin
					if (comp_ready_0 && comp_ready_1 && comp_ready_2)
						 comp_next_state = COMP_WAIT_CALC;
					else
						 comp_next_state = COMP_SEND_DATA;
			  end
			  COMP_WAIT_CALC: begin
					if (comp_calc_done_0 && comp_calc_done_1 && comp_calc_done_2)
						 comp_next_state = COMP_READ_RESULT;
					else
						 comp_next_state = COMP_WAIT_CALC;
			  end
			  COMP_READ_RESULT: begin
					comp_next_state = COMP_PROCESS;
			  end
			  COMP_PROCESS: begin
					comp_next_state = COMP_IDLE;
			  end
			  default: comp_next_state = COMP_IDLE;
		 endcase
	end
    
    // Output arbiter state machine (same logic as before)
    always_comb begin
		 case (output_state)
			  OUTPUT_IDLE: begin
					if (current_state == OUTPUT_TILE && |pending_requests)
						 output_next_state = ARBITRATE;
					else
						 output_next_state = OUTPUT_IDLE;
			  end
			  ARBITRATE: begin
					if (arbitration_valid)
						 output_next_state = SEND_DATA;
					else
						 output_next_state = ARBITRATE;
			  end
			  SEND_DATA: begin
					output_next_state = WAIT_RECEIVED;
			  end
			  WAIT_RECEIVED: begin
					if (received[selected_processor])
						 output_next_state = OUTPUT_IDLE;  
					else
						 output_next_state = WAIT_RECEIVED;
			  end
			  default: output_next_state = OUTPUT_IDLE;
		 endcase
	end
    
    // Main logic implementation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready <= 1;
            calc_done <= 0;
            tile_finished <= 0;
            triangle_pts_out <= '{default: '0};
            current_tile_idx <= 0;
            convert_counter <= 0;
            
            // Reset all signals
            bbox_width <= 0;
            bbox_height <= 0;
            tiles_x <= 0;
            tiles_y <= 0;
            total_tiles <= 0;
            current_x <= 0;
            current_y <= 0;
            tile_x_idx <= 0;
            tile_y_idx <= 0;
            
            corners_inside <= 4'b0000;
            corner_check_counter <= 0;
            bary_valid <= 0;
            bary_read_done <= 0;
            bary_input_counter <= 0;
            bary_output_counter <= 0;
            
            // Initialize conversion signals
            int2float_valid <= 8'h00;
            int2float_ack <= 8'h00;
            
        end else begin
            case (current_state)
                IDLE: begin
                    ready <= 1;
                    calc_done <= 0;
                    tile_finished <= 0;
                    if (data_valid) begin
                        ready <= 0;
                        // Store input data (triangle already in float)
                        tri_pts_float <= triangle_pts;
                        triangle_pts_out <= triangle_pts; // Output triangle points for processors
                        current_tile_idx <= 0;
                        convert_counter <= 0;
                    end
                end
                
                CALCULATE_TILES: begin
                    // Calculate bounding box dimensions and tile counts
                    bbox_width <= xmax_bbox - xmin_bbox + 1;
                    bbox_height <= ymax_bbox - ymin_bbox + 1;
                    tiles_x <= (xmax_bbox - xmin_bbox + tile_width) / tile_width;
                    tiles_y <= (ymax_bbox - ymin_bbox + tile_height) / tile_height;
                    total_tiles <= ((xmax_bbox - xmin_bbox + tile_width) / tile_width) * 
                                   ((ymax_bbox - ymin_bbox + tile_height) / tile_height);
                end
                
                CONVERT_TRIANGLE: begin
                    // Skip - triangle already in floating-point format
                end
                
                PROCESS_TILE: begin
                    // Calculate current tile position
                    tile_x_idx <= current_tile_idx % tiles_x;
                    tile_y_idx <= current_tile_idx / tiles_x;
                    current_x <= xmin_bbox + (current_tile_idx % tiles_x) * tile_width;
                    current_y <= ymin_bbox + (current_tile_idx / tiles_x) * tile_height;
                    
                    // Calculate tile corners (integers)
                    tile_corners_int[0][0] <= xmin_bbox + (current_tile_idx % tiles_x) * tile_width; // Top-left X
                    tile_corners_int[0][1] <= ymin_bbox + (current_tile_idx / tiles_x) * tile_height; // Top-left Y
                    tile_corners_int[1][0] <= xmin_bbox + (current_tile_idx % tiles_x) * tile_width + tile_width - 1; // Top-right X
                    tile_corners_int[1][1] <= ymin_bbox + (current_tile_idx / tiles_x) * tile_height; // Top-right Y
                    tile_corners_int[2][0] <= xmin_bbox + (current_tile_idx % tiles_x) * tile_width; // Bottom-left X
                    tile_corners_int[2][1] <= ymin_bbox + (current_tile_idx / tiles_x) * tile_height + tile_height - 1; // Bottom-left Y
                    tile_corners_int[3][0] <= xmin_bbox + (current_tile_idx % tiles_x) * tile_width + tile_width - 1; // Bottom-right X
                    tile_corners_int[3][1] <= ymin_bbox + (current_tile_idx / tiles_x) * tile_height + tile_height - 1; // Bottom-right Y
                    
                    // Check if tile is small
                    tile_small <= (tile_width <= 4 && tile_height <= 4);
                    convert_counter <= 0;
                end
                
                CONVERT_CORNERS: begin
                    // Convert tile corners from int to float
                    if (convert_counter < 8) begin
                        if (int2float_ready[convert_counter]) begin
                            case (convert_counter)
                                0: int2float_input[0] <= tile_corners_int[0][0];
                                1: int2float_input[1] <= tile_corners_int[0][1];
                                2: int2float_input[2] <= tile_corners_int[1][0];
                                3: int2float_input[3] <= tile_corners_int[1][1];
                                4: int2float_input[4] <= tile_corners_int[2][0];
                                5: int2float_input[5] <= tile_corners_int[2][1];
                                6: int2float_input[6] <= tile_corners_int[3][0];
                                7: int2float_input[7] <= tile_corners_int[3][1];
                            endcase
                            int2float_valid[convert_counter] <= 1;
                        end
                        
                        if (int2float_done[convert_counter]) begin
                            case (convert_counter)
                                0: corner_data_float[0][0] <= int2float_output[0];
                                1: corner_data_float[0][1] <= int2float_output[1];
                                2: corner_data_float[1][0] <= int2float_output[2];
                                3: corner_data_float[1][1] <= int2float_output[3];
                                4: corner_data_float[2][0] <= int2float_output[4];
                                5: corner_data_float[2][1] <= int2float_output[5];
                                6: corner_data_float[3][0] <= int2float_output[6];
                                7: corner_data_float[3][1] <= int2float_output[7];
                            endcase
                            int2float_ack[convert_counter] <= 1;
                            int2float_valid[convert_counter] <= 0;
                            convert_counter <= convert_counter + 1;
                        end
                    end
                end
                
                CHECK_CORNERS: begin
                    // Same barycentric checking logic as before
                    // (Skip if tile_small, otherwise check each corner)
                    if (tile_small) begin
                        // Skip barycentric check for small tiles
                    end else if (corner_check_counter < 4) begin
                        // Barycentric checking process (same as before)
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
                                6: bary_p_input <= corner_data_float[corner_check_counter][0];
                                7: bary_p_input <= corner_data_float[corner_check_counter][1];
                            endcase
                            bary_input_counter <= bary_input_counter + 1;
                            
                            if (bary_input_counter == 7) begin
                                bary_valid <= 0;
                            end
                        end else if (bary_done && bary_output_counter < 3 && comp_state == COMP_IDLE) begin
                            pixel_bary_coords[bary_output_counter] <= bary_result;
                            bary_output_counter <= bary_output_counter + 1;
                        end else if (bary_read_done) begin
                            bary_read_done <= 0;
                        end
                    end
                    
                    // FP Comparator handling (same as before)
                    case (comp_state)
                        COMP_IDLE: begin
                            comp_data_valid_0 <= 0;
                            comp_data_valid_1 <= 0;
                            comp_data_valid_2 <= 0;
                            comp_read_done_0 <= 0;
                            comp_read_done_1 <= 0;
                            comp_read_done_2 <= 0;
                        end
                        COMP_SEND_DATA: begin
                            if (comp_ready_0) begin
                                comp_a_0 <= pixel_bary_coords[0];
                                comp_b_0 <= 32'h00000000;
                                comp_data_valid_0 <= 1;
                            end
                            if (comp_ready_1) begin
                                comp_a_1 <= pixel_bary_coords[1];
                                comp_b_1 <= 32'h00000000;
                                comp_data_valid_1 <= 1;
                            end
                            if (comp_ready_2) begin
                                comp_a_2 <= bary_result;
                                comp_b_2 <= 32'h00000000;
                                comp_data_valid_2 <= 1;
                            end
                        end
                        COMP_WAIT_CALC: begin
                            comp_data_valid_0 <= 0;
                            comp_data_valid_1 <= 0;
                            comp_data_valid_2 <= 0;
                        end
                        COMP_READ_RESULT: begin
                            comp_read_done_0 <= 1;
                            comp_read_done_1 <= 1;
                            comp_read_done_2 <= 1;
                        end
                        COMP_PROCESS: begin
                            comp_read_done_0 <= 0;
                            comp_read_done_1 <= 0;
                            comp_read_done_2 <= 0;
                            
                            wire coord0_ge_zero = (comp_result_0[2] | comp_result_0[1]);
                            wire coord1_ge_zero = (comp_result_1[2] | comp_result_1[1]); 
                            wire bary_ge_zero   = (comp_result_2[2] | comp_result_2[1]);
                            
                            if (coord0_ge_zero && coord1_ge_zero && bary_ge_zero) begin
                                corners_inside[corner_check_counter] <= 1;
                            end
                            
                            bary_read_done <= 1;
                            bary_output_counter <= 0;
                            corner_check_counter <= corner_check_counter + 1;
                        end
                    endcase
                end
                
                OUTPUT_TILE: begin
                    // Store integer corners for output to processors
                    corner_data_int[0][0] <= tile_corners_int[0][0];
                    corner_data_int[0][1] <= tile_corners_int[0][1];
                    corner_data_int[1][0] <= tile_corners_int[1][0];
                    corner_data_int[1][1] <= tile_corners_int[1][1];
                    corner_data_int[2][0] <= tile_corners_int[2][0];
                    corner_data_int[2][1] <= tile_corners_int[2][1];
                    corner_data_int[3][0] <= tile_corners_int[3][0];
                    corner_data_int[3][1] <= tile_corners_int[3][1];
                    
                    // Decide whether to output this tile
                    if (tile_small) begin
                        // Always output small tiles to processor 0
                        pending_requests <= 4'b0001;
                    end else if (|corners_inside) begin
                        // Output tiles with corners inside triangle
                        pending_requests <= pending_requests | request;
                    end else begin
                        // Skip tiles with all corners outside
                        pending_requests <= 4'b0000;
                    end
                end
                
                NEXT_TILE: begin
                    // Move to next tile
                    current_tile_idx <= current_tile_idx + 1;
                    corners_inside <= 4'b0000;
                    corner_check_counter <= 0;
                    bary_valid <= 0;
                    bary_read_done <= 0;
                    bary_input_counter <= 0;
                    bary_output_counter <= 0;
                end
                
                ALL_DONE: begin
                    calc_done <= 1;
                    tile_finished <= 1;
                end
                
                WAIT_READ: begin
                    if (read_done) begin
                        calc_done <= 0;
                        tile_finished <= 0;
                    end
                end
            endcase
            
            // Output arbiter logic (same as before)
            case (output_state)
                OUTPUT_IDLE: begin
                    start <= 4'b0000;
                    arbitration_valid <= 0;
                end
                ARBITRATE: begin
                    arbitration_valid <= 1;
                    if (pending_requests[0]) begin
                        selected_processor <= 0;
                    end else if (pending_requests[1]) begin
                        selected_processor <= 1;
                    end else if (pending_requests[2]) begin
                        selected_processor <= 2;
                    end else if (pending_requests[3]) begin
                        selected_processor <= 3;
                    end else begin
                        arbitration_valid <= 0;
                    end
                end
                SEND_DATA: begin
                    corner_valid[0] <= corner_data_int[0];
                    corner_valid[1] <= corner_data_int[1];  
                    corner_valid[2] <= corner_data_int[2];
                    corner_valid[3] <= corner_data_int[3];
                    start[selected_processor] <= 1;
                    arbitration_valid <= 0;
                end
                WAIT_RECEIVED: begin
                    if (!received[selected_processor]) begin
                        start[selected_processor] <= 1;
                    end else begin
                        start[selected_processor] <= 0;
                        pending_requests[selected_processor] <= 0;
                    end
                end
            endcase
        end
    end

endmodule