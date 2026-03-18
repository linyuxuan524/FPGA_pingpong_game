`timescale 1ns/1ps

module tb_pingpong_game_scoring;
    reg clk;
    reg rst_n;
    reg kd1;
    reg kd2;

    wire [7:0] led;
    wire [6:0] score1;
    wire [6:0] score2;
    wire beep;
    wire SI;
    wire RCK;
    wire SCK;
    wire seg_oe_n;
    wire dig_oe_n;

    // 100MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // 缩小参数，专门做仿真
    pingpong_game #(
        .BALL_STEP_CYCLES(20),
        .DEBOUNCE_CYCLES(3),
        .BEEP_CYCLES(20),
        .HOLD_UNIT_CYCLES(8),
        .SPEED_LEVEL_MAX(7),
        .MIN_CROSS_COUNT(2)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .kd1(kd1),
        .kd2(kd2),
        .led(led),
        .score1(score1),
        .score2(score2),
        .beep(beep),
        .SI(SI),
        .RCK(RCK),
        .SCK(SCK),
        .seg_oe_n(seg_oe_n),
        .dig_oe_n(dig_oe_n)
    );

    // 方便看内部状态
    wire running   = uut.running;
    wire dir       = uut.dir;
    wire [2:0] ball_pos = uut.ball_pos;
    wire flag_left  = uut.flag_left;
    wire flag_right = uut.flag_right;
    wire [63:0] frame_data = uut.u_seven_tube_drive.frame_data;

    // 串行捕获
    reg [63:0] cap_shift;
    reg [6:0]  cap_cnt;

    function [7:0] bitrev8;
        input [7:0] x;
        begin
            bitrev8 = {x[0],x[1],x[2],x[3],x[4],x[5],x[6],x[7]};
        end
    endfunction

    function [63:0] cap_to_frame;
        input [63:0] cap;
        begin
            cap_to_frame = {
                bitrev8(cap[7:0]),
                bitrev8(cap[15:8]),
                bitrev8(cap[23:16]),
                bitrev8(cap[31:24]),
                bitrev8(cap[39:32]),
                bitrev8(cap[47:40]),
                bitrev8(cap[55:48]),
                bitrev8(cap[63:56])
            };
        end
    endfunction

    task press_left_and_release;
        input integer hold_cycles;
        integer i;
        begin
            @(negedge clk);
            kd1 = 1'b0;
            for (i = 0; i < hold_cycles; i = i + 1)
                @(negedge clk);
            kd1 = 1'b1;
        end
    endtask

    task press_right_and_release;
        input integer hold_cycles;
        integer i;
        begin
            @(negedge clk);
            kd2 = 1'b0;
            for (i = 0; i < hold_cycles; i = i + 1)
                @(negedge clk);
            kd2 = 1'b1;
        end
    endtask

    task wait_latchs;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge RCK);
        end
    endtask

    task show_display;
        reg [63:0] recovered;
        begin
            recovered = cap_to_frame(cap_shift);
            $display("[DISPLAY t=%0t] score1=%0d score2=%0d frame=%h recov=%h",
                     $time, score1, score2, frame_data, recovered);
            $display("[FRAME bytes] D8=%02h D7=%02h D6=%02h D5=%02h D4=%02h D3=%02h D2=%02h D1=%02h",
                     frame_data[63:56], frame_data[55:48], frame_data[47:40], frame_data[39:32],
                     frame_data[31:24], frame_data[23:16], frame_data[15:8], frame_data[7:0]);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        kd1   = 1'b1;
        kd2   = 1'b1;
        cap_shift = 64'd0;
        cap_cnt   = 7'd0;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        $display("==== CASE1: left serve, right successful return ====");
        press_left_and_release(12);

        wait (running == 1'b1);
        $display("[RUNNING t=%0t] started dir=%0d ball_pos=%0d led=%b", $time, dir, ball_pos, led);

        // 提前按住右键，等球到最右端再松开，确保是“松开击球”
        wait (ball_pos == 3'd5 && dir == 1'b1 && running == 1'b1);
        @(negedge clk);
        kd2 = 1'b0;
        $display("[RIGHT HOLD t=%0t] kd2 down at pos=%0d led=%b", $time, ball_pos, led);

        wait (ball_pos == 3'd7 && dir == 1'b1 && running == 1'b1);
        @(negedge clk);
        kd2 = 1'b1;
        $display("[RIGHT RELEASE t=%0t] kd2 up at pos=%0d led=%b", $time, ball_pos, led);

        // 检查是否真的反向成功
        wait (dir == 1'b0 || running == 1'b0);
        if (running && dir == 1'b0)
            $display("[PASS] right return success at t=%0t, ball_pos=%0d led=%b", $time, ball_pos, led);
        else
            $display("[FAIL] right return failed at t=%0t, running=%b dir=%b score1=%0d score2=%0d", $time, running, dir, score1, score2);

        // 不再接左侧，让右侧这次回球最终造成一分，验证计分和数码管
        wait (score1 == 7'd1 || score2 == 7'd1);
        $display("[SCORE CHANGE t=%0t] score1=%0d score2=%0d led=%b running=%b", $time, score1, score2, led, running);
        wait_latchs(2);
        show_display();

        $display("FINAL: score1=%0d score2=%0d led=%b running=%b dir=%b ball_pos=%0d", score1, score2, led, running, dir, ball_pos);
        #200;
        $finish;
    end

    // 仿真超时保护：给更长时间，避免误杀
    initial begin
        #2_000_000;
        $display("[TIMEOUT t=%0t] simulation timeout", $time);
        $display("FINAL timeout: score1=%0d score2=%0d led=%b running=%b dir=%b ball_pos=%0d", score1, score2, led, running, dir, ball_pos);
        $finish;
    end

    always @(posedge clk) begin
        if (flag_left || flag_right) begin
            $display("[FLAG t=%0t] left=%b right=%b running=%b dir=%b pos=%0d holdL=%0d holdR=%0d",
                     $time, flag_left, flag_right, running, dir, ball_pos,
                     uut.hold_cycles_left, uut.hold_cycles_right);
        end
    end

    always @(posedge SCK) begin
        cap_shift <= {SI, cap_shift[63:1]};
        if (cap_cnt < 7'd64)
            cap_cnt <= cap_cnt + 1'b1;
    end

    always @(posedge RCK) begin
        $display("[LATCH t=%0t] score1=%0d score2=%0d seg_oe_n=%b dig_oe_n=%b cap_cnt=%0d frame=%h",
                 $time, score1, score2, seg_oe_n, dig_oe_n, cap_cnt, frame_data);
        cap_cnt <= 7'd0;
    end

endmodule
