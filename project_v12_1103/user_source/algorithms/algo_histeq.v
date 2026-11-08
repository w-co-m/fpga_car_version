// 算法5③：移植自算法5交付包，适配 SC520CS 的 RGB888、1280×720、高有效 VS。
// 使用上一帧统计生成映射，本帧应用；像素通路固定4级，不缓存/推迟整帧图像。
// HIST_BITS=20 可容纳921600个同灰度像素；19位不足以统计720p单色帧。
// 建表最多约1800拍，需留足垂直消隐；当前720p显示时序满足这一条件。
// 开机空帧和单色帧使用恒等映射；色差仅在通道未饱和时保持，饱和会改变色差。
`timescale 1ns/1ps

module algo_histeq #(
    parameter GRAY_MODE = 0,        // 内部灰度权值模式（必须与上游一致）
    parameter HIST_BITS = 20,       // 直方图计数位宽：20 位可到1048575 > 1280*720=921600
    parameter STRENGTH  = 256,      // 均衡强度 Q8：256 = 完全均衡（默认），0 = 直通
    parameter VS_ACTIVE_LOW = 0,  // 当前显示高有效VS
    parameter RGB_MODE  = 0         // 0 = Δ 色差保持（默认）；1 = 输出灰度 R=G=B=Y''
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [23:0] rgb_in,
    input  wire        de_in,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire [7:0]  thr_in,      // 未使用（保留）

    output reg  [23:0] rgb_out,
    output reg  [7:0]  y_out,
    output reg         bin_out,
    output reg         de_out,
    output reg         hs_out,
    output reg         vs_out
);

    localparam AW = HIST_BITS + 8; // cdf*256 的位宽，默认28

    //---------------- RGB888分量，保留输入精度----------------
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

    //=================================================================
    // 存储数组先声明（供后面状态机引用；数组本身**不复位**以便推断 BRAM）
    //=================================================================
    reg [HIST_BITS-1:0] hmem [0:255];   // 直方图 256 × HIST_BITS（单读单写 ⇒ ERAM）
    reg [HIST_BITS-1:0] h_rdo;          // 同步读输出
    reg [7:0]           mmap [0:255];   // 映射表 256 × 8bit（⇒ 分布式 RAM）
    reg [7:0]           mapy;           // 映射表同步读输出

    //=================================================================
    // 状态机
    //=================================================================
    localparam S_RST  = 3'd0,   // 复位后：把 256 个 bin 清零
               S_IDLE = 3'd1,   // 统计中（像素流正常）
               S_SUM_A= 3'd2,   // 求和：给读地址
               S_SUM_B= 3'd3,   // 求和：累加
               S_RD_A = 3'd4,   // 建表：给读地址
               S_RD_B = 3'd5,   // 建表：累加 CDF + 清零该 bin
               S_LOOP = 3'd6,   // 阈值跨越循环
               S_WR   = 3'd7;   // 写映射表

    reg [2:0]  st;
    reg [8:0]  cy;                  // 0..255（9bit 便于判 ==255）
    reg [HIST_BITS:0]  sum_acc;     // 求和累加（HIST_BITS+1位）
    reg [HIST_BITS:0]  total;       // 一帧像素总数 = cdf[255]
    reg [AW-1:0]       acc;         // cdf*256
    reg [AW-1:0]       rhs;         // k*total
    reg [8:0]          kk;          // 输出档数 0..256
    reg                map_rdy;
    reg                vs_d;
    reg [HIST_BITS:0]  cmin;        // cdf_min = 第一个非零 bin 的计数
    reg [HIST_BITS:0]  den;         // denom = total - cdfmin
    reg                uni;         // 单色帧标志（只有一个 bin 非零）⇒ 映射表退化为恒等
    reg [1:0] occupied_bins; // 第一遍计数非零桶，提前判定单色，避免低灰度桶先被写成0
    reg                nz;          // 本次建表已经找到第一个非零 bin

    wire fsm_busy = (st != S_IDLE);
    wire vs_active = VS_ACTIVE_LOW ? ~vs_g : vs_g;
    wire frame_end = vs_active & ~vs_d; // 使用灰度域对齐后的VS有效沿启动上一帧建表

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) vs_d <= 1'b0;
        else        vs_d <= vs_active;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_RST; cy <= 9'd0; occupied_bins <= 0;
            sum_acc <= 0; total <= 0; acc <= 0; rhs <= 0; kk <= 9'd0;
            map_rdy <= 1'b0;
            cmin <= 0; den <= 0; uni <= 1'b0; nz <= 1'b0;
        end else begin
            case (st)
            //---------- 复位后清一次直方图（避免未初始化 X 进 CDF）----------
            S_RST: begin
                if (cy == 9'd255) begin st <= S_IDLE; cy <= 9'd0; end
                else                    cy <= cy + 9'd1;
            end
            //---------- 统计中，等帧结束 ----------
            S_IDLE: begin
                if (frame_end) begin
                    st <= S_SUM_A; cy <= 9'd0; sum_acc <= 0; occupied_bins <= 0;
                    cmin <= 0; den <= 0; uni <= 1'b0; nz <= 1'b0; kk <= 9'd0;
                end
            end
            //---------- 第一遍：求 total ----------
            S_SUM_A: st <= S_SUM_B;
            S_SUM_B: begin
                if(h_rdo != 0 && occupied_bins < 2) occupied_bins <= occupied_bins + 1'b1;
                if (cy == 9'd255) begin
                    // 空统计帧（如上电时先到VS）也使用恒等表，避免第一帧全黑。
                    uni <= ((occupied_bins + (h_rdo != 0)) <= 1);
                    total   <= sum_acc + h_rdo;
                    acc     <= 0;
                    rhs     <= {{(AW-HIST_BITS-1){1'b0}}, (sum_acc + h_rdo)};
                    kk      <= 9'd0;
                    st      <= S_RD_A;
                    cy      <= 9'd0;
                end else begin
                    sum_acc <= sum_acc + h_rdo;
                    cy      <= cy + 9'd1;
                    st      <= S_SUM_A;
                end
            end
            //---------- 第二遍：CDF + cdf_min + 阈值跨越 + 出表 ----------
            S_RD_A: st <= S_RD_B;
            S_RD_B: begin
                acc <= acc + {h_rdo, 8'b0};     // cdf += hist[cy]（同时 ×256）
                if (nz == 1'b0) begin
                    if (h_rdo == 0) begin
                        // 还没到第一个非零 bin：该 bin 的映射记为 0（下面 S_WR 用 kk=0）
                        kk <= 9'd0;
                        st <= S_WR;
                    end else if (h_rdo == total) begin
                        // ★ 单色帧：total == cdf_min ⇒ denom = 0（除零）
                        //   约定：映射表退化为**恒等**（全黑仍是全黑、全白仍是全白）
                        uni <= 1'b1;
                        st  <= S_WR;
                        kk  <= 9'd0;
                    end else begin
                        // 第一个非零 bin：记下 cdf_min 与 denom，rhs 初值 = cdfmin*256 + denom
                        cmin <= h_rdo;
                        den  <= total - h_rdo;
                        rhs  <= {h_rdo, 8'b0} + (total - h_rdo);
                        kk   <= 9'd0;
                        nz   <= 1'b1;
                        st   <= S_LOOP;
                    end
                end else begin
                    st <= S_LOOP;
                end
            end
            // 阈值跨越循环：out = max{ k : (cdf−cdfmin)*256 ≥ k*denom }（= floor(差值*256/denom)）
            S_LOOP: begin
                if (acc >= rhs) begin
                    if (kk < 9'd255) begin      // 档数封顶 255
                        kk  <= kk + 9'd1;
                        rhs <= rhs + den;
                    end else begin
                        st <= S_WR;
                    end
                end else begin
                    st <= S_WR;
                end
            end
            S_WR: begin
                if (cy == 9'd255) begin
                    st <= S_IDLE; cy <= 9'd0; map_rdy <= 1'b1;
                end else begin
                    cy <= cy + 9'd1; st <= S_RD_A;
                end
            end
            default: st <= S_IDLE;
            endcase
        end
    end

    //=================================================================
    // 直方图 RAM 的读写控制（数组已在文件前部声明）
    //=================================================================
    reg [7:0] y_d1;
    reg       de_g_d1;

    wire fsm_rd  = (st == S_SUM_A) || (st == S_RD_A);
    wire fsm_clr = (st == S_RST)   || (st == S_RD_B);

    wire coll = (y_g == y_d1);                                  // 本拍读地址 == 本拍写地址
    wire [HIST_BITS:0] wdat = h_rdo + 1'b1;                     // 本拍要写的计数值
    // ★ 补写尾巴 & 抑制"起始拍陈旧写"：
    //   本拍写的是**上一拍那个像素**的计数（地址 y_d1 = 上一拍 Y）。
    //   de 拉低后的第一拍要补写（否则每行最后 1 个像素会丢）；
    //   但 de 拉**起**的第一拍，y_d1 还停在消隐期的 Y（=0）上，会把上一行/上一帧的
    //   计数值写进 bin 0 —— 实测这会污染 cdf_min，导致整张映射表偏移（探针抓到 hist[0]=112）。
    //   ⇒ 丢一拍不损失任何像素：本拍像素的计数会在下一拍作为"上一拍"被写出。
    wire de_rise = de_g & ~de_g_d1;                             // 一行/一帧的第一个有效像素
    wire stat_en = (de_g | (de_g_d1 & ~de_g)) & ~de_rise;       // 含"最后 1 拍补写"
    wire stat_en_g = stat_en & ~fsm_busy;                       // 状态机期间停统计

    // 读：状态机期间用 cy 当地址；统计期间用当前像素 Y，并做同址旁路
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          h_rdo <= 0;
        else if (fsm_rd)     h_rdo <= hmem[cy[7:0]];
        else if (de_g)       h_rdo <= (coll && stat_en_g) ? (h_rdo + 1'b1) : hmem[y_g];
    end

    // 写：统计写（含补写）优先；状态机清零次之
    always @(posedge clk) begin
        if (stat_en_g)       hmem[y_d1]     <= wdat[HIST_BITS-1:0];
        else if (fsm_clr)    hmem[cy[7:0]]  <= {HIST_BITS{1'b0}};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin y_d1 <= 8'd0; de_g_d1 <= 1'b0; end
        else        begin y_d1 <= y_g;  de_g_d1 <= de_g; end
    end

    //=================================================================
    // 映射表 RAM 的写控制（数组已在文件前部声明）
    //=================================================================
    always @(posedge clk) if (st == S_WR) mmap[cy[7:0]] <= uni ? cy[7:0]
                                                            : ((kk > 9'd255) ? 8'd255 : kk[7:0]);

    //=================================================================
    // 应用通路：延迟链（通道 3 拍、Y 1 拍）+ 查表 + 强度混合 + Δ 色差保持
    //=================================================================
    reg [7:0] r8a, g8a, b8a;
    reg [7:0] r8b, g8b, b8b;
    reg [7:0] r8c, g8c, b8c;
    reg [7:0] y_d1a;
    reg       de_s3, hs_s3, vs_s3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r8a<=0; g8a<=0; b8a<=0;  r8b<=0; g8b<=0; b8b<=0;  r8c<=0; g8c<=0; b8c<=0;
            y_d1a<=0; mapy<=0;  de_s3<=0; hs_s3<=0; vs_s3<=0;
        end else begin
            r8a<=r8;   g8a<=g8;   b8a<=b8;
            r8b<=r8a;  g8b<=g8a;  b8b<=b8a;
            r8c<=r8b;  g8c<=g8b;  b8c<=b8b;
            y_d1a <= y_g;
            mapy  <= mmap[y_g];             // 同步读：地址=第 2 拍的 Y，数据第 3 拍有效
            de_s3 <= de_g; hs_s3 <= hs_g; vs_s3 <= vs_g;
        end
    end

    // 强度混合（全无符号）：Y'' = (Y*(256-S) + mapY*S) >> 8
    //   权和 = 256 ⇒ 结果 ≤ 255，**不需要饱和逻辑**；S=256 → Y''=mapY（完全均衡）；S=0 → Y''=Y
    wire [15:0] blend = y_d1a * (256 - STRENGTH) + mapy * STRENGTH;

    // 映射表没建好（或模式刚切过来）⇒ 直通，避免读到未初始化的表
    wire [7:0] ypp = map_rdy ? blend[15:8] : y_d1a;

    // Δ 色差保持：Δ = Y'' - Y
    wire       dsgn = (y_d1a > ypp);
    wire [7:0] dmag = dsgn ? (y_d1a - ypp) : (ypp - y_d1a);

    function [8:0] dadd;
        input [7:0] c;
        input       sgn;
        input [7:0] mag;
        reg [8:0]   v;
        begin
            if (sgn) dadd = (mag > c) ? {1'b1, 8'h00} : {1'b0, (c - mag)};
            else begin
                v = {1'b0, c} + mag;
                dadd = (v > 9'd255) ? {1'b1, 8'hFF} : {1'b0, v[7:0]};
            end
        end
    endfunction

    wire [8:0] rx = (RGB_MODE == 0) ? dadd(r8c, dsgn, dmag) : {1'b0, ypp};
    wire [8:0] gx = (RGB_MODE == 0) ? dadd(g8c, dsgn, dmag) : {1'b0, ypp};
    wire [8:0] bx = (RGB_MODE == 0) ? dadd(b8c, dsgn, dmag) : {1'b0, ypp};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb_out <= 24'd0; y_out <= 8'd0; bin_out <= 1'b0;
            de_out <= 1'b0; hs_out <= 1'b0; vs_out <= 1'b0;
        end else begin
            y_out   <= ypp;
            rgb_out <= {rx[7:0], gx[7:0], bx[7:0]};
            bin_out <= rx[8] | gx[8] | bx[8];
            de_out  <= de_s3;
            hs_out  <= hs_s3;
            vs_out  <= vs_s3;
        end
    end

endmodule


