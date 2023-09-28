module master 
(
    input wire        sys_clk ,
    input wire        rst_n   ,
    input wire        valid_in,
    input wire        ready   ,

    output wire       valid   ,
    output wire [2:0]  data
);

wire [2:0] data_test [0:4];
reg [3:0] data_cnt;


always@(posedge sys_clk or negedge rst_n) 
    if(!rst_n)
        data_cnt <= 4'd0;
    else if(ready)
        data_cnt <= data_cnt + 1'b1;
    else if(data_cnt == 4'd4)
        data_cnt <= 4'd0;
    else
        data_cnt <= data_cnt;


assign {data_test[0], data_test[1], data_test[2], data_test[3], data_test[4]} = 
        {3'b111, 3'b101, 3'b110, 3'b001, 3'b101};

assign data = (valid_in && ready) ? data_test[data_cnt] : 3'd0;


assign valid = valid_in ; 

endmodule