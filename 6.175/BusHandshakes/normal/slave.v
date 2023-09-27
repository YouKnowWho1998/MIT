module slave
(
    input wire      sys_clk  ,
    input wire [2:0] data     ,
    input wire      valid    ,
    input wire      ready_in ,

    output wire     ready
);

reg [7:0] result;

always @(posedge sys_clk) 
    if(valid && ready_in)
        result <= data;
    else 
        result <= 'b0;

assign ready = ready_in;

endmodule