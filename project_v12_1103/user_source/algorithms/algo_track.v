`timescale 1ns/1ps

// RGB888 adapter for the project stream. Coordinates advance only on DE pixels.
// 算法12：复用颜色检测框，按帧平滑位置；丢失时短暂保留黄虚线框。
// 不存储图像帧，当前RGB与同步固定延迟2拍；坐标位宽适配1280×720。
// Pixel outputs are delayed two clocks; VS rising is delayed two clocks before
// one tracking update, after algo_color_detect has published its frame bbox.
module algo_track #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer XW = (IMG_WIDTH <= 1) ? 1 : $clog2(IMG_WIDTH),
    parameter integer YW = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT),
    parameter integer DET_XW = XW,
    parameter integer DET_YW = YW,
    parameter integer SMOOTH_SHIFT = 2,
    parameter integer LOST_MAX = 15,
    parameter integer SNAP_DIST = 64,
    parameter integer BOX_W = 2,
    parameter [23:0] BOX_COLOR = 24'h00FF00,
    parameter [23:0] LOST_COLOR = 24'hFFFF00,
    parameter integer HOLD_DASH = 1,
    parameter integer OSD_EN = 1,
    parameter integer OSD_W = 40,
    parameter integer OSD_H = 24,
    parameter integer OSD_MARGIN = 8,
    parameter [23:0] OSD_COLOR = 24'h00FF00,
    parameter integer HINT_EN = 0,
    parameter [23:0] HINT_COLOR = 24'hFFFF00,
    parameter integer HINT_W = 24,
    parameter integer HINT_H = 24,
    parameter integer VS_ACTIVE_LOW = 0
)(
    input wire clk, rst_n,
    input wire [23:0] rgb_in,
    input wire de_in, hs_in, vs_in,
    input wire enable_in,
    input wire [DET_XW-1:0] det_x_min, det_x_max,
    input wire [DET_YW-1:0] det_y_min, det_y_max,
    input wire det_valid,
    input wire mot_in,
    output reg [XW-1:0] trk_x_min, trk_x_max,
    output reg [YW-1:0] trk_y_min, trk_y_max,
    output reg trk_valid,
    output reg [4:0] lost_cnt,
    output reg update_out,
    output reg [23:0] rgb_out,
    output reg [7:0] y_out,
    output reg bin_out, de_out, hs_out, vs_out
);

    localparam integer CW = (XW > YW) ? XW+2 : YW+2;
    reg [XW-1:0] xc, x1;
    reg [YW-1:0] yc, y1;
    reg vs_active_q, vs_d1, vs_d2;
    reg [23:0] rgb1;
    reg de1, hs1, vs1;
    reg holding;
    wire vs_active = VS_ACTIVE_LOW ? ~vs_in : vs_in;
    wire vs_rise = vs_active & ~vs_active_q;
    // VS只取有效沿并延后2拍：等待颜色核在第1拍发布刚完成帧的bbox。
    wire frame_event = vs_d2 & ~vs_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xc <= 0; yc <= 0; vs_active_q <= 0;
            vs_d1 <= 0; vs_d2 <= 0;
            rgb1 <= 0;
            x1 <= 0; y1 <= 0;
            de1 <= 0; hs1 <= 0; vs1 <= 0;
        end else begin
            vs_active_q <= vs_active;
            vs_d1 <= vs_rise;
            vs_d2 <= vs_d1;
            if (vs_rise) begin
                xc <= 0;
                yc <= 0;
            end else if (de_in) begin
                if (xc == IMG_WIDTH-1) begin
                    xc <= 0;
                    if (yc == IMG_HEIGHT-1) yc <= 0;
                    else yc <= yc + 1'b1;
                end else xc <= xc + 1'b1;
            end
            rgb1 <= rgb_in;
            x1 <= xc; y1 <= yc;
            de1 <= de_in; hs1 <= hs_in; vs1 <= vs_in;
        end
    end

    // State and publication strobe become visible together after this edge.
    always @(posedge clk or negedge rst_n)
        if(!rst_n) update_out<=0; else update_out<=frame_event;

    // 四舍五入的1/4步进；极小位移可能舍入为0，大位移由SNAP_DIST直接吸附。
    function [XW-1:0] blend_x;
        input [XW-1:0] tk, dt;
        reg signed [CW-1:0] delta;
        reg [CW-1:0] mag, step;
        begin
            delta = $signed({1'b0,dt}) - $signed({1'b0,tk});
            mag = delta[CW-1] ? -delta : delta;
            if (SMOOTH_SHIFT == 0) step = mag;
            else step = (mag + (1 << (SMOOTH_SHIFT-1))) >> SMOOTH_SHIFT;
            blend_x = delta[CW-1] ? tk - step[XW-1:0] : tk + step[XW-1:0];
        end
    endfunction
    function [YW-1:0] blend_y;
        input [YW-1:0] tk, dt;
        reg signed [CW-1:0] delta;
        reg [CW-1:0] mag, step;
        begin
            delta = $signed({1'b0,dt}) - $signed({1'b0,tk});
            mag = delta[CW-1] ? -delta : delta;
            if (SMOOTH_SHIFT == 0) step = mag;
            else step = (mag + (1 << (SMOOTH_SHIFT-1))) >> SMOOTH_SHIFT;
            blend_y = delta[CW-1] ? tk - step[YW-1:0] : tk + step[YW-1:0];
        end
    endfunction

    wire det_in_range = (det_x_min <= det_x_max) && (det_y_min <= det_y_max) &&
                        (det_x_max < IMG_WIDTH) && (det_y_max < IMG_HEIGHT);
    wire [XW:0] det_cx = ({1'b0,det_x_min} + {1'b0,det_x_max}) >> 1;
    wire [YW:0] det_cy = ({1'b0,det_y_min} + {1'b0,det_y_max}) >> 1;
    wire [XW:0] trk_cx = ({1'b0,trk_x_min} + {1'b0,trk_x_max}) >> 1;
    wire [YW:0] trk_cy = ({1'b0,trk_y_min} + {1'b0,trk_y_max}) >> 1;
    wire [XW:0] dx = det_cx >= trk_cx ? det_cx-trk_cx : trk_cx-det_cx;
    wire [YW:0] dy = det_cy >= trk_cy ? det_cy-trk_cy : trk_cy-det_cy;
    wire snap = SNAP_DIST != 0 && (dx > SNAP_DIST || dy > SNAP_DIST);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trk_x_min <= 0; trk_x_max <= 0; trk_y_min <= 0; trk_y_max <= 0;
            trk_valid <= 0; lost_cnt <= 0; holding <= 0;
        end else if (!enable_in) begin
            trk_x_min <= 0; trk_x_max <= 0; trk_y_min <= 0; trk_y_max <= 0;
            trk_valid <= 0; lost_cnt <= 0; holding <= 0;
        end else if (frame_event) begin
            if (det_valid && det_in_range) begin
                if (!trk_valid || snap) begin
                    trk_x_min <= det_x_min; trk_x_max <= det_x_max;
                    trk_y_min <= det_y_min; trk_y_max <= det_y_max;
                end else begin
                    trk_x_min <= blend_x(trk_x_min, det_x_min);
                    trk_x_max <= blend_x(trk_x_max, det_x_max);
                    trk_y_min <= blend_y(trk_y_min, det_y_min);
                    trk_y_max <= blend_y(trk_y_max, det_y_max);
                end
                trk_valid <= 1; lost_cnt <= 0; holding <= 0;
            end else if (trk_valid) begin
                // 本次是第LOST_MAX个连续无效框，立即清框，避免多保留一帧。
                if (lost_cnt >= LOST_MAX-1) begin
                    trk_valid <= 0; lost_cnt <= 0; holding <= 0;
                end else begin
                    lost_cnt <= lost_cnt + 1'b1; holding <= 1;
                end
            end
        end
    end

    wire in_span = enable_in && trk_valid && x1 >= trk_x_min && x1 <= trk_x_max &&
                   y1 >= trk_y_min && y1 <= trk_y_max;
    wire edge_on = (x1-trk_x_min < BOX_W) || (trk_x_max-x1 < BOX_W) ||
                   (y1-trk_y_min < BOX_W) || (trk_y_max-y1 < BOX_W);
    wire dash_on = ~((x1[1] ^ y1[1]) & 1'b1);
    wire draw_box = in_span && edge_on && (!(HOLD_DASH && holding) || dash_on);
    wire [XW:0] osd_x0 = IMG_WIDTH - OSD_W - OSD_MARGIN;
    wire in_osd = x1 >= osd_x0 && x1 < osd_x0 + OSD_W &&
                  y1 >= OSD_MARGIN && y1 < OSD_MARGIN + OSD_H;
    wire in_hint = HINT_EN && mot_in && x1 < HINT_W && y1 < HINT_H;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb_out <= 0; y_out <= 0; bin_out <= 0;
            de_out <= 0; hs_out <= 0; vs_out <= 0;
        end else begin
            rgb_out <= (draw_box ? (holding ? LOST_COLOR : BOX_COLOR) : rgb1);
            if (enable_in && OSD_EN && trk_valid && in_osd) rgb_out <= OSD_COLOR;
            else if (enable_in && in_hint) rgb_out <= HINT_COLOR;
            y_out <= in_span ? 8'hff : 8'h00;
            bin_out <= in_span;
            de_out <= de1; hs_out <= hs1; vs_out <= vs1;
        end
    end
endmodule
