`timescale 1ns/1ps
// DDR命令归属仲裁。显示FIFO有余量、旧读回包及MC队列排空后才交给后台。
// queue_idle只代表AW/W/AR已接收；后台的写完成由块引擎读回核对证明。
module polar_ddr_arbiter #(
    parameter integer MIN_DISPLAY_FILL = 320,
    parameter integer STALL_LIMIT = 4194304
)(
    input wire clk, rst_n, calibrated,
    input wire queue_idle, user_ready, rd_valid,
    input wire [127:0] rd_data,
    input wire vi_busy, vi_wr_en,
    input wire [24:0] vi_addr,
    input wire [127:0] vi_data,
    input wire vo_busy, vo_rd_en, vo_frame_pending,
    input wire [8:0] vo_fill,
    input wire [9:0] vo_credit,
    input wire [24:0] vo_addr,
    input wire bg_request, bg_release, bg_rd_en, bg_wr_en,
    input wire [24:0] bg_addr,
    input wire [127:0] bg_data,
    output reg bg_grant,
    output wire live_ready, bg_ready,
    output wire vo_return_valid, bg_return_valid,
    output wire [127:0] return_data,
    output wire wr_en, rd_en,
    output wire [24:0] addr,
    output wire [127:0] wr_data,
    output reg reset_required
);
    reg release_pending;
    reg [5:0] bg_credit;
    localparam TW=(STALL_LIMIT<2)?1:$clog2(STALL_LIMIT);
    reg[TW-1:0]vo_stall,bg_stall;
    wire bg_submit_read = bg_grant && bg_rd_en && calibrated && !reset_required;
    assign live_ready = user_ready && calibrated && !bg_grant && !reset_required;
    assign bg_ready = user_ready && calibrated && bg_grant && !release_pending && !reset_required;
    assign vo_return_valid = rd_valid && !bg_grant;
    assign bg_return_valid = rd_valid && bg_grant;
    assign return_data = rd_data;
    assign wr_en = calibrated && !reset_required && (bg_grant ? bg_wr_en : vi_wr_en);
    assign rd_en = calibrated && !reset_required && (bg_grant ? bg_rd_en : vo_rd_en);
    assign addr = bg_grant ? bg_addr : (vi_wr_en ? vi_addr : vo_addr);
    assign wr_data = bg_grant ? bg_data : vi_data;
    // Unrelated camera writes must never hide a lost display/background response.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin vo_stall<=0;bg_stall<=0;reset_required<=0;end
        else begin
            if(vo_credit==0 || vo_return_valid)vo_stall<=0;
            else if(vo_stall==STALL_LIMIT-1)reset_required<=1;
            else vo_stall<=vo_stall+1'b1;
            if(bg_credit==0 || bg_return_valid)bg_stall<=0;
            else if(bg_stall==STALL_LIMIT-1)reset_required<=1;
            else bg_stall<=bg_stall+1'b1;
            if((bg_return_valid && bg_credit==0 && !bg_submit_read) ||
               (vo_return_valid && vo_credit==0 && !vo_rd_en))reset_required<=1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bg_grant <= 0; release_pending <= 0; bg_credit <= 0;
        end else begin
            case ({bg_submit_read, bg_return_valid})
                2'b10: bg_credit <= bg_credit + 1'b1;
                2'b01: if (bg_credit != 0) bg_credit <= bg_credit - 1'b1;
                default: ;
            endcase
            if (!reset_required && !bg_grant) begin
                release_pending <= 0;
                // 不能先停显示再等FIFO变满；先让显示补足，再抢占短块。
                if (calibrated && bg_request && !vi_busy && !vo_busy &&
                    !vo_frame_pending && vo_fill >= MIN_DISPLAY_FILL &&
                    vo_credit == 0 && queue_idle && !rd_valid &&
                    !vi_wr_en && !vo_rd_en)
                    bg_grant <= 1;
            end else if(!reset_required) begin
                if (bg_release) release_pending <= 1;
                if ((release_pending || bg_release) && bg_credit == 0 &&
                    queue_idle && !rd_valid && !bg_rd_en && !bg_wr_en) begin
                    bg_grant <= 0;
                    release_pending <= 0;
                end
            end
        end
    end
endmodule
