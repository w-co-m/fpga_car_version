// algo_bright.v —— 算法5 子模式①：亮度增强（mode = 0100）
// 【解决的问题】夜间/暗光：整体偏暗，细节埋在低灰度区。
// 【增益】沿用总线上的既有一根 thr_in[7:0]（不新增端口/引脚）：
//     thr_in = 16 → ×1.0（恒等）      32 → ×2.0     48 → ×3.0
//              8 → ×0.5              0 → 目标亮度Y为0（彩色输出还取决于通道差值与裁剪）
//   上板演示给 24~40（×1.5~×2.5）最直观；
//   要拨码/按键实时调：把顶层给 thr_in 的那根 wire 换成你的信号，
//   异步输入进 clk_pix 域前必须**打两拍同步**（按键再去抖），本模块不用改。
//
// 【输出】rgb_out = 增强后的彩色图（默认共同加减 Δ；未发生通道饱和时色差保持）；
//         y_out   = 增强后的亮度 Y'（给后续算法复用）；
//         bin_out = 饱和截断标志（1 = 本像素有通道被钉到 0/255）——可直接当"过曝告警"用。
// 【流水线】固定 3 拍，de/hs/vs 同延 3 拍（内部例化 algo_gray 2 拍 + 变换 1 拍）。
//=============================================================================
// 来源：算法5交付包原 wrapper，保留默认增益与 Δ 色差保持公式，仅改为 RGB888 输入。
// 流水延迟：灰度 2 级 + 变换/输出 1 级，总计 3 级；thr_in 与像素同拍对齐。
`timescale 1ns/1ps

module algo_bright #(
    parameter GRAY_MODE  = 0,       // 内部灰度权值模式（必须与上游一致）
    parameter BRIGHT_ADD = 0,       // 加性偏移 0~127（默认 0 = 纯乘性增益）
    parameter RGB_MODE   = 0        // 0 = Δ 色差保持（默认，1 个乘法器）；1 = 三通道各自乘增益
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [23:0] rgb_in,
    input  wire        de_in,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire [7:0]  thr_in,      // ★ Q4.4 亮度增益（16 = ×1.0）

    output wire [23:0] rgb_out,
    output wire [7:0]  y_out,
    output wire        bin_out,
    output wire        de_out,
    output wire        hs_out,
    output wire        vs_out
);

    algo_level #(
        .GRAY_MODE  (GRAY_MODE),
        .CENTER     (0),                // ★ 中心 = 0 ⇒ 保黑点的乘性增益 = 亮度增强
        .ADD        (BRIGHT_ADD),
        .GAIN_SHIFT (4),                // Q4.4：16 = ×1.0
        .RGB_MODE   (RGB_MODE)
    ) u_core (
        .clk     (clk),    .rst_n  (rst_n),
        .rgb_in  (rgb_in),
        .de_in   (de_in),  .hs_in  (hs_in), .vs_in (vs_in),
        .thr_in  (thr_in),
        .rgb_out (rgb_out),
        .y_out   (y_out),
        .bin_out (bin_out),
        .de_out  (de_out), .hs_out (hs_out), .vs_out (vs_out)
    );

endmodule

