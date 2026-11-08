//=============================================================================
// 算法9：偏振辅助边缘检测（mode 12）
// 输入来自 DDR 读出的极化核心像素流：polar_core 25 级输出 y 与 DoLP 同拍。
// y_in=(i0+i90)>>1；Y 与 DoLP 两路分别计算 Sobel G8。
// vin 可连续 16 个像素后停顿任意长度；空白期间行列状态保持，HS 标记行首。
// 使用 G8=(|Gx|+|Gy|)>>3，公式与普通 Sobel 同定标，但输入量不同，不承诺逐像素相同。
// polar_core 25 级 + 本模块 3 级 = 28 级。默认加权融合后饱和到 255 再比较阈值。
// W_DOLP=0 时 weighted 模式仍执行权重公式；需要纯 Y 边缘时设置 EDGE_MODE=0。
//=============================================================================
`timescale 1ns/1ps

module algo_edge_polar #(
    parameter EDGE_MODE = 1,        // 0 = 仅 Sobel(亮度)；1 = 亮度 + DoLP 双路融合（默认）
    parameter FUSE_MODE = 0,        // 0 = 加权和（推荐）；1 = 取最大
    parameter W_RGB     = 8'd192,   // 融合权重（编译期；建议和 ≈ 256）
    parameter W_DOLP    = 8'd64,    // weighted 模式按公式使用；纯 Y 边缘请设 EDGE_MODE=0
    parameter EDGE_INV  = 0,        // 1 = 反色输出
    parameter BORDER    = 1,        // 1 = 复制边缘（默认，推荐）；0 = 补零
    parameter LB_W      = 1280,      // 一行宽度（= IMG_W）
    parameter LB_DEPTH  = 2048,     // 行缓存深度，必须 >= LB_W+1
    parameter LB_AW     = 11        // = log2(LB_DEPTH)
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- DDR/极化核心输出，两路数据与 vin 同拍 ----
    input  wire [7:0]  y_in,        // y=(i0+i90)>>1
    input  wire [7:0]  dolp_in,     // DoLP8（算法7 的 dolp_out）
    input  wire        vin,         // 像素有效；可连续 16 像素后任意长度停顿
    input  wire        hs_in,       // 行首脉冲（同源）
    input  wire        vs_in,       // 帧首脉冲（同源，1 拍宽）

    input  wire [7:0]  thr_in,      // 边缘二值阈值（比较对象是 G8 = |G|>>3，0~255）

    output reg  [23:0] rgb_out,     // 边缘图：bin ? 白 : 黑
    output reg  [7:0]  y_out,       // 融合后边缘强度（给算法10/11 复用）
    output reg  [7:0]  e_rgb_out,   // 亮度支路边缘强度（调试/复用）
    output reg  [7:0]  e_dolp_out,  // DoLP 支路边缘强度
    output reg         bin_out,     // 边缘二值
    output reg         de_out,
    output reg         hs_out,
    output reg         vs_out
);

    //=================================================================
    // 0) 从"1 拍宽 vs 脉冲"重建"场消隐电平"给行缓存
    //    line_buffer_3x3_sparse 期望 vs 是**电平**（VS_ACTIVE_LOW=1 ⇒ 帧起始区间内为 0），
    //    而总线上 vs 是 1 拍脉冲 ⇒ 这里做成："vs 脉冲之后 ~ 第一条 hs 之前"为 0，其余为 1。
    //=================================================================
    reg vs_lvl;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          vs_lvl <= 1'b0;
        else if (vs_in)      vs_lvl <= 1'b1;      // 收到 vs 脉冲 ⇒ 进入帧起始区间
        else if (hs_in)      vs_lvl <= 1'b0;      // 第一条 hs ⇒ 区间结束
    end
    wire lb_vs = ~vs_lvl;

    //=================================================================
    // 1) 一份行缓存（DW=16）同时给出两路 3x3 窗口（稀疏 de 模式）
    //=================================================================
    wire [15:0] lb_din = {y_in, dolp_in};
    wire [15:0] q00, q01, q02, q10, q11, q12, q20, q21, q22;
    wire        lb_de, lb_hs, lb_vs_o;

    line_buffer_3x3_sparse #(
        .DW         (16),
        .LB_W       (LB_W),
        .LB_DEPTH   (LB_DEPTH),
        .LB_AW      (LB_AW),
        .BORDER     (BORDER),
        .VS_ACTIVE_LOW (1),
        .SPARSE_EN  (1)                     // ★ 稀疏 de：行边界用 hs_in
    ) u_lb (
        .clk (clk), .rst_n (rst_n),
        .din (lb_din), .de_in (vin), .hs_in (hs_in), .vs_in (lb_vs),
        .p00 (q00), .p01 (q01), .p02 (q02),
        .p10 (q10), .p11 (q11), .p12 (q12),
        .p20 (q20), .p21 (q21), .p22 (q22),
        .de_out (lb_de), .hs_out (lb_hs), .vs_out (lb_vs_o),
        .col_out (), .row_out ()
    );

    // 拆出两路的窗口
    wire [7:0] y00=q00[15:8], y01=q01[15:8], y02=q02[15:8];
    wire [7:0] y10=q10[15:8], y11=q11[15:8], y12=q12[15:8];
    wire [7:0] y20=q20[15:8], y21=q21[15:8], y22=q22[15:8];
    wire [7:0] d00=q00[7:0],  d01=q01[7:0],  d02=q02[7:0];
    wire [7:0] d10=q10[7:0],  d11=q11[7:0],  d12=q12[7:0];
    wire [7:0] d20=q20[7:0],  d21=q21[7:0],  d22=q22[7:0];

    //=================================================================
    // 2) Sobel 核：返回 |Gx|+|Gy| ≤ 2040，G8 对输入强度右移 3 位
    //=================================================================
    function [10:0] sobel_abs;
        input [7:0] a00,a01,a02, a10,a11,a12, a20,a21,a22;
        reg [9:0] gr, gl, gt, gb;
        reg signed [10:0] gx, gy;
        begin
            gr = {2'b00,a02} + ({2'b00,a12} << 1) + {2'b00,a22};   // 右列加权和
            gl = {2'b00,a00} + ({2'b00,a10} << 1) + {2'b00,a20};   // 左列加权和
            gt = {2'b00,a00} + ({2'b00,a01} << 1) + {2'b00,a02};   // 上行加权和
            gb = {2'b00,a20} + ({2'b00,a21} << 1) + {2'b00,a22};   // 下行加权和
            gx = {1'b0, gr} - {1'b0, gl};                          // ±1020
            gy = {1'b0, gt} - {1'b0, gb};                          // ±1020
            sobel_abs = (gx[10] ? (~gx + 11'd1) : gx) + (gy[10] ? (~gy + 11'd1) : gy);
        end
    endfunction

    wire [10:0] s_y = sobel_abs(y00,y01,y02,y10,y11,y12,y20,y21,y22);
    wire [10:0] s_d = sobel_abs(d00,d01,d02,d10,d11,d12,d20,d21,d22);
    wire [7:0]  g8_y = s_y[10:3];        // >>3 ⇒ 0~255
    wire [7:0]  g8_d = s_d[10:3];

    //=================================================================
    // 3) 第 2 拍：登记两路边缘强度（+ 同步头/thr 跟进）
    //=================================================================
    reg [7:0] e_y1, e_d1;
    reg       de1, hs1, vs1, vs_pulse_d1;
    reg [7:0] thr1, thr2r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            e_y1 <= 8'd0; e_d1 <= 8'd0; de1 <= 1'b0; hs1 <= 1'b0;
            vs1 <= 1'b0; vs_pulse_d1 <= 1'b0;
            thr1 <= 8'd0; thr2r <= 8'd0;
        end else begin
            e_y1 <= g8_y;  e_d1 <= g8_d;  de1 <= lb_de;
            hs1  <= lb_hs;
            // lb_vs_o is the reconstructed blanking level; preserve the input VS pulse separately.
            vs_pulse_d1 <= vs_in;
            vs1 <= vs_pulse_d1;
            // 阈值链：2 级自由推进（与"比较发生在第 2 级组合逻辑"对上 —— 见下）
            //   thr 与输入按时钟推进，使阈值和对应像素在输出级相遇；停顿长度不受限。
            thr1  <= thr_in;
            thr2r <= thr1;
        end
    end

    //=================================================================
    // 4) 第 3 拍：融合 → 二值 → 输出
    //=================================================================
    wire [7:0] e_d_used = EDGE_MODE ? e_d1 : 8'd0;          // EDGE_MODE=0 ⇒ 仅亮度
    wire [16:0] fsum = ({9'd0, W_RGB} * e_y1) + ({9'd0, W_DOLP} * e_d_used);
    // ★ EDGE_MODE=0（仅亮度）直接输出亮度支路；W_DOLP=0 仍按 W_RGB 加权：
    //   weighted 模式下不因 W_DOLP=0 改变加权公式。
    wire [7:0]  e_fuse = (EDGE_MODE == 0) ? e_y1 :
                         (FUSE_MODE ? ((e_y1 > e_d_used) ? e_y1 : e_d_used)
                                    : ((fsum[16:8] > 9'd255) ? 8'hFF : fsum[15:8]));

    wire bin_c = EDGE_INV ? (e_fuse < thr2r) : (e_fuse >= thr2r);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb_out <= 24'd0; y_out <= 8'd0; e_rgb_out <= 8'd0; e_dolp_out <= 8'd0;
            bin_out <= 1'b0; de_out <= 1'b0; hs_out <= 1'b0; vs_out <= 1'b0;
        end else begin
            y_out     <= e_fuse;
            e_rgb_out <= e_y1;
            e_dolp_out<= e_d_used;
            rgb_out   <= bin_c ? 24'hFFFFFF : 24'h000000;
            bin_out   <= bin_c;
            de_out    <= de1;
            hs_out    <= hs1;
            vs_out    <= vs1;
        end
    end

endmodule
