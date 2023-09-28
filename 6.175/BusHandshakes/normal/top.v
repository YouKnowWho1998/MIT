module top 
(
    input wire        sys_clk   ,
    input wire        rst_n     ,
    input wire        valid_in  ,
    input wire        ready_in  ,

    output wire [2:0] result
);

wire ready;
wire valid;
wire [2:0] data;


slave inst_slave
(
    .sys_clk  (sys_clk),
    .data     (data),
    .valid    (valid),
    .ready_in (ready_in),

    .ready    (ready),
    .result   (result)
);


master inst_master
(
    .sys_clk (sys_clk),
    .rst_n   (rst_n)  ,
    .valid_in(valid_in),
    .ready   (ready),

    .valid   (valid),
    .data    (data)
);
endmodule