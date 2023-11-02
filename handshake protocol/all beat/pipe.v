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

/*
reg [2:0] fifo_data;
reg       fifo_data_valid;*/

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


//data_down 当前级不输入数据 后级要输出数据时将、Buffer中寄存的数据输出 之后恢复正常
assign data_down = ((!ready_up && ready_down) || (ready_up && valid_up)) ? buf_data : data_up;


//ready_up
always @(posedge sys_clk) begin
    ready_up <= ready_down || ~valid_down;
end


//valid_down
always@(posedge sys_clk or negedge rst_n) begin
    if(!rst_n)
        valid_down <= 1'b0;
    else
        valid_down <= ready_up ? (valid_up || buf_valid) : valid_down;
end


/*//fifo_design depth-1

always @(posedge sys_clk) begin
    fifo_data_valid = 1'b0;
    fifo_data = 3'd0;
    ready_up <= ready_down;
    if(ready_up && valid_up) begin //当fifo允许传入数据时 fifo传入数据并将其标志信号拉高
        fifo_data_valid <= valid_up;
        fifo_data <= data_up;
    end else if(valid_down && ready_down) begin //当fifo不允许传入数据而允许传出数据时 fifo数据向后级传出
        fifo_data_valid <= 1'b0;                 //并将其标志信号拉低 代表fifo内部排空了数据
        fifo_data <= 3'd0;
    end else begin
        fifo_data_valid <= fifo_data_valid;
        fifo_data <= fifo_data;
    end
end


//挤出气泡
always@ (posedge sys_clk) begin
    ready_up <= (ready_down || ((~(valid_up && ready_up)) && ~fifo_data_valid));
end
// 1.当后级要传出数据时 2.前级不传入数据 && FIFO内部无数据
// 可以拉高ready信号一周期 将空FIFO利用起来存入一个数据


assign data_down = fifo_data;

assign valid_down = fifo_data_valid;

*///=============================================================================================================
/* 思考：

    FIFO设计的特点：(depth为1)
        1.FIFO在ready_down为0，ready_up为1时暂存一个数据。
        2.在ready_down由低电平到高电平的这个周期，首先将FIFO内部数据输出。
        3.如果ready_down继续为高电平，则FIFO将直通。
        4.如果ready_down信号拉低电平超过1周期，则某些情况下必须要使用深度2的FIFO才可满足设计。(见示意图)

    skid buffer设计的特点：
        1.和深度1的FIFO设计类似，本质上都是一级寄存器。
        2.当ready_down为低电平，valid_up和ready_up为高电平时buffer存入一个数据，同时在ready_down拉
        回高电平时首先输出buffer中的数据。
        3.之后ready_up再为高电平时，数据可以直接传输至后级，因为此时buffer中的数据已经传出。(类似于fifo直通)

*/
//=============================================================================================================



endmodule