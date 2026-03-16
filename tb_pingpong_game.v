`timescale 1ns/1ps

module tb_pingpong_game;
    reg         clk;
    reg         rst_n;
    reg         kd1;
    reg         kd2;
    wire [7:0]  led;
    wire [6:0]  score1;
    wire [6:0]  score2;
    wire        beep;
    wire [13:0] seven_segment;

    localparam integer BALL_STEP_CYCLES = 3;
    localparam integer DEBOUNCE_CYCLES  = 2;
    localparam integer BEEP_CYCLES      = 4;
    localparam integer HOLD_UNIT_CYCLES = 4;

    pingpong_game #(
        .BALL_STEP_CYCLES(BALL_STEP_CYCLES),
        .DEBOUNCE_CYCLES (DEBOUNCE_CYCLES),
        .BEEP_CYCLES     (BEEP_CYCLES),
        .HOLD_UNIT_CYCLES(HOLD_UNIT_CYCLES)
    ) uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .kd1          (kd1),
        .kd2          (kd2),
        .led          (led),
        .score1       (score1),
        .score2       (score2),
        .beep         (beep),
        .seven_segment(seven_segment)
    );

    always #10 clk = ~clk;

    task k1_charge_and_release;
        input integer hold_low_cycles;
        integer i;
        begin
            @(negedge clk);
            kd1 = 1'b0;
            for (i = 0; i < hold_low_cycles; i = i + 1)
                @(negedge clk);
            kd1 = 1'b1;
        end
    endtask

    task k2_charge_and_release;
        input integer hold_low_cycles;
        integer i;
        begin
            @(negedge clk);
            kd2 = 1'b0;
            for (i = 0; i < hold_low_cycles; i = i + 1)
                @(negedge clk);
            kd2 = 1'b1;
        end
    endtask

    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;
        kd1   = 1'b1;
        kd2   = 1'b1;

        #100;
        rst_n = 1'b1;
        #40;

        // 场景1：左侧长按发球，得到较高初速度
        k1_charge_and_release(24);

        // 右侧预先蓄力，在球到最右边时释放，实现回球
        wait (led == 8'b0100_0000);
        @(negedge clk);
        kd2 = 1'b0;
        repeat (12) @(negedge clk);
        wait (led == 8'b1000_0000);
        @(negedge clk);
        kd2 = 1'b1;

        // 场景2：左侧这次蓄力不足，只有当“本步后速度掉到0且仍未过线”时，才判不过线，右侧加1分
        wait (score2 == 7'd0);
        wait (led == 8'b0000_0001);
        @(posedge clk);
        k1_charge_and_release(3);
        wait (score2 == 7'd1);

        // 场景3：右侧故意提前释放，判提前击球，左侧加1分
        @(posedge clk);
        k2_charge_and_release(20);
        wait (led == 8'b0001_0000);
        k1_charge_and_release(2);
        wait (score1 == 7'd1);

        #200;
        $stop;
    end

    initial begin
        $monitor("t=%0t rst_n=%b kd1=%b kd2=%b led=%b score1=%0d score2=%0d beep=%b pos=%0d dir=%b run=%b speed=%0d travel=%0d holdL=%0d holdR=%0d",
                 $time, rst_n, kd1, kd2, led, score1, score2, beep,
                 uut.ball_pos, uut.dir, uut.running, uut.speed_level, uut.travel_count,
                 uut.hold_cycles_left, uut.hold_cycles_right);
    end
endmodule
