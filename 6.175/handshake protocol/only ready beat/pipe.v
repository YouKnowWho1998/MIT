module pipe
(
    input wire        sys_clk   ,
    input wire        valid_up  ,
    input wire [2:0]  data_up   ,
    input wire        ready_down,

    output reg        ready_up  ,
    output wire       valid_down,
    output wire [2:0] data_down 
);

//=============================================================================================================

reg [2:0] buf_data;
wire      buf_valid; //skid buffer design


//=============================================================================================================

//buf_valid 当前级输入数据 后级不输出数据时将这个数据寄存到Buffer中
assign buf_valid = ready_up && ~ready_down;

//buf_data
always @(posedge sys_clk) begin
    buf_data = 'd0;
    if(buf_valid)
        buf_data <= data_up;
    else if(ready_down) //后级要输出数据 将buffer中的数据输出 清空buffer
        buf_data <= 'd0;
    else
        buf_data <= buf_data;
end

//valid_down
assign valid_down = valid_up || buf_valid;

//data_down 当前级不输入数据 后级要输出数据时将、Buffer中寄存的数据输出 之后恢复正常
assign data_down = (!ready_up && ready_down) ? buf_data : data_up;


//ready_up
always @(posedge sys_clk) begin
    ready_up <= ready_down;
end



endmodule