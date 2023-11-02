module top
(
    input wire        sys_clk,
    input wire        rst_n  ,
    input wire        valid_in,
    input wire        ready_in,

    output wire [2:0] result
);

wire       valid_up;
wire       valid_down;
wire       valid_middle;
wire       ready_down;
wire       ready_up;
wire       ready_middle;
wire [2:0] data_up;
wire [2:0] data_down;
wire [2:0] data_middle;


master inst_master
(
    .sys_clk (sys_clk),
    .rst_n   (rst_n),
    .ready_up(ready_up),

    .valid_up(valid_up),
    .data_up (data_up) 
);

pipe_valid inst_pipe_valid
(
    .sys_clk     (sys_clk),
    .rst_n       (rst_n),
    .valid_up    (valid_up),
    .data_up     (data_up),
    .ready_middle(ready_middle),

    .ready_up    (ready_up),
    .valid_middle(valid_middle),
    .data_middle (data_middle)
);

pipe_ready inst_pipe_ready
(
    .sys_clk      (sys_clk),
    .valid_middle (valid_middle),
    .data_middle  (data_middle),
    .ready_down   (ready_down),

    .ready_middle (ready_middle),
    .valid_down   (valid_down),
    .data_down    (data_down)
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