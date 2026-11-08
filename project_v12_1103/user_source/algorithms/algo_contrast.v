// algo_contrast.v —— 算法5 子模式②：对比度增强（mode = 0101）
// 【解决的问题】目标和背景灰度接近（低对比度），边界看不清。
// 【方案：以中灰 128 为轴的线性拉伸】
//       Y' = sat( (Y - 128) * gain / 16 + 128 )
//  128 为轴：128 是 8bit 灰度的中点，拉伸时把中灰固定、亮部更亮暗部更暗，
//   整体平均亮度不变（画面不会整体变亮变暗，只"变冲"）。
// 【增益范围与量化】thr_in[7:0] = Q4.4 增益（16 = ×1.0）：
//     thr_in = 16 → ×1.0（恒等，锚点）
//              20 → ×1.25     24 → ×1.5      32 → ×2.0      48 → ×3.0
//              0  → ×0.0（全部压到中灰 128 附近 ⇒ 整幅变灰，可用于反向演示）
//    推荐演示给 24~32；
//    范围取 0~15.9（Q4.4 而不是 Q3.5）：×2.0 是常用档，Q4.4 里 32 整除无误差；
//    再大的增益（×4 以上）对 8bit 图像没有意义（一步就饱和）。
//    定点化位宽：8bit 增益 × 8bit 灰度 = 16bit 乘积，右移 4 位后 12bit，
//    与位宽核算一致（见 algo_level.v 头注释），无中间溢出。
//
// 【与亮度增强的关系：能合并，已经合并了】
//   两者都是 Y' = sat( (Y - CENTER) * gain / 2^SHIFT + CENTER + ADD )：
//     CENTER = 0   → 亮度增强（保黑点）
//     CENTER = 128 → 对比度增强（保中灰）
//   本文件与 algo_bright.v 都是 **algo_level.v 的一行例化**（只差 CENTER/ADD 两个参数），
//   综合出来的逻辑各自独立、可单独演示，但真值来源只有一份。
//
// 【输出/延时】与 algo_bright 完全一致：rgb 彩色（未发生通道饱和时 Δ 色差保持）+ y_out + bin_out(饱和标志)；
//   固定 3 拍，de/hs/vs 同延 3 拍。
//=============================================================================
// 来源：算法5交付包原 wrapper，保留默认增益与 Δ 色差保持公式，仅改为 RGB888 输入。
// 流水延迟：灰度 2 级 + 变换/输出 1 级，总计 3 级；thr_in 与像素同拍对齐。
`timescale 1ns/1ps

module algo_contrast #(
    parameter GRAY_MODE    = 0,
    parameter CONTRAST_ADD = 0,     // 加性偏移 0~127（默认 0；>0 = 拉完再整体提亮）
    parameter RGB_MODE     = 0      // 0 = Δ 色差保持（默认）；1 = 三通道各自乘增益
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [23:0] rgb_in,
    input  wire        de_in,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire [7:0]  thr_in,      // ★ Q4.4 对比度增益（16 = ×1.0）

    output wire [23:0] rgb_out,
    output wire [7:0]  y_out,
    output wire        bin_out,
    output wire        de_out,
    output wire        hs_out,
    output wire        vs_out
);

    algo_level #(
        .GRAY_MODE  (GRAY_MODE),
        .CENTER     (128),              // ★ 中心 = 128 ⇒ 以中灰为轴拉伸 = 对比度增强
        .ADD        (CONTRAST_ADD),
        .GAIN_SHIFT (4),
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
