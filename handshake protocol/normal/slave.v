module slave
(
    input wire          sys_clk  ,
    input wire [2:0]    data     ,
    input wire          valid    ,
    input wire          ready_in ,

    output wire         ready    ,
    output wire [2:0]   result
);

assign result = (valid && ready_in) ? data : 3'd0;

assign ready = ready_in;

endmodule