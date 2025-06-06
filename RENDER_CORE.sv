module RENDER_CORE #(
    parameter CORE_ID = 7'd0
)(
    input logic clk,
    input logic rst_n,
    
	 //interface arbiter vertex
	 input logic [31:0] vertex_data,          
    input logic [6:0] target_core_id,        
     logic vertex_valid,                
    input logic [86:0] vertex_request,         
    input logic [86:0] vertex_read_done      
);
    

endmodule
