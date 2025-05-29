// Module coordinate_transformer - Chuyển đổi từ clip space sang screen space -- checked
module coordinate_transformer (
    input logic clk,
    input logic rst_n,
    
    // Handshake protocol
    output logic ready,
    input logic data_valid,
    output logic calc_done,
    input logic read_done,
    
    // Input data
    input logic [31:0] clip_coords_in[3][4],    // 3 vertices, 4 components each
    input logic [31:0] viewport_matrix[4][4],
    
    // Output data
    output logic [31:0] screen_coords_out[3][4],  // Transformed coordinates
    output logic [31:0] screen_2d_out[3][2]      // 2D screen coordinates
);

    typedef enum logic [2:0] {
        IDLE,
        TRANSFORM_VERTICES,
        PERSPECTIVE_DIVIDE,
        OUTPUT_RESULTS,
        WAIT_READ
    } transform_state_t;
    
    transform_state_t current_state, next_state;
    
    // Internal storage
    logic [31:0] clip_coords[3][4];
    logic [31:0] viewport_mat[4][4];
    logic [31:0] transformed_coords[3][4];
    logic [31:0] screen_2d[3][2];
    
    // Processing counters
    logic [1:0] vertex_counter;
    logic [4:0] transform_stage;
    
    // Matrix multiplication for viewport transformation
    logic matrix_mul_ready, matrix_mul_valid, matrix_mul_done, matrix_mul_read_done;
    logic [31:0] matrix_mul_data, matrix_mul_result;
    
    mul4x4_4x4_wrapper viewport_transformer (
        .iClk(clk),
        .iRstn(rst_n),
        .ready(matrix_mul_ready),
        .data_valid(matrix_mul_valid),
        .data(matrix_mul_data),
        .calc_done(matrix_mul_done),
        .result(matrix_mul_result),
        .read_done(matrix_mul_read_done)
    );
    
    // Perspective divide implementation - sử dụng divider với interface đúng
    logic [31:0] div_a, div_b, div_z;
    logic div_a_stb, div_b_stb, div_z_stb;
    logic div_a_ack, div_b_ack, div_z_ack;
    logic [1:0] divide_component; // 0=x, 1=y, skip z for 2D output
    
    divider perspective_divider (
        .clk(clk), .rst(~rst_n),
        .input_a(div_a), .input_a_stb(div_a_stb), .input_a_ack(div_a_ack),
        .input_b(div_b), .input_b_stb(div_b_stb), .input_b_ack(div_b_ack),
        .output_z(div_z), .output_z_stb(div_z_stb), .output_z_ack(div_z_ack)
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
                if (data_valid) next_state = TRANSFORM_VERTICES;
            end
            TRANSFORM_VERTICES: begin
                if (vertex_counter == 3 && transform_stage >= 25) 
                    next_state = PERSPECTIVE_DIVIDE;
            end
            PERSPECTIVE_DIVIDE: begin
                if (vertex_counter == 3)
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
    
    // Store input data
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clip_coords <= '{default: '0};
            viewport_mat <= '{default: '0};
            transformed_coords <= '{default: '0};
            screen_2d <= '{default: '0};
            vertex_counter <= 0;
            transform_stage <= 0;
        end else if (current_state == IDLE && data_valid) begin
            clip_coords <= clip_coords_in;
            viewport_mat <= viewport_matrix;
            vertex_counter <= 0;
            transform_stage <= 0;
        end
    end
    
    // Matrix transformation implementation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            matrix_mul_valid <= 0;
            matrix_mul_read_done <= 0;
            matrix_mul_data <= 32'h0;
        end else if (current_state == TRANSFORM_VERTICES) begin
            if (vertex_counter < 3) begin
                // For each vertex: transformed = viewport_matrix * clip_vertex
                // Send viewport matrix first (16 elements), then vertex (4 elements)
                case (transform_stage)
                    // Send viewport matrix elements (0-15)
                    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15: begin
                        if (matrix_mul_ready && !matrix_mul_valid) begin
                            matrix_mul_valid <= 1;
                            matrix_mul_data <= viewport_mat[transform_stage >> 2][transform_stage & 2'b11];
                        end else if (matrix_mul_valid) begin
                            matrix_mul_valid <= 0;
                            transform_stage <= transform_stage + 1;
                        end
                    end
                    
                    // Send current vertex elements (16-19)
                    16, 17, 18, 19: begin
                        if (matrix_mul_ready && !matrix_mul_valid) begin
                            matrix_mul_valid <= 1;
                            matrix_mul_data <= clip_coords[vertex_counter][transform_stage - 16];
                        end else if (matrix_mul_valid) begin
                            matrix_mul_valid <= 0;
                            if (transform_stage == 19) begin
                                transform_stage <= 20; // Trigger computation
                            end else begin
                                transform_stage <= transform_stage + 1;
                            end
                        end
                    end
                    
                    // Wait for computation and read results
                    20: begin
                        if (matrix_mul_done) begin
                            transform_stage <= 21; // Start reading results
                        end
                    end
                    
                    // Read 4 result elements
                    21, 22, 23, 24: begin
                        transformed_coords[vertex_counter][transform_stage - 21] <= matrix_mul_result;
                        if (transform_stage == 24) begin
                            matrix_mul_read_done <= 1;
                            transform_stage <= 25;
                        end else begin
                            transform_stage <= transform_stage + 1;
                        end
                    end
                    
                    // Move to next vertex
                    25: begin
                        matrix_mul_read_done <= 0;
                        vertex_counter <= vertex_counter + 1;
                        transform_stage <= 0; // Reset for next vertex
                    end
                endcase
            end
        end else if (current_state == IDLE) begin
            matrix_mul_valid <= 0;
            matrix_mul_read_done <= 0;
            transform_stage <= 0;
            vertex_counter <= 0;
        end
    end
    
    // Perspective divide implementation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_a <= 32'h0; div_b <= 32'h0;
            div_a_stb <= 0; div_b_stb <= 0; div_z_ack <= 0;
            divide_component <= 0;
            vertex_counter <= 0;
        end else if (current_state == PERSPECTIVE_DIVIDE) begin
            if (vertex_counter < 3) begin
                // Divide x,y by w for current vertex - tuần tự a rồi b
                case (divide_component)
                    0, 1: begin // x and y components
                        // Send input_a first (dividend)
                        if (!div_a_stb) begin
                            div_a <= transformed_coords[vertex_counter][divide_component]; // x or y
                            div_a_stb <= 1;
                        end else if (div_a_stb && div_a_ack) begin
                            div_a_stb <= 0;
                            // Then send input_b (divisor)
                            div_b <= transformed_coords[vertex_counter][3]; // w
                            div_b_stb <= 1;
                        end else if (div_b_stb && div_b_ack) begin
                            div_b_stb <= 0;
                            // Wait for result
                        end else if (div_z_stb) begin
                            screen_2d[vertex_counter][divide_component] <= div_z;
                            div_z_ack <= 1;
                            divide_component <= divide_component + 1;
                        end else if (div_z_ack) begin
                            div_z_ack <= 0;
                        end
                    end
                    
                    2: begin // Move to next vertex
                        divide_component <= 0;
                        vertex_counter <= vertex_counter + 1;
                    end
                endcase
            end
        end else if (current_state == IDLE) begin
            vertex_counter <= 0;
            divide_component <= 0;
            div_a <= 32'h0; div_b <= 32'h0;
            div_a_stb <= 0; div_b_stb <= 0; div_z_ack <= 0;
        end
    end
    
    // Output assignments
    assign ready = (current_state == IDLE);
    assign calc_done = (current_state == OUTPUT_RESULTS);
    assign screen_coords_out = transformed_coords;
    assign screen_2d_out = screen_2d;

endmodule