module pipe
(
    input wire        sys_clk   ,
    input wire        rst_n     ,
    input wire        valid_up  ,
    input wire [2:0]  data_up   ,
    input wire        ready_down,

    output wire       ready_up  ,
    output reg        valid_down,
    output reg [2:0]  data_down 
);



//valid_down
always@(posedge sys_clk or negedge rst_n) begin
    if(!rst_n)
        valid_down <= 1'b0;
    else
        valid_down <= ready_up ? valid_up : valid_down;
end


//data_down
always@(posedge sys_clk or negedge rst_n) begin
    if(!rst_n)
        data_down <= 'd0;
    else
        data_down <= (ready_up && valid_up) ? data_up : data_down;
end

//ready_up
assign ready_up = ready_down || ~valid_down;



endmodule