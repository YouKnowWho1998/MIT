module master 
(
    input wire        sys_clk ,
    input wire        valid_in,
    input wire        ready_up,

    output wire       valid_up,
    output wire [2:0] data_up
);

wire [2:0] data_test [0:2];
reg [2:0]  data_cnt;

assign {data_test[0], data_test[1], data_test[2]} = {3'b111, 3'b101, 3'b110};



//data_cnt
always@(posedge sys_clk) begin
    if(!valid_in)
        data_cnt <= 'd0;
    else if(valid_in && ready_up)
        data_cnt <= data_cnt + 1'b1;
    else if(valid_in && !ready_up)
        data_cnt <= data_cnt;
    else if(data_cnt == 'd2)
        data_cnt <= 'd0;
    else
        data_cnt <= 'd0;
end


assign data_up = valid_in ? data_test[data_cnt] : 3'd0;


assign valid_up = valid_in ; 

endmodule