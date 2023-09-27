`timescale 1ns/1ns
module tb_top();

reg       sys_clk;
reg [2:0] data_in;
reg       valid_in;
reg       ready_in;


always #10 sys_clk = ~sys_clk; //生成50MHZ 20ns的时钟信号

initial begin
    sys_clk = 1'b1;
end

initial begin
    data_in= 2'b11;
    #20
    data_in= 2'b10;    
    #20
    data_in= 2'b11;  
    #20
    data_in= 2'b11;  
    #20
    data_in= 2'b01;
    #20
    data_in= 2'b10;
    #20
    data_in= 2'b11;
end    

initial begin
    valid_in = 1'b0;
    ready_in = 1'b0;
    #20
    valid_in = 1'b1;
    ready_in = 1'b1;
    #100
    valid_in = 1'b0;
    ready_in = 1'b0;
end


top inst_top
(
    .sys_clk   (sys_clk),
    .data_in   (data_in),
    .valid_in  (valid_in),
    .ready_in  (ready_in)
);



endmodule