module bounding_box_calc (
    input logic clk,
    input logic rst_n,
    
    // Handshake protocol
    output logic ready,
    input logic data_valid,
    output logic calc_done,
    input logic read_done,
    
    // Input data  
    input logic [31:0] screen_pts[3][2],    // 3 vertices, x,y coordinates
    input logic [31:0] width,
    input logic [31:0] height,
    
    // Output data
    output logic [31:0] bbox_out[4]         // [min_x, max_x, min_y, max_y]
);

    typedef enum logic [2:0] {
        IDLE,
        FIND_MIN_MAX,
        CLAMP_TO_SCREEN,
        OUTPUT_RESULT,
        WAIT_READ
    } bbox_state_t;
    
    bbox_state_t current_state, next_state;
    
    logic [31:0] min_x, max_x, min_y, max_y;
    logic [31:0] pts[3][2];
    
    // Comparator for finding min/max
    logic [31:0] comp_a, comp_b;
    logic comp_a_greater;
    
    // Simple floating point comparator (implement based on IEEE 754)
    assign comp_a_greater = (comp_a > comp_b);  // Simplified
    
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
                if (data_valid) next_state = FIND_MIN_MAX;
            end
            FIND_MIN_MAX: begin
                next_state = CLAMP_TO_SCREEN;
            end
            CLAMP_TO_SCREEN: begin
                next_state = OUTPUT_RESULT;
            end
            OUTPUT_RESULT: begin
                next_state = WAIT_READ;
            end
            WAIT_READ: begin
                if (read_done) next_state = IDLE;
            end
        endcase
    end
    
    // Find min/max coordinates
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            min_x <= 32'h7F7FFFFF;  // Max positive float
            max_x <= 32'hFF7FFFFF;  // Max negative float  
            min_y <= 32'h7F7FFFFF;
            max_y <= 32'hFF7FFFFF;
        end else if (current_state == IDLE && data_valid) begin
            pts <= screen_pts;
        end else if (current_state == FIND_MIN_MAX) begin
            // Find bounding box
            min_x <= (pts[0][0] < pts[1][0]) ? 
                     ((pts[0][0] < pts[2][0]) ? pts[0][0] : pts[2][0]) :
                     ((pts[1][0] < pts[2][0]) ? pts[1][0] : pts[2][0]);
            max_x <= (pts[0][0] > pts[1][0]) ? 
                     ((pts[0][0] > pts[2][0]) ? pts[0][0] : pts[2][0]) :
                     ((pts[1][0] > pts[2][0]) ? pts[1][0] : pts[2][0]);
            min_y <= (pts[0][1] < pts[1][1]) ? 
                     ((pts[0][1] < pts[2][1]) ? pts[0][1] : pts[2][1]) :
                     ((pts[1][1] < pts[2][1]) ? pts[1][1] : pts[2][1]);
            max_y <= (pts[0][1] > pts[1][1]) ? 
                     ((pts[0][1] > pts[2][1]) ? pts[0][1] : pts[2][1]) :
                     ((pts[1][1] > pts[2][1]) ? pts[1][1] : pts[2][1]);
        end else if (current_state == CLAMP_TO_SCREEN) begin
            // Clamp to screen boundaries
            if (min_x < 32'h0) min_x <= 32'h0;
            if (min_y < 32'h0) min_y <= 32'h0;  
            if (max_x >= width) max_x <= width - 1;
            if (max_y >= height) max_y <= height - 1;
        end
    end
    
    assign ready = (current_state == IDLE);
    assign calc_done = (current_state == OUTPUT_RESULT);
    assign bbox_out[0] = min_x;
    assign bbox_out[1] = max_x;
    assign bbox_out[2] = min_y;
    assign bbox_out[3] = max_y;

endmodule
