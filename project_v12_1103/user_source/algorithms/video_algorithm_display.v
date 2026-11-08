`timescale 1ns/1ps
// Common pixel-domain integration point. Extend algo_bank, then ALGO_COUNT.
// 模块作用：连接按键控制与算法库。所有图像处理均在 HDMI 像素时钟域完成。
// 端口约定：RGB888 的高、中、低字节分别为 R、G、B；DE 高有效，RGB 与同步信号必须同拍对应。
module video_algorithm_display #(
    // 配置参数在综合前确定。CLK_HZ 应匹配实际像素时钟；ALGO_COUNT 必须与算法库分支数量一致。
    parameter CLK_HZ = 75000000,
    parameter DEBOUNCE_MS = 20,
    parameter DEBOUNCE_CYCLES = 0,
    parameter ALGO_COUNT = 16,
    parameter EXTERNAL_RENDER_MODE = 0,
    parameter ENABLE_POLAR_CONTROL = 0,
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter BIN_THRESHOLD = 128,
    parameter EDGE_THRESHOLD = 32,
    parameter THRESHOLD_STEP = 1,

    parameter BRIGHT_GAIN = 24,
    parameter CONTRAST_GAIN = 24,
    parameter GAIN_STEP = 1,

    parameter ENABLE_FRAME_GUARD = 0,

    parameter MOTION_THRESHOLD = 8,
    parameter ENABLE_MOTION_THRESHOLD_CONTROL = 1,

    // 各运行时参数的允许调节范围
    parameter BIN_THRESHOLD_MIN = 0,
    parameter BIN_THRESHOLD_MAX = 255,

    parameter EDGE_THRESHOLD_MIN = 0,
    parameter EDGE_THRESHOLD_MAX = 255,

    parameter BRIGHT_GAIN_MIN = 0,
    parameter BRIGHT_GAIN_MAX = 255,

    parameter CONTRAST_GAIN_MIN = 0,
    parameter CONTRAST_GAIN_MAX = 255,

    parameter MOTION_THRESHOLD_MIN = 1,
    parameter MOTION_THRESHOLD_MAX = 255
)(
    input wire clk, rst_n,
    input wire key0_n, key1_n,
    input wire threshold_edit, // SW1：1调2/3阈值、4/5增益、偏振采集，模式13查看命中掩膜
    input wire [23:0] rgb_in,
    input wire de_in, hs_in, vs_in,
    output wire [23:0] rgb_out,
    output wire de_out, hs_out, vs_out,
    output wire [3:0] mode_active,
    output wire [3:0] mode_pending_out,
    input wire [3:0] render_mode_in,
    output wire polar_capture_pulse, polar_restart_pulse,
    output wire [7:0] bin_threshold_active, edge_threshold_active,
    output wire [7:0] bright_gain_active, contrast_gain_active,
    output wire threshold_edit_active,
    input wire frame_valid_in, bank_run,
    output wire [7:0] motion_threshold_active,
 output wire trk_update, trk_valid,
 output wire [4:0] trk_lost_cnt,
 output wire [((IMG_WIDTH<=1)?1:$clog2(IMG_WIDTH))-1:0] trk_x_min,trk_x_max,
 output wire [((IMG_HEIGHT<=1)?1:$clog2(IMG_HEIGHT))-1:0] trk_y_min,trk_y_max
);
    // Asynchronous assertion, synchronous release in the actual pixel domain.
    // 复位可以立即生效，但释放经过两级寄存器，避免各内部模块在不同拍脱离复位。
    reg [1:0] reset_pipe;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) reset_pipe <= 2'b00;
        else reset_pipe <= {reset_pipe[0], 1'b1};
    wire pixel_rst_n = reset_pipe[1];
    reg vs_d;
    always @(posedge clk or negedge pixel_rst_n)
        if (!pixel_rst_n) vs_d <= 1'b0;
        else vs_d <= vs_in;
    // The example's VS is active HIGH in vertical blanking. Both old/new
    // branches have drained before this point; it is not the first active pixel.
    // 重要：只在高有效 VS 的上升沿且 DE=0 时提交模式，避免同一帧中途切换算法。
    // 若改用低有效 VS，必须同时修改这里的边沿检测，不能只改行缓存极性。
    wire frame_commit = vs_in & ~vs_d & ~de_in;
    wire [3:0] mode_pending;
    wire [3:0] render_mode = EXTERNAL_RENDER_MODE ? render_mode_in : mode_active;
    // 按键先更新 mode_pending；到 frame_commit 才更新 mode_active，真正改变输出画面。
        key_mode_ctrl #(
        .CLK_HZ(CLK_HZ),
        .DEBOUNCE_MS(DEBOUNCE_MS),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),

        .ALGO_COUNT(ALGO_COUNT),

        .ENABLE_THRESHOLD_CONTROL(1),
        .ENABLE_MOTION_THRESHOLD_CONTROL(ENABLE_MOTION_THRESHOLD_CONTROL),
        .ENABLE_POLAR_CONTROL(ENABLE_POLAR_CONTROL),
        .EXTERNAL_EDIT_MODE(EXTERNAL_RENDER_MODE),

        // 启动默认参数
        .BIN_THRESHOLD(BIN_THRESHOLD),
        .EDGE_THRESHOLD(EDGE_THRESHOLD),
        .THRESHOLD_STEP(THRESHOLD_STEP),

        .BRIGHT_GAIN(BRIGHT_GAIN),
        .CONTRAST_GAIN(CONTRAST_GAIN),
        .GAIN_STEP(GAIN_STEP),

        .MOTION_THRESHOLD(MOTION_THRESHOLD),

        // BINARY 范围
        .BIN_THRESHOLD_MIN(BIN_THRESHOLD_MIN),
        .BIN_THRESHOLD_MAX(BIN_THRESHOLD_MAX),

        // SOBEL 范围
        .EDGE_THRESHOLD_MIN(EDGE_THRESHOLD_MIN),
        .EDGE_THRESHOLD_MAX(EDGE_THRESHOLD_MAX),

        // BRIGHT 范围
        .BRIGHT_GAIN_MIN(BRIGHT_GAIN_MIN),
        .BRIGHT_GAIN_MAX(BRIGHT_GAIN_MAX),

        // CONTRAST 范围
        .CONTRAST_GAIN_MIN(CONTRAST_GAIN_MIN),
        .CONTRAST_GAIN_MAX(CONTRAST_GAIN_MAX),

        // MOTION 范围
        .MOTION_THRESHOLD_MIN(MOTION_THRESHOLD_MIN),
        .MOTION_THRESHOLD_MAX(MOTION_THRESHOLD_MAX)
    ) u_mode (
        .clk(clk), .rst_n(pixel_rst_n),
        .key0_n(key0_n), .key1_n(key1_n), .threshold_edit(threshold_edit),
        .frame_commit(frame_commit), .threshold_edit_active(threshold_edit_active),
        .bin_threshold_active(bin_threshold_active), .edge_threshold_active(edge_threshold_active),
        .bright_gain_active(bright_gain_active), .contrast_gain_active(contrast_gain_active),
        .motion_threshold_active(motion_threshold_active),
        .edit_mode_in(render_mode),
        .polar_capture_pulse(polar_capture_pulse), .polar_restart_pulse(polar_restart_pulse),
        .mode_pending(mode_pending), .mode_active(mode_active)
    );
    assign mode_pending_out = mode_pending;
    // A DDR recovery resets algorithm history, not keys, video timing or the OSD.
    wire bank_async_rst_n=pixel_rst_n && (!ENABLE_FRAME_GUARD || bank_run);
    wire bank_rst_n;
    reset_sync u_bank_reset(.clk(clk),.async_rst_n(bank_async_rst_n),.rst_n(bank_rst_n));
    reg[8:0] bank_init_count;
    reg bank_frame_started;
    always @(posedge clk or negedge bank_rst_n)
        if(!bank_rst_n)begin bank_init_count<=0;bank_frame_started<=0;end
        else begin
            if(bank_init_count!=9'd256)bank_init_count<=bank_init_count+1'b1;
            if(frame_commit && bank_init_count==9'd256)bank_frame_started<=1;
        end
    wire admitted=!ENABLE_FRAME_GUARD || (frame_valid_in && bank_frame_started);
    wire[23:0] bank_rgb;
    wire bank_de,bank_hs,bank_vs;
    reg[4:0] timing_de,timing_hs,timing_vs,valid_pipe;
    always @(posedge clk or negedge pixel_rst_n)
        if(!pixel_rst_n)begin timing_de<=0;timing_hs<=0;timing_vs<=0;valid_pipe<=0;end
        else begin
            timing_de<={timing_de[3:0],de_in};timing_hs<={timing_hs[3:0],hs_in};
            timing_vs<={timing_vs[3:0],vs_in};valid_pipe<={valid_pipe[3:0],admitted};
        end
    assign rgb_out=ENABLE_FRAME_GUARD ? (valid_pipe[4] ? bank_rgb : 24'd0) : bank_rgb;
    assign de_out=ENABLE_FRAME_GUARD ? timing_de[4] : bank_de;
    assign hs_out=ENABLE_FRAME_GUARD ? timing_hs[4] : bank_hs;
    assign vs_out=ENABLE_FRAME_GUARD ? timing_vs[4] : bank_vs;
    // 所有算法共享输入并持续运行，mode_active 只控制输出选择，不停止未选中的算法。
    algo_bank #(.IMG_WIDTH(IMG_WIDTH), .IMG_HEIGHT(IMG_HEIGHT), .BIN_THRESHOLD(BIN_THRESHOLD),
                .EDGE_THRESHOLD(EDGE_THRESHOLD), .DYNAMIC_THRESHOLD(1), .DYNAMIC_GAIN(1),
                .BRIGHT_GAIN(BRIGHT_GAIN), .CONTRAST_GAIN(CONTRAST_GAIN),
                .MOTION_THRESHOLD(MOTION_THRESHOLD),
                .MOTION_DYNAMIC_THRESHOLD(ENABLE_MOTION_THRESHOLD_CONTROL)) u_bank (
        .clk(clk), .rst_n(ENABLE_FRAME_GUARD ? bank_rst_n : pixel_rst_n), .mode(render_mode),
        .bin_threshold_in(bin_threshold_active), .edge_threshold_in(edge_threshold_active),
        .bright_gain_in(bright_gain_active), .contrast_gain_in(contrast_gain_active),
        .motion_threshold_in(motion_threshold_active),
        .color_debug_in(threshold_edit_active),
        .rgb_in(rgb_in), .de_in(de_in && admitted), .hs_in(hs_in), .vs_in(vs_in),
        .trk_update(trk_update),.trk_valid(trk_valid),.trk_lost_cnt(trk_lost_cnt),
        .trk_x_min(trk_x_min),.trk_x_max(trk_x_max),.trk_y_min(trk_y_min),.trk_y_max(trk_y_max),
        .rgb_out(bank_rgb), .de_out(bank_de), .hs_out(bank_hs), .vs_out(bank_vs)
    );
endmodule
