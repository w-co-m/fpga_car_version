`timescale 1ns/1ps
// RGB888 实时分支共享5拍输出延迟；9..12是后台偏振结果页直通。
// 模块作用：处理同一视频流并按DDR已确认的mode选择，14运动检测，15目标跟踪。
// 模式0..8：原图、灰度、二值化、Sobel、亮度、对比度、均衡、腐蚀、膨胀。
module algo_bank #(
 parameter IMG_WIDTH=1280,
 parameter IMG_HEIGHT=720,
 parameter LB_DEPTH=2048,
 parameter LB_AW=11,
 parameter BIN_THRESHOLD=8'd128,
 parameter EDGE_THRESHOLD=8'd32,
 parameter DYNAMIC_THRESHOLD=0, // 0使用综合参数，1使用输入的运行时阈值
 parameter DYNAMIC_GAIN=0, // 0保留固定增益，1使用帧边界提交的运行时增益
 parameter [7:0] BRIGHT_GAIN=24, // Q4.4：24表示1.5倍亮度增益
 parameter [7:0] CONTRAST_GAIN=24, // 围绕128拉伸，Q4.4增益1.5倍
 parameter [7:0] COLOR_THRESHOLD=8'd96, // 旧规则0~3色差门限；规则4使用独立相对红度参数
 parameter COLOR_MIN_PIX=16,
 parameter MOTION_THRESHOLD=8,
 parameter MOTION_MIN_PIX=1000,
 parameter OUTPUT_LATENCY=5,
 parameter VS_ACTIVE_LOW=0,
 parameter integer COLOR_DET_RULE=6,
 parameter [7:0] COLOR_RED_MIN=8'd24,
 parameter [4:0] COLOR_RED_RATIO_Q4=5'd17,
 parameter [7:0] COLOR_RED_CHROMA_MIN=8'd6,
 parameter [7:0] COLOR_ASPECT_MIN_Q44=8'd5,
 parameter [7:0] COLOR_ASPECT_MAX_Q44=8'd48,
 parameter [8:0] COLOR_FILL_MIN_Q8=9'd64,
 parameter integer MOTION_BLOCK_MEAN=1,
 parameter integer MOTION_DYNAMIC_THRESHOLD=0
)(
 input wire clk,input wire rst_n,input wire [23:0] rgb_in,input wire [3:0] mode,
 input wire de_in,input wire hs_in,input wire vs_in,
 input wire [7:0] bin_threshold_in,input wire [7:0] edge_threshold_in,
 input wire [7:0] bright_gain_in,input wire [7:0] contrast_gain_in,
 output reg [23:0] rgb_out,output reg de_out,output reg hs_out,output reg vs_out,
 input wire color_debug_in, // SW1 in mode13; omitted legacy inputs are treated as off.
 input wire [7:0] motion_threshold_in,
 output wire trk_update, trk_valid,
 output wire [4:0] trk_lost_cnt,
 output wire [((IMG_WIDTH<=1)?1:$clog2(IMG_WIDTH))-1:0] trk_x_min,trk_x_max,
 output wire [((IMG_HEIGHT<=1)?1:$clog2(IMG_HEIGHT))-1:0] trk_y_min,trk_y_max
);
 // 重要：这是各分支的原始流水级数。公共 OUTPUT_LATENCY 不得小于最长分支。
 // 新增算法时更新实例、信号、延迟补偿和 case，并修改顶层 ALGO_COUNT。
 localparam RAW_LATENCY=1,GRAY_LATENCY=2,BINARY_LATENCY=3,SOBEL_LATENCY=5;
 // Invalid integration parameters must fail elaboration instead of wrapping addresses.
 generate if(OUTPUT_LATENCY<5 || IMG_WIDTH>LB_DEPTH || IMG_WIDTH>(1<<LB_AW))begin:g_bad_config
  ERROR_ALGO_BANK_LATENCY_OR_LINE_BUFFER_CONFIGURATION invalid_configuration();
 end endgenerate
 wire [23:0] raw_rgb,gray_rgb,bin_rgb,sobel_rgb;
 wire [7:0] gray_y;
 wire raw_de,raw_hs,raw_vs,gray_de,gray_hs,gray_vs,bin_de,bin_hs,bin_vs,sobel_de,sobel_hs,sobel_vs;
 wire [23:0] raw_aligned,gray_aligned,bin_aligned,sobel_aligned;
 wire raw_de_a,raw_hs_a,raw_vs_a,gray_de_a,gray_hs_a,gray_vs_a,bin_de_a,bin_hs_a,bin_vs_a,sobel_de_a,sobel_hs_a,sobel_vs_a;
 // 九路同时运行，Sobel 行缓存持续积累历史行，切换到它时不必重新等待缓存填充。
 algo_passthrough u_raw(.clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.rgb_out(raw_rgb),.de_out(raw_de),.hs_out(raw_hs),.vs_out(raw_vs));
 algo_gray u_gray(.clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.rgb_out(gray_rgb),.y_out(gray_y),.de_out(gray_de),.hs_out(gray_hs),.vs_out(gray_vs));
 algo_binary #(.BIN_THRESHOLD(BIN_THRESHOLD),.DYNAMIC_THRESHOLD(DYNAMIC_THRESHOLD)) u_binary(.clk(clk),.rst_n(rst_n),.threshold_in(bin_threshold_in),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.rgb_out(bin_rgb),.de_out(bin_de),.hs_out(bin_hs),.vs_out(bin_vs));
 algo_sobel #(.IMG_WIDTH(IMG_WIDTH),.LB_DEPTH(LB_DEPTH),.LB_AW(LB_AW),.EDGE_THRESHOLD(EDGE_THRESHOLD),.VS_ACTIVE_LOW(VS_ACTIVE_LOW),.DYNAMIC_THRESHOLD(DYNAMIC_THRESHOLD)) u_sobel(.clk(clk),.rst_n(rst_n),.threshold_in(edge_threshold_in),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.rgb_out(sobel_rgb),.de_out(sobel_de),.hs_out(sobel_hs),.vs_out(sobel_vs));
 // 统一总延迟为 5 级：原图补 4、灰度补 3、二值化补 2、Sobel 补 0。
 // RGB 和 DE/HS/VS 一起延迟，不能只补颜色数据，否则像素与显示位置错位。
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-RAW_LATENCY)) u_raw_align(.clk(clk),.rst_n(rst_n),.data_in(raw_rgb),.de_in(raw_de),.hs_in(raw_hs),.vs_in(raw_vs),.data_out(raw_aligned),.de_out(raw_de_a),.hs_out(raw_hs_a),.vs_out(raw_vs_a));
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-GRAY_LATENCY)) u_gray_align(.clk(clk),.rst_n(rst_n),.data_in(gray_rgb),.de_in(gray_de),.hs_in(gray_hs),.vs_in(gray_vs),.data_out(gray_aligned),.de_out(gray_de_a),.hs_out(gray_hs_a),.vs_out(gray_vs_a));
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-BINARY_LATENCY)) u_binary_align(.clk(clk),.rst_n(rst_n),.data_in(bin_rgb),.de_in(bin_de),.hs_in(bin_hs),.vs_in(bin_vs),.data_out(bin_aligned),.de_out(bin_de_a),.hs_out(bin_hs_a),.vs_out(bin_vs_a));
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-SOBEL_LATENCY)) u_sobel_align(.clk(clk),.rst_n(rst_n),.data_in(sobel_rgb),.de_in(sobel_de),.hs_in(sobel_hs),.vs_in(sobel_vs),.data_out(sobel_aligned),.de_out(sobel_de_a),.hs_out(sobel_hs_a),.vs_out(sobel_vs_a));
 // 新增分支持续运行，直方图均衡利用上一帧统计；形态学处理灰度3x3邻域。
 wire [23:0] bright_rgb,bright_aligned;
 wire bright_de,bright_hs,bright_vs,bright_de_a,bright_hs_a,bright_vs_a;
 algo_bright u_bright(.clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(DYNAMIC_GAIN ? bright_gain_in : BRIGHT_GAIN),.rgb_out(bright_rgb),.y_out(),.bin_out(),.de_out(bright_de),.hs_out(bright_hs),.vs_out(bright_vs));
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-3)) u_bright_align(.clk(clk),.rst_n(rst_n),.data_in(bright_rgb),.de_in(bright_de),.hs_in(bright_hs),.vs_in(bright_vs),.data_out(bright_aligned),.de_out(bright_de_a),.hs_out(bright_hs_a),.vs_out(bright_vs_a));
 wire [23:0] contrast_rgb,contrast_aligned;
 wire contrast_de,contrast_hs,contrast_vs,contrast_de_a,contrast_hs_a,contrast_vs_a;
 algo_contrast u_contrast(.clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(DYNAMIC_GAIN ? contrast_gain_in : CONTRAST_GAIN),.rgb_out(contrast_rgb),.y_out(),.bin_out(),.de_out(contrast_de),.hs_out(contrast_hs),.vs_out(contrast_vs));
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-3)) u_contrast_align(.clk(clk),.rst_n(rst_n),.data_in(contrast_rgb),.de_in(contrast_de),.hs_in(contrast_hs),.vs_in(contrast_vs),.data_out(contrast_aligned),.de_out(contrast_de_a),.hs_out(contrast_hs_a),.vs_out(contrast_vs_a));
 wire [23:0] histeq_rgb,histeq_aligned;
 wire histeq_de,histeq_hs,histeq_vs,histeq_de_a,histeq_hs_a,histeq_vs_a;
 algo_histeq #(.HIST_BITS(20),.VS_ACTIVE_LOW(VS_ACTIVE_LOW)) u_histeq(.clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(8'd128),.rgb_out(histeq_rgb),.y_out(),.bin_out(),.de_out(histeq_de),.hs_out(histeq_hs),.vs_out(histeq_vs));
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-4)) u_histeq_align(.clk(clk),.rst_n(rst_n),.data_in(histeq_rgb),.de_in(histeq_de),.hs_in(histeq_hs),.vs_in(histeq_vs),.data_out(histeq_aligned),.de_out(histeq_de_a),.hs_out(histeq_hs_a),.vs_out(histeq_vs_a));
 wire [23:0] erode_rgb,erode_aligned;
 wire erode_de,erode_hs,erode_vs,erode_de_a,erode_hs_a,erode_vs_a;
 algo_morph #(.LB_W(IMG_WIDTH),.LB_DEPTH(LB_DEPTH),.LB_AW(LB_AW),.VS_ACTIVE_LOW(VS_ACTIVE_LOW),.OP_FROM_THR(0),.MORPH_OP(0)) u_erode(.clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(8'd128),.rgb_out(erode_rgb),.y_out(),.bin_out(),.de_out(erode_de),.hs_out(erode_hs),.vs_out(erode_vs));
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-4)) u_erode_align(.clk(clk),.rst_n(rst_n),.data_in(erode_rgb),.de_in(erode_de),.hs_in(erode_hs),.vs_in(erode_vs),.data_out(erode_aligned),.de_out(erode_de_a),.hs_out(erode_hs_a),.vs_out(erode_vs_a));
 wire [23:0] dilate_rgb,dilate_aligned;
 wire dilate_de,dilate_hs,dilate_vs,dilate_de_a,dilate_hs_a,dilate_vs_a;
 algo_morph #(.LB_W(IMG_WIDTH),.LB_DEPTH(LB_DEPTH),.LB_AW(LB_AW),.VS_ACTIVE_LOW(VS_ACTIVE_LOW),.OP_FROM_THR(0),.MORPH_OP(1)) u_dilate(.clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(8'd128),.rgb_out(dilate_rgb),.y_out(),.bin_out(),.de_out(dilate_de),.hs_out(dilate_hs),.vs_out(dilate_vs));
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-4)) u_dilate_align(.clk(clk),.rst_n(rst_n),.data_in(dilate_rgb),.de_in(dilate_de),.hs_in(dilate_hs),.vs_in(dilate_vs),.data_out(dilate_aligned),.de_out(dilate_de_a),.hs_out(dilate_hs_a),.vs_out(dilate_vs_a));
 // 颜色检测始终共享原始RGB输入；偏振页只关闭本帧统计，避免把结果页当作新目标。
 wire live_algorithm_enable=!((mode>=4'd9)&&(mode<=4'd12));
 localparam TRACK_XW=(IMG_WIDTH<=1)?1:$clog2(IMG_WIDTH);
 localparam TRACK_YW=(IMG_HEIGHT<=1)?1:$clog2(IMG_HEIGHT);
 wire [TRACK_XW-1:0] color_bbox_x_min,color_bbox_x_max;
 wire [TRACK_YW-1:0] color_bbox_y_min,color_bbox_y_max;
 wire color_bbox_valid,color_bbox_fresh;
 wire [23:0] color_rgb,color_aligned;
 wire color_mask,color_mask_aligned;
 wire color_de,color_hs,color_vs,color_de_a,color_hs_a,color_vs_a;
 reg color_vs_prev,color_debug_active;
 wire color_vs_active=VS_ACTIVE_LOW ? ~vs_in : vs_in;
 always @(posedge clk or negedge rst_n)
   if(!rst_n)begin color_vs_prev<=0;color_debug_active<=0;end
   else begin
     color_vs_prev<=color_vs_active;
     if(color_vs_active && !color_vs_prev && !de_in)
       color_debug_active<=(color_debug_in===1'b1);
   end
 algo_color_detect #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.TARGET_COLOR(0),
     .DET_RULE(COLOR_DET_RULE),.RED_MIN(COLOR_RED_MIN),.RED_RATIO_Q4(COLOR_RED_RATIO_Q4),
     .RED_CHROMA_MIN(COLOR_RED_CHROMA_MIN),
     .R_SAT_MIN(8'd192),.SHAPE_FILTER_EN(1),.TARGET_SHAPE(0),
     .ASPECT_MIN_Q44(COLOR_ASPECT_MIN_Q44),.ASPECT_MAX_Q44(COLOR_ASPECT_MAX_Q44),
     .FILL_MIN_Q8(COLOR_FILL_MIN_Q8),
     .S_DEF(COLOR_THRESHOLD),.MIN_PIX(COLOR_MIN_PIX),.BOX_W(2),.BOX_FILL(0),
     .BOX_COLOR(24'h00ff00),.VS_ACTIVE_LOW(VS_ACTIVE_LOW)) u_color_detect (
     .clk(clk),.rst_n(rst_n),.enable_in(live_algorithm_enable),
     .rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(8'd0),
     .rgb_out(color_rgb),.y_out(),.bin_out(color_mask),.de_out(color_de),.hs_out(color_hs),.vs_out(color_vs),
     .bbox_x_min(color_bbox_x_min),.bbox_x_max(color_bbox_x_max),
     .bbox_y_min(color_bbox_y_min),.bbox_y_max(color_bbox_y_max),.bbox_valid(color_bbox_valid),.bbox_fresh(color_bbox_fresh),.hit_cnt(),
     .shape_type(),.shape_ok(),.bbox_valid_raw(),.fill_ratio_q8(),.aspect_ratio_q44());
 // 检测核为3拍，补齐到各模式共用的OUTPUT_LATENCY级。
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-3)) u_color_align(
     .clk(clk),.rst_n(rst_n),.data_in(color_rgb),.de_in(color_de),.hs_in(color_hs),.vs_in(color_vs),
     .data_out(color_aligned),.de_out(color_de_a),.hs_out(color_hs_a),.vs_out(color_vs_a));
 video_delay #(.DATA_WIDTH(1),.DELAY(OUTPUT_LATENCY-3)) u_color_mask_align(
     .clk(clk),.rst_n(rst_n),.data_in(color_mask),.de_in(color_de),.hs_in(color_hs),.vs_in(color_vs),
     .data_out(color_mask_aligned),.de_out(),.hs_out(),.vs_out());
 // Tracking reuses the detector's published frame bbox and always sees the original stream.
 wire [23:0] track_rgb,track_aligned;
 wire track_de,track_hs,track_vs,track_de_a,track_hs_a,track_vs_a;
 algo_track #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),
     .DET_XW(TRACK_XW),.DET_YW(TRACK_YW),.SMOOTH_SHIFT(2),.LOST_MAX(15),
     .SNAP_DIST(64),.BOX_W(2),.HINT_EN(0),.VS_ACTIVE_LOW(VS_ACTIVE_LOW)) u_track (
     .clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),
     .enable_in(live_algorithm_enable),.det_x_min(color_bbox_x_min),.det_x_max(color_bbox_x_max),
     .det_y_min(color_bbox_y_min),.det_y_max(color_bbox_y_max),.det_valid(color_bbox_fresh),.mot_in(1'b0),
     .trk_x_min(trk_x_min),.trk_x_max(trk_x_max),.trk_y_min(trk_y_min),.trk_y_max(trk_y_max),.trk_valid(trk_valid),.lost_cnt(trk_lost_cnt),.update_out(trk_update),
     .rgb_out(track_rgb),.y_out(),.bin_out(),.de_out(track_de),.hs_out(track_hs),.vs_out(track_vs));
 // Tracker adds two pixel clocks; align its RGB and syncs with the shared output latency.
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-2)) u_track_align(
     .clk(clk),.rst_n(rst_n),.data_in(track_rgb),.de_in(track_de),.hs_in(track_hs),.vs_in(track_vs),
     .data_out(track_aligned),.de_out(track_de_a),.hs_out(track_hs_a),.vs_out(track_vs_a));
 // 算法11复用灰度核：原RGB补1拍到总2拍，与gray_y/gray_de同位置。
 // 参考在普通RGB模式连续更新；偏振结果页期间失效，返回后完整预热一帧。
 wire [23:0] raw_gray_aligned,motion_rgb,motion_aligned;
 wire motion_de,motion_hs,motion_vs,motion_de_a,motion_hs_a,motion_vs_a;
 // A threshold committed on raw VS must travel with gray RGB/sync. Without
 // these two stages it can affect the previous frame's final block in flight.
 reg [7:0] motion_threshold_gray1,motion_threshold_gray2;
 always @(posedge clk or negedge rst_n)
   if(!rst_n)begin
     motion_threshold_gray1<=MOTION_THRESHOLD;
     motion_threshold_gray2<=MOTION_THRESHOLD;
   end else begin
     motion_threshold_gray1<=motion_threshold_in;
     motion_threshold_gray2<=motion_threshold_gray1;
   end
 video_delay #(.DATA_WIDTH(24),.DELAY(GRAY_LATENCY-RAW_LATENCY)) u_motion_rgb_align(
     .clk(clk),.rst_n(rst_n),.data_in(raw_rgb),.de_in(raw_de),.hs_in(raw_hs),.vs_in(raw_vs),
     .data_out(raw_gray_aligned),.de_out(),.hs_out(),.vs_out());
 algo_motion #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.DS_LOG2(4),
     .BLOCK_MEAN_MODE(MOTION_BLOCK_MEAN),
     .DIFF_THR(MOTION_THRESHOLD),.MOTION_CNT(MOTION_MIN_PIX),.VS_ACTIVE_LOW(VS_ACTIVE_LOW)) u_motion(
     .clk(clk),.rst_n(rst_n),.enable_in(live_algorithm_enable),.rgb_in(raw_gray_aligned),
     .y_in(gray_y),.de_in(gray_de),.hs_in(gray_hs),.vs_in(gray_vs),
     .threshold_in(MOTION_DYNAMIC_THRESHOLD ? motion_threshold_gray2 : 8'd0),
     .rgb_out(motion_rgb),.mask_out(),.bin_out(),.motion_detected(),.motion_pixel_cnt(),.ref_ready(),
     .de_out(motion_de),.hs_out(motion_hs),.vs_out(motion_vs));
 video_delay #(.DATA_WIDTH(24),.DELAY(OUTPUT_LATENCY-GRAY_LATENCY-2)) u_motion_align(
     .clk(clk),.rst_n(rst_n),.data_in(motion_rgb),.de_in(motion_de),.hs_in(motion_hs),.vs_in(motion_vs),
     .data_out(motion_aligned),.de_out(motion_de_a),.hs_out(motion_hs_a),.vs_out(motion_vs_a));
 // 组合多路选择器，不再增加寄存级；模式应在集成模块的垂直消隐期切换。
 always @* begin
  case(mode)
   4'd1:begin rgb_out=gray_aligned;de_out=gray_de_a;hs_out=gray_hs_a;vs_out=gray_vs_a;end
   4'd2:begin rgb_out=bin_aligned;de_out=bin_de_a;hs_out=bin_hs_a;vs_out=bin_vs_a;end
   4'd3:begin rgb_out=sobel_aligned;de_out=sobel_de_a;hs_out=sobel_hs_a;vs_out=sobel_vs_a;end
   4'd4:begin rgb_out=bright_aligned;de_out=bright_de_a;hs_out=bright_hs_a;vs_out=bright_vs_a;end
   4'd5:begin rgb_out=contrast_aligned;de_out=contrast_de_a;hs_out=contrast_hs_a;vs_out=contrast_vs_a;end
   4'd6:begin rgb_out=histeq_aligned;de_out=histeq_de_a;hs_out=histeq_hs_a;vs_out=histeq_vs_a;end
   4'd7:begin rgb_out=erode_aligned;de_out=erode_de_a;hs_out=erode_hs_a;vs_out=erode_vs_a;end
   4'd8:begin rgb_out=dilate_aligned;de_out=dilate_de_a;hs_out=dilate_hs_a;vs_out=dilate_vs_a;end
   // 后台DoLP/AoP/Fusion/PEDGE页已经是RGB888结果，直接沿用RAW的5级延迟。
   4'd9,4'd10,4'd11,4'd12:begin rgb_out=raw_aligned;de_out=raw_de_a;hs_out=raw_hs_a;vs_out=raw_vs_a;end
   4'd13:begin rgb_out=color_debug_active ? (color_mask_aligned ? 24'h00ff00 : 24'h000000) : color_aligned;de_out=color_de_a;hs_out=color_hs_a;vs_out=color_vs_a;end
   4'd14:begin rgb_out=motion_aligned;de_out=motion_de_a;hs_out=motion_hs_a;vs_out=motion_vs_a;end
   4'd15:begin rgb_out=track_aligned;de_out=track_de_a;hs_out=track_hs_a;vs_out=track_vs_a;end
   default:begin rgb_out=raw_aligned;de_out=raw_de_a;hs_out=raw_hs_a;vs_out=raw_vs_a;end
  endcase
 end
endmodule

