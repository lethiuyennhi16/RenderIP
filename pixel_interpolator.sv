module pixel_interpolator (
    input logic clk,
    input logic rst_n,
    
    // Handshake protocol
    output logic ready,
    input logic data_valid,
    output logic calc_done,
    input logic read_done,
    
    // Input data
    input logic [31:0] barycentric_coords[3],  // u, v, w
    input logic [31:0] vertex_data[3][8],      // 3 vertices, up to 8 attributes each
    input logic [2:0] attribute_count,         // Number of attributes to interpolate
    
    // Output data
    output logic [31:0] interpolated_data[8]   // Interpolated attributes
);

    typedef enum logic [2:0] {
        IDLE,
        MULTIPLY_ATTRIBUTES,
        SUM_CONTRIBUTIONS,
        OUTPUT_RESULTS,
        WAIT_READ
    } interp_state_t;
    
    interp_state_t current_state, next_state;
    
    // Internal storage
    logic [31:0] bary_coords[3];
    logic [31:0] vert_data[3][8];
    logic [31:0] products[3][8];      // Products of bary_coords * vertex_data
    logic [31:0] interpolated[8];
    
    // Processing counters
    logic [2:0] attr_counter;
    logic [1:0] vertex_counter;
    logic [4:0] multiply_stage;
    
    // Arithmetic units
    logic [31:0] mul_a, mul_b, mul_z;
    logic mul_a_stb, mul_b_stb, mul_z_stb;
    logic mul_a_ack, mul_b_ack, mul_z_ack;
    
    logic [31:0] add_a, add_b, add_z;
    logic add_a_stb, add_b_stb, add_z_stb;
    logic add_a_ack, add_b_ack, add_z_ack;
    
    multiplier mul_unit (
        .clk(clk), .rst(~rst_n),
        .input_a(mul_a), .input_a_stb(mul_a_stb), .input_a_ack(mul_a_ack),
        .input_b(mul_b), .input_b_stb(mul_b_stb), .input_b_ack(mul_b_ack),
        .output_z(mul_z), .output_z_stb(mul_z_stb), .output_z_ack(mul_z_ack)
    );
    
    adder add_unit (
        .clk(clk), .rst(~rst_n),
        .input_a(add_a), .input_a_stb(add_a_stb), .input_a_ack(add_a_ack),
        .input_b(add_b), .input_b_stb(add_b_stb), .input_b_ack(add_b_ack),
        .output_z(add_z), .output_z_stb(add_z_stb), .output_z_ack(add_z_ack)
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
                if (data_valid) next_state = MULTIPLY_ATTRIBUTES;
            end
            MULTIPLY_ATTRIBUTES: begin
                if (attr_counter >= attribute_count && vertex_counter == 3)
                    next_state = SUM_CONTRIBUTIONS;
            end
            SUM_CONTRIBUTIONS: begin
                if (attr_counter >= attribute_count)
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
            bary_coords <= '{default: '0};
            vert_data <= '{default: '0};
        end else if (current_state == IDLE && data_valid) begin
            bary_coords <= barycentric_coords;
            vert_data <= vertex_data;
        end
    end
    
    // Multiply barycentric coordinates with vertex attributes
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            attr_counter <= 0;
            vertex_counter <= 0;
            multiply_stage <= 0;
            products <= '{default: '0};
            mul_a <= 0; mul_b <= 0;
            mul_a_stb <= 0; mul_b_stb <= 0; mul_z_ack <= 0;
        end else if (current_state == MULTIPLY_ATTRIBUTES) begin
            // Perform multiplication: bary_coords[vertex] * vert_data[vertex][attr]
            case (multiply_stage)
                0: begin
                    mul_a <= bary_coords[vertex_counter];
                    mul_b <= vert_data[vertex_counter][attr_counter];
                    mul_a_stb <= 1;
                    if (mul_a_stb && mul_a_ack) begin
                        mul_a_stb <= 0;
                        multiply_stage <= 1;
                    end
                end
                1: begin
                    mul_b_stb <= 1;
                    if (mul_b_stb && mul_b_ack) begin
                        mul_b_stb <= 0;
                        multiply_stage <= 2;
                    end
                end
                2: begin
                    if (mul_z_stb) begin
                        products[vertex_counter][attr_counter] <= mul_z;
                        mul_z_ack <= 1;
                        multiply_stage <= 3;
                    end
                end
                3: begin
                    mul_z_ack <= 0;
                    multiply_stage <= 0;
                    
                    // Move to next vertex/attribute
                    if (vertex_counter < 2) begin
                        vertex_counter <= vertex_counter + 1;
                    end else begin
                        vertex_counter <= 0;
                        if (attr_counter < attribute_count - 1) begin
                            attr_counter <= attr_counter + 1;
                        end else begin
                            attr_counter <= attr_counter + 1; // Will trigger state change
                        end
                    end
                end
            endcase
        end else if (current_state == IDLE) begin
            attr_counter <= 0;
            vertex_counter <= 0;
            multiply_stage <= 0;
            mul_a_stb <= 0; mul_b_stb <= 0; mul_z_ack <= 0;
        end
    end
    
    // Sum contributions from all vertices for each attribute
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interpolated <= '{default: '0};
            add_a <= 0; add_b <= 0;
            add_a_stb <= 0; add_b_stb <= 0; add_z_ack <= 0;
        end else if (current_state == SUM_CONTRIBUTIONS) begin
            // For each attribute, sum: products[0][attr] + products[1][attr] + products[2][attr]
            // Simplified: assume instantaneous addition for now
            for (int attr = 0; attr < 8; attr++) begin
                if (attr < attribute_count) begin
                    // This would need proper pipelined addition in real implementation
                    interpolated[attr] <= products[0][attr] + products[1][attr] + products[2][attr];
                end
            end
            attr_counter <= attribute_count; // Signal completion
        end else if (current_state == IDLE) begin
            add_a_stb <= 0; add_b_stb <= 0; add_z_ack <= 0;
        end
    end
    
    assign ready = (current_state == IDLE);
    assign calc_done = (current_state == OUTPUT_RESULTS);
    assign interpolated_data = interpolated;

endmodule