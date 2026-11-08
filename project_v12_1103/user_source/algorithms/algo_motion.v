`timescale 1ns/1ps
// 算法11：旧模式首像素采样；生产均值模式覆盖块内全部像素。
// rgb_in/y_in/sync需在输入端已经对齐；算法仓复用 algo_gray 的两拍输出。
module algo_motion #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer DS_LOG2 = 4,
    parameter integer DIFF_THR = 32,
    parameter integer MOTION_CNT = 1000,
    parameter integer VS_ACTIVE_LOW = 0,
    parameter integer STATUS_OSD = 1,
    parameter integer OSD_W = 48,
    parameter integer OSD_H = 32,
    parameter integer OSD_MARGIN = 8,
    parameter integer BLOCK_MEAN_MODE = 0
)(
    input wire clk,
    input wire rst_n,
    input wire enable_in,
    input wire [23:0] rgb_in,
    input wire [7:0] y_in,
    input wire de_in,
    input wire hs_in,
    input wire vs_in,
    input wire [7:0] threshold_in,
    output reg [23:0] rgb_out,
    output reg [7:0] mask_out,
    output reg bin_out,
    output reg motion_detected,
    output reg [((IMG_WIDTH*IMG_HEIGHT < 2) ? 1 : $clog2(IMG_WIDTH*IMG_HEIGHT+1))-1:0] motion_pixel_cnt,
    output reg ref_ready,
    output reg de_out,
    output reg hs_out,
    output reg vs_out
);
    localparam integer TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;
    localparam integer COUNT_W = (TOTAL_PIXELS < 2) ? 1 : $clog2(TOTAL_PIXELS + 1);
    localparam integer BLOCK_SIZE = (1 << DS_LOG2);
    localparam integer BLOCKS_PER_ROW = (IMG_WIDTH + BLOCK_SIZE - 1) / BLOCK_SIZE;
    localparam integer REF_WORDS = BLOCKS_PER_ROW * IMG_HEIGHT;
    localparam integer ADDR_W = (REF_WORDS < 2) ? 1 : $clog2(REF_WORDS);
    localparam integer X_W = (IMG_WIDTH < 2) ? 1 : $clog2(IMG_WIDTH);
    localparam integer Y_W = (IMG_HEIGHT < 2) ? 1 : $clog2(IMG_HEIGHT);
    localparam integer BLOCK_POS_W = (BLOCK_SIZE < 2) ? 1 : $clog2(BLOCK_SIZE);
    localparam integer SUM_W = 8 + DS_LOG2;
    localparam integer TAIL_LEN = (IMG_WIDTH % BLOCK_SIZE == 0) ? BLOCK_SIZE : IMG_WIDTH % BLOCK_SIZE;
    localparam integer OSD_X = (IMG_WIDTH > OSD_W + OSD_MARGIN) ? IMG_WIDTH - OSD_W - OSD_MARGIN : 0;
    localparam [23:0] MOTION_COLOR = 24'hFF0000;
    localparam [23:0] STATUS_COLOR = 24'h00FF00;

    reg vs_active_d;
    wire vs_active = VS_ACTIVE_LOW ? ~vs_in : vs_in;
    wire vs_rise = vs_active & ~vs_active_d;

    reg frame_started;
    reg frame_good;
    // 20位计数可表示720p的921600个像素，不会像19位计数那样溢出。
    reg [COUNT_W-1:0] frame_pixel_count;
    reg [COUNT_W-1:0] frame_motion_count;
    reg [X_W-1:0] x_pos;
    reg [Y_W-1:0] y_pos;
    reg [BLOCK_POS_W-1:0] block_pos;
    reg [ADDR_W-1:0] block_addr;
    reg [7:0] sample_hold;
    reg block_motion;
    reg [SUM_W-1:0] block_sum;

    // Mean mode stores {previous motion flag, mean Y}. The flag is displayed
    // at the SAME position next frame, so no horizontal shift or extra pixel
    // latency is introduced. Legacy mode folds away the unused ninth bit.
    // RAM is deliberately not reset; ref_ready masks it until a full warmup.
    // 块末写本帧样本并预读下一地址，使下一块首像素可直接比较，避免同址读写。
    reg [8:0] ref_ram [0:REF_WORDS-1];
    reg [8:0] ref_q;

    wire pixel_valid = enable_in && frame_started && !vs_rise && de_in &&
                       (frame_pixel_count < TOTAL_PIXELS);
    wire block_first = (block_pos == 0);
    wire block_last = (block_pos == BLOCK_SIZE-1) || (x_pos == IMG_WIDTH-1);
    wire block_write = pixel_valid && block_last;
    wire [ADDR_W-1:0] next_addr = (block_addr == REF_WORDS-1) ? {ADDR_W{1'b0}} : block_addr + 1'b1;
    // VS边沿强制预取地址0，保证只有一个空白时钟的帧也能正确比较首块。
    wire [ADDR_W-1:0] ram_read_addr = vs_rise ? {ADDR_W{1'b0}} :
                                      (block_write ? next_addr : block_addr);
    wire [7:0] sample_to_write = (block_first && block_last) ? y_in : sample_hold;
    wire [8:0] delta = (y_in >= ref_q[7:0]) ? ({1'b0,y_in}-{1'b0,ref_q[7:0]}) : ({1'b0,ref_q[7:0]}-{1'b0,y_in});
    wire [7:0] active_threshold = (threshold_in == 0) ? DIFF_THR[7:0] : threshold_in;
    wire first_sample_motion = ref_ready && (delta >= {1'b0,active_threshold});
    wire [SUM_W-1:0] sum_including_pixel = block_first ? y_in : block_sum + y_in;
    // TAIL_LEN is a nonzero elaboration constant. Production width 1280 has
    // no partial block, so synthesis keeps only the power-of-two shift.
    wire [7:0] current_mean = ((TAIL_LEN != BLOCK_SIZE) && (x_pos == IMG_WIDTH-1)) ?
        (({1'b0,sum_including_pixel} + TAIL_LEN/2) / TAIL_LEN) :
        (({1'b0,sum_including_pixel} + BLOCK_SIZE/2) >> DS_LOG2);
    wire [8:0] mean_delta = (current_mean >= ref_q[7:0]) ?
        ({1'b0,current_mean}-{1'b0,ref_q[7:0]}) : ({1'b0,ref_q[7:0]}-{1'b0,current_mean});
    wire mean_motion = ref_ready && (mean_delta >= {1'b0,active_threshold});
    wire current_motion = BLOCK_MEAN_MODE ? (ref_ready && ref_q[8]) :
                          (block_first ? first_sample_motion : block_motion);
    wire [8:0] record_to_write = BLOCK_MEAN_MODE ? {mean_motion,current_mean} : {1'b0,sample_to_write};
    wire [COUNT_W-1:0] block_pixel_count = ((TAIL_LEN != BLOCK_SIZE) && (x_pos == IMG_WIDTH-1)) ? TAIL_LEN : BLOCK_SIZE;

    always @(posedge clk) begin
        if (enable_in && block_write) begin
            ref_ram[block_addr] <= record_to_write;
        end
        if (REF_WORDS == 1 && enable_in && block_write) begin
            // Defined next-frame reference for the degenerate one-word image.
            ref_q <= record_to_write;
        end else begin
            ref_q <= ref_ram[ram_read_addr];
        end
    end

    // 只在 VS 有效沿发布上一帧结果；缺失/超额像素的帧清除参考有效标志。
    // 关闭本算法后不写RAM，重新启用必须等到新VS并完整写入一帧。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_active_d <= 1'b0;
            frame_started <= 1'b0;
            frame_good <= 1'b0;
            frame_pixel_count <= {COUNT_W{1'b0}};
            frame_motion_count <= {COUNT_W{1'b0}};
            x_pos <= {X_W{1'b0}};
            y_pos <= {Y_W{1'b0}};
            block_pos <= {BLOCK_POS_W{1'b0}};
            block_addr <= {ADDR_W{1'b0}};
            sample_hold <= 8'd0;
            block_motion <= 1'b0;
            block_sum <= 0;
            motion_pixel_cnt <= {COUNT_W{1'b0}};
            motion_detected <= 1'b0;
            ref_ready <= 1'b0;
        end else begin
            vs_active_d <= vs_active;

            if (!enable_in) begin
                frame_started <= 1'b0;
                frame_good <= 1'b0;
                frame_pixel_count <= {COUNT_W{1'b0}};
                frame_motion_count <= {COUNT_W{1'b0}};
                x_pos <= {X_W{1'b0}};
                y_pos <= {Y_W{1'b0}};
                block_pos <= {BLOCK_POS_W{1'b0}};
                block_addr <= {ADDR_W{1'b0}};
                block_motion <= 1'b0;
                block_sum <= 0;
                motion_pixel_cnt <= {COUNT_W{1'b0}};
                motion_detected <= 1'b0;
                ref_ready <= 1'b0;
            end else if (vs_rise) begin
                if (frame_started && frame_good && (frame_pixel_count == TOTAL_PIXELS)) begin
                    motion_pixel_cnt <= frame_motion_count;
                    motion_detected <= (frame_motion_count >= MOTION_CNT);
                    ref_ready <= 1'b1;
                end else begin
                    motion_pixel_cnt <= {COUNT_W{1'b0}};
                    motion_detected <= 1'b0;
                    ref_ready <= 1'b0;
                end
                frame_started <= 1'b1;
                frame_good <= 1'b1;
                frame_pixel_count <= {COUNT_W{1'b0}};
                frame_motion_count <= {COUNT_W{1'b0}};
                x_pos <= {X_W{1'b0}};
                y_pos <= {Y_W{1'b0}};
                block_pos <= {BLOCK_POS_W{1'b0}};
                block_addr <= {ADDR_W{1'b0}};
                block_motion <= 1'b0;
                block_sum <= 0;
            end else if (de_in && frame_started) begin
                if (frame_pixel_count < TOTAL_PIXELS) begin
                    frame_pixel_count <= frame_pixel_count + 1'b1;
                    if (block_first) begin
                        sample_hold <= y_in;
                        block_motion <= first_sample_motion;
                    end
                    block_sum <= sum_including_pixel;
                    if (BLOCK_MEAN_MODE) begin
                        if (block_last && mean_motion)
                            frame_motion_count <= frame_motion_count + block_pixel_count;
                    end else if (current_motion)
                        frame_motion_count <= frame_motion_count + 1'b1;

                    if (block_last) begin
                        block_pos <= {BLOCK_POS_W{1'b0}};
                        block_addr <= next_addr;
                    end else begin
                        block_pos <= block_pos + 1'b1;
                    end
                    if (x_pos == IMG_WIDTH-1) begin
                        x_pos <= {X_W{1'b0}};
                        if (y_pos == IMG_HEIGHT-1)
                            y_pos <= {Y_W{1'b0}};
                        else
                            y_pos <= y_pos + 1'b1;
                    end else begin
                        x_pos <= x_pos + 1'b1;
                    end
                end else begin
                    frame_good <= 1'b0;
                end
            end
        end
    end

    // 两级寄存流水线：RGB、掩膜和同步信号保持同一拍对齐。
    // Mean mode reads last frame's per-block decisions. Frame-level status and
    // the red mask therefore both describe the last complete measurement.
    reg [23:0] rgb_d1;
    reg [7:0] mask_d1;
    reg de_d1, hs_d1, vs_d1;
    reg motion_d1;
    reg [X_W-1:0] x_d1;
    reg [Y_W-1:0] y_d1;
    wire status_area = STATUS_OSD && (IMG_WIDTH >= OSD_W + OSD_MARGIN) &&
                       (IMG_HEIGHT >= OSD_H + OSD_MARGIN) &&
                       (x_d1 >= OSD_X) && (x_d1 < OSD_X + OSD_W) &&
                       (y_d1 >= OSD_MARGIN) && (y_d1 < OSD_MARGIN + OSD_H);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb_d1 <= 24'd0;
            mask_d1 <= 8'd0;
            de_d1 <= 1'b0;
            hs_d1 <= 1'b0;
            vs_d1 <= 1'b0;
            motion_d1 <= 1'b0;
            x_d1 <= {X_W{1'b0}};
            y_d1 <= {Y_W{1'b0}};
            rgb_out <= 24'd0;
            mask_out <= 8'd0;
            bin_out <= 1'b0;
            de_out <= 1'b0;
            hs_out <= 1'b0;
            vs_out <= 1'b0;
        end else begin
            rgb_d1 <= rgb_in;
            mask_d1 <= (pixel_valid && current_motion) ? 8'hFF : 8'h00;
            motion_d1 <= pixel_valid && current_motion;
            de_d1 <= de_in;
            hs_d1 <= hs_in;
            vs_d1 <= vs_in;
            x_d1 <= x_pos;
            y_d1 <= y_pos;
            rgb_out <= status_area && motion_detected ? STATUS_COLOR :
                       (motion_d1 ? MOTION_COLOR : rgb_d1);
            mask_out <= mask_d1;
            bin_out <= |mask_d1;
            de_out <= de_d1;
            hs_out <= hs_d1;
            vs_out <= vs_d1;
        end
    end
endmodule
