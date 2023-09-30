module top
(
    input wire        sys_clk,
    input wire        valid_in,
    input wire        ready_in,

    output wire [2:0] result
);

wire       valid_up;
wire       valid_down;
wire       ready_down;
wire       ready_up;
wire [2:0] data_up;
wire [2:0] data_down;


master inst_master
(
    .sys_clk (sys_clk),
    .valid_in(valid_in),
    .ready_up(ready_up),

    .valid_up(valid_up),
    .data_up (data_up) 
);


pipe inst_pipe
(
    .sys_clk   (sys_clk),
    .valid_up  (valid_up),
    .data_up   (data_up),
    .ready_down(ready_down),

    .ready_up  (ready_up),
    .valid_down(valid_down),
    .data_down (data_down)
);


slave inst_slave
(
    .sys_clk   (sys_clk),
    .ready_in  (ready_in),
    .valid_down(valid_down),
    .data_down (data_down),


    .ready_down(ready_down),
    .result    (result)
);


endmodule