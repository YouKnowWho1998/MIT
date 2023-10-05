module slave
(
    input wire          sys_clk   ,
    input wire          ready_in  ,    
    input wire [2:0]    data_down ,
    input wire          valid_down,

    output wire         ready_down,
    output wire [2:0]   result
);




assign result = (valid_down && ready_in) ? data_down : 3'b0;

assign ready_down = ready_in;

endmodule