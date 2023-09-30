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

reg [2:0] fifo_data;
reg       fifo_data_valid;

//=============================================================================================================
//fifo_design depth-1

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

assign data_down = fifo_data;

assign valid_down = fifo_data_valid;




endmodule