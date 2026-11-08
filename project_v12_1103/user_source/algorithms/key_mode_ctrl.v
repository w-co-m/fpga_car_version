`timescale 1ns/1ps

// 两级同步、连续稳定消抖、双键仲裁，以及模式/阈值按键控制。
// KEY0/KEY1 低有效；SW1（threshold_edit）高电平选择阈值、增益或偏振操作。
module key_mode_ctrl #(
    parameter integer CLK_HZ = 75000000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer ALGO_COUNT = 4,
    parameter integer DEBOUNCE_CYCLES = 0,
    parameter integer ENABLE_THRESHOLD_CONTROL = 0,
    parameter integer ENABLE_POLAR_CONTROL = 0,
    parameter integer BIN_THRESHOLD = 128,
    parameter integer EDGE_THRESHOLD = 32,
    parameter integer THRESHOLD_STEP = 1,
    parameter integer BRIGHT_GAIN = 24,
    parameter integer CONTRAST_GAIN = 24,
    parameter integer GAIN_STEP = 1,
    parameter integer EXTERNAL_EDIT_MODE = 0,
    parameter integer MOTION_THRESHOLD = 8,
    parameter integer ENABLE_MOTION_THRESHOLD_CONTROL = 0,

    parameter integer BIN_THRESHOLD_MIN = 0,
    parameter integer BIN_THRESHOLD_MAX = 255,

    parameter integer EDGE_THRESHOLD_MIN = 0,
    parameter integer EDGE_THRESHOLD_MAX = 255,

    parameter integer BRIGHT_GAIN_MIN = 0,
    parameter integer BRIGHT_GAIN_MAX = 255,

    parameter integer CONTRAST_GAIN_MIN = 0,
    parameter integer CONTRAST_GAIN_MAX = 255,

    parameter integer MOTION_THRESHOLD_MIN = 1,
    parameter integer MOTION_THRESHOLD_MAX = 255
) (
    input wire clk,
    input wire rst_n,
    input wire key0_n,
    input wire key1_n,
    input wire frame_commit,
    output reg [3:0] mode_pending,
    output reg [3:0] mode_active,
    input wire threshold_edit,
    input wire [3:0] edit_mode_in,
    output wire threshold_edit_active,
    output reg [7:0] bin_threshold_active,
    output reg [7:0] edge_threshold_active,
    output reg [7:0] bright_gain_active,
    output reg [7:0] contrast_gain_active,
    output reg polar_capture_pulse,
    output reg polar_restart_pulse,
    output reg [7:0] motion_threshold_active
);

    // 64 位中间乘积避免频率与毫秒相乘时溢出；仿真可直接覆盖周期数。
    localparam [63:0] DB_CYCLES_WIDE =
        (64'd1 * CLK_HZ * DEBOUNCE_MS + 999) / 1000;
    localparam integer DB_CYCLES = (DEBOUNCE_CYCLES > 0) ?
        DEBOUNCE_CYCLES : ((DB_CYCLES_WIDE < 1) ? 1 : DB_CYCLES_WIDE);
    localparam integer ARB_CYCLES = DB_CYCLES + 2;
    localparam integer DB_CNT_W = (DB_CYCLES <= 1) ? 1 : $clog2(DB_CYCLES + 1);
    localparam integer ARB_CNT_W = (ARB_CYCLES <= 1) ? 1 : $clog2(ARB_CYCLES + 1);

    reg [1:0] key0_sync, key1_sync, selector_sync;
    reg key0_released, key1_released, selector_confirmed;
    reg [DB_CNT_W-1:0] key0_count, key1_count, selector_count;
    reg armed, arbitration_active, arbitration_suppressed, arbitration_previous;
    reg arbitration_selector_sample, arbitration_selector_confirmed;
    reg [3:0] arbitration_mode;
    reg [ARB_CNT_W-1:0] arbitration_count;
    reg [7:0] bin_threshold_pending, edge_threshold_pending;
    reg [7:0] bright_gain_pending, contrast_gain_pending;
    reg [7:0] motion_threshold_pending;

    wire [3:0] event_mode;
    wire [3:0] control_mode = EXTERNAL_EDIT_MODE ? edit_mode_in : mode_active;
    // 本拍双键已按下，或另一键恰在事件采样沿完成消抖时，抑制本次动作。
    wire key0_press_completes = key0_released && !key0_sync[1] && (key0_count == DB_CYCLES - 1);
    wire key1_press_completes = key1_released && !key1_sync[1] && (key1_count == DB_CYCLES - 1);
    wire two_key_press_at_event =
        (!key0_released || key0_press_completes) &&
        (!key1_released || key1_press_completes);

    wire press_event = arbitration_active &&
        (arbitration_count == {{(ARB_CNT_W-1){1'b0}}, 1'b1}) &&
        !arbitration_suppressed && !two_key_press_at_event &&
        (selector_sync[1] == arbitration_selector_sample) &&
        (selector_confirmed == arbitration_selector_confirmed) &&
        // 算法切换允许已有pending模式在仲裁期间先提交；参数编辑锁定目标显示模式。
        (!ENABLE_THRESHOLD_CONTROL || !arbitration_selector_confirmed ||
         (control_mode == arbitration_mode));
    wire mode_event = press_event &&
        (!ENABLE_THRESHOLD_CONTROL || !arbitration_selector_confirmed);
    wire polar_event = press_event && ENABLE_POLAR_CONTROL &&
        arbitration_selector_confirmed && (arbitration_mode >= 4'd9) && (arbitration_mode <= 4'd12);
    wire threshold_event = press_event && ENABLE_THRESHOLD_CONTROL &&
        arbitration_selector_confirmed &&
        ((arbitration_mode == 4'd2) || (arbitration_mode == 4'd3) ||
         (arbitration_mode == 4'd4) || (arbitration_mode == 4'd5));
    wire motion_threshold_event = press_event && ENABLE_MOTION_THRESHOLD_CONTROL &&
        arbitration_selector_confirmed && (arbitration_mode == 4'd14);
    // ----------------------------------------------------------------
    // Runtime parameter adjustment with independent saturation limits.
    //
    // arbitration_previous = 1 : KEY0，参数减小
    // arbitration_previous = 0 : KEY1，参数增大
    //
    // 各算法上下限通过 parameter 从上层配置。
    // ----------------------------------------------------------------

    // MODE E：运动检测阈值
    wire [7:0] motion_threshold_next =
        !motion_threshold_event ?
            motion_threshold_pending :
        arbitration_previous ?
            ((motion_threshold_pending <= MOTION_THRESHOLD_MIN) ?
                MOTION_THRESHOLD_MIN :
                motion_threshold_pending - 8'd1) :
            ((motion_threshold_pending >= MOTION_THRESHOLD_MAX) ?
                MOTION_THRESHOLD_MAX :
                motion_threshold_pending + 8'd1);

    // MODE 2：二值化阈值
    wire [7:0] bin_threshold_next =
        (!threshold_event || arbitration_mode != 4'd2) ?
            bin_threshold_pending :
        arbitration_previous ?
            ((bin_threshold_pending <=
              (BIN_THRESHOLD_MIN + THRESHOLD_STEP)) ?
                BIN_THRESHOLD_MIN :
                bin_threshold_pending - THRESHOLD_STEP) :
            ((bin_threshold_pending >=
              (BIN_THRESHOLD_MAX - THRESHOLD_STEP)) ?
                BIN_THRESHOLD_MAX :
                bin_threshold_pending + THRESHOLD_STEP);

    // MODE 3：Sobel 边缘检测阈值
    wire [7:0] edge_threshold_next =
        (!threshold_event || arbitration_mode != 4'd3) ?
            edge_threshold_pending :
        arbitration_previous ?
            ((edge_threshold_pending <=
              (EDGE_THRESHOLD_MIN + THRESHOLD_STEP)) ?
                EDGE_THRESHOLD_MIN :
                edge_threshold_pending - THRESHOLD_STEP) :
            ((edge_threshold_pending >=
              (EDGE_THRESHOLD_MAX - THRESHOLD_STEP)) ?
                EDGE_THRESHOLD_MAX :
                edge_threshold_pending + THRESHOLD_STEP);

    // algo_bright/algo_contrast 的 thr_in 是 Q4.4 增益；
    // 16 = 1.0 倍，24 = 1.5 倍。
    // MODE 4：亮度增益
    wire [7:0] bright_gain_next =
        (!threshold_event || arbitration_mode != 4'd4) ?
            bright_gain_pending :
        arbitration_previous ?
            ((bright_gain_pending <=
              (BRIGHT_GAIN_MIN + GAIN_STEP)) ?
                BRIGHT_GAIN_MIN :
                bright_gain_pending - GAIN_STEP) :
            ((bright_gain_pending >=
              (BRIGHT_GAIN_MAX - GAIN_STEP)) ?
                BRIGHT_GAIN_MAX :
                bright_gain_pending + GAIN_STEP);

    // MODE 5：对比度增益
    wire [7:0] contrast_gain_next =
        (!threshold_event || arbitration_mode != 4'd5) ?
            contrast_gain_pending :
        arbitration_previous ?
            ((contrast_gain_pending <=
              (CONTRAST_GAIN_MIN + GAIN_STEP)) ?
                CONTRAST_GAIN_MIN :
                contrast_gain_pending - GAIN_STEP) :
            ((contrast_gain_pending >=
              (CONTRAST_GAIN_MAX - GAIN_STEP)) ?
                CONTRAST_GAIN_MAX :
                contrast_gain_pending + GAIN_STEP);

    assign threshold_edit_active = ENABLE_THRESHOLD_CONTROL ? selector_confirmed : 1'b0;
    assign event_mode = mode_event ?
        (arbitration_previous ?
            ((mode_pending == 0) ? (ALGO_COUNT - 1) : (mode_pending - 1'b1)) :
            ((mode_pending == (ALGO_COUNT - 1)) ? 4'd0 : (mode_pending + 1'b1))) :
        mode_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key0_sync <= 2'b11;
            key1_sync <= 2'b11;
            selector_sync <= 2'b00;
            key0_released <= 1'b1;
            key1_released <= 1'b1;
            selector_confirmed <= 1'b0;
            key0_count <= {DB_CNT_W{1'b0}};
            key1_count <= {DB_CNT_W{1'b0}};
            selector_count <= {DB_CNT_W{1'b0}};
            armed <= 1'b1;
            arbitration_active <= 1'b0;
            arbitration_suppressed <= 1'b0;
            arbitration_previous <= 1'b0;
            arbitration_selector_sample <= 1'b0;
            arbitration_selector_confirmed <= 1'b0;
            arbitration_mode <= 4'd0;
            arbitration_count <= {ARB_CNT_W{1'b0}};
            mode_pending <= 4'd0;
            mode_active <= 4'd0;
            bin_threshold_pending <= BIN_THRESHOLD;
            edge_threshold_pending <= EDGE_THRESHOLD;
            bright_gain_pending <= BRIGHT_GAIN;
            contrast_gain_pending <= CONTRAST_GAIN;
            motion_threshold_pending <= MOTION_THRESHOLD;
            bin_threshold_active <= BIN_THRESHOLD;
            edge_threshold_active <= EDGE_THRESHOLD;
            bright_gain_active <= BRIGHT_GAIN;
            contrast_gain_active <= CONTRAST_GAIN;
            motion_threshold_active <= MOTION_THRESHOLD;
            polar_capture_pulse <= 1'b0;
            polar_restart_pulse <= 1'b0;
        end else begin
            polar_capture_pulse <= 1'b0;
            polar_restart_pulse <= 1'b0;
            key0_sync <= {key0_sync[0], key0_n};
            key1_sync <= {key1_sync[0], key1_n};
            selector_sync <= {selector_sync[0],
                              ENABLE_THRESHOLD_CONTROL ? threshold_edit : 1'b0};

            if (key0_sync[1] == key0_released) key0_count <= 0;
            else if (key0_count == DB_CYCLES - 1) begin
                key0_released <= key0_sync[1];
                key0_count <= 0;
            end else key0_count <= key0_count + 1'b1;

            if (key1_sync[1] == key1_released) key1_count <= 0;
            else if (key1_count == DB_CYCLES - 1) begin
                key1_released <= key1_sync[1];
                key1_count <= 0;
            end else key1_count <= key1_count + 1'b1;

            // SW1 使用与按键相同的同步级数和连续稳定消抖。
            if (!ENABLE_THRESHOLD_CONTROL || selector_sync[1] == selector_confirmed)
                selector_count <= 0;
            else if (selector_count == DB_CYCLES - 1) begin
                selector_confirmed <= selector_sync[1];
                selector_count <= 0;
            end else selector_count <= selector_count + 1'b1;

            // 锁存选择开关和当前显示模式；窗口内任何变化都会粘滞抑制本次动作。
            if (armed && !arbitration_active && (!key0_released || !key1_released)) begin
                armed <= 1'b0;
                if (key0_released ^ key1_released) begin
                    arbitration_active <= 1'b1;
                    arbitration_suppressed <= 1'b0;
                    arbitration_previous <= !key0_released;
                    arbitration_selector_sample <= selector_sync[1];
                    arbitration_selector_confirmed <= selector_confirmed;
                    arbitration_mode <= control_mode;
                    arbitration_count <= ARB_CYCLES;
                end else begin
                    arbitration_active <= 1'b0;
                    arbitration_suppressed <= 1'b1;
                end
            end else if (arbitration_active) begin
                if (armed && (!key0_released || !key1_released)) begin
                    armed <= 1'b0;
                    arbitration_suppressed <= 1'b1;
                end
                if ((!key0_released && !key1_released) ||
                    (selector_sync[1] != arbitration_selector_sample) ||
                    (selector_confirmed != arbitration_selector_confirmed) ||
                    (ENABLE_THRESHOLD_CONTROL && arbitration_selector_confirmed &&
                     (control_mode != arbitration_mode)))
                    arbitration_suppressed <= 1'b1;
                if (arbitration_count != 0)
                    arbitration_count <= arbitration_count - 1'b1;
                else arbitration_active <= 1'b0;
            end

            if (!key0_released && !key1_released)
                arbitration_suppressed <= 1'b1;

            if (key0_released && key1_released) begin
                armed <= 1'b1;
                if (!arbitration_active) begin
                    arbitration_suppressed <= 1'b0;
                    arbitration_count <= {ARB_CNT_W{1'b0}};
                end
            end

            if (mode_event) mode_pending <= event_mode;
            if (frame_commit) mode_active <= event_mode;
            // SW1=1 时极化模式的 KEY3/KEY2 在消抖和仲裁完成后各发单拍命令。
            if (polar_event && !arbitration_previous) polar_capture_pulse <= 1'b1;
            if (polar_event &&  arbitration_previous) polar_restart_pulse <= 1'b1;

            if (threshold_event && arbitration_mode == 4'd2)
                bin_threshold_pending <= bin_threshold_next;
            if (threshold_event && arbitration_mode == 4'd3)
                edge_threshold_pending <= edge_threshold_next;
            if (threshold_event && arbitration_mode == 4'd4)
                bright_gain_pending <= bright_gain_next;
            if (threshold_event && arbitration_mode == 4'd5)
                contrast_gain_pending <= contrast_gain_next;
            if (motion_threshold_event)
                motion_threshold_pending <= motion_threshold_next;
            if (frame_commit) begin
                bin_threshold_active <= bin_threshold_next;
                edge_threshold_active <= edge_threshold_next;
                bright_gain_active <= bright_gain_next;
                contrast_gain_active <= contrast_gain_next;
                motion_threshold_active <= motion_threshold_next;
            end
        end
    end
endmodule
