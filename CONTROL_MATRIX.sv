module CONTROL_MATRIX (
    input logic clk,
    input logic rst_n,
    
    // Interface với READ_MASTER (nhận lookat data)
    input logic        lookat_data_valid,
    input logic [31:0] lookat_data,     // Stream: eye_xyz, center_xyz, up_xyz, light_xyz
    output logic       lookat_ready,
    
    // Interface với CONTROL
    input logic        start_calc_matrix,
    output logic       calc_matrix_done,
    input logic [31:0] width_framebuffer,
    input logic [31:0] height_framebuffer,
    
    // Interface với RENDER_CORE (shared access)
    input logic [86:0] matrix_request,      // Core requests
    input logic [86:0][2:0] matrix_opcode,  // Matrix type: 1=ModelView, 2=Projection, 3=Viewport, 4=Combined, 5=Light
    output logic [31:0] matrix_data,        // Matrix elements 
    output logic [6:0]  target_core_id,
    output logic        matrix_valid,
    input logic [86:0]  matrix_read_done    // Core completed reading matrix
);

    // Matrix opcodes
    localparam MATRIX_MODELVIEW   = 3'd1;
    localparam MATRIX_PROJECTION  = 3'd2; 
    localparam MATRIX_VIEWPORT    = 3'd3;
    localparam MATRIX_COMBINED    = 3'd4;  // ModelView * Projection
    localparam MATRIX_LIGHT       = 3'd5;  // Light vector in view coordinates
    localparam [31:0] VP_RATIO_3_8  = 32'h3EC00000;  // 0.375f (3/8)
	localparam [31:0] VP_RATIO_1_2  = 32'h3F000000;  // 0.5f (1/2)	
    // Main FSM states
    typedef enum logic [4:0] {
        IDLE            = 5'd0,
        RECEIVE_DATA    = 5'd1,
        
        // ModelView calculation pipeline
        CALC_Z_SUB      = 5'd2,   // z = center - eye (3 subtractions)
        CALC_Z_NORM     = 5'd3,   // z = normalize(z)
        CALC_X_CROSS    = 5'd4,   // x = cross(up, z)
        CALC_X_NORM     = 5'd5,   // x = normalize(x)
        CALC_Y_CROSS    = 5'd6,   // y = cross(z, x)
        BUILD_MINV      = 5'd7,   // Construct Minv matrix
        BUILD_TR        = 5'd8,   // Construct Tr matrix  
        MULT_MODELVIEW  = 5'd9,   // ModelView = Minv * Tr
        
        // Projection calculation
        CALC_EYE_CENTER_DIST = 5'd10,  // |eye - center|
        CALC_PROJECTION = 5'd11,
        
        // Other calculations
        CALC_VIEWPORT   = 5'd12,
        MULT_COMBINED   = 5'd13,  // ModelView * Projection
        MULT_LIGHT      = 5'd14,  // ModelView * light_vector
        
        MATRICES_READY  = 5'd15,
        SERVE_REQUEST   = 5'd16,
        SEND_MATRIX     = 5'd17,
        WAIT_ACK        = 5'd18
    } state_t;
    
    state_t current_state, next_state;
    
    // Sub-FSM for vector subtraction
    typedef enum logic [2:0] {
        SUB_IDLE  = 3'd0,
        SUB_SEND_A = 3'd1,
        SUB_WAIT_A = 3'd2,
        SUB_SEND_B = 3'd3,
        SUB_WAIT_B = 3'd4,
        SUB_GET_RESULT = 3'd5,
        SUB_DONE = 3'd6
    } sub_state_t;
    
    sub_state_t sub_current_state, sub_next_state;
    
    // Projection calculation FSM  
    typedef enum logic [1:0] {
        PROJ_IDLE     = 2'd0,
        PROJ_CALC_DIV = 2'd1,
        PROJ_BUILD    = 2'd2
    } proj_state_t;
    
    proj_state_t proj_current_state, proj_next_state;
    
    // Viewport calculation FSM - optimized with parallel operations
    typedef enum logic [2:0] {
		VP_IDLE              = 3'd0,
		VP_CALC_WIDTH_BOTH   = 3'd1,  // Calculate width_3_8 and width_1_2 in parallel
		VP_CALC_HEIGHT_BOTH  = 3'd2,  // Calculate height_3_8 and height_1_2 in parallel
		VP_BUILD_MATRIX      = 3'd3
	} viewport_state_t;
		
    viewport_state_t vp_current_state, vp_next_state;
    
    // Distance calculation FSM
    typedef enum logic [3:0] {
		DIST_IDLE         = 4'd0,
		DIST_MULT_PARALLEL = 4'd1,  // x² and y² parallel
		DIST_MULT_Z       = 4'd2,   // z²
		DIST_ADD_XY       = 4'd3,   // x² + y² - NEW STATE
		DIST_ADD_Z        = 4'd4,   // (x²+y²) + z² - NEW STATE
		DIST_SQRT         = 4'd5    // sqrt(x²+y²+z²)
	} dist_state_t;
    
    dist_state_t dist_current_state, dist_next_state;
	
	typedef enum logic [2:0] {
		ARITH_IDLE     = 3'd0,
		ARITH_SEND_A   = 3'd1,
		ARITH_WAIT_A   = 3'd2,
		ARITH_SEND_B   = 3'd3,
		ARITH_WAIT_B   = 3'd4,
		ARITH_GET_RESULT = 3'd5
	} arith_state_t;

	// Matrix multiplication state tracking
	typedef enum logic [1:0] {
		MAT_MULT_IDLE     = 2'd0,
		MAT_MULT_SENDING  = 2'd1,
		MAT_MULT_RECEIVING = 2'd2
	} mat_mult_state_t;

	mat_mult_state_t mat_mult_state;
	// Declare states for all arithmetic units
	arith_state_t add1_state, add2_state;
	arith_state_t mul1_state, mul2_state;
	arith_state_t div1_state, div2_state;
    
    // Input data storage
    logic [31:0] eye[3];         // Camera position
    logic [31:0] center[3];      // Camera target
    logic [31:0] up[3];          // Camera up vector
    logic [31:0] light[3];       // Light direction
    logic [3:0]  data_count;     // Input counter (0-11)
    
    // Intermediate calculation vectors
    logic [31:0] z_temp[3];      // center - eye
    logic [31:0] z_vec[3];       // normalized z
    logic [31:0] x_temp[3];      // cross(up, z)
    logic [31:0] x_vec[3];       // normalized x
    logic [31:0] y_vec[3];       // cross(z, x)
    logic [31:0] eye_center_dist; // |eye - center| for projection
    
    // Matrix storage
    logic [31:0] modelview_matrix[16];   // 4x4 ModelView matrix
    logic [31:0] projection_matrix[16];  // 4x4 Projection matrix
    logic [31:0] viewport_matrix[16];    // 4x4 Viewport matrix
    logic [31:0] combined_matrix[16];    // 4x4 Combined matrix
    logic [31:0] light_view[3];          // Light vector in view coordinates
    logic [31:0] minv_matrix[16];        // Temporary Minv matrix
    logic [31:0] tr_matrix[16];          // Temporary Tr matrix
    logic [31:0] neg_one_div_f;          //-1/f
    
    // Viewport calculation variables
    logic [31:0] w_div_8, h_div_8, w_3div4, h_3div4;
    logic [31:0] w_sum, h_sum;  // Final sums for viewport matrix
    
    // Distance calculation variables
    logic [31:0] x_squared, y_squared, z_squared;
    logic [31:0] xy_sum, xyz_sum;
    
    // Operation counters and flags
    logic [1:0]  vector_count;           // For 3-element vector operations
    logic [4:0]  matrix_count;           // For matrix element streaming
    logic [4:0]  stream_count;           // For streaming operations
	logic [1:0]  count_cross_out;
    logic        sub_op_done;
	logic cross_sending_started;
    
    // Matrix serving
    logic [6:0]  serving_core;
    logic [2:0]  serving_opcode;
    logic [4:0]  matrix_element_count;   // 0-15 for matrices, 0-2 for vectors
    
    // Priority encoder for requests
    logic [6:0]  requesting_core;
    logic [2:0]  requesting_opcode;
    logic        valid_request_found;
	
	//counter cross
	logic [1:0] x_cross_count;  
	logic [1:0] y_cross_count; 
    //
	logic mul1_complete, mul2_complete, add1_complete;
	logic div1_complete;
	logic build_proj_done;
	logic [31:0] width_3_8, width_1_2, height_3_8, height_1_2;
	logic mul1_vp_complete, mul2_vp_complete;
    // Arithmetic unit interfaces
    
    // Adder/Subtractor 1
    logic [31:0] add1_input_a, add1_input_b;
    logic        add1_input_a_stb, add1_input_b_stb;
    logic        add1_input_a_ack, add1_input_b_ack;
    logic [31:0] add1_output_z;
    logic        add1_output_z_stb;
    logic        add1_output_z_ack;
    
    // Adder/Subtractor 2
    logic [31:0] add2_input_a, add2_input_b;
    logic        add2_input_a_stb, add2_input_b_stb;
    logic        add2_input_a_ack, add2_input_b_ack;
    logic [31:0] add2_output_z;
    logic        add2_output_z_stb;
    logic        add2_output_z_ack;
    
    // Multiplier 1
    logic [31:0] mul1_input_a, mul1_input_b;
    logic        mul1_input_a_stb, mul1_input_b_stb;
    logic        mul1_input_a_ack, mul1_input_b_ack;
    logic [31:0] mul1_output_z;
    logic        mul1_output_z_stb;
    logic        mul1_output_z_ack;
    
    // Multiplier 2
    logic [31:0] mul2_input_a, mul2_input_b;
    logic        mul2_input_a_stb, mul2_input_b_stb;
    logic        mul2_input_a_ack, mul2_input_b_ack;
    logic [31:0] mul2_output_z;
    logic        mul2_output_z_stb;
    logic        mul2_output_z_ack;
    
    // Divider 1
    logic [31:0] div1_input_a, div1_input_b;
    logic        div1_input_a_stb, div1_input_b_stb;
    logic        div1_input_a_ack, div1_input_b_ack;
    logic [31:0] div1_output_z;
    logic        div1_output_z_stb;
    logic        div1_output_z_ack;
    
    // Divider 2
    logic [31:0] div2_input_a, div2_input_b;
    logic        div2_input_a_stb, div2_input_b_stb;
    logic        div2_input_a_ack, div2_input_b_ack;
    logic [31:0] div2_output_z;
    logic        div2_output_z_stb;
    logic        div2_output_z_ack;
    
    // Vector normalize (parallel interface)
    logic        norm_ready;
    logic        norm_data_valid;
    logic        norm_calc_done;
    logic        norm_read_done;
    logic [31:0] norm_x_in, norm_y_in, norm_z_in;
    logic [31:0] norm_x_out, norm_y_out, norm_z_out;
    
    // Cross product (stream interface)
    logic        cross_ready;
    logic        cross_data_valid;
    logic [31:0] cross_data;
    logic        cross_data_done;
    logic        cross_calc_done;
    logic [31:0] cross_result;
    logic        cross_read_done;
    
    // Matrix multiplier (stream interface)
    logic        mat_mult_ready;
    logic        mat_mult_data_valid;
    logic [31:0] mat_mult_data;
    logic        mat_mult_calc_done;
    logic [31:0] mat_mult_result;
    logic        mat_mult_read_done;
    
    // Square root for distance calculation
    logic        sqrt_ready;
    logic        sqrt_data_valid;
    logic [31:0] sqrt_data_in;
    logic        sqrt_calc_done;
    logic [31:0] sqrt_result_out;
    logic        sqrt_read_done;
    
    // Instantiate arithmetic units
    
    adder float_adder_1 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(add1_input_a),
        .input_b(add1_input_b),
        .input_a_stb(add1_input_a_stb),
        .input_b_stb(add1_input_b_stb),
        .input_a_ack(add1_input_a_ack),
        .input_b_ack(add1_input_b_ack),
        .output_z(add1_output_z),
        .output_z_stb(add1_output_z_stb),
        .output_z_ack(add1_output_z_ack)
    );
    
    adder float_adder_2 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(add2_input_a),
        .input_b(add2_input_b),
        .input_a_stb(add2_input_a_stb),
        .input_b_stb(add2_input_b_stb),
        .input_a_ack(add2_input_a_ack),
        .input_b_ack(add2_input_b_ack),
        .output_z(add2_output_z),
        .output_z_stb(add2_output_z_stb),
        .output_z_ack(add2_output_z_ack)
    );
    
    multiplier float_multiplier_1 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(mul1_input_a),
        .input_b(mul1_input_b),
        .input_a_stb(mul1_input_a_stb),
        .input_b_stb(mul1_input_b_stb),
        .input_a_ack(mul1_input_a_ack),
        .input_b_ack(mul1_input_b_ack),
        .output_z(mul1_output_z),
        .output_z_stb(mul1_output_z_stb),
        .output_z_ack(mul1_output_z_ack)
    );
    
    multiplier float_multiplier_2 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(mul2_input_a),
        .input_b(mul2_input_b),
        .input_a_stb(mul2_input_a_stb),
        .input_b_stb(mul2_input_b_stb),
        .input_a_ack(mul2_input_a_ack),
        .input_b_ack(mul2_input_b_ack),
        .output_z(mul2_output_z),
        .output_z_stb(mul2_output_z_stb),
        .output_z_ack(mul2_output_z_ack)
    );
    
    divider float_divider_1 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(div1_input_a),
        .input_b(div1_input_b),
        .input_a_stb(div1_input_a_stb),
        .input_b_stb(div1_input_b_stb),
        .input_a_ack(div1_input_a_ack),
        .input_b_ack(div1_input_b_ack),
        .output_z(div1_output_z),
        .output_z_stb(div1_output_z_stb),
        .output_z_ack(div1_output_z_ack)
    );
    
    divider float_divider_2 (
        .clk(clk),
        .rst(~rst_n),
        .input_a(div2_input_a),
        .input_b(div2_input_b),
        .input_a_stb(div2_input_a_stb),
        .input_b_stb(div2_input_b_stb),
        .input_a_ack(div2_input_a_ack),
        .input_b_ack(div2_input_b_ack),
        .output_z(div2_output_z),
        .output_z_stb(div2_output_z_stb),
        .output_z_ack(div2_output_z_ack)
    );
    
    // Vector normalize - parallel interface
    vector_normalize_3d norm_unit (
        .clk(clk),
        .rst_n(rst_n),
        .ready(norm_ready),
        .data_valid(norm_data_valid),
        .calc_done(norm_calc_done),
        .read_done(norm_read_done),
        .x_in(norm_x_in),
        .y_in(norm_y_in),
        .z_in(norm_z_in),
        .x_out(norm_x_out),
        .y_out(norm_y_out),
        .z_out(norm_z_out)
    );
    
    // Cross product - stream interface
    cross_product_3x1_wrapper cross_unit (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(cross_ready),
        .data_valid(cross_data_valid),
        .data(cross_data),
        //.data_done(cross_data_done),
        .calc_done(cross_calc_done),
        .result(cross_result),
        .read_done(cross_read_done)
    );
    
    // Matrix multiplier - stream interface
    mul4x4_4x4_wrapper matrix_mult_unit (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(mat_mult_ready),
        .data_valid(mat_mult_data_valid),
        .data(mat_mult_data),
        .calc_done(mat_mult_calc_done),
        .result(mat_mult_result),
        .read_done(mat_mult_read_done)
    );
    
    // Square root
    sqrt_slave sqrt_unit (
        .clk(clk),
        .rst_n(rst_n),
        .ready(sqrt_ready),
        .data_valid(sqrt_data_valid),
        .data_in(sqrt_data_in),
        .calc_done(sqrt_calc_done),
        .result_out(sqrt_result_out),
        .read_done(sqrt_read_done)
    );
    
    // Priority encoder for core requests
    always_comb begin
        requesting_core = 7'd127;
        requesting_opcode = 3'b0;
        valid_request_found = 1'b0;
        
        for (int i = 0; i < 87; i++) begin
            if (matrix_request[i] && (i < requesting_core)) begin
                requesting_core = i[6:0];
                requesting_opcode = matrix_opcode[i];
                valid_request_found = 1'b1;
            end
        end
    end
    
    // Projection calculation using divider unit
    always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			neg_one_div_f <= 32'h00000000;
			div1_state <= ARITH_IDLE;
			div1_complete <= 1'b0;
			
			// Divider 1 controls  
			div1_input_a <= 32'b0;
			div1_input_b <= 32'b0;
			div1_input_a_stb <= 1'b0;
			div1_input_b_stb <= 1'b0;
			div1_output_z_ack <= 1'b0;
		end else begin
			// Default values
			div1_input_a_stb <= 1'b0;
			div1_input_b_stb <= 1'b0;
			div1_output_z_ack <= 1'b0;
			
			case (proj_current_state)
				PROJ_CALC_DIV: begin
					// Start divider operation
					if (div1_state == ARITH_IDLE && !div1_complete) begin
						div1_state <= ARITH_SEND_A;
						div1_complete <= 1'b0;
					end
					
					// Sequential divider protocol
					case (div1_state)
						ARITH_SEND_A: begin
							div1_input_a <= 32'hBF800000;  // -1.0f
							div1_input_a_stb <= 1'b1;
							if (div1_input_a_ack) begin
								div1_state <= ARITH_WAIT_A;
							end
						end
						
						ARITH_WAIT_A: begin
							div1_state <= ARITH_SEND_B;
						end
						
						ARITH_SEND_B: begin
							div1_input_b <= eye_center_dist;
							div1_input_b_stb <= 1'b1;
							if (div1_input_b_ack) begin
								div1_state <= ARITH_WAIT_B;
							end
						end
						
						ARITH_WAIT_B: begin
							div1_state <= ARITH_GET_RESULT;
						end
						
						ARITH_GET_RESULT: begin
							if (div1_output_z_stb) begin
								neg_one_div_f <= div1_output_z;
								div1_output_z_ack <= 1'b1;
								div1_state <= ARITH_IDLE;
								div1_complete <= 1'b1;  // Set completion flag
							end
						end
					endcase
				end
				
				default: begin
					// Reset completion flag when leaving projection calculation
					div1_complete <= 1'b0;
				end
			endcase
		end
	end
    
    // Viewport calculation using multiplier unit
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            w_div_8 <= 32'b0;
            h_div_8 <= 32'b0;
            w_3div4 <= 32'b0;
            h_3div4 <= 32'b0;
            // Multiplier controls
            mul1_input_a <= 32'b0;
            mul1_input_b <= 32'b0;
            mul1_input_a_stb <= 1'b0;
            mul1_input_b_stb <= 1'b0;
            mul1_output_z_ack <= 1'b0;
        end else begin
            // Default values
            mul1_input_a_stb <= 1'b0;
            mul1_input_b_stb <= 1'b0;
            mul1_output_z_ack <= 1'b0;
            
            case (vp_current_state)
				VP_CALC_WIDTH_BOTH: begin
					// PARALLEL: mul1 for width*3/8, mul2 for width*1/2
					if (mul1_state == ARITH_IDLE && mul2_state == ARITH_IDLE && 
						!mul1_vp_complete && !mul2_vp_complete) begin
						mul1_state <= ARITH_SEND_A;
						mul2_state <= ARITH_SEND_A;
					end
					
					// mul1: width * 3/8
					case (mul1_state)
						ARITH_SEND_A: begin
							mul1_input_a <= width_framebuffer;
							mul1_input_a_stb <= 1'b1;
							if (mul1_input_a_ack) begin
								mul1_state <= ARITH_WAIT_A;
							end
						end
						
						ARITH_WAIT_A: begin
							mul1_state <= ARITH_SEND_B;
						end
						
						ARITH_SEND_B: begin
							mul1_input_b <= VP_RATIO_3_8;  // 3/8
							mul1_input_b_stb <= 1'b1;
							if (mul1_input_b_ack) begin
								mul1_state <= ARITH_WAIT_B;
							end
						end
						
						ARITH_WAIT_B: begin
							mul1_state <= ARITH_GET_RESULT;
						end
						
						ARITH_GET_RESULT: begin
							if (mul1_output_z_stb) begin
								width_3_8 <= mul1_output_z;
								mul1_output_z_ack <= 1'b1;
								mul1_state <= ARITH_IDLE;
								mul1_vp_complete <= 1'b1;
							end
						end
					endcase
					
					// mul2: width * 1/2
					case (mul2_state)
						ARITH_SEND_A: begin
							mul2_input_a <= width_framebuffer;
							mul2_input_a_stb <= 1'b1;
							if (mul2_input_a_ack) begin
								mul2_state <= ARITH_WAIT_A;
							end
						end
						
						ARITH_WAIT_A: begin
							mul2_state <= ARITH_SEND_B;
						end
						
						ARITH_SEND_B: begin
							mul2_input_b <= VP_RATIO_1_2;  // 1/2
							mul2_input_b_stb <= 1'b1;
							if (mul2_input_b_ack) begin
								mul2_state <= ARITH_WAIT_B;
							end
						end
						
						ARITH_WAIT_B: begin
							mul2_state <= ARITH_GET_RESULT;
						end
						
						ARITH_GET_RESULT: begin
							if (mul2_output_z_stb) begin
								width_1_2 <= mul2_output_z;
								mul2_output_z_ack <= 1'b1;
								mul2_state <= ARITH_IDLE;
								mul2_vp_complete <= 1'b1;
							end
						end
					endcase
				end
				
				VP_CALC_HEIGHT_BOTH: begin
					// PARALLEL: mul1 for height*3/8, mul2 for height*1/2
					if (mul1_state == ARITH_IDLE && mul2_state == ARITH_IDLE && 
						!mul1_vp_complete && !mul2_vp_complete) begin
						mul1_state <= ARITH_SEND_A;
						mul2_state <= ARITH_SEND_A;
						mul1_vp_complete <= 1'b0;  // Reset for new operation
						mul2_vp_complete <= 1'b0;
					end
					
					// mul1: height * 3/8
					case (mul1_state)
						ARITH_SEND_A: begin
							mul1_input_a <= height_framebuffer;
							mul1_input_a_stb <= 1'b1;
							if (mul1_input_a_ack) begin
								mul1_state <= ARITH_WAIT_A;
							end
						end
						
						ARITH_WAIT_A: begin
							mul1_state <= ARITH_SEND_B;
						end
						
						ARITH_SEND_B: begin
							mul1_input_b <= VP_RATIO_3_8;  // 3/8
							mul1_input_b_stb <= 1'b1;
							if (mul1_input_b_ack) begin
								mul1_state <= ARITH_WAIT_B;
							end
						end
						
						ARITH_WAIT_B: begin
							mul1_state <= ARITH_GET_RESULT;
						end
						
						ARITH_GET_RESULT: begin
							if (mul1_output_z_stb) begin
								height_3_8 <= mul1_output_z;
								mul1_output_z_ack <= 1'b1;
								mul1_state <= ARITH_IDLE;
								mul1_vp_complete <= 1'b1;
							end
						end
					endcase
					
					// mul2: height * 1/2
					case (mul2_state)
						ARITH_SEND_A: begin
							mul2_input_a <= height_framebuffer;
							mul2_input_a_stb <= 1'b1;
							if (mul2_input_a_ack) begin
								mul2_state <= ARITH_WAIT_A;
							end
						end
						
						ARITH_WAIT_A: begin
							mul2_state <= ARITH_SEND_B;
						end
						
						ARITH_SEND_B: begin
							mul2_input_b <= VP_RATIO_1_2;  // 1/2
							mul2_input_b_stb <= 1'b1;
							if (mul2_input_b_ack) begin
								mul2_state <= ARITH_WAIT_B;
							end
						end
						
						ARITH_WAIT_B: begin
							mul2_state <= ARITH_GET_RESULT;
						end
						
						ARITH_GET_RESULT: begin
							if (mul2_output_z_stb) begin
								height_1_2 <= mul2_output_z;
								mul2_output_z_ack <= 1'b1;
								mul2_state <= ARITH_IDLE;
								mul2_vp_complete <= 1'b1;
							end
						end
					endcase
				end
			endcase
        end
    end
    
    // Main state machine
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Sub-FSM for vector operations
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            sub_current_state <= SUB_IDLE;
        end else begin
            sub_current_state <= sub_next_state;
        end
    end
    
    // Projection calculation sub-FSM
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            proj_current_state <= PROJ_IDLE;
        end else begin
            proj_current_state <= proj_next_state;
        end
    end
    
    // Viewport calculation sub-FSM
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            vp_current_state <= VP_IDLE;
        end else begin
            vp_current_state <= vp_next_state;
        end
    end
    
    // Distance calculation sub-FSM
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            dist_current_state <= DIST_IDLE;
        end else begin
            dist_current_state <= dist_next_state;
        end
    end
    
    // Main next state logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (start_calc_matrix && lookat_data_valid) begin
                    next_state = RECEIVE_DATA;
                end else if (valid_request_found) begin
                    next_state = SERVE_REQUEST;
                end
            end
            
            RECEIVE_DATA: begin
                if (data_count >= 11) begin
                    next_state = CALC_Z_SUB;
                end
            end
            
            CALC_Z_SUB: begin
                if (sub_op_done) begin
                    next_state = CALC_Z_NORM;
                end
            end
            
            CALC_Z_NORM: begin
                if (norm_calc_done) begin
                    next_state = CALC_X_CROSS;
                end
            end
            
            CALC_X_CROSS: begin
                if (cross_calc_done && x_cross_count == 2'd2) begin
                    next_state = CALC_X_NORM;
                end
            end
            
            CALC_X_NORM: begin
                if (norm_calc_done) begin
                    next_state = CALC_Y_CROSS;
                end
            end
            
            CALC_Y_CROSS: begin
                if (cross_calc_done && y_cross_count == 2'd2) begin
                    next_state = BUILD_MINV;
                end
            end
            
            BUILD_MINV: begin
                next_state = BUILD_TR;
            end
            
            BUILD_TR: begin
                next_state = MULT_MODELVIEW;
            end
            
            MULT_MODELVIEW: begin
				if (mat_mult_state == MAT_MULT_IDLE && mat_mult_read_done) begin
					next_state = CALC_EYE_CENTER_DIST;
				end
			end
            
            CALC_EYE_CENTER_DIST: begin
                if (dist_current_state == DIST_IDLE && sqrt_calc_done) begin
                    next_state = CALC_PROJECTION;
                end
            end
            
            CALC_PROJECTION: begin
                if (proj_current_state == PROJ_IDLE) begin  // Wait for projection calculation to complete
                    next_state = CALC_VIEWPORT;
                end
            end
            
            CALC_VIEWPORT: begin
                if (vp_current_state == VP_IDLE) begin  // Wait for viewport calculation to complete
                    next_state = MULT_COMBINED;
                end
            end
            
            MULT_COMBINED: begin
				if (mat_mult_state == MAT_MULT_IDLE && mat_mult_read_done) begin
					next_state = MULT_LIGHT;
				end
			end
            
            MULT_LIGHT: begin
				if (mat_mult_state == MAT_MULT_IDLE && mat_mult_read_done) begin
					next_state = MATRICES_READY;
				end
			end
            
            MATRICES_READY: begin
                if (valid_request_found) begin
                    next_state = SERVE_REQUEST;
                end
            end
            
            SERVE_REQUEST: begin
                next_state = SEND_MATRIX;
            end
            
            SEND_MATRIX: begin
                if ((serving_opcode == MATRIX_LIGHT && matrix_element_count >= 2) ||
                    (serving_opcode != MATRIX_LIGHT && matrix_element_count >= 15)) begin
                    next_state = WAIT_ACK;
                end
            end
            
            WAIT_ACK: begin
                if (matrix_read_done[serving_core]) begin
                    next_state = MATRICES_READY;
                end
            end
        endcase
    end
    
    // Sub-FSM next state logic for vector subtraction
    always_comb begin
    sub_next_state = sub_current_state;
    
		case (sub_current_state)
			SUB_IDLE: begin
				if (current_state == CALC_Z_SUB && !sub_op_done) begin
					sub_next_state = SUB_SEND_A;
				end
			end
			
			SUB_SEND_A: begin
				if (add1_input_a_ack) begin
					sub_next_state = SUB_WAIT_A;
				end
			end
			
			SUB_WAIT_A: begin
				// Wait one cycle for handshake to complete
				sub_next_state = SUB_SEND_B;
			end
			
			SUB_SEND_B: begin
				if (add1_input_b_ack) begin
					sub_next_state = SUB_WAIT_B;
				end
			end
			
			SUB_WAIT_B: begin
				// Wait one cycle for handshake to complete
				sub_next_state = SUB_GET_RESULT;
			end
			
			SUB_GET_RESULT: begin
				if (add1_output_z_stb) begin
					sub_next_state = SUB_DONE;
				end
			end
			
			SUB_DONE: begin
				if (vector_count == 2) begin
					// All components done, stay in SUB_DONE until main FSM moves away
					sub_next_state = SUB_IDLE;
				end else begin
					// More components to process, go back to SUB_SEND_A
					sub_next_state = SUB_SEND_A;
				end
			end
			
			default: begin
				sub_next_state = SUB_IDLE;
			end
		endcase
	end
    
    // Viewport FSM next state logic
    always_comb begin
		vp_next_state = vp_current_state;
		
		case (vp_current_state)
			VP_IDLE: begin
				if (current_state == CALC_VIEWPORT) begin
					vp_next_state = VP_CALC_WIDTH_BOTH;
				end
			end
			
			VP_CALC_WIDTH_BOTH: begin
				if (mul1_state == ARITH_IDLE && mul2_state == ARITH_IDLE && 
					mul1_vp_complete && mul2_vp_complete) begin
					vp_next_state = VP_CALC_HEIGHT_BOTH;
				end
			end
			
			VP_CALC_HEIGHT_BOTH: begin
				if (mul1_state == ARITH_IDLE && mul2_state == ARITH_IDLE && 
					mul1_vp_complete && mul2_vp_complete) begin
					vp_next_state = VP_BUILD_MATRIX;
				end
			end
			
			VP_BUILD_MATRIX: begin
				vp_next_state = VP_IDLE;
			end
		endcase
	end
    
    // Distance FSM next state logic
    always_comb begin
		dist_next_state = dist_current_state;
		
		case (dist_current_state)
			DIST_IDLE: begin
				if (current_state == CALC_EYE_CENTER_DIST) begin
					dist_next_state = DIST_MULT_PARALLEL;
				end
			end
			
			DIST_MULT_PARALLEL: begin
				if (mul1_state == ARITH_IDLE && mul2_state == ARITH_IDLE && 
					mul1_complete && mul2_complete) begin
					dist_next_state = DIST_MULT_Z;
				end
			end
			
			DIST_MULT_Z: begin
				if (mul1_state == ARITH_IDLE && mul1_complete) begin
					dist_next_state = DIST_ADD_XY;
				end
			end
			
			DIST_ADD_XY: begin
				if (add1_state == ARITH_IDLE && add1_complete) begin
					dist_next_state = DIST_ADD_Z;
				end
			end
			
			DIST_ADD_Z: begin
				if (add1_state == ARITH_IDLE && add1_complete) begin
					dist_next_state = DIST_SQRT;
				end
			end
			
			DIST_SQRT: begin
				if (sqrt_calc_done) begin
					dist_next_state = DIST_IDLE;
				end
			end
		endcase
	end
    //FSM Projection matrix
	always_comb begin
		proj_next_state = proj_current_state;
		
		case (proj_current_state)
			PROJ_IDLE: begin
				if (current_state == CALC_PROJECTION) begin
					proj_next_state = PROJ_CALC_DIV;
				end
			end
			
			PROJ_CALC_DIV: begin
				if (div1_state == ARITH_IDLE && div1_complete) begin
					proj_next_state = PROJ_BUILD;
				end
			end
			
			PROJ_BUILD: begin
				if (build_proj_done == 1'b1) begin
					proj_next_state = PROJ_IDLE;
				end
			end
		endcase
	end
    // Input data reception
    always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			data_count <= 4'b0;
		end else begin
			case (current_state)
				RECEIVE_DATA: begin
					if (lookat_data_valid) begin
						if (data_count == 11) begin
							data_count <= 4'b0;
						end else begin
							data_count <= data_count + 1'b1;
						end
					end
				end
				default: data_count <= 4'b0;
			endcase
		end
	end

	// Vector data loading
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			for (int i = 0; i < 3; i++) begin
				eye[i] <= 32'b0;
				center[i] <= 32'b0;
				up[i] <= 32'b0;
				light[i] <= 32'b0;
			end
		end else begin
			if (current_state == RECEIVE_DATA && lookat_data_valid) begin
				// Load based on current counter (before increment)
				if (data_count < 3) begin
					eye[data_count] <= lookat_data;
				end else if (data_count < 6) begin
					center[data_count - 3] <= lookat_data;
				end else if (data_count < 9) begin
					up[data_count - 6] <= lookat_data;
				end else if (data_count < 12) begin
					light[data_count - 9] <= lookat_data;
				end
			end
		end
	end
    
// Vector subtraction control (z = center - eye) - using adder_1
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			vector_count <= 2'b0;
			sub_op_done <= 1'b0;
			add1_input_a <= 32'b0;
			add1_input_b <= 32'b0;
			add1_input_a_stb <= 1'b0;
			add1_input_b_stb <= 1'b0;
			add1_output_z_ack <= 1'b0;
		end else begin
			if (current_state == CALC_Z_SUB) begin
				case (sub_current_state)
					SUB_IDLE: begin
						sub_op_done <= 1'b0;
						add1_input_a_stb <= 1'b0;
						add1_input_b_stb <= 1'b0;
						add1_output_z_ack <= 1'b0;
					end
					
					SUB_SEND_A: begin
						add1_input_a <= center[vector_count];
						add1_input_a_stb <= 1'b1;
						add1_input_b_stb <= 1'b0;
						add1_output_z_ack <= 1'b0;
					end
					
					SUB_WAIT_A: begin
						add1_input_a_stb <= 1'b0;
						add1_input_b_stb <= 1'b0;
						add1_output_z_ack <= 1'b0;
					end
					
					SUB_SEND_B: begin
						add1_input_b <= {~eye[vector_count][31], eye[vector_count][30:0]};
						add1_input_a_stb <= 1'b0;
						add1_input_b_stb <= 1'b1;
						add1_output_z_ack <= 1'b0;
					end
					
					SUB_WAIT_B: begin
						add1_input_a_stb <= 1'b0;
						add1_input_b_stb <= 1'b0;
						add1_output_z_ack <= 1'b0;
					end
					
					SUB_GET_RESULT: begin
						add1_input_a_stb <= 1'b0;
						add1_input_b_stb <= 1'b0;
						if (add1_output_z_stb) begin
							add1_output_z_ack <= 1'b1;
							z_temp[vector_count] <= add1_output_z;
						end else begin
							add1_output_z_ack <= 1'b0;
						end
					end
					
					SUB_DONE: begin
						add1_input_a_stb <= 1'b0;
						add1_input_b_stb <= 1'b0;
						add1_output_z_ack <= 1'b1;  // EXPLICIT SET - NO DEFAULT CONFLICT
						
						if (vector_count == 2) begin
							sub_op_done <= 1'b1;
							vector_count <= 2'b0;
						end else begin
							vector_count <= vector_count + 1'b1;
						end
					end
				endcase
			end else begin
				sub_op_done <= 1'b0;
				vector_count <= 2'b0;
				add1_input_a_stb <= 1'b0;
				add1_input_b_stb <= 1'b0;
				add1_output_z_ack <= 1'b0;
			end
		end
	end
    
    // Vector normalize control
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            norm_data_valid <= 1'b0;
            norm_read_done <= 1'b0;
        end else begin
            norm_data_valid <= 1'b0;
            norm_read_done <= 1'b0;
            
            case (current_state)
                CALC_Z_NORM: begin
                    if (norm_ready && !norm_data_valid) begin
                        norm_x_in <= z_temp[0];
                        norm_y_in <= z_temp[1];
                        norm_z_in <= z_temp[2];
                        norm_data_valid <= 1'b1;
                    end
                    if (norm_calc_done) begin
                        z_vec[0] <= norm_x_out;
                        z_vec[1] <= norm_y_out;
                        z_vec[2] <= norm_z_out;
                        norm_read_done <= 1'b1;
                    end
                end
                
                CALC_X_NORM: begin
                    if (norm_ready && !norm_data_valid) begin
                        norm_x_in <= x_temp[0];
                        norm_y_in <= x_temp[1];
                        norm_z_in <= x_temp[2];
                        norm_data_valid <= 1'b1;
                    end
                    if (norm_calc_done) begin
                        x_vec[0] <= norm_x_out;
                        x_vec[1] <= norm_y_out;
                        x_vec[2] <= norm_z_out;
                        norm_read_done <= 1'b1;
                    end
                end
            endcase
        end
    end
    
    // Cross product control (stream interface)

	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			x_cross_count <= 2'b0;
		end else begin
			if (current_state == CALC_X_CROSS) begin
				if (cross_calc_done) begin
					if (x_cross_count == 2'd2) begin
						x_cross_count <= 2'b0;  // Reset after 3rd element
					end else begin
						x_cross_count <= x_cross_count + 1'b1;  // Increment
					end
				end
			end else begin
				x_cross_count <= 2'b0;  // Reset when not in CALC_X_CROSS
			end
		end
	end

	// Y Cross Counter Logic  
	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			y_cross_count <= 2'b0;
		end else begin
			if (current_state == CALC_Y_CROSS) begin
				if (cross_calc_done) begin
					if (y_cross_count == 2'd2) begin
						y_cross_count <= 2'b0;  // Reset after 3rd element
					end else begin
						y_cross_count <= y_cross_count + 1'b1;  // Increment
					end
				end
			end else begin
				y_cross_count <= 2'b0;  // Reset when not in CALC_Y_CROSS
			end
		end
	end

	always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			cross_data_valid <= 1'b0;
			cross_read_done <= 1'b0;
			stream_count <= 5'b0;
			cross_sending_started <= 1'b0;
		end else begin
			// Default values
			// cross_data_valid <= 1'b0;
			// cross_read_done <= 1'b0;
			
			case (current_state)
				CALC_X_CROSS: begin
					
					if ((cross_ready && !cross_sending_started) || 
						(cross_sending_started && stream_count < 6)) begin
						
						cross_sending_started <= 1'b1;
						cross_data_valid <= 1'b1;
						
						case (stream_count)
							5'd0: cross_data <= up[0];
							5'd1: cross_data <= up[1];
							5'd2: cross_data <= up[2];
							5'd3: cross_data <= z_vec[0];
							5'd4: cross_data <= z_vec[1];
							5'd5: cross_data <= z_vec[2];
						endcase
						stream_count <= stream_count + 1'b1;
						
						if (stream_count == 6) begin
							cross_data_valid <= 1'b0;
						end
					end
					
					// Output receiving logic - USE x_cross_count
					if (cross_calc_done) begin
						x_temp[x_cross_count] <= cross_result;  // Use x_cross_count instead
						
						if (x_cross_count == 2'd2) begin
							// Completed receiving all 3 elements
							cross_read_done <= 1'b1;
							stream_count <= 5'b0;
							cross_sending_started <= 1'b0;
						end
					end
				end
				
				CALC_Y_CROSS: begin
					// Input sending logic
					if ((cross_ready && !cross_sending_started) || 
						(cross_sending_started && stream_count < 6)) begin
						
						cross_sending_started <= 1'b1;
						cross_data_valid <= 1'b1;
						
						case (stream_count)
							5'd0: cross_data <= z_vec[0];
							5'd1: cross_data <= z_vec[1];
							5'd2: cross_data <= z_vec[2];
							5'd3: cross_data <= x_vec[0];
							5'd4: cross_data <= x_vec[1];
							5'd5: cross_data <= x_vec[2];
						endcase
						stream_count <= stream_count + 1'b1;
						
						if (stream_count == 6) begin
							cross_data_valid <= 1'b0;
						end
					end
					
					
					if (cross_calc_done) begin
						y_vec[y_cross_count] <= cross_result;  
						
						if (y_cross_count == 2'd2) begin
							// Completed receiving all 3 elements
							cross_read_done <= 1'b1;
							stream_count <= 5'b0;
							cross_sending_started <= 1'b0;
						end
					end
				end
				
				default: begin
					stream_count <= 5'b0;
					cross_sending_started <= 1'b0;
					
				end
			endcase
		end
	end
    
    // Matrix construction logic
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 16; i++) begin
                minv_matrix[i] <= 32'b0;
                tr_matrix[i] <= 32'b0;
                projection_matrix[i] <= 32'b0;
                viewport_matrix[i] <= 32'b0;
				build_proj_done <= 1'b0;
            end
        end else begin
            case (current_state)
                BUILD_MINV: begin
                    // Minv = {{x.x,x.y,x.z,0}, {y.x,y.y,y.z,0}, {z.x,z.y,z.z,0}, {0,0,0,1}}
                    minv_matrix[0] <= x_vec[0];  minv_matrix[1] <= x_vec[1];  minv_matrix[2] <= x_vec[2];  minv_matrix[3] <= 32'h00000000;
                    minv_matrix[4] <= y_vec[0];  minv_matrix[5] <= y_vec[1];  minv_matrix[6] <= y_vec[2];  minv_matrix[7] <= 32'h00000000;  
                    minv_matrix[8] <= z_vec[0];  minv_matrix[9] <= z_vec[1];  minv_matrix[10] <= z_vec[2]; minv_matrix[11] <= 32'h00000000;
                    minv_matrix[12] <= 32'h00000000; minv_matrix[13] <= 32'h00000000; minv_matrix[14] <= 32'h00000000; minv_matrix[15] <= 32'h3F800000; // 1.0f
                end
                
                BUILD_TR: begin
                    // Tr = {{1,0,0,-eye.x}, {0,1,0,-eye.y}, {0,0,1,-eye.z}, {0,0,0,1}}
                    tr_matrix[0] <= 32'h3F800000;  tr_matrix[1] <= 32'h00000000;  tr_matrix[2] <= 32'h00000000;  tr_matrix[3] <= {~eye[0][31], eye[0][30:0]};
                    tr_matrix[4] <= 32'h00000000;  tr_matrix[5] <= 32'h3F800000;  tr_matrix[6] <= 32'h00000000;  tr_matrix[7] <= {~eye[1][31], eye[1][30:0]};
                    tr_matrix[8] <= 32'h00000000;  tr_matrix[9] <= 32'h00000000;  tr_matrix[10] <= 32'h3F800000; tr_matrix[11] <= {~eye[2][31], eye[2][30:0]};
                    tr_matrix[12] <= 32'h00000000; tr_matrix[13] <= 32'h00000000; tr_matrix[14] <= 32'h00000000; tr_matrix[15] <= 32'h3F800000;
                end
                
                CALC_PROJECTION: begin
                    // Projection calculation handled by sub-FSM
                    if (proj_current_state == PROJ_BUILD) begin
                        // Projection = {{1,0,0,0}, {0,-1,0,0}, {0,0,1,0}, {0,0,-1/f,0}}
                        projection_matrix[0] <= 32'h3F800000;  projection_matrix[1] <= 32'h00000000;  projection_matrix[2] <= 32'h00000000;  projection_matrix[3] <= 32'h00000000;
                        projection_matrix[4] <= 32'h00000000;  projection_matrix[5] <= 32'hBF800000;  projection_matrix[6] <= 32'h00000000;  projection_matrix[7] <= 32'h00000000; // -1.0f
                        projection_matrix[8] <= 32'h00000000;  projection_matrix[9] <= 32'h00000000;  projection_matrix[10] <= 32'h3F800000; projection_matrix[11] <= 32'h00000000;
                        projection_matrix[12] <= 32'h00000000; projection_matrix[13] <= 32'h00000000; projection_matrix[14] <= neg_one_div_f; projection_matrix[15] <= 32'h00000000; // -1/f
						build_proj_done <= 1'b1;
                    end
                end
                
                CALC_VIEWPORT: begin
                    // Viewport calculation handled by sub-FSM
                    if (vp_current_state == VP_BUILD_MATRIX) begin
                        // viewport(width/8, height/8, width*3/4, height*3/4)
                        // Viewport = {{w*3/8, 0, 0, w/8+w*3/8}, {0, h*3/8, 0, h/8+h*3/8}, {0,0,1,0}, {0,0,0,1}}
                        
                        viewport_matrix[0] <= w_3div4;        // w * 3/4 for scaling
                        viewport_matrix[1] <= 32'h00000000;
                        viewport_matrix[2] <= 32'h00000000;  
                        // Calculate w/8 + w*3/4 for translation
                        viewport_matrix[3] <= w_div_8;        // Simplified, should add w_div_8 + w_3div4
                        
                        viewport_matrix[4] <= 32'h00000000;
                        viewport_matrix[5] <= h_3div4;        // h * 3/4 for scaling
                        viewport_matrix[6] <= 32'h00000000;
                        // Calculate h/8 + h*3/4 for translation  
                        viewport_matrix[7] <= h_div_8;        // Simplified, should add h_div_8 + h_3div4
                        
                        viewport_matrix[8] <= 32'h00000000;
                        viewport_matrix[9] <= 32'h00000000;
                        viewport_matrix[10] <= 32'h3F800000; // 1.0f
                        viewport_matrix[11] <= 32'h00000000;
                        
                        viewport_matrix[12] <= 32'h00000000;
                        viewport_matrix[13] <= 32'h00000000;
                        viewport_matrix[14] <= 32'h00000000;
                        viewport_matrix[15] <= 32'h3F800000; // 1.0f
                    end
                end
            endcase
        end
    end
    
    // Matrix multiplication control (stream interface)
    always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			mat_mult_data_valid <= 1'b0;
			mat_mult_read_done <= 1'b0;
			matrix_count <= 5'b0;
			mat_mult_state <= MAT_MULT_IDLE;
		end else begin
			mat_mult_data_valid <= 1'b0;
			mat_mult_read_done <= 1'b0;
			
			case (current_state)
				MULT_MODELVIEW: begin
					case (mat_mult_state)
						MAT_MULT_IDLE: begin
							if (mat_mult_ready) begin
								mat_mult_state <= MAT_MULT_SENDING;
								matrix_count <= 5'b0;
							end
						end
						
						MAT_MULT_SENDING: begin
							if (matrix_count <= 31) begin  // Changed: <= 31 instead of < 32
								mat_mult_data_valid <= 1'b1;
								// Stream Minv matrix first (16 elements), then Tr matrix (16 elements)
								if (matrix_count < 16) begin
									mat_mult_data <= minv_matrix[matrix_count];
								end else begin
									mat_mult_data <= tr_matrix[matrix_count - 16];
								end
								
								if (matrix_count == 31) begin
									// Last element sent, move to receiving
									mat_mult_state <= MAT_MULT_RECEIVING;
									matrix_count <= 5'b0;
								end else begin
									matrix_count <= matrix_count + 1'b1;
								end
							end
						end
						
						MAT_MULT_RECEIVING: begin
							if (mat_mult_calc_done) begin
								modelview_matrix[matrix_count] <= mat_mult_result;
								matrix_count <= matrix_count + 1'b1;
								
								if (matrix_count == 15) begin
									// All 16 results received
									mat_mult_read_done <= 1'b1;
									mat_mult_state <= MAT_MULT_IDLE;
									matrix_count <= 5'b0;
								end
							end
						end
					endcase
				end
				
				MULT_COMBINED: begin
					case (mat_mult_state)
						MAT_MULT_IDLE: begin
							if (mat_mult_ready) begin
								mat_mult_state <= MAT_MULT_SENDING;
								matrix_count <= 5'b0;
							end
						end
						
						MAT_MULT_SENDING: begin
							if (matrix_count <= 31) begin  // Changed: <= 31 instead of < 32
								mat_mult_data_valid <= 1'b1;
								// FIXED: Stream Projection matrix first, then ModelView matrix
								if (matrix_count < 16) begin
									mat_mult_data <= projection_matrix[matrix_count];    // A matrix
								end else begin
									mat_mult_data <= modelview_matrix[matrix_count - 16]; // B matrix
								end
								
								if (matrix_count == 31) begin
									// Last element sent, move to receiving
									mat_mult_state <= MAT_MULT_RECEIVING;
									matrix_count <= 5'b0;
								end else begin
									matrix_count <= matrix_count + 1'b1;
								end
							end
						end
						
						MAT_MULT_RECEIVING: begin
							if (mat_mult_calc_done) begin
								combined_matrix[matrix_count] <= mat_mult_result;
								matrix_count <= matrix_count + 1'b1;
								
								if (matrix_count == 15) begin
									mat_mult_read_done <= 1'b1;
									mat_mult_state <= MAT_MULT_IDLE;
									matrix_count <= 5'b0;
								end
							end
						end
					endcase
				end
				
				MULT_LIGHT: begin
					case (mat_mult_state)
						MAT_MULT_IDLE: begin
							if (mat_mult_ready) begin
								mat_mult_state <= MAT_MULT_SENDING;
								matrix_count <= 5'b0;
							end
						end
						
						MAT_MULT_SENDING: begin
							if (matrix_count <= 19) begin  // Changed: <= 19 instead of < 20
								mat_mult_data_valid <= 1'b1;
								// Stream ModelView matrix (16 elements), then light vector (4 elements)
								if (matrix_count < 16) begin
									mat_mult_data <= modelview_matrix[matrix_count];
								end else if (matrix_count < 19) begin
									mat_mult_data <= light[matrix_count - 16];
								end else begin
									mat_mult_data <= 32'h00000000; // w component = 0
								end
								
								if (matrix_count == 19) begin
									// Last element sent, move to receiving
									mat_mult_state <= MAT_MULT_RECEIVING;
									matrix_count <= 5'b0;
								end else begin
									matrix_count <= matrix_count + 1'b1;
								end
							end
						end
						
						MAT_MULT_RECEIVING: begin
							if (mat_mult_calc_done) begin
								if (matrix_count < 3) begin  // Only 3 results for vector
									light_view[matrix_count] <= mat_mult_result;
									matrix_count <= matrix_count + 1'b1;
									
									if (matrix_count == 2) begin
										mat_mult_read_done <= 1'b1;
										mat_mult_state <= MAT_MULT_IDLE;
										matrix_count <= 5'b0;
									end
								end
							end
						end
					endcase
				end
				
				default: begin
					mat_mult_state <= MAT_MULT_IDLE;
					matrix_count <= 5'b0;
				end
			endcase
		end
	end

    
    // Distance calculation using parallel arithmetic units
    always_ff @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			sqrt_data_valid <= 1'b0;
			sqrt_read_done <= 1'b0;
			eye_center_dist <= 32'h3F800000;
			x_squared <= 32'b0;
			y_squared <= 32'b0; 
			z_squared <= 32'b0;
			xy_sum <= 32'b0;
			xyz_sum <= 32'b0;
			mul1_state <= ARITH_IDLE;
			mul2_state <= ARITH_IDLE;
			add1_state <= ARITH_IDLE;
			mul1_complete <= 1'b0;
			mul2_complete <= 1'b0;
			add1_complete <= 1'b0;
			
			// Multiplier controls (keep existing)
			mul1_input_a <= 32'b0;
			mul1_input_b <= 32'b0;
			mul1_input_a_stb <= 1'b0;
			mul1_input_b_stb <= 1'b0;
			mul1_output_z_ack <= 1'b0;
			
			mul2_input_a <= 32'b0;
			mul2_input_b <= 32'b0;
			mul2_input_a_stb <= 1'b0;
			mul2_input_b_stb <= 1'b0;
			mul2_output_z_ack <= 1'b0;
			
			// Adder controls
			add1_input_a <= 32'b0;
			add1_input_b <= 32'b0;
			add1_input_a_stb <= 1'b0;
			add1_input_b_stb <= 1'b0;
			add1_output_z_ack <= 1'b0;
		end else begin
			
			case (dist_current_state)
				DIST_MULT_PARALLEL: begin
					// Start both multipliers from IDLE
					if (mul1_state == ARITH_IDLE && mul2_state == ARITH_IDLE && 
						!mul1_complete && !mul2_complete) begin
						mul1_state <= ARITH_SEND_A;
						mul2_state <= ARITH_SEND_A;
					end
					
					// Multiplier 1: z_temp[0]²
					case (mul1_state)
						ARITH_SEND_A: begin
							mul1_input_a <= z_temp[0];
							mul1_input_a_stb <= 1'b1;
							if (mul1_input_a_ack) begin
								mul1_state <= ARITH_WAIT_A;
							end
						end
						
						ARITH_WAIT_A: begin
							mul1_state <= ARITH_SEND_B;
						end
						
						ARITH_SEND_B: begin
							mul1_input_b <= z_temp[0];
							mul1_input_b_stb <= 1'b1;
							if (mul1_input_b_ack) begin
								mul1_state <= ARITH_WAIT_B;
							end
						end
						
						ARITH_WAIT_B: begin
							mul1_state <= ARITH_GET_RESULT;
						end
						
						ARITH_GET_RESULT: begin
							if (mul1_output_z_stb) begin
								x_squared <= mul1_output_z;
								mul1_output_z_ack <= 1'b1;
								mul1_state <= ARITH_IDLE;
								mul1_complete <= 1'b1;  // Set completion flag
							end
						end
					endcase
					
					// Multiplier 2: z_temp[1]²
					case (mul2_state)
						ARITH_SEND_A: begin
							mul2_input_a <= z_temp[1];
							mul2_input_a_stb <= 1'b1;
							if (mul2_input_a_ack) begin
								mul2_state <= ARITH_WAIT_A;
							end
						end
						
						ARITH_WAIT_A: begin
							mul2_state <= ARITH_SEND_B;
						end
						
						ARITH_SEND_B: begin
							mul2_input_b <= z_temp[1];
							mul2_input_b_stb <= 1'b1;
							if (mul2_input_b_ack) begin
								mul2_state <= ARITH_WAIT_B;
							end
						end
						
						ARITH_WAIT_B: begin
							mul2_state <= ARITH_GET_RESULT;
						end
						
						ARITH_GET_RESULT: begin
							if (mul2_output_z_stb) begin
								y_squared <= mul2_output_z;
								mul2_output_z_ack <= 1'b1;
								mul2_state <= ARITH_IDLE;
								mul2_complete <= 1'b1;  // Set completion flag
							end
						end
					endcase
				end
				
				DIST_MULT_Z: begin
					if (mul1_state == ARITH_IDLE && !mul1_complete) begin
						mul1_state <= ARITH_SEND_A;
						mul1_complete <= 1'b0;  // Reset for new operation
					end
					
					case (mul1_state)
						ARITH_SEND_A: begin
							mul1_input_a <= z_temp[2];
							mul1_input_a_stb <= 1'b1;
							if (mul1_input_a_ack) begin
								mul1_state <= ARITH_WAIT_A;
							end
						end
						
						ARITH_WAIT_A: begin
							mul1_state <= ARITH_SEND_B;
						end
						
						ARITH_SEND_B: begin
							mul1_input_b <= z_temp[2];
							mul1_input_b_stb <= 1'b1;
							if (mul1_input_b_ack) begin
								mul1_state <= ARITH_WAIT_B;
							end
						end
						
						ARITH_WAIT_B: begin
							mul1_state <= ARITH_GET_RESULT;
						end
						
						ARITH_GET_RESULT: begin
							if (mul1_output_z_stb) begin
								z_squared <= mul1_output_z;
								mul1_output_z_ack <= 1'b1;
								mul1_state <= ARITH_IDLE;
								mul1_complete <= 1'b1;  // Set completion flag
							end
						end
					endcase
				end
				
				DIST_ADD_XY: begin
					if (add1_state == ARITH_IDLE && !add1_complete) begin
						add1_state <= ARITH_SEND_A;
						add1_complete <= 1'b0;  // Reset for new operation
					end
					
					case (add1_state)
						ARITH_SEND_A: begin
							add1_input_a <= x_squared;
							add1_input_a_stb <= 1'b1;
							if (add1_input_a_ack) begin
								add1_state <= ARITH_WAIT_A;
							end
						end
						
						ARITH_WAIT_A: begin
							add1_state <= ARITH_SEND_B;
						end
						
						ARITH_SEND_B: begin
							add1_input_b <= y_squared;
							add1_input_b_stb <= 1'b1;
							if (add1_input_b_ack) begin
								add1_state <= ARITH_WAIT_B;
							end
						end
						
						ARITH_WAIT_B: begin
							add1_state <= ARITH_GET_RESULT;
						end
						
						ARITH_GET_RESULT: begin
							if (add1_output_z_stb) begin
								xy_sum <= add1_output_z;
								add1_output_z_ack <= 1'b1;
								add1_state <= ARITH_IDLE;
								add1_complete <= 1'b1;  // Set completion flag
							end
						end
					endcase
				end
				
				DIST_ADD_Z: begin
					if (add1_state == ARITH_IDLE && !add1_complete) begin
						add1_state <= ARITH_SEND_A;
						add1_complete <= 1'b0;  // Reset for new operation
					end
					
					case (add1_state)
						ARITH_SEND_A: begin
							add1_input_a <= xy_sum;
							add1_input_a_stb <= 1'b1;
							if (add1_input_a_ack) begin
								add1_state <= ARITH_WAIT_A;
							end
						end
						
						ARITH_WAIT_A: begin
							add1_state <= ARITH_SEND_B;
						end
						
						ARITH_SEND_B: begin
							add1_input_b <= z_squared;
							add1_input_b_stb <= 1'b1;
							if (add1_input_b_ack) begin
								add1_state <= ARITH_WAIT_B;
							end
						end
						
						ARITH_WAIT_B: begin
							add1_state <= ARITH_GET_RESULT;
						end
						
						ARITH_GET_RESULT: begin
							if (add1_output_z_stb) begin
								xyz_sum <= add1_output_z;
								add1_output_z_ack <= 1'b1;
								add1_state <= ARITH_IDLE;
								add1_complete <= 1'b1;  // Set completion flag
							end
						end
					endcase
				end
				
				default: begin
					// Reset completion flags when leaving distance calculation
					mul1_complete <= 1'b0;
					mul2_complete <= 1'b0;
					add1_complete <= 1'b0;
				end
				
				DIST_SQRT: begin
					if (sqrt_ready && !sqrt_data_valid) begin
						sqrt_data_in <= xyz_sum;
						sqrt_data_valid <= 1'b1;
					end
					if (sqrt_calc_done) begin
						eye_center_dist <= sqrt_result_out;
						sqrt_read_done <= 1'b1;
					end
				end
			endcase
		end
	end
		
    // Matrix serving logic
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            serving_core <= 7'b0;
            serving_opcode <= 3'b0;
            matrix_element_count <= 5'b0;
        end else begin
            case (current_state)
                SERVE_REQUEST: begin
                    serving_core <= requesting_core;
                    serving_opcode <= requesting_opcode;
                    matrix_element_count <= 5'b0;
                end
                
                SEND_MATRIX: begin
                    matrix_element_count <= matrix_element_count + 1'b1;
                end
                
                WAIT_ACK: begin
                    if (matrix_read_done[serving_core]) begin
                        matrix_element_count <= 5'b0;
                    end
                end
            endcase
        end
    end
    
    // Output control signals
    assign lookat_ready = (current_state == RECEIVE_DATA);
    assign calc_matrix_done = (current_state == MATRICES_READY);
    
    // Matrix serving output
    always_comb begin
        matrix_data = 32'b0;
        target_core_id = 7'b0;
        matrix_valid = 1'b0;
        
        if (current_state == SEND_MATRIX) begin
            target_core_id = serving_core;
            matrix_valid = 1'b1;
            
            case (serving_opcode)
                MATRIX_MODELVIEW: matrix_data = modelview_matrix[matrix_element_count];
                MATRIX_PROJECTION: matrix_data = projection_matrix[matrix_element_count];
                MATRIX_VIEWPORT: matrix_data = viewport_matrix[matrix_element_count];
                MATRIX_COMBINED: matrix_data = combined_matrix[matrix_element_count];
                MATRIX_LIGHT: begin
                    if (matrix_element_count < 3) begin
                        matrix_data = light_view[matrix_element_count];
                    end
                end
                default: matrix_data = 32'b0;
            endcase
        end
    end

endmodule