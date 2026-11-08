//=============================================================================
// 算法9专用稀疏 3x3 窗口缓存；原 line_buffer_3x3.v 保持不变，本模块仅供算法9使用。
// 核心实例参数：DW=16、LB_W=1280、LB_DEPTH=2048、LB_AW=11，存放 {y,DoLP}。
// SPARSE_EN=1 时 HS 清列号；vin 空白期间列号和读地址状态保持，支持连续突发及任意长度停顿。
// VS_ACTIVE_LOW=1：帧消隐区间复位行状态；HS 行首脉冲领先该行首个有效像素一拍。
// 两行存储器不复位以保留同步 RAM 推断形式；BORDER 可选复制或补零。资源以整机综合实测为准。
//=============================================================================
`timescale 1ns/1ps

module line_buffer_3x3_sparse #(
    parameter DW            = 8,        // 数据位宽：8 = 灰度(Sobel/均值滤波)；1 = 二值(形态学)
    parameter LB_W          = 640,      // 一行最多多少个有效像素（= IMG_W）
    parameter LB_DEPTH      = 1024,     // 行缓存深度，必须 >= LB_W+1，建议 2 的幂
    parameter LB_AW         = 10,       // 地址位宽 = log2(LB_DEPTH)
    parameter BORDER        = 1,        // 1 = 复制边缘（默认，推荐）；0 = 补零
    parameter VS_ACTIVE_LOW = 1,        // 1 = vs_in 低有效（与 video_timing 的 tmg_vsync 一致）
    // ★ 稀疏 de 模式（算法9 的有效像素可成块连续，块间可有任意长度空白）
    //   稠密模式下"de 无效即把列号清零"是对的；但稀疏模式下 de 每来一个就拉低一次，
    //   列号会被每个像素复位 ⇒ 行缓存全乱。SPARSE_EN=1 时改为用 hs_in 界定行边界：
    //     列号只在 hs（行首）清零；de 无效期间保持。hs_in 在稠密模式下没被逻辑使用（只延到 hs_out），
    //     本文件为算法9专用克隆，不修改或替代普通 line_buffer_3x3。
    parameter SPARSE_EN     = 0
)(
    input  wire          clk,
    input  wire          rst_n,

    input  wire [DW-1:0] din,           // 输入像素（灰度/二值）
    input  wire          de_in,         // 有效像素；SPARSE_EN=1 时行内允许任意空白
    input  wire          hs_in,
    input  wire          vs_in,

    // ---- 3x3 窗口：p[r][c]，r=0 下(当前行 y)，r=2 上(y-2)；c=2 右(当前列 x)，c=0 左(x-2) ----
    output wire [DW-1:0] p00, p01, p02, // 上  行 (y-2)
    output wire [DW-1:0] p10, p11, p12, // 中  行 (y-1)   p11 = 窗口中心(数学上是 (y-1,x-1))
    output wire [DW-1:0] p20, p21, p22, // 下  行 (y  )   p22 = 当前输入像素

    output wire          de_out,        // 窗口有效（比 de_in 晚 1 拍）
    output wire          hs_out,
    output wire          vs_out,
    output wire [10:0]   col_out,       // 窗口右列(=当前列)的列号，供需要位置的算法用
    output wire [10:0]   row_out        // 窗口下行的行号(=当前输入行的行号)
);

    localparam ZERO_DW = {DW{1'b0}};

    //=====================================================================
    // 行缓存（**不复位**，否则推断不出 BRAM）
    //=====================================================================
    reg [DW-1:0] lb1 [0:LB_DEPTH-1];
    reg [DW-1:0] lb2 [0:LB_DEPTH-1];
    reg [DW-1:0] d1, d2;

    // 列计数器：de 有效时 0..LB_W-1
    //   稠密模式（SPARSE_EN=0）：de 无效（行消隐）时清零 —— 这就是"行切换"，不需要行号/行起始信号；
    //   稀疏模式（SPARSE_EN=1）：只在行首（hs_in）清零，de 无效期间保持（否则每像素复位一次）。
    reg [LB_AW-1:0] x;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      x <= {LB_AW{1'b0}};
        else if (de_in)  x <= x + 1'b1;
        else if (SPARSE_EN ? hs_in : 1'b1) x <= {LB_AW{1'b0}};
    end

    // 读地址前视 1 列。稠密模式消隐时读 0；稀疏模式在 HS 预读第 0 列并在空白时保持地址。
    //   ★ 稀疏模式必须**在空转周期保持地址**：否则 ra 被反复拉成 0，d1/d2 被 lb1[0]/lb2[0] 覆盖，
    //     下一个像素的三行数据全错（实测现象：稀疏输出与稠密输出逐像素不同）。
    //     规则：像素周期用 x+1（前视）；行首(hs)用 0（预装第 0 列，等同稠密期的消隐读）；其余保持。
    reg  [LB_AW-1:0] ra_h;
    wire [LB_AW-1:0] ra_dense = de_in ? (x + 1'b1) : {LB_AW{1'b0}};
    wire [LB_AW-1:0] ra_spars = de_in ? (x + 1'b1) : (hs_in ? {LB_AW{1'b0}} : ra_h);
    wire [LB_AW-1:0] ra = SPARSE_EN ? ra_spars : ra_dense;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ra_h <= {LB_AW{1'b0}};
        else        ra_h <= ra;
    end

    always @(posedge clk) begin
        if (de_in) lb1[x] <= din;       // 行缓存1 <- 本行
        d1 <= lb1[ra];                  // -> 上一行同列
        if (de_in) lb2[x] <= d1;        // 行缓存2 <- 上一行
        d2 <= lb2[ra];                  // -> 上上行同列
    end

    //=====================================================================
    // 行号：识别"当前输入行的行号"，用于处理图像上边界
    //   vs 低有效（VS_ACTIVE_LOW=1）期间置位 vs_seen；下一次行起始时把行号清 0。
    //   这样"vs 之后的第一条有效行"行号恰好是 0（而不是 1）。
    //=====================================================================
    reg        de_d1;
    reg [10:0] row_idx;
    reg        vs_seen;

    wire in_vblank = VS_ACTIVE_LOW ? ~vs_in : vs_in;
    // 行起始判定：稠密 = de 上升沿；稀疏 = hs 脉冲（de 是稀疏脉冲，上升沿每像素都有，不能当行首）
    wire line_start = SPARSE_EN ? hs_in : (de_in & ~de_d1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_d1    <= 1'b0;
            row_idx  <= 11'd0;
            vs_seen  <= 1'b0;
        end else begin
            de_d1 <= de_in;
            if (in_vblank) vs_seen <= 1'b1;
            if (line_start) begin
                if (vs_seen) begin row_idx <= 11'd0;        vs_seen <= 1'b0; end
                else              row_idx <= row_idx + 11'd1;
            end
        end
    end

    // 垂直边界：row1 = y-1、row2 = y-2 是否存在
    //   ★ 这里必须用**组合**的 row_cur，不能用寄存的 row_idx：
    //     row_idx <= 0 要到"本行第一个像素那个时钟沿"才生效，
    //     而三行数据正是在那一拍被装进移位寄存器的 ⇒ 直接用 row_idx 会晚一拍，
    //     于是本行前两行会误判成"存在"，把上一帧/上一行的残余数据当邻域用（实测出人工边缘）。
    wire [10:0] row_cur = line_start ? (vs_seen ? 11'd0 : (row_idx + 11'd1)) : row_idx;
    wire r1_ok = (row_cur >= 11'd1);
    wire r2_ok = (row_cur >= 11'd2);

    wire [DW-1:0] row0 = din;                                              // y
    wire [DW-1:0] row1 = r1_ok ? d1 : (BORDER ? row0 : ZERO_DW);           // y-1
    wire [DW-1:0] row2 = r2_ok ? d2 : (BORDER ? (r1_ok ? d1 : row0) : ZERO_DW); // y-2

    //=====================================================================
    // 3 列移位寄存器（de_in 门控：消隐期保持，行首自然从 0 列开始）
    //=====================================================================
    reg [DW-1:0] s0 [0:2];      // 行 y
    reg [DW-1:0] s1 [0:2];      // 行 y-1
    reg [DW-1:0] s2 [0:2];      // 行 y-2
    reg [LB_AW-1:0] xc;         // 窗口右列的列号（= 列号延迟 1 拍）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0[0] <= ZERO_DW; s0[1] <= ZERO_DW; s0[2] <= ZERO_DW;
            s1[0] <= ZERO_DW; s1[1] <= ZERO_DW; s1[2] <= ZERO_DW;
            s2[0] <= ZERO_DW; s2[1] <= ZERO_DW; s2[2] <= ZERO_DW;
            xc    <= {LB_AW{1'b0}};
        end else begin
            xc <= x;
            if (de_in) begin
                s0[0] <= s0[1]; s0[1] <= s0[2]; s0[2] <= row0;
                s1[0] <= s1[1]; s1[1] <= s1[2]; s1[2] <= row1;
                s2[0] <= s2[1]; s2[1] <= s2[2]; s2[2] <= row2;
            end
        end
    end

    //=====================================================================
    // 水平边界：窗口右列 = xc（s*[2]），中列 = xc-1（s*[1]），左列 = xc-2（s*[0]）
    //   xc==0 时"中/左"不存在，xc==1 时"左"不存在；按 BORDER 复制或补零。
    //=====================================================================
    assign p02 = s2[2];
    assign p01 = (xc >= 1) ? s2[1] : (BORDER ? s2[2] : ZERO_DW);
    assign p00 = (xc >= 2) ? s2[0] : (BORDER ? ((xc == 1) ? s2[1] : s2[2]) : ZERO_DW);
    assign p12 = s1[2];
    assign p11 = (xc >= 1) ? s1[1] : (BORDER ? s1[2] : ZERO_DW);
    assign p10 = (xc >= 2) ? s1[0] : (BORDER ? ((xc == 1) ? s1[1] : s1[2]) : ZERO_DW);
    assign p22 = s0[2];
    assign p21 = (xc >= 1) ? s0[1] : (BORDER ? s0[2] : ZERO_DW);
    assign p20 = (xc >= 2) ? s0[0] : (BORDER ? ((xc == 1) ? s0[1] : s0[2]) : ZERO_DW);

    // 同步头同延时（整个模块固定 1 拍）
    reg hs_d1, vs_d1;

    assign de_out  = de_d1;
    assign hs_out  = hs_d1;
    assign vs_out  = vs_d1;
    assign col_out = {1'b0, xc};        // 窗口右列列号
    assign row_out = row_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin hs_d1 <= 1'b0; vs_d1 <= 1'b0; end
        else        begin hs_d1 <= hs_in; vs_d1 <= vs_in; end
    end

endmodule
