module slave
(
    input wire          sys_clk   ,
    input wire          rst_n     ,
    input wire          ready_in  ,    
    input wire [2:0]    data_up   ,
    input wire          valid_up  ,

    output wire         ready_down,
    output wire [2:0]   result
);

reg       valid_down;
reg [2:0] data_down;
wire      ready_up;


//valid_down
always@(posedge sys_clk or negedge rst_n)
    if(!rst_n)  
        valid_down <= 1'b0;                                                  
    else 
        valid_down <= ready_up ? valid_up : valid_down;


//data_down
always@(posedge sys_clk or negedge rst_n)
    if(!rst_n)  
        data_down <= 3'b0;
    else
        data_down <= (valid_up && ready_up) ? data_up : data_down;


//ready_up
assign ready_up = ready_in || ~valid_down;



assign result = (valid_down && ready_in) ? data_down : 3'b0;

assign ready_down = ready_up;

endmodule