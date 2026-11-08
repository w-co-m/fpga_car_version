// algo_level.v —— 线性变换内核（算法5 子模式①②共用：亮度增强 / 对比度增强）
// 亮度增强和对比度增强**是同一个线性变换**，只差一个"中心点"：
//     对比度：Y' = (Y - 128) * gain / 2^SHIFT + 128        ← 以中灰 128 为轴拉伸
//     亮度  ：Y' = (Y -   0) * gain / 2^SHIFT + 0 + ADD    ← 以黑点 0 为轴缩放（保黑点）
//   两者都能写成  Y' = sat( (Y - CENTER) * gain / 2^SHIFT + CENTER + ADD )
//   ⇒ 用同一个模块 + 参数 CENTER 区分（algo_bright.v 固定 CENTER=0，
//     algo_contrast.v 固定 CENTER=128），**只有一份真值来源**，
// thr_in[7:0] 复用为「增益」，Q4.4 定点：gain = thr_in / 16
//     thr_in = 8'd16  → ×1.0（恒等，锚点）
//     thr_in = 8'd32  → ×2.0
//     thr_in = 8'd8   → ×0.5
//     thr_in = 8'd48  → ×3.0
//     thr_in = 8'd0   → ×0.0（亮度目标0，对比度目标128，彩色通道仍按RGB_MODE恢复）
//   ★ 注意：顶层给算法3(二值化)的默认值 8'd128 对算法5 是 ×8 ⇒ 会全白。
//     上板演示算法5 时 thr_in 要给 16~48（见 交付说明 §3、§7）。
//
// 【溢出：饱和，不截断（不环绕）】
//   截断(取低 8 位)会把亮部直接翻回黑，画面上是刺眼的"黑洞"伪影；
//   饱和(钉在 0/255)只是丢高光细节，视觉上自然。所有通道统一饱和，
//   并将裁剪/负向零边界标志引到 bin_out（见下）。
//
// 【颜色怎么保：Δ 色差保持（默认，RGB_MODE=0）】
//   只算一个亮度映射 Y' = f(Y)，然后三通道**同加减** Δ = Y' - Y：
//       R' = sat(R + Δ)   G' = sat(G + Δ)   B' = sat(B + Δ)
//   ⇒ 不除法、不乘 3 次；未饱和时色差 (R-G, G-B) 不变；通道饱和时色差会变化。
//     中性灰像素 (R=G=B=Y) 恰好变成 (Y',Y',Y') ⇒ 亮度语义严格正确。
//     （对比之下"三通道各自乘 gain"会把饱和度一起放大、颜色变冲；
//      那版留着 RGB_MODE=1，代价是 4 个乘法器而不是 1 个。见文档 §3.1）
//
// 【位宽核算（算出来的，不是"应该够"）】
//   正支：(c-CENTER) ≤ 255，× gain ≤ 255*255 = 65025 ⇒ 16bit 不溢出；
//         >>4 后 ≤ 4064，+CENTER+ADD ≤ 4319 ⇒ 17bit 足够，饱和判据 v>255 一比较即可。
//   负支：v = CENTER+ADD - (t*gain>>4)，t ≤ 128 ⇒ t*gain ≤ 32640 ⇒ 15bit；
//         判 v<0 即饱和到 0。
//   Δ：|Δ| ≤ 255 ⇒ 9bit（符号+幅度分开表示，全程无符号算术 ⇒ TD 不会踩有符号坑）
//
// 【流水线：固定 3 拍】de/hs/vs 与像素**同延 3 拍**（灰度 2 + 变换/输出 1）
//   thr_in 延 2 拍（= 总延时-1），到变换那一级才与像素相遇（与算法3/4 同一纪律）。
//=============================================================================
// 来源：算法5交付包 algo_level 核心，保持原线性变换公式，改接工程 RGB888 灰度接口。
// 流水延迟：灰度 2 级 + 变换/输出 1 级，共 3 级，thr_in 与对应像素对齐。
`timescale 1ns/1ps

module algo_level #(
    parameter GRAY_MODE  = 0,       // 内部灰度权值模式（见 algo_gray.v）
    parameter CENTER     = 0,       // 0 = 亮度增强；128 = 对比度增强
    parameter ADD        = 0,       // 加性偏移（0~127，编译期；默认 0）
    parameter GAIN_SHIFT = 4,       // 增益定点：gain = thr_in / 2^GAIN_SHIFT
    parameter RGB_MODE   = 0        // 0 = Δ 色差保持（默认，1 个乘法器）；1 = 三通道各自乘 gain
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [23:0] rgb_in,
    input  wire        de_in,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire [7:0]  thr_in,      // ★ Q4.4 增益（16 = ×1.0）

    output reg  [23:0] rgb_out,
    output reg  [7:0]  y_out,
    output reg         bin_out,     // ★ 本算法族无阈值语义 ⇒ 复用为「裁剪或亮度触及负向0边界标志」
    output reg         de_out,
    output reg         hs_out,
    output reg         vs_out
);

    localparam [7:0]  C8   = CENTER;            // 中心点（0 或 128）
    localparam [15:0] CADD = CENTER + ADD;      // 中心 + 偏移（≥0）

    //---------------- RGB888 拆分（接口与现有 RGB888 版 algo_gray 一致）----------------
    wire [7:0] r8 = rgb_in[23:16];
    wire [7:0] g8 = rgb_in[15:8];
    wire [7:0] b8 = rgb_in[7:0];

    //---------------- 灰度（例化算法2，2 拍）----------------
    wire [7:0]  y_g;
    wire        de_g, hs_g, vs_g;
    wire [23:0] rgb_g_unused;

    algo_gray #(.GRAY_MODE (GRAY_MODE)) u_gray (
        .clk     (clk),    .rst_n  (rst_n),
        .rgb_in  (rgb_in),
        .de_in   (de_in),  .hs_in  (hs_in), .vs_in (vs_in),
        .rgb_out (rgb_g_unused),
        .y_out   (y_g),
        .de_out  (de_g),   .hs_out (hs_g),  .vs_out (vs_g)
    );

    //---------------- 增益流水（延 2 拍 = 总延时 3 − 1）----------------
    reg [7:0] thr_s1, thr_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin thr_s1 <= 8'd0; thr_s2 <= 8'd0; end
        else        begin thr_s1 <= thr_in; thr_s2 <= thr_s1; end
    end

    //---------------- 单通道线性变换（组合；全程无符号算术）----------------
    //   返回 {裁剪/负向0边界标志, 结果}；沿用原包v>=CADD的边界语义
    function [8:0] xform;
        input [7:0] c;
        input [7:0] g;
        reg [15:0] t, p;
        reg [17:0] v, w;
        begin
            if (CENTER == 0) begin
                p = c * g;                                  // ≤ 65025 ⇒ 16bit
                v = (p >> GAIN_SHIFT) + CADD;
                xform = (v > 18'd255) ? {1'b1, 8'hFF} : {1'b0, v[7:0]};
            end else begin
                if (c >= C8) begin                          // 正支：向上拉伸
                    t = c - C8;
                    p = t * g;
                    v = (p >> GAIN_SHIFT) + CADD;
                    xform = (v > 18'd255) ? {1'b1, 8'hFF} : {1'b0, v[7:0]};
                end else begin                              // 负支：向下压
                    t = C8 - c;
                    p = t * g;
                    v = p >> GAIN_SHIFT;
                    w = (v >= CADD) ? 18'd0 : (CADD - v);
                    xform = (v >= CADD) ? {1'b1, 8'h00} : {1'b0, w[7:0]};
                end
            end
        end
    endfunction

    //---------------- 通道加常量偏移（用于 Δ 色差保持路径）----------------
    function [8:0] dadd;
        input [7:0] c;
        input       sgn;        // 1 = 减
        input [7:0] mag;        // 幅度
        reg [8:0]   v;
        begin
            if (sgn) dadd = (mag > c) ? {1'b1, 8'h00} : {1'b0, (c - mag)};
            else begin
                v = {1'b0, c} + mag;
                dadd = (v > 9'd255) ? {1'b1, 8'hFF} : {1'b0, v[7:0]};
            end
        end
    endfunction

    //---------------- 通道延迟 2 拍（第 3 拍与 Y' 同拍）----------------
    reg [7:0] r8a, g8a, b8a;        // 第 1 拍
    reg [7:0] r8b, g8b, b8b;        // 第 2 拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r8a <= 8'd0; g8a <= 8'd0; b8a <= 8'd0;
            r8b <= 8'd0; g8b <= 8'd0; b8b <= 8'd0;
        end else begin
            r8a <= r8; g8a <= g8; b8a <= b8;
            r8b <= r8a; g8b <= g8a; b8b <= b8a;
        end
    end

    //---------------- 第 3 拍：变换 + 色差保持 + 输出登记 ----------------
    wire [8:0] yx  = xform(y_g, thr_s2);        // {饱和, Y'}
    wire [7:0] yp  = yx[7:0];
    wire       ycl = yx[8];

    wire       dsgn = (y_g > yp);               // Δ = yp - y_g
    wire [7:0] dmag = dsgn ? (y_g - yp) : (yp - y_g);

    wire [8:0] rx = (RGB_MODE == 0) ? dadd(r8b, dsgn, dmag) : xform(r8b, thr_s2);
    wire [8:0] gx = (RGB_MODE == 0) ? dadd(g8b, dsgn, dmag) : xform(g8b, thr_s2);
    wire [8:0] bx = (RGB_MODE == 0) ? dadd(b8b, dsgn, dmag) : xform(b8b, thr_s2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb_out <= 24'd0;
            y_out   <= 8'd0;
            bin_out <= 1'b0;
            de_out  <= 1'b0;
            hs_out  <= 1'b0;
            vs_out  <= 1'b0;
        end else begin
            y_out   <= yp;
            rgb_out <= {rx[7:0], gx[7:0], bx[7:0]};
            bin_out <= ycl | rx[8] | gx[8] | bx[8];     // 饱和截断标志
            de_out  <= de_g;
            hs_out  <= hs_g;
            vs_out  <= vs_g;
        end
    end

endmodule

