module pingpong_game #(
    parameter integer BALL_STEP_CYCLES = 3_000_000, //球移动一步所需的时钟周期数，决定基础速度
    parameter integer DEBOUNCE_CYCLES  = 500_000,   //按键消抖计数周期
    parameter integer BEEP_CYCLES      = 50_000_000, //蜂鸣器响持续时间
    parameter integer HOLD_UNIT_CYCLES = 2_000_000, //按键按住时间单位，用于计算速度等级
    parameter integer SPEED_LEVEL_MAX  = 7,
    parameter integer MIN_CROSS_COUNT  = 4          //最低速时球必须移动的最小次数，否则不过线
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        kd1,
    input  wire        kd2,
    output wire [7:0]  led,
    output reg  [6:0]  score1,
    output reg  [6:0]  score2,
    output wire        beep,
    output wire       SI,
    output wire       RCK,
    output wire       SCK,
    output wire       seg_oe_n,
    output wire       dig_oe_n
);
    wire        flag_left;
    wire        flag_right;
    wire [31:0] hold_cycles_left;
    wire [31:0] hold_cycles_right;

    reg         running; //游戏运行状态，1表示游戏中，0表示等待发球
    reg         dir;
    reg [2:0]   ball_pos;
    reg [3:0]   speed_level;
    reg [3:0]   travel_count; //上次击球后球移动的步数
    reg [31:0]  step_cnt;
    reg [31:0]  beep_cnt;
    reg         beep_start;
    reg         step_restart;
    reg         score_pause;
    reg [31:0]  score_pause_cnt;

    wire [31:0] current_step_cycles;
    wire        step_tick;
    wire [3:0]  travel_after_step;
    wire [3:0]  speed_after_step;
    wire        fail_to_cross_after_step;
    wire        key_enable;

    function [6:0] score_inc_sat;
        input [6:0] score_in;
        begin
            if (score_in < 7'd11)
                score_inc_sat = score_in + 7'd1;
            else
                score_inc_sat = score_in;
        end
    endfunction

    function [3:0] hold_to_speed; //将按住的周期数转换为速度等级
        input [31:0] hold_cycles_in;
        reg   [31:0] q;
        begin
            if (HOLD_UNIT_CYCLES <= 0) begin
                hold_to_speed = SPEED_LEVEL_MAX;
            end else begin
                q = hold_cycles_in / HOLD_UNIT_CYCLES;
                if (q >= (SPEED_LEVEL_MAX - 1))
                    hold_to_speed = SPEED_LEVEL_MAX;
                else
                    hold_to_speed = q[3:0] + 4'd1;
            end
        end
    endfunction

    function [31:0] speed_to_step_cycles; //将速度等级转换为步进所需的时钟周期数
        input [3:0] spd;
        reg   [31:0] factor;
        begin //速度越快，因子越小，步进周期越短，球移动越快
            if (spd >= SPEED_LEVEL_MAX)
                factor = 32'd1;
            else if (spd <= 4'd1)
                factor = SPEED_LEVEL_MAX;
            else
                factor = SPEED_LEVEL_MAX + 1 - spd;

            speed_to_step_cycles = BALL_STEP_CYCLES * factor;
        end
    endfunction

    assign current_step_cycles        = speed_to_step_cycles(speed_level);
    assign step_tick                  = running && (step_cnt >= current_step_cycles - 1'b1);
    assign travel_after_step          = travel_count + 1'b1;
    assign speed_after_step           = (speed_level > 4'd0) ? (speed_level - 1'b1) : 4'd0;
    assign fail_to_cross_after_step   = (speed_after_step < 4'd1) && (travel_after_step < MIN_CROSS_COUNT);
    assign led                        = running ? (8'b0000_0001 << ball_pos) : 8'b0000_0000;
    assign beep                       = (beep_cnt != 32'd0);
    assign key_enable                 = !score_pause;

    key_processor #(
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_key_processor (
        .clk              (clk),
        .rst_n            (rst_n),
        .enable           (key_enable),
        .kd1              (kd1),
        .kd2              (kd2),
        .flag_left        (flag_left),
        .flag_right       (flag_right),
        .hold_cycles_left (hold_cycles_left),
        .hold_cycles_right(hold_cycles_right)
    );

    seven_tube_drive u_seven_tube_drive (
    .clk      (clk),
    .rst_n    (rst_n),
    .left_num (score1),
    .right_num(score2),
    .SI       (SI),
    .RCK      (RCK),
    .SCK      (SCK),
    .seg_oe_n (seg_oe_n),
    .dig_oe_n (dig_oe_n)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step_cnt <= 32'd0;
        end else if (!running) begin
            step_cnt <= 32'd0;
        end else if (step_restart) begin
            step_cnt <= 32'd0;
        end else if (step_tick) begin
            // step_tick在running=1且step_cnt >= current_step_cycles - 1时产生，表示球应移动一格
            step_cnt <= 32'd0;
        end else begin
            // 否则每个时钟加1
            step_cnt <= step_cnt + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beep_cnt <= 32'd0;
        end else if (beep_start) begin
            if (BEEP_CYCLES > 0)
                beep_cnt <= BEEP_CYCLES;
            else
                beep_cnt <= 32'd0;
        end else if (beep_cnt != 32'd0) begin
            beep_cnt <= beep_cnt - 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running         <= 1'b0;
            dir             <= 1'b1;
            ball_pos        <= 3'd0;
            speed_level     <= 4'd0;
            travel_count    <= 4'd0;
            score1          <= 7'd0;
            score2          <= 7'd0;
            beep_start      <= 1'b0;
            step_restart    <= 1'b0;
            score_pause     <= 1'b0;
            score_pause_cnt <= 32'd0;
        end else begin
            beep_start   <= 1'b0;
            step_restart <= 1'b0;

            if (score_pause) begin
                if (score_pause_cnt >= 32'd49_999_999) begin
                    score_pause     <= 1'b0;
                    score_pause_cnt <= 32'd0;
                end else begin
                    score_pause_cnt <= score_pause_cnt + 1'b1;
                end
            end else begin
                score_pause_cnt <= 32'd0;
            end

            if (!running) begin
                travel_count <= 4'd0;
                speed_level  <= 4'd0;

                if (!score_pause) begin
                    if (flag_left) begin
                        running      <= 1'b1;
                        dir          <= 1'b1; //方向向右
                        ball_pos     <= 3'd0; //球在左端(0)
                        speed_level  <= hold_to_speed(hold_cycles_left);
                        travel_count <= 4'd0;
                        step_restart <= 1'b1;
                    end else if (flag_right) begin
                        running      <= 1'b1;
                        dir          <= 1'b0;
                        ball_pos     <= 3'd7;
                        speed_level  <= hold_to_speed(hold_cycles_right);
                        travel_count <= 4'd0;
                        step_restart <= 1'b1;
                    end
                end

            end else begin
                /*
                 * 回球时采用“按下蓄力、松开击球”的方式：
                 * - 释放得越晚，hold_cycles 越大，初速度越快
                 * - 若在本方底线到来之前提前释放，则判提前击球，对方得分
                 */
                if (dir && flag_right) begin
                    if (ball_pos == 3'd7) begin
                        dir          <= 1'b0;
                        ball_pos     <= 3'd6;
                        speed_level  <= hold_to_speed(hold_cycles_right);
                        travel_count <= 4'd0;
                        step_restart <= 1'b1;
                    end else begin //否则提前击球，左侧玩家得分，游戏停止，蜂鸣器响
                        score1          <= score_inc_sat(score1);
                        running         <= 1'b0;
                        score_pause     <= 1'b1;
                        score_pause_cnt <= 32'd0;
                        speed_level     <= 4'd0;
                        travel_count    <= 4'd0;
                        beep_start      <= 1'b1;
                    end
                end else if (!dir && flag_left) begin
                    if (ball_pos == 3'd0) begin
                        dir          <= 1'b1;
                        ball_pos     <= 3'd1;
                        speed_level  <= hold_to_speed(hold_cycles_left);
                        travel_count <= 4'd0;
                        step_restart <= 1'b1;
                    end else begin
                        score2          <= score_inc_sat(score2);
                        running         <= 1'b0;
                        score_pause     <= 1'b1;
                        score_pause_cnt <= 32'd0;
                        speed_level     <= 4'd0;
                        travel_count    <= 4'd0;
                        beep_start      <= 1'b1;
                    end
                end else if (step_tick) begin //步进事件
                    if (dir) begin
                        if (ball_pos < 3'd7) begin
                            ball_pos <= ball_pos + 1'b1; //球的位置加一

                            if (fail_to_cross_after_step) begin
                                score2          <= score_inc_sat(score2);
                                score_pause     <= 1'b1;
                                score_pause_cnt <= 32'd0;
                                running         <= 1'b0;
                                speed_level     <= 4'd0;
                                travel_count    <= travel_after_step;
                                beep_start      <= 1'b1;
                            end else begin //否则travel_count加一，若速度大于一则速度减一
                                travel_count <= travel_after_step;
                                if (speed_level > 4'd1)
                                    speed_level <= speed_level - 1'b1;
                                else
                                    speed_level <= 4'd1;
                            end
                        end else begin
                            score1          <= score_inc_sat(score1);
                            running         <= 1'b0;
                            score_pause     <= 1'b1;
                            score_pause_cnt <= 32'd0;
                            speed_level     <= 4'd0;
                            travel_count    <= 4'd0;
                            beep_start      <= 1'b1;
                        end
                    end else begin
                        if (ball_pos > 3'd0) begin
                            ball_pos <= ball_pos - 1'b1;

                            if (fail_to_cross_after_step) begin
                                score1          <= score_inc_sat(score1);
                                running         <= 1'b0;
                                score_pause     <= 1'b1;
                                score_pause_cnt <= 32'd0;
                                speed_level     <= 4'd0;
                                travel_count    <= travel_after_step;
                                beep_start      <= 1'b1;
                            end else begin
                                travel_count <= travel_after_step;
                                if (speed_level > 4'd1)
                                    speed_level <= speed_level - 1'b1;
                                else
                                    speed_level <= 4'd1;
                            end
                        end else begin
                            score2          <= score_inc_sat(score2);
                            running         <= 1'b0;
                            score_pause     <= 1'b1;
                            score_pause_cnt <= 32'd0;
                            speed_level     <= 4'd0;
                            travel_count    <= 4'd0;
                            beep_start      <= 1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule
