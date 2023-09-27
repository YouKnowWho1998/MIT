module master 
(
    input wire        sys_clk ,
    input wire        valid_in,
    input wire [2:0]   data_in ,
    input wire        ready   ,

    output wire       valid   ,
    output reg [2:0]  data 
);

always @(posedge sys_clk) 
    if(valid_in)
        data <= data_in;
    else 
        data <= 2'b0;

assign valid = valid_in ; 

endmodule