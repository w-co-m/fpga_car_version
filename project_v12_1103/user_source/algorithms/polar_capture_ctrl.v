`timescale 1ns/1ps
// 手动偏振片：每按一次NEXT，等待固定白平衡后的完整帧，再冻结读页复制。
// 先置pause、再经过下一帧边界才取rp，避免边界上wp/rp同时变动导致源页被覆盖。
// 四角度齐全后逐块计算；全部块读回核对成功，才一次性发布三个结果页面。
`include "../ddr_page_map.vh"
module polar_capture_ctrl #(
    parameter integer FRAME_BLOCKS = 57600,
    parameter integer SETTLE_FRAMES = 3,
    parameter integer REQUIRE_GOOD_SETTLE = 0,
    parameter [24:0] ANGLE0_BASE=`DDR_MAP_ANGLE0_BASE,
    parameter [24:0] ANGLE45_BASE=`DDR_MAP_ANGLE45_BASE,
    parameter [24:0] ANGLE90_BASE=`DDR_MAP_ANGLE90_BASE,
    parameter [24:0] ANGLE135_BASE=`DDR_MAP_ANGLE135_BASE
)(
    input wire clk, rst_n, capture_pulse, restart_pulse,
    input wire frame_start,
    input wire good_frame, // 新完成并发布的有效帧事件，DDR域；不能用保留旧页代替。
    input wire [1:0] live_page,
    input wire [3:0] page_valid,
    input wire result_source_active,
    input wire block_busy, block_done, block_error,
    input wire block_abort_ack, block_reset_required,
    output reg display_pause,
    output reg [1:0] angle,
    output wire capture_busy, compute_busy,
    output reg ready, error,
    output reg block_start, block_compute, block_abort_req,
    output reg [24:0] source_addr, dest_addr, block_offset
);
    localparam IDLE=0, SETTLE=1, FREEZE=2, COPY_START=3, COPY_WAIT=4,
               LIVE_WAIT=5, COMPUTE_START=6, COMPUTE_WAIT=7, ABORT_WAIT=8;
    reg [3:0] state;
    reg [7:0] settle_count;
    reg [15:0] block_index;
    reg [24:0] frozen_base, snapshot_base;
    reg restart_pending;
    function [24:0] live_base;
        input [1:0] page;
        begin case(page)
            0:live_base=`DDR_MAP_LIVE0_BASE; 1:live_base=`DDR_MAP_LIVE1_BASE;
            2:live_base=`DDR_MAP_LIVE2_BASE; 3:live_base=`DDR_MAP_LIVE3_BASE;
        endcase end
    endfunction
    function [24:0] angle_base;
        input [1:0] a;
        begin case(a)
            0:angle_base=ANGLE0_BASE; 1:angle_base=ANGLE45_BASE;
            2:angle_base=ANGLE90_BASE; 3:angle_base=ANGLE135_BASE;
        endcase end
    endfunction
    assign capture_busy = state==SETTLE || state==FREEZE || state==COPY_START || state==COPY_WAIT;
    assign compute_busy = state==LIVE_WAIT || state==COMPUTE_START || state==COMPUTE_WAIT || state==ABORT_WAIT;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; display_pause<=0; angle<=0; ready<=0; error<=0;
            block_start<=0; block_compute<=0; source_addr<=0; dest_addr<=0;
            block_offset<=0; block_index<=0; settle_count<=0;
            frozen_base<=0; snapshot_base<=0; restart_pending<=0;
            block_abort_req<=0;
        end else begin
            block_start<=0;
            if(block_reset_required||block_error)begin
                // 终端硬故障只能由全链路复位清除，保持显示暂停并锁住整组结果。
                ready<=0;error<=1;display_pause<=1;block_abort_req<=0;
                restart_pending<=0;state<=ABORT_WAIT;
            end else if(restart_pending)begin
                ready<=0;display_pause<=1;block_abort_req<=1;state<=ABORT_WAIT;
                if(block_abort_ack)begin
                    state<=IDLE;display_pause<=0;angle<=0;ready<=0;error<=0;
                    restart_pending<=0;block_abort_req<=0;block_index<=0;block_offset<=0;
                end
            end else if(restart_pulse)begin
                ready<=0;
                if(!block_busy&&!block_start)begin
                    state<=IDLE;display_pause<=0;angle<=0;error<=0;
                    block_index<=0;block_offset<=0;
                end else begin
                    display_pause<=1;restart_pending<=1;block_abort_req<=1;state<=ABORT_WAIT;
                end
            end else case(state)
                IDLE: if(capture_pulse && !block_busy) begin
                    ready<=0; error<=0; settle_count<=0; state<=SETTLE;
                    if(ready) angle<=0; // 完成后再按NEXT，从新的0°整组开始。
                end
                // 页面保护会保留旧好图；只有新的好帧才能证明当前角度/WB已经稳定。
                SETTLE: if(frame_start && (!REQUIRE_GOOD_SETTLE || good_frame)) begin
                    if(settle_count+1 >= SETTLE_FRAMES) begin display_pause<=1; state<=FREEZE; end
                    else settle_count<=settle_count+1'b1;
                end
                FREEZE: if(frame_start) begin
                    if(page_valid[live_page]) begin
                        frozen_base<=live_base(live_page); snapshot_base<=angle_base(angle);
                        block_index<=0; block_offset<=0; state<=COPY_START;
                    end else begin
                        display_pause<=0; error<=1; state<=IDLE;
                    end
                end
                COPY_START: if(!block_busy) begin
                    source_addr<=frozen_base+block_offset; dest_addr<=snapshot_base+block_offset;
                    block_compute<=0; block_start<=1; state<=COPY_WAIT;
                end
                COPY_WAIT: if(block_done) begin
                    if(block_index==FRAME_BLOCKS-1) begin
                        display_pause<=0; block_index<=0; block_offset<=0;
                        if(angle==3) state<=LIVE_WAIT;
                        else begin angle<=angle+1'b1; state<=IDLE; end
                    end else begin
                        block_index<=block_index+1'b1; block_offset<=block_offset+25'd24;
                        state<=COPY_START;
                    end
                end
                LIVE_WAIT: if(!result_source_active && !block_busy) state<=COMPUTE_START;
                COMPUTE_START: if(!block_busy) begin
                    block_compute<=1; block_start<=1; state<=COMPUTE_WAIT;
                end
                COMPUTE_WAIT: if(block_done) begin
                    if(block_index==FRAME_BLOCKS-1) begin ready<=1; error<=0; angle<=0; state<=IDLE; end
                    else begin block_index<=block_index+1'b1; block_offset<=block_offset+25'd24; state<=COMPUTE_START; end
                end
                ABORT_WAIT: ; // 未核对完成时保持忙，SW0复位可终止故障DDR事务。
                default: state<=IDLE;
            endcase
        end
    end
endmodule
