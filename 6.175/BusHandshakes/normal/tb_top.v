`timescale 1ns/1ns
module tb_top();

reg        sys_clk;
reg        valid_in;
reg        ready_in;
wire [2:0] result;



always #10 sys_clk = ~sys_clk; //生成50MHZ 20ns的时钟信号

initial begin
    sys_clk = 1'b1;
end

initial begin
    valid_in <= 1'b0;
    #20
    valid_in <= 1'b1;
    #60
    valid_in <= 1'b0;
end


top inst_top
(
    .sys_clk   (sys_clk),
    .valid_in  (valid_in),
    .ready_in  (ready_in),

    .result    (result)
);

endmodule