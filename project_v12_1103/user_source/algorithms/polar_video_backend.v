`timescale 1ns/1ps
// 偏振后台集成：按钮/模式来自像素域，快照/计算/DDR调度统一在DDR用户时钟域。
// 结果显示页只有ready时可选择；ready撤销后显示源在下一个VS返回实时预览。
`include "../ddr_page_map.vh"
module polar_video_backend #(
    parameter integer FRAME_BLOCKS=57600,
    parameter integer SETTLE_FRAMES=3,
    parameter integer REQUIRE_GOOD_SETTLE=0,
    parameter integer ENABLE_POLAR_EDGE=0,
    parameter integer IMG_WIDTH=1280,
    parameter integer CHECK_FRAME_LAYOUT=0
)(
    input wire pixel_clk, camera_clk, ddr_clk, rst_n,
    input wire [3:0] requested_mode,
    input wire capture_pulse, restart_pulse,
    input wire camera_frame_start,
    input wire camera_good_frame,
    input wire [1:0] live_page,
    input wire [3:0] page_valid,
    input wire [3:0] displayed_mode,
    input wire displayed_result,
    input wire vo_busy, vo_frame_pending,
    input wire [8:0] vo_fill,
    input wire [9:0] vo_credit,
    input wire vo_rd_en,
    input wire [24:0] vo_addr,
    input wire vi_busy, vi_wr_en,
    input wire [24:0] vi_addr,
    input wire [127:0] vi_data,
    input wire calibrated, queue_idle, user_ready, user_rd_valid,
    input wire [127:0] user_rd_data,
    output wire display_pause, background_owner, live_ready,
    output wire vo_return_valid,
    output wire user_wr_en, user_rd_en,
    output wire [24:0] user_addr,
    output wire [127:0] user_wr_data,
    output reg [24:0] source_base,
    output wire [3:0] source_mode,
    output wire source_is_result,
    output wire source_valid,
    output wire [3:0] render_mode,
    output wire [1:0] polar_angle,
    output wire polar_capture_busy, polar_compute_busy, polar_ready, polar_error,
    output wire fixed_white_balance,
    output wire reset_required
);
    generate if(CHECK_FRAME_LAYOUT && (IMG_WIDTH!=1280 || FRAME_BLOCKS!=57600 ||
        FRAME_BLOCKS*3!=`DDR_MAP_FRAME_WORDS || FRAME_BLOCKS*24!=`DDR_MAP_FRAME_SPAN ||
        {1'b0,`DDR_MAP_FUSION_BASE}+`DDR_MAP_FRAME_SPAN>26'd33554432))begin:g_bad_page_map
        ERROR_POLAR_FIXED_720P_DDR_PAGE_LAYOUT invalid_configuration();
    end endgenerate
    wire pixel_rst_n, camera_rst_n, ddr_rst_n;
    reset_sync u_reset_pixel(.clk(pixel_clk),.async_rst_n(rst_n),.rst_n(pixel_rst_n));
    reset_sync u_reset_camera(.clk(camera_clk),.async_rst_n(rst_n),.rst_n(camera_rst_n));
    reset_sync u_reset_ddr(.clk(ddr_clk),.async_rst_n(rst_n),.rst_n(ddr_rst_n));
    wire [3:0] mode_ddr;
    wire capture_ddr,restart_ddr;
    polar_status_cdc #(.WIDTH(4)) u_mode_cdc(
        .src_clk(pixel_clk),.src_rst_n(pixel_rst_n),.src_data(requested_mode),
        .dst_clk(ddr_clk),.dst_rst_n(ddr_rst_n),.dst_data(mode_ddr));
    polar_status_cdc #(.WIDTH(4)) u_render_cdc(
        .src_clk(ddr_clk),.src_rst_n(ddr_rst_n),.src_data(displayed_mode),
        .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),.dst_data(render_mode));
    polar_pulse_cdc u_capture_cdc(.src_clk(pixel_clk),.src_rst_n(pixel_rst_n),.src_pulse(capture_pulse),
        .dst_clk(ddr_clk),.dst_rst_n(ddr_rst_n),.dst_pulse(capture_ddr));
    polar_pulse_cdc u_restart_cdc(.src_clk(pixel_clk),.src_rst_n(pixel_rst_n),.src_pulse(restart_pulse),
        .dst_clk(ddr_clk),.dst_rst_n(ddr_rst_n),.dst_pulse(restart_ddr));
    // 偏振四角度必须使用同一颜色增益。未完成组期间即使暂时切回RAW也保持增益，
    // 防止采集进行到一半时模式变化让四张图使用不同的颜色响应。
    reg fixed_wb_request;
    (* async_reg="true" *) reg fixed_wb_1,fixed_wb_2;
    always @(posedge camera_clk or negedge camera_rst_n)
        if(!camera_rst_n)begin fixed_wb_1<=0;fixed_wb_2<=0;end
        else begin fixed_wb_1<=fixed_wb_request;fixed_wb_2<=fixed_wb_1;end
    assign fixed_white_balance=fixed_wb_2;

    wire [1:0] angle_ddr;
    wire capture_busy_ddr,compute_busy_ddr,ready_ddr,error_ddr;
    always @(posedge ddr_clk or negedge ddr_rst_n)
        if(!ddr_rst_n)fixed_wb_request<=0;
        else fixed_wb_request<=(mode_ddr>=9 && mode_ddr<=12) || capture_busy_ddr || compute_busy_ddr || (angle_ddr!=0);
    wire block_busy,block_done,block_error,block_start,block_compute;
    wire block_abort_req,block_abort_ack,block_reset_required,arbiter_reset_required;
    assign reset_required=block_reset_required | arbiter_reset_required;
    wire [24:0] copy_source,copy_dest,block_offset;
    polar_capture_ctrl #(.FRAME_BLOCKS(FRAME_BLOCKS),.SETTLE_FRAMES(SETTLE_FRAMES),
        .REQUIRE_GOOD_SETTLE(REQUIRE_GOOD_SETTLE)) u_capture(
        .clk(ddr_clk),.rst_n(ddr_rst_n),.capture_pulse(capture_ddr && mode_ddr>=9 && mode_ddr<=12),
        .restart_pulse(restart_ddr),.frame_start(camera_frame_start),.good_frame(camera_good_frame),.live_page(live_page),
        .page_valid(page_valid),.result_source_active(displayed_result),
        .block_busy(block_busy),.block_done(block_done),.block_error(block_error),
        .block_abort_req(block_abort_req),.block_abort_ack(block_abort_ack),.block_reset_required(block_reset_required),
        .display_pause(display_pause),.angle(angle_ddr),.capture_busy(capture_busy_ddr),
        .compute_busy(compute_busy_ddr),.ready(ready_ddr),.error(error_ddr),
        .block_start(block_start),.block_compute(block_compute),.source_addr(copy_source),
        .dest_addr(copy_dest),.block_offset(block_offset));
    wire [5:0] pixel_status;
    polar_status_cdc #(.WIDTH(6)) u_status_cdc(
        .src_clk(ddr_clk),.src_rst_n(ddr_rst_n),
        .src_data({angle_ddr,capture_busy_ddr,compute_busy_ddr,ready_ddr,error_ddr}),
        .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),.dst_data(pixel_status));
    assign {polar_angle,polar_capture_busy,polar_compute_busy,polar_ready,polar_error}=pixel_status;

    wire request,owner_release,bg_ready,bg_rd_en,bg_wr_en,bg_return_valid;
    wire [24:0] bg_addr;wire [127:0] bg_data;
    polar_block_engine #(.ENABLE_EDGE(ENABLE_POLAR_EDGE),.IMG_WIDTH(IMG_WIDTH)) u_block(.clk(ddr_clk),.rst_n(ddr_rst_n),.start(block_start),
        .op_compute(block_compute),.source_addr(copy_source),.dest_addr(copy_dest),.block_offset(block_offset),
        .abort_req(block_abort_req),.abort_ack(block_abort_ack),.reset_required(block_reset_required),
        .busy(block_busy),.done(block_done),.error(block_error),.request(request),
        .grant(background_owner),.owner_release(owner_release),.ddr_ready(bg_ready),
        .rd_en(bg_rd_en),.wr_en(bg_wr_en),.addr(bg_addr),.wr_data(bg_data),
        .rd_valid(bg_return_valid),.rd_data(user_rd_data));
    polar_ddr_arbiter u_arbiter(.clk(ddr_clk),.rst_n(ddr_rst_n),.calibrated(calibrated),
        .queue_idle(queue_idle),.user_ready(user_ready),.rd_valid(user_rd_valid),.rd_data(user_rd_data),
        .vi_busy(vi_busy),.vi_wr_en(vi_wr_en),.vi_addr(vi_addr),.vi_data(vi_data),
        .vo_busy(vo_busy),.vo_rd_en(vo_rd_en),.vo_frame_pending(vo_frame_pending),
        .vo_fill(vo_fill),.vo_credit(vo_credit),.vo_addr(vo_addr),
        .bg_request(request),.bg_release(owner_release),.bg_rd_en(bg_rd_en),.bg_wr_en(bg_wr_en),
        .bg_addr(bg_addr),.bg_data(bg_data),.bg_grant(background_owner),.live_ready(live_ready),
        .bg_ready(bg_ready),.vo_return_valid(vo_return_valid),.bg_return_valid(bg_return_valid),
        .return_data(),.wr_en(user_wr_en),.rd_en(user_rd_en),.addr(user_addr),.wr_data(user_wr_data),
        .reset_required(arbiter_reset_required));
    // 实时源必须是完整好页；结果源由整组readback完成的ready证明有效。
    assign source_valid=source_is_result || page_valid[live_page];
    assign source_mode=mode_ddr;
    assign source_is_result=ready_ddr && mode_ddr>=9 && (mode_ddr<=11 || (ENABLE_POLAR_EDGE && mode_ddr==12));
    always @* begin
        case(live_page)
            0:source_base=`DDR_MAP_LIVE0_BASE;1:source_base=`DDR_MAP_LIVE1_BASE;
            2:source_base=`DDR_MAP_LIVE2_BASE;3:source_base=`DDR_MAP_LIVE3_BASE;
        endcase
        if(source_is_result)case(mode_ddr)
            9:source_base=`DDR_MAP_DOLP_BASE;
            10:source_base=`DDR_MAP_AOP_BASE;
            11:source_base=`DDR_MAP_FUSION_BASE;
            12:source_base=`DDR_MAP_EDGE_BASE;
            default: ;
        endcase
    end
endmodule
