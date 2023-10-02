module master 
(
    input wire         sys_clk ,
    input wire         ready   ,

    output reg         valid   ,
    output wire [2:0]  data
);

wire [2:0] data_test [0:2];
reg [3:0] data_cnt;


//data_cnt
always@(posedge sys_clk) begin
    if(!valid)
        data_cnt <= 1'b0;
    else if(data_cnt == 'd0)
        data_cnt <= data_cnt;        
    else if(valid && ready)
        data_cnt <= data_cnt + 1'b1;    
    else if(valid && !ready)
        data_cnt <= data_cnt;
    else
        data_cnt <= 1'b0;
end


//data_test
assign {data_test[0], data_test[1], data_test[2]} = {3'b111, 3'b101, 3'b110};




//data
assign data = valid ? data_test[data_cnt] : 3'd0;


//valid
always@(posedge sys_clk) begin
    valid = 1'b0;
    if(ready)
        valid <= ready;
    else if(valid && ready && data_cnt == 'd2)
        valid <= 1'b0;
    else
        valid <= valid;
end



endmodule