module RAM (
    input              clk,
    input              reset_n,           // Reset t�ch c?c th?p

    // Read interface
    input              iRead,
    input      [31:0]  iAddress,       
    input      [7:0]   iBurstcount,   

    output reg [31:0]  oData,
    output reg         oWaitrequest,
    output reg         oDatavalid,

    // Write interface
    input              iWrite,
    input      [31:0]  iWriteaddress,
    input      [31:0]  iWritedata
);

    localparam MEM_DEPTH = 148549376;
    reg [31:0] memory [0:MEM_DEPTH-1];

    reg [23:0] burst_base_addr;
    reg [7:0]  burst_count;
    reg        burst_active;

    always @(posedge clk) begin
        if (!reset_n) begin
            oWaitrequest <= 0;
            oDatavalid   <= 0;
            oData        <= 0;
            burst_active <= 0;
            burst_count  <= 0;
        end else begin
            // Ghi d? li?u n?u c� iWrite
            if (iWrite) begin
                memory[iWriteaddress[25:2]] <= iWritedata;
            end

            // ??c d? li?u ki?u burst
            if (iRead && !burst_active && !oWaitrequest) begin
                burst_base_addr <= iAddress[25:2];  
                burst_count     <= iBurstcount;
                burst_active    <= 1;
                oWaitrequest    <= 1;  
                oDatavalid      <= 0;
            end

            if (burst_active) begin
                if (burst_count != 0) begin
                    oData        <= memory[burst_base_addr];
                    oDatavalid   <= 1;
                    burst_base_addr <= burst_base_addr + 1;
                    burst_count  <= burst_count - 1;
                end else begin
                    oDatavalid   <= 0;
                    oWaitrequest <= 0;
                    burst_active <= 0;
                end
            end else begin
                oDatavalid <= 0;
            end
        end
    end

endmodule

