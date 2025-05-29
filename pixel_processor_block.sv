// ===========================
// Module pixel_processor_block - Xử lý 1 khối liên tục NxM pixels
// ===========================
module pixel_processor_block (
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
    
    // Block coordinates to process (như nested for loop trong code C)
    input logic [31:0] block_start_x,           // tile_x trong code C
    input logic [31:0] block_start_y,           // tile_y trong code C  
    input logic [31:0] block_width,             // current_tile_width trong code C
    input logic [31:0] block_height,            // current_tile_height trong code C
    
    // Vertex data for interpolation
    input logic [31:0] vertex_uv[3][2],         // UV coordinates
    input logic [31:0] vertex_nrm[3][3],        // Normal vectors
    
    // Fragment processor interface (xuất từng pixel một)
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
    output logic [31:0] zbuffer_addr_out,
    output logic zbuffer_req_out,
    input logic [31:0] zbuffer_data_in,
    input logic zbuffer_valid_in,
    output logic zbuffer_read_done_out
);

    typedef enum logic [3:0] {
        IDLE,
        NESTED_LOOP_START,
        CALCULATE_BARYCENTRIC,
        CHECK_BOUNDS,
        DEPTH_TEST,
        INTERPOLATE_ATTRIBUTES,
        SEND_TO_FRAGMENT,
        INCREMENT_Y,
        INCREMENT_X,
        BLOCK_DONE
    } block_state_t;
    
    block_state_t current_state, next_state;
    
    // Nested loop counters (giống code C)
    logic [31:0] current_x, current_y;      // x, y trong nested for loop  
    logic [31:0] start_x, start_y;          // block boundaries
    logic [31:0] end_x, end_y;
    logic [31:0] width, height;
    
    // Triangle and vertex data storage
    logic [31:0] tri_pts[3][2];
    logic [31:0] clip_verts[3][4];
    logic [31:0] vert_uv[3][2];
    logic [31:0] vert_nrm[3][3];
    
    // Current pixel processing data
    logic [31:0] pixel_barycentric[3];      // bc_screen trong code C
    logic [31:0] pixel_bc_clip[3];          // bc_clip trong code C  
    logic [31:0] pixel_depth;               // frag_depth trong code C
    logic [31:0] pixel_zbuffer;             // zbuffer value
    logic pixel_inside_triangle;            // bc.x >= 0 && bc.y >= 0 && bc.z >= 0
    logic depth_test_pass;                  // frag_depth > zbuffer check
    
    // Interpolated attributes
    logic [31:0] interp_uv[2];
    logic [31:0] interp_normal[3];
    
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
        .barycentric_coords(pixel_barycentric),
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
                if (data_valid) 
                    next_state = NESTED_LOOP_START;
            end
            NESTED_LOOP_START: begin
                next_state = CALCULATE_BARYCENTRIC;
            end
            CALCULATE_BARYCENTRIC: begin
                if (bary_done) 
                    next_state = CHECK_BOUNDS;
            end
            CHECK_BOUNDS: begin
                if (pixel_inside_triangle)
                    next_state = DEPTH_TEST;
                else
                    next_state = INCREMENT_Y;  // Skip this pixel
            end
            DEPTH_TEST: begin
                if (zbuffer_valid_in) begin
                    if (depth_test_pass)
                        next_state = INTERPOLATE_ATTRIBUTES;
                    else
                        next_state = INCREMENT_Y;  // Failed depth test
                end
            end
            INTERPOLATE_ATTRIBUTES: begin
                if (interp_done)
                    next_state = SEND_TO_FRAGMENT;
            end
            SEND_TO_FRAGMENT: begin
                if (fragment_ready)
                    next_state = INCREMENT_Y;
            end
            INCREMENT_Y: begin
                if (current_y >= end_y - 1)
                    next_state = INCREMENT_X;
                else
                    next_state = CALCULATE_BARYCENTRIC;  // Next Y
            end
            INCREMENT_X: begin
                if (current_x >= end_x - 1)
                    next_state = BLOCK_DONE;
                else
                    next_state = CALCULATE_BARYCENTRIC;  // Next X, reset Y
            end
            BLOCK_DONE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Store input data and initialize loop
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tri_pts <= '{default: '0};
            clip_verts <= '{default: '0};
            vert_uv <= '{default: '0};
            vert_nrm <= '{default: '0};
            start_x <= 0; start_y <= 0;
            end_x <= 0; end_y <= 0;
            width <= 0; height <= 0;
        end else if (current_state == IDLE && data_valid) begin
            tri_pts <= triangle_pts;
            clip_verts <= clip_vertices;
            vert_uv <= vertex_uv;
            vert_nrm <= vertex_nrm;
            
            // Set loop boundaries
            start_x <= block_start_x;
            start_y <= block_start_y;
            end_x <= block_start_x + block_width;
            end_y <= block_start_y + block_height;
            width <= block_width;
            height <= block_height;
        end else if (current_state == NESTED_LOOP_START) begin
            // Initialize nested loop: for (x = start_x; x < end_x; x++)
            //                         for (y = start_y; y < end_y; y++)
            current_x <= start_x;
            current_y <= start_y;
        end
    end
    
    // Nested loop iteration control (giống code C)  
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_x <= 0;
            current_y <= 0;
        end else if (current_state == INCREMENT_Y) begin
            if (current_y < end_y - 1) begin
                current_y <= current_y + 1;  // y++ trong inner loop
            end
        end else if (current_state == INCREMENT_X) begin
            if (current_x < end_x - 1) begin
                current_x <= current_x + 1;  // x++ trong outer loop
                current_y <= start_y;        // Reset y = start_y
            end
        end
    end
    
    // Calculate barycentric coordinates for current pixel
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bary_valid <= 0;
            bary_read_done <= 0;
            bary_input_counter <= 0;
            bary_output_counter <= 0;
            pixel_barycentric <= '{default: '0};
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
                pixel_barycentric[bary_output_counter] <= bary_output;
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
    
    // Check if pixel is inside triangle (giống code C)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_inside_triangle <= 0;
        end else if (current_state == CHECK_BOUNDS) begin
            // if (bc_screen.x < 0 || bc_screen.y < 0 || bc_screen.z < 0) continue;
            pixel_inside_triangle <= (pixel_barycentric[0] >= 32'h0 && 
                                    pixel_barycentric[1] >= 32'h0 && 
                                    pixel_barycentric[2] >= 32'h0);
        end
    end
    
    // Depth test (giống code C)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zbuffer_req_out <= 0;
            zbuffer_addr_out <= 0;
            zbuffer_read_done_out <= 0;
            pixel_depth <= 0;
            pixel_zbuffer <= 0;
            depth_test_pass <= 0;
            pixel_bc_clip <= '{default: '0};
        end else if (current_state == DEPTH_TEST) begin
            if (!zbuffer_req_out) begin
                // Request z-buffer value: zbuffer[x + y * image.width()]
                zbuffer_addr_out <= current_y * 32'd800 + current_x;  // Assuming width=800
                zbuffer_req_out <= 1;
                
                // Calculate bc_clip và frag_depth như trong code C:
                // vec3 bc_clip = {bc_screen.x/pts[0][3], bc_screen.y/pts[1][3], bc_screen.z/pts[2][3]};
                // bc_clip = bc_clip / (bc_clip.x + bc_clip.y + bc_clip.z);
                // double frag_depth = vec3{clip_verts[0][2], clip_verts[1][2], clip_verts[2][2]} * bc_clip;
                
                // Simplified version (cần dùng proper divider/multiplier)
                pixel_bc_clip[0] <= pixel_barycentric[0]; // Placeholder
                pixel_bc_clip[1] <= pixel_barycentric[1];
                pixel_bc_clip[2] <= pixel_barycentric[2];
                pixel_depth <= pixel_barycentric[0] + pixel_barycentric[1] + pixel_barycentric[2]; // Placeholder
                
            end else if (zbuffer_valid_in) begin
                pixel_zbuffer <= zbuffer_data_in;
                zbuffer_req_out <= 0;
                zbuffer_read_done_out <= 1;
                
                // if (frag_depth > zbuffer[x + y * image.width()]) continue;
                depth_test_pass <= (pixel_depth <= zbuffer_data_in);  // Less or equal for depth test
                
            end else if (zbuffer_read_done_out) begin
                zbuffer_read_done_out <= 0;
            end
        end else if (current_state == IDLE) begin
            zbuffer_req_out <= 0;
            zbuffer_read_done_out <= 0;
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
                interp_vertex_data[v][0] <= vert_uv[v][0];    // U coordinate
                interp_vertex_data[v][1] <= vert_uv[v][1];    // V coordinate  
                interp_vertex_data[v][2] <= vert_nrm[v][0];   // Normal X
                interp_vertex_data[v][3] <= vert_nrm[v][1];   // Normal Y
                interp_vertex_data[v][4] <= vert_nrm[v][2];   // Normal Z
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
    
    // Send to fragment processor (giống code C)
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
                fragment_bc_screen <= pixel_barycentric;
                fragment_bc_clip <= pixel_bc_clip;
                fragment_frag_depth <= pixel_depth;
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
    assign calc_done = (current_state == BLOCK_DONE);

endmodule