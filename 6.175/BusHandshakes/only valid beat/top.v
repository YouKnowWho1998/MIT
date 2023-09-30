module top
(
    input wire        sys_clk,
    input wire        rst_n,
    input wire        valid_in,
    input wire        ready_in,

    output wire [2:0] result
);

wire ready_down;
wire valid_up;
wire [2:0] data_up;


master inst_master
(
    .sys_clk (sys_clk),
    .rst_n   (rst_n),
    .valid_in(valid_in),
    .ready_up(ready_down),

    .valid_up(valid_up),
    .data_up(data_up)
);

slave inst_slave
(
    .sys_clk   (sys_clk),
    .rst_n     (rst_n),
    .ready_in  (ready_in),    
    .data_up   (data_up),
    .valid_up  (valid_up),

    .ready_down(ready_down),
    .result    (result)
);










endmodule