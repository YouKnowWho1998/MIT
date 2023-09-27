module top 
(
    input wire      sys_clk   ,
    input wire [2:0] data_in   ,
    input wire      valid_in  ,
    input wire      ready_in  
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

    .ready    (ready)
);


master inst_master
(
    .sys_clk (sys_clk),
    .valid_in(valid_in),
    .data_in (data_in),
    .ready   (ready),

    .valid   (valid),
    .data    (data)
);
endmodule