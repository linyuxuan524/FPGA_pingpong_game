module seven_tube_drive #(
    parameter integer CLK_FREQ_HZ   = 100_000_000,
    parameter integer SHIFT_TICK_HZ = 200_000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [6:0] left_num,
    input  wire [6:0] right_num,

    output reg        SI,
    output reg        RCK,
    output reg        SCK,
    output wire       seg_oe_n,   // 对应 595OE，低有效
    output wire       dig_oe_n    // 数码位使能
);

    // ----------------------------
    // 1. 分数拆成十位/个位
    // ----------------------------
    wire [3:0] left_tens;
    wire [3:0] left_ones;
    wire [3:0] right_tens;
    wire [3:0] right_ones;

    assign left_tens  = (left_num  >= 7'd10) ? (left_num  / 10) : 4'hF;
    assign left_ones  = left_num  % 10;
    assign right_tens = (right_num >= 7'd10) ? (right_num / 10) : 4'hF;
    assign right_ones = right_num % 10;

    // ----------------------------
    // 2. 6位显示内容
    //    从左到右：左十 左个 - - 右十 右个
    //    对应老师例程常见习惯：
    //    D6 D5 D4 D3 D2 D1
    // ----------------------------
    wire [7:0] seg_d1; // 最右：右个位
    wire [7:0] seg_d2; // 右十位
    wire [7:0] seg_d3; // -
    wire [7:0] seg_d4; // -
    wire [7:0] seg_d5; // 左个位
    wire [7:0] seg_d6; // 左十位
    wire [7:0] seg_d7; // 空白
    wire [7:0] seg_d8; // 空白

    seg7_cc_encoder u_enc_d1 (.data(right_ones), .seg(seg_d1));
    seg7_cc_encoder u_enc_d2 (.data(right_tens), .seg(seg_d2));
    seg7_cc_encoder u_enc_d3 (.data(4'hA),      .seg(seg_d3)); // '-'
    seg7_cc_encoder u_enc_d4 (.data(4'hA),      .seg(seg_d4)); // '-'
    seg7_cc_encoder u_enc_d5 (.data(left_ones), .seg(seg_d5));
    seg7_cc_encoder u_enc_d6 (.data(left_tens), .seg(seg_d6));
    seg7_cc_encoder u_enc_d7 (.data(4'hF),      .seg(seg_d7)); // blank
    seg7_cc_encoder u_enc_d8 (.data(4'hF),      .seg(seg_d8)); // blank

    // ----------------------------
    // 3. 拼成64位数据
    // 老师例程里每位是8bit段码，8位总共64bit
    // D1 在最低8位，D8 在最高8位
    // ----------------------------
    wire [63:0] frame_data;
    assign frame_data = {
        seg_d8, seg_d7, seg_d6, seg_d5,
        seg_d4, seg_d3, seg_d2, seg_d1
    };

    // ----------------------------
    // 4. 时钟分频，产生移位节拍
    // ----------------------------
    localparam integer SHIFT_DIV = (CLK_FREQ_HZ / SHIFT_TICK_HZ);
    localparam [2:0] ST_LOAD  = 3'd0;
    localparam [2:0] ST_SCK_L = 3'd1;
    localparam [2:0] ST_SCK_H = 3'd2;
    localparam [2:0] ST_LATCH = 3'd3;

    reg [31:0] div_cnt;
    reg        tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 32'd0;
            tick    <= 1'b0;
        end else begin
            if (div_cnt >= SHIFT_DIV - 1) begin
                div_cnt <= 32'd0;
                tick    <= 1'b1;
            end else begin
                div_cnt <= div_cnt + 1'b1;
                tick    <= 1'b0;
            end
        end
    end

    // ----------------------------
    // 5. 64位移位发送到 595
    // ----------------------------
    reg [2:0]  state;
    reg [63:0] shreg;
    reg [6:0]  bit_cnt;

    assign seg_oe_n = 1'b0; // 595OE 低有效，常开
    assign dig_oe_n = 1'b1; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= ST_LOAD;
            shreg   <= 64'd0;
            bit_cnt <= 7'd0;
            SI      <= 1'b0;
            SCK     <= 1'b0;
            RCK     <= 1'b0;
        end else if (tick) begin
            case (state)
                ST_LOAD: begin
                    shreg   <= frame_data;
                    bit_cnt <= 7'd64;
                    SI      <= frame_data[0];
                    SCK     <= 1'b0;
                    RCK     <= 1'b0;
                    state   <= ST_SCK_H;
                end

                ST_SCK_H: begin
                    SCK   <= 1'b1;   // 送出当前 SI
                    RCK   <= 1'b0;
                    state <= ST_SCK_L;
                end

                ST_SCK_L: begin
                    SCK <= 1'b0;
                    RCK <= 1'b0;

                    shreg <= {1'b0, shreg[63:1]};
                    bit_cnt <= bit_cnt - 1'b1;

                    if (bit_cnt == 7'd1) begin
                        SI    <= 1'b0;
                        state <= ST_LATCH;
                    end else begin
                        SI    <= shreg[1];
                        state <= ST_SCK_H;
                    end
                end

                ST_LATCH: begin
                    RCK   <= 1'b1;   // 锁存到 595 输出
                    SCK   <= 1'b0;
                    SI    <= 1'b0;
                    state <= ST_LOAD;
                end

                default: begin
                    state <= ST_LOAD;
                end
            endcase
        end else begin
            // 让 RCK 只保持一个 tick 宽度
            if (state != ST_LATCH)
                RCK <= 1'b0;
        end
    end

endmodule


// ======================================================
// 共阴数码管编码器：高电平点亮
// seg = {a,b,c,d,e,f,g,dp}
// 4'hA -> '-'
// 4'hF -> blank
// 编码风格与老师给的 DELED.vhd 一致
// ======================================================
module seg7_cc_encoder (
    input  wire [3:0] data,
    output reg  [7:0] seg
);
    always @(*) begin
        case (data)
            4'h0: seg = 8'b11111100;
            4'h1: seg = 8'b01100000;
            4'h2: seg = 8'b11011010;
            4'h3: seg = 8'b11110010;
            4'h4: seg = 8'b01100110;
            4'h5: seg = 8'b10110110;
            4'h6: seg = 8'b10111110;
            4'h7: seg = 8'b11100000;
            4'h8: seg = 8'b11111110;
            4'h9: seg = 8'b11110110;
            4'hA: seg = 8'b00000010; // 只亮 g 段，显示 '-'
            4'hF: seg = 8'b00000000;
            default: seg = 8'b00000000;
        endcase
    end
endmodule


