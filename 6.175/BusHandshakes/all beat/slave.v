module slave
(
    input wire          sys_clk   ,
    input wire          ready_in  ,
    input wire          valid_down,
    input wire [2:0]    data_down ,


    output wire         ready_down,
    output wire [2:0]   result
);





//result
assign result =  (valid_down && ready_in) ? data_down : 3'b0;

//ready_down
assign ready_down = ready_in;

endmodule