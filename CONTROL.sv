module CONTROL (
    input logic clk,
    input logic rst_n,
    
    // Interface slave (Avalon MM Slave)
    input logic chipselect,
    input logic read,
    input logic write,
    input logic [31:0] writedata,
    output logic [31:0] readdata,
    input logic [3:0] address,
    output logic interrupt,
    
    // Interface read_master
    output logic start_read,
    output logic [31:0] length_read,
    output logic [31:0] RM_startaddress,
    input logic RM_done,
    
    // Interface writemaster
    output logic start_write,
    output logic [31:0] length_write,
    output logic [31:0] WM_startaddress,
    output logic WM_done,
    
    // Matrix calculation interface
    input logic calc_matrix_done,
    output logic start_calc_matrix,
    
    // Texture and buffer addresses
    output logic [31:0] width_tex,
    output logic [31:0] height_tex,
    output logic [31:0] addr_diff_tex,
    output logic [31:0] addr_norm_tex,
    output logic [31:0] addr_spec_tex,
    output logic [31:0] addr_z_buffer, 
    
    // Render core interface
    output logic start_render,
    input logic render_done
);

    // Register map
    localparam REG_CONTROL          = 4'h0;  // [0]: start, [1]: reset
    localparam REG_STATUS           = 4'h1;  // [0]: busy, [1]: done, [3:2]: state
    localparam REG_WIDTH_OUTPUT     = 4'h2;
    localparam REG_HEIGHT_OUTPUT    = 4'h3;
    localparam REG_BASE_ADDR_OBJ    = 4'h4;
    localparam REG_LENGTH_OBJ       = 4'h5;
    localparam REG_BASE_ADDR_LOOKAT = 4'h6;
    localparam REG_BASE_ADDR_DIFF   = 4'h7;
    localparam REG_BASE_ADDR_NORM   = 4'h8;
    localparam REG_BASE_ADDR_SPEC   = 4'h9;
    localparam REG_BASE_ADDR_ZBUF   = 4'hA;
    localparam REG_BASE_ADDR_FRAME  = 4'hB;
	localparam REG_BASE_ADDR_WTEXT  = 4'hC;
	localparam REG_BASE_ADDR_HTEXT  = 4'hD;

    // Internal registers
    logic [31:0] width_output;
    logic [31:0] height_output;
    logic [31:0] base_addr_obj;
    logic [31:0] length_obj;
    logic [31:0] base_addr_lookat;
    logic [31:0] base_addr_diff_tex;
    logic [31:0] base_addr_norm_tex;
    logic [31:0] base_addr_spec_tex;
    logic [31:0] base_addr_z_buffer;
    logic [31:0] base_addr_framebuffer;
    logic [31:0] control;
    logic [31:0] status;
	logic [31:0] width_texture;
	logic [31:0] height_texture;

    // State machine
    typedef enum logic [2:0] {
        IDLE         = 3'b000,
        READ_LOOKAT  = 3'b001,
        CALC_MATRIX  = 3'b010,
        START_RENDER = 3'b011,
        RENDERING    = 3'b100,
        DONE         = 3'b101
    } state_t;

    state_t current_state, next_state;
    
    // Internal control signals
    logic start_pulse;
    logic busy;
    logic done_flag;
    
    // Edge detection for start signal
    logic start_prev;
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            start_prev <= 1'b0;
        end else begin
            start_prev <= control[0];
        end
    end
    assign start_pulse = control[0] & ~start_prev;

    // State machine - current state
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // State machine - next state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (start_pulse) begin
                    next_state = READ_LOOKAT;
                end
            end
            
            READ_LOOKAT: begin
                if (RM_done) begin
                    next_state = CALC_MATRIX;
                end
            end
            
            CALC_MATRIX: begin
                if (calc_matrix_done) begin
                    next_state = START_RENDER;
                end
            end
            
            START_RENDER: begin
                next_state = RENDERING; // Chỉ ở đây 1 clock
            end
            
            RENDERING: begin
                if (render_done) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                if (!control[0]) begin  // Wait for software to clear start bit
                    next_state = IDLE;
                end
            end
        endcase
    end

    // Control outputs based on state
    always_comb begin
        // Default values
        start_read = 1'b0;
        start_calc_matrix = 1'b0;
        start_render = 1'b0;
        start_write = 1'b0;
        busy = 1'b0;
        done_flag = 1'b0;
        
        case (current_state)
            IDLE: begin
                // Ready state
            end
            
            READ_LOOKAT: begin
                busy = 1'b1;
                start_read = 1'b1;  // Continuously assert while reading
            end
            
            CALC_MATRIX: begin
                busy = 1'b1;
                start_calc_matrix = 1'b1;  // Continuously assert while calculating
            end
            
            START_RENDER: begin
                busy = 1'b1;
                start_render = 1'b1;  // Assert for exactly 1 clock
            end
            
            RENDERING: begin
                busy = 1'b1;
                // Just wait for render_done
            end
            
            DONE: begin
                done_flag = 1'b1;
            end
        endcase
    end

    // Read master address assignment
    always_comb begin
        case (current_state)
            READ_LOOKAT: begin
                RM_startaddress = base_addr_lookat;
                length_read = 32'd48;  // 4 vectors * 3 floats * 4 bytes (eye, center, up, light)
            end
            default: begin
                RM_startaddress = base_addr_obj;
                length_read = length_obj;
            end
        endcase
    end

    // Write master assignment
    assign WM_startaddress = base_addr_framebuffer;
    assign length_write = width_output * height_output * 4;  // RGBA, 4 bytes per pixel
    assign WM_done = (current_state == DONE);

    // Texture outputs
    assign width_tex = width_texture;
    assign height_tex = height_texture;
    assign addr_diff_tex = base_addr_diff_tex;
    assign addr_norm_tex = base_addr_norm_tex;
    assign addr_spec_tex = base_addr_spec_tex;

    // Status register
    assign status = {26'b0, current_state[2:0], done_flag, busy};

    // Interrupt generation
    assign interrupt = done_flag;

    // Avalon MM Slave interface - Write
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            width_output <= 32'd800;
            height_output <= 32'd600;
            base_addr_obj <= 32'h0;
            length_obj <= 32'h0;
            base_addr_lookat <= 32'h0;
            base_addr_diff_tex <= 32'h0;
            base_addr_norm_tex <= 32'h0;
            base_addr_spec_tex <= 32'h0;
            base_addr_z_buffer <= 32'h0;
            base_addr_framebuffer <= 32'h0;
            control <= 32'h0;
        end else begin
            if (chipselect && write) begin
                case (address)
                    REG_CONTROL: control <= writedata;
                    REG_WIDTH_OUTPUT: width_output <= writedata;
                    REG_HEIGHT_OUTPUT: height_output <= writedata;
                    REG_BASE_ADDR_OBJ: base_addr_obj <= writedata;
                    REG_LENGTH_OBJ: length_obj <= writedata;
                    REG_BASE_ADDR_LOOKAT: base_addr_lookat <= writedata;
                    REG_BASE_ADDR_DIFF: base_addr_diff_tex <= writedata;
                    REG_BASE_ADDR_NORM: base_addr_norm_tex <= writedata;
                    REG_BASE_ADDR_SPEC: base_addr_spec_tex <= writedata;
                    REG_BASE_ADDR_ZBUF: base_addr_z_buffer <= writedata;
                    REG_BASE_ADDR_FRAME: base_addr_framebuffer <= writedata;
                endcase
            end
            
            // Auto-clear start bit when done
            if (current_state == DONE && next_state == IDLE) begin
                control[0] <= 1'b0;
            end
        end
    end

    // Avalon MM Slave interface - Read
    always_comb begin
        readdata = 32'h0;
        if (chipselect && read) begin
            case (address)
                REG_CONTROL: readdata = control;
                REG_STATUS: readdata = status;
                REG_WIDTH_OUTPUT: readdata = width_output;
                REG_HEIGHT_OUTPUT: readdata = height_output;
                REG_BASE_ADDR_OBJ: readdata = base_addr_obj;
                REG_LENGTH_OBJ: readdata = length_obj;
                REG_BASE_ADDR_LOOKAT: readdata = base_addr_lookat;
                REG_BASE_ADDR_DIFF: readdata = base_addr_diff_tex;
                REG_BASE_ADDR_NORM: readdata = base_addr_norm_tex;
                REG_BASE_ADDR_SPEC: readdata = base_addr_spec_tex;
                REG_BASE_ADDR_ZBUF: readdata = base_addr_z_buffer;
                REG_BASE_ADDR_FRAME: readdata = base_addr_framebuffer;
                default: readdata = 32'h0;
            endcase
        end
    end

endmodule