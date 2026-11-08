`timescale 1ns/1ps

//=============================================================================
// 算法10：颜色目标检测与包围框（模式13 COLORBOX）
//-----------------------------------------------------------------------------
// 来源：new_algorithm/算法10交付包（2026-10-17 修订版）
//   交付核心 rtl/算法 10 颜色目标检测与包围框.v  SHA256 27F7F5A6DE022333F5C09F5F169F56EE93B410C4B14743AB64C892A25848A926
//   交付顶层算法流水线的顶层调度器.v              SHA256 EC0BF32C0AA264290...
//
// 【为什么不是整包覆盖】交付包的调度器/参数源按 640x480 RGB565、25MHz 像素时钟、
//   OV5640 寄存器表设计（video_defs.vh：IMG_W=640、IMG_H=480）；本板原理图为
//   HX1P35B_FT（PH1P35MDG324）+ MIPI 摄像头 SC500CS + HDMI，工程为 1280x720 RGB888、
//   75MHz 像素时钟、DDR 帧缓存与偏振后台。整包覆盖会改掉采集/显示/OSD 等非算法部分，
//   因此只把**算法本体**移植进本文件，保留工程既有的 RGB888/720p 壳体。
//
// 【与交付包逐项对齐的算法语义】
//   · 颜色判定  DET_RULE=0 差分 / 1 绝对上下限 / 2 抗暖白(R-G 且 R 饱和) / 3 规则2+第三通道差分
//   · 2026-10-20：追加规则4，相对红度+低亮度下限，改善同比变暗时的漏检；规则0~3不变。
//   · 追加规则5：低饱和红色扇区，支持粉红目标；旧规则0~4不变。
//   · 规则6    分行程连通区域，选择并保持单个红色目标；不使用长宽比/填充率筛选。
//   · 旧规则0~5保留整帧 bbox 统计；新规则6接口不变，像素延迟仍为3拍。
//   · 画框      BOX_W 线宽、BOX_FILL 实心、BOX_COLOR 框色
//   · 抗噪      MIN_PIX 命中像素下限
//   · 形状筛选  SHAPE_FILTER_EN/TARGET_SHAPE/ASPECT_*/FILL_*/SHAPE_TOL_Q8，全程无除法
//   · 调试视图  DEBUG_VIEW=1 时命中像素=纯绿、未命中=原图变暗 1/4
//   只有两处按本工程规模做了等价改写（不改变算法结果）：
//     1) 通道用完整 RGB888（交付包为 RGB565 的 r6/g6/b6），阈值按名义 ×4 缩放，
//        旧规则见 algo_bank 的 COLOR_THRESHOLD=96 与 R_SAT_MIN=192；
//     2) 交付包的运行时端口 r_sat_in 在本工程合并为编译期参数 R_SAT_MIN
//        （板上没有对应旋钮，algo_bank 也没有运行期配置通路）。
//
// 【保留的工程壳体（交付包没有、但本工程已验证的加固）】
//   · VS 取上升沿 frame_start，而非电平，避免 VS 多拍重复锁存；
//   · 帧末最后一个有效像素仍计入本帧（publish_* 先合并再发布）；
//   · enable_in 关闭时统计与形状状态确定性清零（模式9~12 不被偏振页污染）；
//   · X/Y/HIT 位宽按 IMG_WIDTH/IMG_HEIGHT 派生，1280x720 时为 11/10/20 位。
//
// 时序：像素级 3 级流水（RGB/sync 同延），帧级 1 帧（bbox 整帧统计后锁存）。
//=============================================================================
module algo_color_detect #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer TARGET_COLOR = 0,
    parameter integer DET_RULE = 0,
    parameter [7:0] R_MIN = 8'd128,
    parameter [7:0] R_MAX = 8'd255,
    parameter [7:0] G_MIN = 8'd0,
    parameter [7:0] G_MAX = 8'd64,
    parameter [7:0] B_MIN = 8'd0,
    parameter [7:0] B_MAX = 8'd128,
    parameter [7:0] S_DEF = 8'd32,
    parameter integer MIN_PIX = 16,
    parameter integer BOX_W = 2,
    parameter integer BOX_FILL = 0,
    parameter [23:0] BOX_COLOR = 24'h00FF00,
    parameter integer VS_ACTIVE_LOW = 0,
    parameter integer XW = (IMG_WIDTH <= 1) ? 1 : $clog2(IMG_WIDTH),
    parameter integer YW = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT),
    parameter integer HIT_W = (IMG_WIDTH*IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_WIDTH*IMG_HEIGHT+1),
    parameter [7:0] R_SAT_MIN = 8'd192,
    parameter integer SHAPE_FILTER_EN = 0,
    parameter integer TARGET_SHAPE = 0,
    parameter [7:0] ASPECT_MIN_Q44 = 8'd12,
    parameter [7:0] ASPECT_MAX_Q44 = 8'd20,
    parameter [8:0] FILL_MIN_Q8 = 9'd180,
    parameter [8:0] FILL_MAX_Q8 = 9'd260,
    parameter [7:0] SHAPE_TOL_Q8 = 8'd28,
    parameter integer SHAPE_FILL_EN = 1,
    // 交付包同款调试视图：1 = 命中像素画纯绿、未命中像素取原图>>2（变暗 1/4）。
    // 生产配置为 0；置 1 时综合会常量折叠出独立视图通道，不增加 DSP/ERAM。
    parameter integer DEBUG_VIEW = 0,
    // Rule 4 is red-only. Q4 ratio 24 means R >= 1.5*G and R >= 1.5*B.
    // Keep a calibration knob for the sensor noise floor and white-balance response.
    parameter [7:0] RED_MIN = 8'd64,
    parameter [4:0] RED_RATIO_Q4 = 5'd24,
    parameter [7:0] RED_CHROMA_MIN = 8'd6
)(
    input  wire clk,
    input  wire rst_n,
    input  wire enable_in,
    input  wire [23:0] rgb_in,
    input  wire de_in,
    input  wire hs_in,
    input  wire vs_in,
    input  wire [7:0] thr_in,
    output reg [23:0] rgb_out,
    output reg [7:0] y_out,
    output reg bin_out,
    output reg de_out,
    output reg hs_out,
    output reg vs_out,
    output reg [XW-1:0] bbox_x_min,
    output reg [XW-1:0] bbox_x_max,
    output reg [YW-1:0] bbox_y_min,
    output reg [YW-1:0] bbox_y_max,
    output reg bbox_valid,
    output reg [HIT_W-1:0] hit_cnt,
    output reg [1:0] shape_type,
    output reg shape_ok,
    output reg bbox_valid_raw,
    // These outputs are 0/1/2 range bands, not numeric ratios.
    output reg [7:0] fill_ratio_q8,
    output reg bbox_fresh, // current completed frame actually measured the selected object
    output reg [7:0] aspect_ratio_q44
);
    localparam [XW-1:0] X_MAX = IMG_WIDTH-1;
    localparam [YW-1:0] Y_MAX = IMG_HEIGHT-1;

    generate if (((DET_RULE == 4) || (DET_RULE == 5) || (DET_RULE == 6)) && (TARGET_COLOR == 0) &&
                 ((RED_MIN == 0) || (RED_RATIO_Q4 <= 16) ||
                  ((DET_RULE >= 5) && (RED_CHROMA_MIN == 0)))) begin:g_bad_red_config
        ERROR_COLOR_RED_MIN_OR_RATIO_CONFIGURATION invalid_configuration();
    end endgenerate

    wire [7:0] r = rgb_in[23:16];
    wire [7:0] g = rgb_in[15:8];
    wire [7:0] b = rgb_in[7:0];
    wire [7:0] rg = (r > g) ? r-g : 8'd0;
    wire [7:0] rb = (r > b) ? r-b : 8'd0;
    wire [7:0] gr = (g > r) ? g-r : 8'd0;
    wire [7:0] gb = (g > b) ? g-b : 8'd0;
    wire [7:0] br = (b > r) ? b-r : 8'd0;
    wire [7:0] bg = (b > g) ? b-g : 8'd0;
    wire [7:0] threshold = (thr_in == 0) ? S_DEF : thr_in;
    wire red_hit = (rg >= threshold) && (rb >= threshold);
    wire green_hit = (gr >= threshold) && (gb >= threshold);
    wire blue_hit = (br >= threshold) && (bg >= threshold);
    wire abs_hit = (r >= R_MIN) && (r <= R_MAX) &&
                   (g >= G_MIN) && (g <= G_MAX) &&
                   (b >= B_MIN) && (b <= B_MAX);
    wire rule2_red_hit = (rg >= threshold) && (r >= R_SAT_MIN);
    wire rule2_green_hit = (gr >= threshold) && (g >= R_SAT_MIN);
    wire rule2_blue_hit = (br >= threshold) && (b >= R_SAT_MIN);
    wire rule2_hit = (TARGET_COLOR == 1) ? rule2_green_hit :
                     (TARGET_COLOR == 2) ? rule2_blue_hit : rule2_red_hit;
    // DET_RULE=3（交付包同款）= 规则2 + 保留"目标通道 vs 第三通道"的差分。
    // 交付包注释明确：加回第三通道差分挡不住白炽灯（暖白 R-B 本来就大），
    // 它的价值只在"画面里有青/品红类同亮度杂物"时收窄误判，故默认不开。
    wire rule3_red_hit = rule2_red_hit && (rb >= threshold);
    wire rule3_green_hit = rule2_green_hit && (gb >= threshold);
    wire rule3_blue_hit = rule2_blue_hit && (bg >= threshold);
    wire rule3_hit = (TARGET_COLOR == 1) ? rule3_green_hit :
                     (TARGET_COLOR == 2) ? rule3_blue_hit : rule3_red_hit;
    // 13 bits cover 31*255=7905. Constant-ratio products synthesize without division.
    // G/B=0 needs no special case; the independent RED_MIN rejects dark noise.
    wire [12:0] red_scaled = {1'b0, r, 4'b0000};
    wire [12:0] green_scaled = RED_RATIO_Q4 * {5'b00000, g};
    wire [12:0] blue_scaled = RED_RATIO_Q4 * {5'b00000, b};
    wire relative_red_hit = (r >= RED_MIN) &&
                            (red_scaled >= green_scaled) &&
                            (red_scaled >= blue_scaled);
    // A low ratio admits pale pink. Restrict hue around red to reject warm white
    // and orange: 3*abs(G-B) <= R-min(G,B), equivalent to +/-20 degrees for R=max.
    wire [7:0] gb_min = (g < b) ? g : b;
    wire [7:0] red_chroma = (r > gb_min) ? r-gb_min : 8'd0;
    wire [7:0] gb_delta = (g >= b) ? g-b : b-g;
    wire [9:0] hue_distance = {2'b00, gb_delta} + {1'b0, gb_delta, 1'b0};
    wire pink_red_hit = relative_red_hit && (red_chroma >= RED_CHROMA_MIN) &&
                        (hue_distance <= {2'b00, red_chroma});
    // Rule 6 retains the weak pink branch and admits a wider red hue only
    // for strongly red-dominant pixels. No low-saturation skin expansion.
    wire strong_red_hit=(r>=RED_MIN) && (red_chroma>=RED_CHROMA_MIN) &&
                        ({1'b0,r,1'b0}>={2'b00,g}+{1'b0,g,1'b0}) &&
                        ({1'b0,r,1'b0}>={2'b00,b}+{1'b0,b,1'b0}) &&
                        ({1'b0,gb_delta,1'b0}<={2'b00,red_chroma});
    wire color_hit = (DET_RULE == 1 || TARGET_COLOR == 3) ? abs_hit :
                     (DET_RULE == 2) ? rule2_hit :
                     (DET_RULE == 3) ? rule3_hit :
                     (DET_RULE == 4 && TARGET_COLOR == 0) ? relative_red_hit :
                     (DET_RULE == 5 && TARGET_COLOR == 0) ? pink_red_hit :
                     (DET_RULE == 6 && TARGET_COLOR == 0) ? (pink_red_hit || strong_red_hit) :
                     (TARGET_COLOR == 1) ? green_hit :
                     (TARGET_COLOR == 2) ? blue_hit : red_hit;

    wire vs_active = VS_ACTIVE_LOW ? ~vs_in : vs_in;
    reg vs_active_d;
    wire frame_start = vs_active && !vs_active_d;
    reg de_d;
    reg [XW-1:0] x_count;
    reg [YW-1:0] y_count;

    // DE按像素推进x，DE下降沿结束一行并推进y；VS有效沿重新定位帧首。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_active_d <= 1'b0;
            de_d <= 1'b0;
            x_count <= 0;
            y_count <= 0;
        end else begin
            vs_active_d <= vs_active;
            de_d <= de_in;
            if (frame_start) begin
                x_count <= 0;
                y_count <= 0;
            end else if (de_in) begin
                if (x_count == X_MAX) x_count <= 0;
                else x_count <= x_count + 1'b1;
            end else if (de_d) begin
                x_count <= 0;
                if (y_count == Y_MAX) y_count <= 0;
                else y_count <= y_count + 1'b1;
            end
        end
    end

    wire [XW-1:0] region_x0,region_x1;
    wire [YW-1:0] region_y0,region_y1;
    wire [HIT_W-1:0] region_hits;
    wire region_valid,region_overflow,region_fresh;
    generate if(DET_RULE==6 && TARGET_COLOR==0) begin:g_regions
        red_region_selector #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),
            .XW(XW),.YW(YW),.HIT_W(HIT_W),.MIN_PIX(MIN_PIX)) u_regions (
            .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.frame_start(frame_start),
            .de_in(de_in),.hit_in(color_hit),.x_in(x_count),.y_in(y_count),
            .x_min(region_x0),.x_max(region_x1),.y_min(region_y0),.y_max(region_y1),
            .valid(region_valid),.measurement_valid(region_fresh),.hits(region_hits),.overflow(region_overflow));
    end else begin:g_no_regions
        assign region_x0=0;assign region_x1=0;assign region_y0=0;assign region_y1=0;
        assign region_fresh=0;assign region_hits=0;assign region_valid=0;assign region_overflow=0;
    end endgenerate

    // 第一级：对齐原像素、检测结果、坐标和帧边界。
    reg [23:0] rgb1;
    reg [XW-1:0] x1;
    reg [YW-1:0] y1;
    reg hit1, enable1, de1, hs1, vs1, frame_start1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb1 <= 0; x1 <= 0; y1 <= 0;
            hit1 <= 0; enable1 <= 0; de1 <= 0; hs1 <= 0; vs1 <= 0; frame_start1 <= 0;
        end else begin
            rgb1 <= rgb_in;
            x1 <= x_count;
            y1 <= y_count;
            hit1 <= color_hit;
            enable1 <= enable_in;
            de1 <= de_in; hs1 <= hs_in; vs1 <= vs_in;
            frame_start1 <= frame_start;
        end
    end

    reg [XW-1:0] stat_x_min, stat_x_max;
    reg [YW-1:0] stat_y_min, stat_y_max;
    reg [HIT_W-1:0] stat_hits;
    reg stat_seen;
    wire [XW-1:0] x_min_next = (!stat_seen || x1 < stat_x_min) ? x1 : stat_x_min;
    wire [XW-1:0] x_max_next = (!stat_seen || x1 > stat_x_max) ? x1 : stat_x_max;
    wire [YW-1:0] y_min_next = (!stat_seen || y1 < stat_y_min) ? y1 : stat_y_min;
    wire [YW-1:0] y_max_next = (!stat_seen || y1 > stat_y_max) ? y1 : stat_y_max;
    wire hit1_valid = de1 && hit1;
    wire [XW-1:0] publish_x_min = (hit1_valid && enable1) ? x_min_next : stat_x_min;
    wire [XW-1:0] publish_x_max = (hit1_valid && enable1) ? x_max_next : stat_x_max;
    wire [YW-1:0] publish_y_min = (hit1_valid && enable1) ? y_min_next : stat_y_min;
    wire [YW-1:0] publish_y_max = (hit1_valid && enable1) ? y_max_next : stat_y_max;
    wire [HIT_W-1:0] publish_hits = stat_hits + ((hit1_valid && enable1) ? 1'b1 : 1'b0);
    wire publish_seen = stat_seen || (hit1_valid && enable1);

    // Shape geometry is evaluated from the same current-frame values that are
    // published at frame_start1, including a hit on the final active pixel.
    localparam integer FW_W = XW + 1;
    localparam integer FH_W = YW + 1;
    localparam integer AREA_W = FW_W + FH_W;
    localparam integer ASPECT_W = ((FW_W + 4) > (FH_W + 8)) ? (FW_W + 4) : (FH_W + 8);
    localparam integer SHAPE_PROD_W = AREA_W + 9;
    localparam integer SHAPE_CMP_W = ((SHAPE_PROD_W) > (HIT_W + 8)) ? SHAPE_PROD_W : (HIT_W + 8);
    wire [FW_W-1:0] shape_w = publish_seen ?
        ({1'b0, publish_x_max} - {1'b0, publish_x_min} + {{XW{1'b0}}, 1'b1}) : {FW_W{1'b0}};
    wire [FH_W-1:0] shape_h = publish_seen ?
        ({1'b0, publish_y_max} - {1'b0, publish_y_min} + {{YW{1'b0}}, 1'b1}) : {FH_W{1'b0}};
    wire [ASPECT_W-1:0] shape_w16 = {shape_w, 4'b0};
    wire [ASPECT_W-1:0] aspect_min_h = ASPECT_MIN_Q44 * shape_h;
    wire [ASPECT_W-1:0] aspect_max_h = ASPECT_MAX_Q44 * shape_h;
    wire aspect_pass = publish_seen && (shape_w != 0) && (shape_h != 0) &&
                       (shape_w16 >= aspect_min_h) && (shape_w16 <= aspect_max_h);

    wire [AREA_W-1:0] shape_w_ext = shape_w;
    wire [AREA_W-1:0] shape_h_ext = shape_h;
    wire [2*AREA_W-1:0] shape_area_full = shape_w_ext * shape_h_ext;
    wire [AREA_W-1:0] shape_area = shape_area_full[AREA_W-1:0];
    wire [SHAPE_PROD_W-1:0] area_ext = shape_area;
    wire [SHAPE_PROD_W-1:0] fill_min_ext = FILL_MIN_Q8;
    wire [SHAPE_PROD_W-1:0] fill_max_ext = FILL_MAX_Q8;
    wire [2*SHAPE_PROD_W-1:0] fill_min_full = fill_min_ext * area_ext;
    wire [2*SHAPE_PROD_W-1:0] fill_max_full = fill_max_ext * area_ext;
    wire [SHAPE_PROD_W-1:0] fill_min_area = fill_min_full[SHAPE_PROD_W-1:0];
    wire [SHAPE_PROD_W-1:0] fill_max_area = fill_max_full[SHAPE_PROD_W-1:0];
    wire [SHAPE_CMP_W-1:0] shape_hits256 =
        {{(SHAPE_CMP_W-HIT_W-8){1'b0}}, publish_hits, 8'b0};
    wire [SHAPE_CMP_W-1:0] fill_min_cmp = fill_min_area;
    wire [SHAPE_CMP_W-1:0] fill_max_cmp = fill_max_area;
    wire fill_pass = (SHAPE_FILL_EN == 0) ||
                     (publish_seen && (shape_area != 0) &&
                      (shape_hits256 >= fill_min_cmp) && (shape_hits256 <= fill_max_cmp));

    localparam [8:0] RECT_MIN_Q8 = (SHAPE_TOL_Q8 >= 8'd255) ? 9'd0 : (9'd255 - SHAPE_TOL_Q8);
    localparam [8:0] CIRC_MIN_Q8 = (SHAPE_TOL_Q8 >= 8'd201) ? 9'd0 : (9'd201 - SHAPE_TOL_Q8);
    localparam [8:0] CIRC_MAX_Q8 = 9'd201 + SHAPE_TOL_Q8;
    localparam [8:0] TRI_MIN_Q8 = (SHAPE_TOL_Q8 >= 8'd128) ? 9'd0 : (9'd128 - SHAPE_TOL_Q8);
    localparam [8:0] TRI_MAX_Q8 = 9'd128 + SHAPE_TOL_Q8;
    wire [SHAPE_PROD_W-1:0] rect_min_ext = RECT_MIN_Q8;
    wire [SHAPE_PROD_W-1:0] circ_min_ext = CIRC_MIN_Q8;
    wire [SHAPE_PROD_W-1:0] circ_max_ext = CIRC_MAX_Q8;
    wire [SHAPE_PROD_W-1:0] tri_min_ext = TRI_MIN_Q8;
    wire [SHAPE_PROD_W-1:0] tri_max_ext = TRI_MAX_Q8;
    wire [2*SHAPE_PROD_W-1:0] rect_min_full = rect_min_ext * area_ext;
    wire [2*SHAPE_PROD_W-1:0] circ_min_full = circ_min_ext * area_ext;
    wire [2*SHAPE_PROD_W-1:0] circ_max_full = circ_max_ext * area_ext;
    wire [2*SHAPE_PROD_W-1:0] tri_min_full = tri_min_ext * area_ext;
    wire [2*SHAPE_PROD_W-1:0] tri_max_full = tri_max_ext * area_ext;
    wire [SHAPE_PROD_W-1:0] rect_min_area = rect_min_full[SHAPE_PROD_W-1:0];
    wire [SHAPE_PROD_W-1:0] circ_min_area = circ_min_full[SHAPE_PROD_W-1:0];
    wire [SHAPE_PROD_W-1:0] circ_max_area = circ_max_full[SHAPE_PROD_W-1:0];
    wire [SHAPE_PROD_W-1:0] tri_min_area = tri_min_full[SHAPE_PROD_W-1:0];
    wire [SHAPE_PROD_W-1:0] tri_max_area = tri_max_full[SHAPE_PROD_W-1:0];
    wire [SHAPE_CMP_W-1:0] rect_min_cmp = rect_min_area;
    wire [SHAPE_CMP_W-1:0] circ_min_cmp = circ_min_area;
    wire [SHAPE_CMP_W-1:0] circ_max_cmp = circ_max_area;
    wire [SHAPE_CMP_W-1:0] tri_min_cmp = tri_min_area;
    wire [SHAPE_CMP_W-1:0] tri_max_cmp = tri_max_area;
    wire classify_rect = publish_seen && (shape_area != 0) && (shape_hits256 >= rect_min_cmp);
    wire classify_circle = publish_seen && (shape_area != 0) &&
                           (shape_hits256 >= circ_min_cmp) && (shape_hits256 <= circ_max_cmp);
    wire classify_triangle = publish_seen && (shape_area != 0) &&
                             (shape_hits256 >= tri_min_cmp) && (shape_hits256 <= tri_max_cmp);
    wire [1:0] shape_type_now = classify_rect ? 2'd1 : classify_circle ? 2'd2 :
                                classify_triangle ? 2'd3 : 2'd0;
    wire shape_pass = aspect_pass && fill_pass &&
                      ((TARGET_SHAPE == 0) || (shape_type_now == TARGET_SHAPE[1:0]));
    wire [7:0] aspect_band = !publish_seen || (shape_h == 0) ? 8'd0 :
                             (shape_w16 < aspect_min_h) ? 8'd0 :
                             (shape_w16 > aspect_max_h) ? 8'd2 : 8'd1;
    wire [7:0] fill_band = (SHAPE_FILL_EN == 0) ? 8'd1 :
                            (!publish_seen || (shape_area == 0)) ? 8'd0 :
                            (shape_hits256 < fill_min_cmp) ? 8'd0 :
                            (shape_hits256 > fill_max_cmp) ? 8'd2 : 8'd1;
    wire publish_raw_valid = publish_seen && (publish_hits >= MIN_PIX);
    wire publish_shape_valid = publish_raw_valid &&
                               ((SHAPE_FILTER_EN == 0) || shape_pass);

    // 消费stage1数据。若VS紧随最后一个输入像素，其统计仍先进入本级再发布。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stat_x_min <= {XW{1'b1}}; stat_x_max <= 0;
            stat_y_min <= {YW{1'b1}}; stat_y_max <= 0;
            stat_hits <= 0; stat_seen <= 0;
            bbox_x_min <= 0; bbox_x_max <= 0; bbox_y_min <= 0; bbox_y_max <= 0;
            bbox_fresh <= 0; bbox_valid <= 0; hit_cnt <= 0;
            shape_type <= 0; shape_ok <= 0; bbox_valid_raw <= 0;
            fill_ratio_q8 <= 0; aspect_ratio_q44 <= 0;
        end else if (!enable_in || (frame_start1 && !enable1)) begin
            stat_x_min <= {XW{1'b1}}; stat_x_max <= 0;
            stat_y_min <= {YW{1'b1}}; stat_y_max <= 0;
            stat_hits <= 0; stat_seen <= 0;
            bbox_x_min <= 0; bbox_x_max <= 0; bbox_y_min <= 0; bbox_y_max <= 0;
            bbox_fresh <= 0; bbox_valid <= 0; hit_cnt <= 0;
            shape_type <= 0; shape_ok <= 0; bbox_valid_raw <= 0;
            fill_ratio_q8 <= 0; aspect_ratio_q44 <= 0;
        end else if (DET_RULE==6 && TARGET_COLOR==0) begin
            bbox_x_min<=region_x0;bbox_x_max<=region_x1;
            bbox_y_min<=region_y0;bbox_y_max<=region_y1;bbox_valid<=region_valid;
            bbox_fresh<=region_fresh;
            bbox_valid_raw<=region_valid;shape_ok<=region_valid;shape_type<=0;hit_cnt<=region_hits;
            fill_ratio_q8<=region_valid?1:0;aspect_ratio_q44<=region_valid?1:0;
        end else if (frame_start1) begin
            bbox_fresh <= publish_shape_valid;
            bbox_valid <= publish_shape_valid;
            bbox_valid_raw <= publish_raw_valid;
            shape_type <= publish_raw_valid ? shape_type_now : 2'd0;
            shape_ok <= publish_shape_valid;
            fill_ratio_q8 <= fill_band;
            aspect_ratio_q44 <= aspect_band;
            bbox_x_min <= publish_raw_valid ? publish_x_min : 0;
            bbox_x_max <= publish_raw_valid ? publish_x_max : 0;
            bbox_y_min <= publish_raw_valid ? publish_y_min : 0;
            bbox_y_max <= publish_raw_valid ? publish_y_max : 0;
            hit_cnt <= publish_hits;
            stat_x_min <= {XW{1'b1}}; stat_x_max <= 0;
            stat_y_min <= {YW{1'b1}}; stat_y_max <= 0;
            stat_hits <= 0; stat_seen <= 0;
        end else if (hit1_valid && enable1) begin
            stat_x_min <= x_min_next; stat_x_max <= x_max_next;
            stat_y_min <= y_min_next; stat_y_max <= y_max_next;
            stat_hits <= stat_hits + 1'b1;
            stat_seen <= 1'b1;
        end
    end

    // 第二级：用稳定的上一帧bbox判断框边，避免比较链进入帧统计反馈。
    reg [23:0] rgb2;
    reg hit2, enable2, de2, hs2, vs2, box2;
    reg [XW-1:0] x2;
    reg [YW-1:0] y2;
    wire in_span = bbox_valid && x1 >= bbox_x_min && x1 <= bbox_x_max &&
                   y1 >= bbox_y_min && y1 <= bbox_y_max;
    wire on_edge = ((x1 - bbox_x_min) < BOX_W) || ((bbox_x_max - x1) < BOX_W) ||
                   ((y1 - bbox_y_min) < BOX_W) || ((bbox_y_max - y1) < BOX_W);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb2 <= 0; hit2 <= 0; enable2 <= 0; de2 <= 0; hs2 <= 0; vs2 <= 0; box2 <= 0;
            x2 <= 0; y2 <= 0;
        end else begin
            rgb2 <= rgb1; hit2 <= hit1; enable2 <= enable1; de2 <= de1; hs2 <= hs1; vs2 <= vs1;
            x2 <= x1; y2 <= y1;
            box2 <= in_span && (BOX_FILL || on_edge);
        end
    end

    // 第三级：输出图像、掩膜与同步；RGB原图逐位保持。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb_out <= 0; y_out <= 0; bin_out <= 0;
            de_out <= 0; hs_out <= 0; vs_out <= 0;
        end else begin
            // DEBUG_VIEW（交付包同款）：命中=纯绿，未命中=原图右移2位（变暗1/4），
            // 用于现场调颜色阈值；生产 DEBUG_VIEW=0 时该分支被常量折叠。
            rgb_out <= DEBUG_VIEW ? (hit2 ? 24'h00ff00 : {2'b00, rgb2[23:2]}) :
                       ((enable2 && de2 && box2) ? BOX_COLOR : rgb2);
            y_out <= hit2 ? 8'hff : 8'h00;
            bin_out <= hit2;
            de_out <= de2; hs_out <= hs2; vs_out <= vs2;
        end
    end
endmodule
