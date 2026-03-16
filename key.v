module key_processor #(
    parameter integer DEBOUNCE_CYCLES = 500_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        kd1,
    input  wire        kd2,
    output wire        flag_left,
    output wire        flag_right,
    output wire [31:0] hold_cycles_left,
    output wire [31:0] hold_cycles_right
);
    key_filter #(
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_key_filter_left (
        .clk        (clk),
        .rst_n      (rst_n),
        .key_n      (kd1),
        .flag       (flag_left),
        .hold_cycles(hold_cycles_left)
    );

    key_filter #(
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_key_filter_right (
        .clk        (clk),
        .rst_n      (rst_n),
        .key_n      (kd2),
        .flag       (flag_right),
        .hold_cycles(hold_cycles_right)
    );
endmodule


module key_filter #(
    parameter integer DEBOUNCE_CYCLES = 500_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_n,
    output wire        flag,
    output wire [31:0] hold_cycles
);
    localparam [1:0] S_IDLE      = 2'd0;
    localparam [1:0] S_DB_PRESS  = 2'd1;
    localparam [1:0] S_PRESSED   = 2'd2;
    localparam [1:0] S_WAIT_HIGH = 2'd3;

    reg        key_ff0;
    reg        key_ff1;
    reg [1:0]  state;
    reg [31:0] cnt;
    reg [31:0] hold_cnt;
    reg [31:0] hold_cycles_latched;

    wire key_pressed;
    wire key_released;
    wire release_event;

    assign key_pressed  = (key_ff1 == 1'b0);
    assign key_released = (key_ff1 == 1'b1);

    /*
     * 这里把 flag 做成组合事件信号：
     * 只要“已确认处于按下态 S_PRESSED”且“当前同步后的按键已经释放”，
     * flag 当拍就为 1。
     * 这样 pingpong_game 在同一个 clk 上升沿就能看到 flag，
     * 从而在检测到提前击球时当拍立刻 running<=0、LED 全灭并加分。
     */
    assign release_event = (state == S_PRESSED) && key_released;
    assign flag          = release_event;
    assign hold_cycles   = release_event ? hold_cnt : hold_cycles_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_ff0 <= 1'b1;
            key_ff1 <= 1'b1;
        end else begin
            key_ff0 <= key_n;
            key_ff1 <= key_ff0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= S_IDLE;
            cnt                 <= 32'd0;
            hold_cnt            <= 32'd0;
            hold_cycles_latched <= 32'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    cnt      <= 32'd0;
                    hold_cnt <= 32'd0;
                    if (key_pressed) begin
                        if (DEBOUNCE_CYCLES <= 1) begin
                            state    <= S_PRESSED;
                            hold_cnt <= 32'd0;
                        end else begin
                            state <= S_DB_PRESS;
                            cnt   <= 32'd1;
                        end
                    end
                end

                S_DB_PRESS: begin
                    if (key_pressed) begin
                        if (cnt >= DEBOUNCE_CYCLES - 1) begin
                            state    <= S_PRESSED;
                            cnt      <= 32'd0;
                            hold_cnt <= 32'd0;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end else begin
                        state <= S_IDLE;
                        cnt   <= 32'd0;
                    end
                end

                S_PRESSED: begin
                    if (key_pressed) begin
                        if (hold_cnt != 32'hffff_ffff)
                            hold_cnt <= hold_cnt + 1'b1;
                    end else begin
                        hold_cycles_latched <= hold_cnt;
                        state               <= S_WAIT_HIGH;
                        cnt                 <= 32'd0;
                    end
                end

                S_WAIT_HIGH: begin
                    if (key_released) begin
                        if ((DEBOUNCE_CYCLES <= 1) || (cnt >= DEBOUNCE_CYCLES - 1)) begin
                            state <= S_IDLE;
                            cnt   <= 32'd0;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end else begin
                        state <= S_PRESSED;
                        cnt <= 32'd0;
                    end
                end

                default: begin
                    state <= S_IDLE;
                    cnt   <= 32'd0;
                end
            endcase
        end
    end
endmodule
