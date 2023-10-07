module master 
(
    input wire        sys_clk ,
    input wire        rst_n   ,
    input wire        ready_up,

    output reg        valid_up,
    output wire [2:0] data_up
);

wire [2:0] data_test [0:2];
reg [2:0]  data_cnt;
reg        ready_up_master;


assign {data_test[0], data_test[1], data_test[2]} = {3'b111, 3'b101, 3'b110};


//data_cnt
always@(posedge sys_clk) begin
    if(!valid_up)
        data_cnt <= 'd0;
    else if(data_cnt == 'd2 && ready_up && valid_up)
        data_cnt <= 'd0;        
    else if(valid_up && ready_up)
        data_cnt <= data_cnt + 1'b1;
    else if(valid_up && !ready_up)
        data_cnt <= data_cnt;         
    else
        data_cnt <= 'd0;
end



//valid_up
always@(posedge sys_clk or negedge rst_n) begin
    if(!rst_n)
        valid_up <= 1'b0;
    else if(valid_up && ready_up_master && (data_cnt == 'd2))
        valid_up <= 1'b0;          
    else if(ready_up_master)
        valid_up <= 1'b1;
    else if(!ready_up_master)
        valid_up <= valid_up;
end


always @(posedge sys_clk or negedge rst_n) begin
    if(!rst_n)
        ready_up_master <= 1'b0;
    else
        ready_up_master <= ready_up;
end


assign data_up = valid_up ? data_test[data_cnt] : 3'd0;




endmodule