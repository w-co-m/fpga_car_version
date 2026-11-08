// 算法8：RGB、DoLP、AoP同拍输入的融合模块，改编自算法8交付包。
// 本工程algo_polar_core同时接收四角度RGB888与光强，每拍可处理一组坐标。
// algo_polar_fusion串接25级偏振核与本模块2级寄存器，组合共27级。
// rgb_unpol_in名称沿用交付接口，实际是四角度平均RGB，不构成去反光保证。
// y_unpol_in是与该RGB/DoLP/AoP对应的亮度参考；三路须同位置、同拍。
// FUSION_MODE=0用DoLP调制亮度，1定点加权，2取max；AOP_HUE选择方向伪彩。
// thr_in低7位为K（0回落K_DEF），最高位0抑制、1增强。
// 饱和RGB加保留未饱和通道的色差，饱和后颜色关系可能改变。
// 本模块由板级顶层的模式11偏振处理链调用，不单独增加按键显示模式或引脚。
`timescale 1ns/1ps

module algo_fusion #(
    parameter FUSION_MODE = 0,          // 0=DoLP 引导增益 1=三通道加权和 2=max
    parameter K_DEF       = 7'd64,      // MODE0 默认 K（thr_in[6:0] 会在运行时覆盖它）
    parameter W_RGB       = 8'd128,     // MODE1 权重（编译期；建议三者之和 ≈ 256）
    parameter W_DOLP      = 8'd96,
    parameter W_AOP       = 8'd32,      //   ★ 建议默认 0：AoP 是角度，线性加权有 180° 接缝
    parameter AOP_HUE     = 0,          // 0=保留四角度平均RGB 1=AoP 方向伪彩
    parameter BIN_THR     = 8'd128      // bin_out：DoLP ≥ 此值判"强偏振/反光"
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 三路输入：由 algo_polar 同拍给出（已在源头对齐；无需行/帧缓存）----
    input  wire [23:0] rgb_unpol_in,    // 四角度样本平均 RGB
    input  wire [7:0]  y_unpol_in,      // 配对和亮度参考（= S0/2）
    input  wire [7:0]  dolp_in,         // DoLP8
    input  wire [7:0]  aop_in,          // AoP8
    input  wire        vin,             // 三路共用的有效脉冲（= algo_polar 的 de_out）
    input  wire        hs_in, vs_in,    // 同源同步头
    input  wire [7:0]  thr_in,          // [6:0]=偏振强度 K；[7]=极性(0 抑制/1 增强)

    // ---- 输出 ----
    output reg  [23:0] rgb_out,         // 融合结果（彩色；AOP_HUE=1 时为方向伪彩）
    output reg  [7:0]  y_out,           // 融合亮度 8bit（给算法9 做偏振辅助边缘）
    output reg  [7:0]  dolp_out,        // DoLP8 直通（算法9 要用）
    output reg  [7:0]  aop_out,         // AoP8 直通（后续算法/伪彩可用）
    output reg         bin_out,         // DoLP ≥ BIN_THR 的"强偏振/反光"掩膜
    output reg         de_out,          // 与vin对应，支持每拍一像素，延迟2级
    output reg         hs_out,
    output reg         vs_out
);

    //=================================================================
    // 统一把三路拆分好，按 FUSION_MODE 算融合亮度
    //=================================================================
    wire [7:0] yr = y_unpol_in;                       // 配对和亮度参考
    wire [7:0] rr = rgb_unpol_in[23:16];
    wire [7:0] gr = rgb_unpol_in[15:8];
    wire [7:0] br = rgb_unpol_in[7:0];

    wire [6:0] k7     = (thr_in[6:0] == 7'd0) ? K_DEF : thr_in[6:0];   // 全零则用参数默认值
    wire       inc    = thr_in[7];                    // 0=抑制偏振 1=增强偏振

    //---- MODE 0：DoLP 引导自适应增益 ----
    wire [14:0] gterm = k7 * dolp_in;                 // ≤127×255 = 32385
    wire [8:0]  gadj  = gterm[14:7];                  // ≤253
    wire [9:0]  gain0 = inc ? (10'd256 + {1'b0, gadj})      // 增强偏振（反光更亮）
                            : (10'd256 - {1'b0, gadj});      // 降低高 DoLP 像素亮度
    wire [16:0] ypre0 = yr * gain0[8:0];              // ≤255×509 = 129795（17bit 不溢出）
    wire [7:0]  y0    = (ypre0[16:8] > 8'd255) ? 8'hFF : ypre0[16:8];   // 饱和（不环绕）

    //---- MODE 1：三通道定点加权和（全常数乘法 ⇒ 0 DSP）----
    wire [17:0] wsum = ({10'b0, W_RGB}  * yr)
                     + ({10'b0, W_DOLP} * dolp_in)
                     + ({10'b0, W_AOP}  * aop_in);
    wire [7:0]  y1   = (wsum[17:8] > 8'd255) ? 8'hFF : wsum[15:8];

    //---- MODE 2：max(Y, DoLP) ----
    wire [7:0]  y2   = (yr > dolp_in) ? yr : dolp_in;

    wire [7:0] yf = (FUSION_MODE == 0) ? y0 : (FUSION_MODE == 1) ? y1 : y2;

    //---- 亮度差值；未饱和通道保留色差，饱和裁剪可能改变色差 ----
    wire signed [8:0] dlt = $signed({1'b0, yf}) - $signed({1'b0, yr});
    function [7:0] satadd;
        input [7:0] c;  input signed [8:0] d;
        reg signed [9:0] t;
        begin
            t = $signed({1'b0, c}) + d;
            if (t[9] == 1'b1)      satadd = 8'd0;        // 下溢 ⇒ 钉 0
            else if (t > 10'sd255) satadd = 8'hFF;       // 上溢 ⇒ 钉 255
            else                   satadd = t[7:0];
        end
    endfunction

    // （Δ 保持的饱和加放在第二级：r2/g2/b2）

    //=================================================================
    // AoP 方向伪彩（可选）：256×24 色环（0..255 映射 0..360°）× 融合亮度
    //=================================================================
    function [23:0] hue_wheel;               // 生成方式固定、可复现（见交付说明）
        input [7:0] a;
        reg [7:0] h;  reg [7:0] q;  reg [7:0] t;
        begin
            h = a;                                        // 0..255 → 色相环
            q = (h >> 6);                                 // 4 段（每段 64）
            t = (h & 8'h3F) << 2;                         // 0..252
            case (q)
            2'd0: hue_wheel = {8'hFF, t,     8'h00};      // R→G
            2'd1: hue_wheel = {8'hFF-t, 8'hFF, 8'h00};    // G→R 减
            2'd2: hue_wheel = {8'h00, 8'hFF, t};          // B→
            default: hue_wheel = {t, 8'h00, 8'hFF};       // R→
            endcase
        end
    endfunction

    //=================================================================
    // 输出：**两级、valid 全程跟着走**（延时固定 2 拍，像素与 de_out 同拍）
    //   ★ 踩过的坑：第一版把 rgb_out 写成"每拍都登记组合结果"、de_out 走两级，
    //     结果像素比 de_out 早一拍 ⇒ 输出与同步头错位（TB 里表现为"看到的不是那个像素"）。
    //     纪律：输出登记必须与它的 valid 在同一个沿、同一级。
    //=================================================================
    reg        v1r, hs1r, vs1r;
    reg [7:0]  y1r, dolp1r, aop1r;
    reg signed [8:0] dl1r;                    // Δ = Y' − Y（第一级算好，第二级只做饱和加）
    reg [23:0] col1r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1r <= 1'b0; hs1r <= 1'b0; vs1r <= 1'b0;
            y1r <= 8'd0; dolp1r <= 8'd0; aop1r <= 8'd0; dl1r <= 9'sd0; col1r <= 24'd0;
        end else begin
            v1r    <= vin;
            hs1r   <= hs_in;
            vs1r   <= vs_in;
            y1r    <= yf;
            dolp1r <= dolp_in;
            aop1r  <= aop_in;
            dl1r   <= dlt;
            col1r  <= rgb_unpol_in;
        end
    end

    // 第二级：Δ 保持（或 AoP 伪彩），与 de_out 同沿登记
    wire [7:0] r2 = satadd(col1r[23:16], dl1r);
    wire [7:0] g2 = satadd(col1r[15:8],  dl1r);
    wire [7:0] b2 = satadd(col1r[7:0],   dl1r);

    wire [23:0] hue2 = hue_wheel(aop1r);
    // ★ 位宽坑（同 §"小位宽×大位宽"）：两个 8bit 相乘若直接写 `>>8`，
    //   表达式的上下文位宽仍是 8 位 ⇒ 乘积回绕、右移后恒为 0（实测伪彩全黑）。
    //   必须先把乘积登记到 16 位再取高位。
    wire [15:0] hR2 = hue2[23:16] * y1r;
    wire [15:0] hG2 = hue2[15:8]  * y1r;
    wire [15:0] hB2 = hue2[7:0]   * y1r;
    wire [7:0]  rh2 = hR2[15:8], gh2 = hG2[15:8], bh2 = hB2[15:8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb_out <= 24'd0; y_out <= 8'd0; dolp_out <= 8'd0; aop_out <= 8'd0;
            bin_out <= 1'b0; de_out <= 1'b0; hs_out <= 1'b0; vs_out <= 1'b0;
        end else begin
            de_out   <= v1r;
            hs_out   <= hs1r;
            vs_out   <= vs1r;
            y_out    <= y1r;
            dolp_out <= dolp1r;
            aop_out  <= aop1r;
            bin_out  <= (dolp1r >= BIN_THR);
            if (AOP_HUE) rgb_out <= {rh2, gh2, bh2};
            else         rgb_out <= {r2, g2, b2};
        end
    end

endmodule
