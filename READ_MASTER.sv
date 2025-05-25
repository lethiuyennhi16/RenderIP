module READ_MASTER (
    input  logic        iClk,
    input  logic        iRstn,
    
    // Interface control
    input  logic        Start,
    input  logic [31:0] Length,
    input  logic [31:0] RM_startaddress,
    output logic        RM_done,
    
    // Interface với CONTROL_MATRIX
    output logic        CM_lookat_data_valid,
    output logic [31:0] CM_lookat_data,
    input  logic        CM_lookat_ready,
    
    // Interface FIFO-VERTEX (chỉ GHI vertex data)
    input  logic        FF_vertex_almostfull,
    output logic        FF_vertex_writerequest,
    output logic [31:0] FF_vertex_data,
    
    // Interface FIFO-TEXTURE (chỉ ĐỌC texture addresses và z-buffer)
    input  logic        FF_texture_empty,
    output logic        FF_texture_readrequest,
    input  logic [31:0] FF_texture_q,        // [31:24]=core_id, [23:0]=address
    
    // Interface FIFO-RGB (chỉ GHI RGB values)
    input  logic        FF_rgb_almostfull,
    output logic        FF_rgb_writerequest,
    output logic [31:0] FF_rgb_data,
    
    // Interface master - slave (Avalon Memory Mapped)
    input  logic        iRM_readdatavalid,
    input  logic        iRM_waitrequest,
    output logic        oRM_read,
    output logic [31:0] oRM_readaddress,
    input  logic [31:0] iRM_readdata,
    output logic [3:0]  oRM_burstcount
);

    // Parameters
    localparam VERTEX_BURST_SIZE = 8;       // Max Avalon burst size
    localparam BURSTS_PER_FACE = 3;         // 24/8 = 3 bursts per face
    localparam RGB_FIFO_THRESHOLD = 200;    // Interrupt threshold
    
    // FSM for vertex reading
    typedef enum logic [2:0] {
        V_IDLE            = 3'b000,
        V_READ_LOOKAT     = 3'b001,  // Thêm state mới cho lookat
        V_SEND_LOOKAT     = 3'b002,  // Gửi lookat data cho CONTROL_MATRIX
        V_START_BURST     = 3'b011,
        V_BURST_READ      = 3'b100,
        V_WAIT_DATA       = 3'b101,
        V_WRITE_FIFO      = 3'b110,
        V_DONE            = 3'b111
    } vertex_state_t;
    
    // FSM for texture/z-buffer reading
    typedef enum logic [2:0] {
        T_IDLE           = 3'b000,
        T_READ_ADDR      = 3'b001,
        T_START_READ     = 3'b010,  
        T_WAIT_DATA      = 3'b011,
        T_WRITE_DATA     = 3'b100,
        T_WRITE_ID       = 3'b101
    } texture_state_t;
    
    // Memory arbitration FSM
    typedef enum logic [1:0] {
        ARB_IDLE         = 2'b00,
        ARB_VERTEX       = 2'b01,
        ARB_TEXTURE      = 2'b10
    } arb_state_t;
    
    // State registers
    vertex_state_t  vertex_cs, vertex_ns;
    texture_state_t texture_cs, texture_ns;
    arb_state_t     arb_cs, arb_ns;
    
    // Internal registers for vertex
    logic [31:0] vertex_address;
    logic [31:0] vertex_count;          // Total words read
    logic [31:0] vertex_length;         // Total words to read
    logic [2:0]  burst_word_count;      // 0-7 within current burst
    logic [1:0]  face_burst_count;      // 0-2 bursts per face
    logic        vertex_reading_burst;   // Flag: currently in burst read
    
    // Lookat data management
    logic [3:0]  lookat_count;          // Counter for 12 lookat words
    logic [31:0] lookat_buffer[12];     // Buffer for lookat data
    
    // Internal registers for texture
    logic [7:0]  texture_core_id;
    logic [23:0] texture_address;
    logic [31:0] texture_data_reg;
    
    // Control signals
    logic vertex_req, texture_req;
    logic vertex_grant, texture_grant;
    logic texture_priority;
    logic vertex_burst_interrupt;
    logic vertex_can_start_burst;
    
    // FIFO level estimation
    logic [8:0] rgb_fifo_level;
    logic [8:0] rgb_write_count;
    
    // Track RGB FIFO level (simplified)
    always_ff @(posedge iClk, negedge iRstn) begin
        if (!iRstn) begin
            rgb_write_count <= 9'b0;
        end else begin
            if (FF_rgb_writerequest && !FF_rgb_almostfull) begin
                rgb_write_count <= rgb_write_count + 1'b1;
            end
        end
    end
    
    assign rgb_fifo_level = rgb_write_count;
    assign texture_priority = (rgb_fifo_level > RGB_FIFO_THRESHOLD) || FF_rgb_almostfull;
    assign vertex_burst_interrupt = texture_priority && texture_req && vertex_reading_burst;
    assign vertex_can_start_burst = !texture_priority || !texture_req;
    
    //=============================================================================
    // State Machine Updates
    //=============================================================================
    always_ff @(posedge iClk, negedge iRstn) begin
        if (!iRstn) begin
            vertex_cs  <= V_IDLE;
            texture_cs <= T_IDLE;
            arb_cs     <= ARB_IDLE;
        end else begin
            vertex_cs  <= vertex_ns;
            texture_cs <= texture_ns;
            arb_cs     <= arb_ns;
        end
    end
    
    //=============================================================================
    // Vertex Registers Update
    //=============================================================================
    always_ff @(posedge iClk, negedge iRstn) begin
        if (!iRstn) begin
            vertex_address       <= 32'b0;
            vertex_count         <= 32'b0;
            vertex_length        <= 32'b0;
            burst_word_count     <= 3'b0;
            face_burst_count     <= 2'b0;
            vertex_reading_burst <= 1'b0;
        end else begin
            case (vertex_cs)
                V_IDLE: begin
                    if (Start) begin
                        vertex_address <= RM_startaddress;
                        vertex_count   <= 32'b0;
                        vertex_length  <= Length;
                        burst_word_count <= 3'b0;
                        face_burst_count <= 2'b0;
                        vertex_reading_burst <= 1'b0;
                        lookat_count <= 4'b0;  // Reset lookat counter
                    end
                end
                
                V_READ_LOOKAT: begin
                    if (iRM_readdatavalid) begin
                        lookat_buffer[lookat_count] <= iRM_readdata;
                        lookat_count <= lookat_count + 1'b1;
                        vertex_address <= vertex_address + 4;
                    end
                end
                
                V_START_BURST: begin
                    if (vertex_grant && !iRM_waitrequest) begin
                        vertex_reading_burst <= 1'b1;
                        burst_word_count <= 3'b0;
                    end
                end
                
                V_WAIT_DATA: begin
                    if (iRM_readdatavalid) begin
                        burst_word_count <= burst_word_count + 1'b1;
                        vertex_count <= vertex_count + 1'b1;
                        vertex_address <= vertex_address + 4; // Next word address
                        
                        // Check if burst completed
                        if (burst_word_count == VERTEX_BURST_SIZE - 1) begin
                            vertex_reading_burst <= 1'b0;
                            if (face_burst_count == BURSTS_PER_FACE - 1) begin
                                face_burst_count <= 2'b0; // Reset for next face
                            end else begin
                                face_burst_count <= face_burst_count + 1'b1;
                            end
                        end
                    end
                end
            endcase
        end
    end
    
    //=============================================================================
    // Texture Registers Update
    //=============================================================================
    always_ff @(posedge iClk, negedge iRstn) begin
        if (!iRstn) begin
            texture_core_id   <= 8'b0;
            texture_address   <= 24'b0;
            texture_data_reg  <= 32'b0;
        end else begin
            case (texture_cs)
                T_READ_ADDR: begin
                    if (!FF_texture_empty) begin
                        texture_core_id <= FF_texture_q[31:24];
                        texture_address <= FF_texture_q[23:0];
                    end
                end
                
                T_WAIT_DATA: begin
                    if (iRM_readdatavalid) begin
                        texture_data_reg <= iRM_readdata;
                    end
                end
            endcase
        end
    end
    
    //=============================================================================
    // Vertex FSM Logic
    //=============================================================================
    always_comb begin
        vertex_ns = vertex_cs;
        vertex_req = 1'b0;
        
        case (vertex_cs)
            V_IDLE: begin
                if (Start && !FF_vertex_almostfull && vertex_can_start_burst) begin
                    if (vertex_count < vertex_length) begin
                        vertex_ns = V_START_BURST;
                    end else begin
                        vertex_ns = V_DONE;
                    end
                end
            end
            
            V_START_BURST: begin
                vertex_req = 1'b1;
                if (vertex_grant && !iRM_waitrequest) begin
                    vertex_ns = V_BURST_READ;
                end else if (vertex_burst_interrupt) begin
                    vertex_ns = V_IDLE; // Yield to texture
                end
            end
            
            V_BURST_READ: begin
                vertex_ns = V_WAIT_DATA;
            end
            
            V_WAIT_DATA: begin
                if (iRM_readdatavalid) begin
                    vertex_ns = V_WRITE_FIFO;
                end
            end
            
            V_WRITE_FIFO: begin
                if (!FF_vertex_almostfull) begin
                    if (burst_word_count == VERTEX_BURST_SIZE - 1) begin
                        // Burst completed
                        if (vertex_count >= vertex_length) begin
                            vertex_ns = V_DONE;
                        end else begin
                            vertex_ns = V_IDLE; // Check priority for next burst
                        end
                    end else begin
                        vertex_ns = V_WAIT_DATA; // Continue receiving burst data
                    end
                end
            end
            
            V_DONE: begin
                // Stay in done state
            end
        endcase
    end
    
    //=============================================================================
    // Texture FSM Logic  
    //=============================================================================
    always_comb begin
        texture_ns = texture_cs;
        texture_req = 1'b0;
        
        case (texture_cs)
            T_IDLE: begin
                if (!FF_texture_empty) begin
                    texture_ns = T_READ_ADDR;
                end
            end
            
            T_READ_ADDR: begin
                texture_ns = T_START_READ;
            end
            
            T_START_READ: begin
                texture_req = 1'b1;
                if (texture_grant && !iRM_waitrequest) begin
                    texture_ns = T_WAIT_DATA;
                end
            end
            
            T_WAIT_DATA: begin
                if (iRM_readdatavalid) begin
                    texture_ns = T_WRITE_DATA;
                end
            end
            
            T_WRITE_DATA: begin
                if (!FF_rgb_almostfull) begin
                    texture_ns = T_WRITE_ID;
                end
            end
            
            T_WRITE_ID: begin
                if (!FF_rgb_almostfull) begin
                    texture_ns = T_IDLE;
                end
            end
        endcase
    end
    
    //=============================================================================
    // Memory Arbitration Logic
    //=============================================================================
    always_comb begin
        arb_ns = arb_cs;
        vertex_grant = 1'b0;
        texture_grant = 1'b0;
        
        case (arb_cs)
            ARB_IDLE: begin
                if (texture_req && vertex_req) begin
                    if (texture_priority) begin
                        arb_ns = ARB_TEXTURE;
                        texture_grant = 1'b1;
                    end else begin
                        arb_ns = ARB_VERTEX;
                        vertex_grant = 1'b1;
                    end
                end else if (texture_req) begin
                    arb_ns = ARB_TEXTURE;
                    texture_grant = 1'b1;
                end else if (vertex_req) begin
                    arb_ns = ARB_VERTEX;
                    vertex_grant = 1'b1;
                end
            end
            
            ARB_VERTEX: begin
                vertex_grant = 1'b1;
                if (!vertex_req) begin
                    arb_ns = ARB_IDLE;
                end
            end
            
            ARB_TEXTURE: begin
                texture_grant = 1'b1;
                if (!texture_req) begin
                    arb_ns = ARB_IDLE;
                end
            end
        endcase
    end
    
    //=============================================================================
    // Output Logic
    //=============================================================================
    
    // Memory interface outputs
    always_comb begin
        oRM_read = 1'b0;
        oRM_readaddress = 32'b0;
        oRM_burstcount = 4'b0;
        
        if (vertex_grant) begin
            if (vertex_cs == V_READ_LOOKAT) begin
                oRM_read = 1'b1;
                oRM_readaddress = vertex_address;
                oRM_burstcount = 4'b1; // Single word reads for lookat
            end else begin
                oRM_read = 1'b1;
                oRM_readaddress = vertex_address;
                oRM_burstcount = VERTEX_BURST_SIZE;
            end
        end else if (texture_grant) begin
            oRM_read = 1'b1;
            oRM_readaddress = {8'b0, texture_address}; // Extend to 32-bit
            oRM_burstcount = 4'b1; // Single read
        end
    end
    
    // CONTROL_MATRIX interface outputs
    logic [3:0] cm_send_count;
    
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            cm_send_count <= 4'b0;
        end else begin
            if (vertex_cs == V_SEND_LOOKAT) begin
                if (CM_lookat_ready && cm_send_count < 12) begin
                    cm_send_count <= cm_send_count + 1'b1;
                end
            end else begin
                cm_send_count <= 4'b0;
            end
        end
    end
    
    assign CM_lookat_data_valid = (vertex_cs == V_SEND_LOOKAT) && (cm_send_count < 12);
    assign CM_lookat_data = lookat_buffer[cm_send_count];
    
    // FIFO interface outputs
    assign FF_vertex_writerequest = (vertex_cs == V_WRITE_FIFO) && !FF_vertex_almostfull && iRM_readdatavalid;
    assign FF_vertex_data = iRM_readdata;
    
    assign FF_texture_readrequest = (texture_cs == T_READ_ADDR) && !FF_texture_empty;
    
    always_comb begin
        FF_rgb_writerequest = 1'b0;
        FF_rgb_data = 32'b0;
        
        if (texture_cs == T_WRITE_DATA && !FF_rgb_almostfull) begin
            FF_rgb_writerequest = 1'b1;
            FF_rgb_data = texture_data_reg;
        end else if (texture_cs == T_WRITE_ID && !FF_rgb_almostfull) begin
            FF_rgb_writerequest = 1'b1;
            FF_rgb_data = {24'b0, texture_core_id};
        end
    end
    
    // Control outputs
    assign RM_done = (vertex_cs == V_DONE);

endmodule