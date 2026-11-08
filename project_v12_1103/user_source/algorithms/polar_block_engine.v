`timescale 1ns/1ps
// 偏振后台块引擎：每次处理16个连续RGB888像素（384 bit / 3个128 bit DDR字）。
// DDR地址以16 bit为单位，因此相邻128 bit字地址相差8；偏移量由上层按块提供。
// 只在grant且ready时发出单拍命令。读返回按顺序计数；写后逐字读回全部内容，
// 用于覆盖DDR命令队列尚未完成物理写入的情况。计算期间释放DDR所有权。
`include "../ddr_page_map.vh"
module polar_block_engine #(
    parameter [24:0] ANGLE0_BASE = `DDR_MAP_ANGLE0_BASE,
    parameter [24:0] ANGLE45_BASE = `DDR_MAP_ANGLE45_BASE,
    parameter [24:0] ANGLE90_BASE = `DDR_MAP_ANGLE90_BASE,
    parameter [24:0] ANGLE135_BASE = `DDR_MAP_ANGLE135_BASE,
    parameter [24:0] DOLP_BASE = `DDR_MAP_DOLP_BASE,
    parameter [24:0] AOP_BASE = `DDR_MAP_AOP_BASE,
    parameter [24:0] FUSION_BASE = `DDR_MAP_FUSION_BASE,
    parameter integer ENABLE_EDGE = 0,
    parameter integer IMG_WIDTH = 1280,
    parameter [24:0] EDGE_BASE = `DDR_MAP_EDGE_BASE,
    parameter [7:0] EDGE_THRESHOLD = 8'd24,
    parameter integer VERIFY_MAX_PASSES = 4096,
    parameter integer BLOCK_LIMIT = 67108864
)(
    input wire clk, rst_n, start, op_compute,
    input wire [24:0] source_addr, dest_addr, block_offset,
    output wire busy,
    output reg done, error,
    output wire request,
    input wire grant,
    output reg owner_release,
    input wire ddr_ready,
    output wire rd_en, wr_en,
    output wire [24:0] addr,
    output wire [127:0] wr_data,
    input wire rd_valid,
    input wire [127:0] rd_data,
    input wire abort_req,
    output reg abort_ack,
    output reg reset_required
);
    localparam [4:0] ST_IDLE=0, ST_READ_ISSUE=1, ST_READ_WAIT=2,
        ST_RELEASE_WAIT=3, ST_FEED=4, ST_CORE_WAIT=5, ST_BUILD=6,
        ST_WRITE_ISSUE=7, ST_VERIFY_ISSUE=8, ST_VERIFY_WAIT=9,
        ST_FINISH_WAIT=10, ST_ERROR_HOLD=11, ST_PRE_FRAME=12,
        ST_PRE_GAP=13, ST_PRE_LINE=14, ST_RETRY_RELEASE=15,
        ST_ABORT_READ_DRAIN=16, ST_ABORT_RELEASE=17, ST_ABORT_LOCAL=18,
        ST_TERMINAL=19;
    localparam AFTER_READ_FEED=1'b0, AFTER_READ_WRITE=1'b1;
    localparam integer VERIFY_W=(VERIFY_MAX_PASSES<2)?1:$clog2(VERIFY_MAX_PASSES+1);
    localparam integer BLOCK_W=(BLOCK_LIMIT<2)?1:$clog2(BLOCK_LIMIT+1);

    reg [4:0] state;
    reg compute_latched;
    reg [24:0] src_latched,dst_latched,offset_latched;
    reg after_release;
    reg [4:0] read_total,read_issued,read_returned;
    reg [3:0] write_total,write_index,verify_issued,verify_returned;
    reg [VERIFY_W-1:0] verify_attempts;
    reg [BLOCK_W-1:0] blocks_started;
    reg abort_seen,abort_after_verify;
    reg verify_mismatch;
    wire abort_active=(abort_req===1'b1);
    wire core_rst_n=rst_n&&(state!=ST_ABORT_LOCAL);
    reg [4:0] feed_index,raw_count,fused_count;
    reg [4:0] edge_count;
    reg raw_seen,fusion_seen,edge_seen;
    reg [23:0] fusion_pixel,edge_pixel;
    reg [5:0] core_age;
    localparam integer BLOCKS_PER_LINE=IMG_WIDTH/16;
    localparam integer COL_W=(BLOCKS_PER_LINE<2)?1:$clog2(BLOCKS_PER_LINE);
    reg [COL_W-1:0] column_block;
    reg compute_frame_start,compute_line_start;
    // Per-pixel consume/append reuses these as DoLP/AoP/Fusion/Edge result buffers.
    reg [383:0] angle0_words,angle45_words,angle90_words,angle135_words;
    reg [127:0] expected_word;
    reg [3:0] expected_index;

    wire [23:0] rgb0_in,rgb45_in,rgb90_in,rgb135_in;
    wire [7:0] i0_in,i45_in,i90_in,i135_in;
    // 按像素串行移位，避免用feed_index驱动四个384 bit宽动态多路器。
    assign rgb0_in=angle0_words[383:360];
    assign rgb45_in=angle45_words[383:360];
    assign rgb90_in=angle90_words[383:360];
    assign rgb135_in=angle135_words[383:360];
    // RGB888绿色字节作为强度；四角度图像必须来自同一固定白平衡/曝光组。
    assign i0_in=rgb0_in[15:8];
    assign i45_in=rgb45_in[15:8];
    assign i90_in=rgb90_in[15:8];
    assign i135_in=rgb135_in[15:8];

    wire [23:0] polar_rgb_unused,polar_aop_rgb,fusion_rgb,edge_rgb;
    wire [7:0] polar_y,polar_dolp_unused,polar_aop_unused;
    wire polar_de,polar_hs,polar_vs,edge_de,core_ready;
    // Sparse edge row/frame markers precede the first completed pixel.
    assign polar_hs=ENABLE_EDGE && (state==ST_PRE_LINE);
    assign polar_vs=ENABLE_EDGE && (state==ST_PRE_FRAME);
    wire edge_hs_in=(state==ST_PRE_LINE);
    wire edge_vs_in=(state==ST_PRE_FRAME);
    wire [7:0] fusion_y_unused,fusion_dolp,fusion_aop;
    wire fusion_bin_unused,fusion_de,fusion_hs_unused,fusion_vs_unused;
    algo_polar_fusion u_polar_fusion(
        .clk(clk),.rst_n(core_rst_n),.i0(i0_in),.i45(i45_in),.i90(i90_in),.i135(i135_in),
        .rgb0(rgb0_in),.rgb45(rgb45_in),.rgb90(rgb90_in),.rgb135(rgb135_in),
        .de_in(state==ST_FEED && core_ready),.hs_in(1'b0),
        .vs_in(1'b0),.thr_in(8'h40),.ready_out(core_ready),
        .polar_rgb_out(polar_rgb_unused),.polar_y_out(polar_y),
        .polar_aop_rgb_out(polar_aop_rgb),
        .polar_dolp_out(polar_dolp_unused),.polar_aop_out(polar_aop_unused),
        .polar_de_out(polar_de),.polar_hs_out(),.polar_vs_out(),
        .rgb_out(fusion_rgb),.y_out(fusion_y_unused),.dolp_out(fusion_dolp),
        .aop_out(fusion_aop),.bin_out(fusion_bin_unused),.de_out(fusion_de),
        .hs_out(fusion_hs_unused),.vs_out(fusion_vs_unused));

    generate if(ENABLE_EDGE)begin:g_edge
        algo_edge_polar #(.EDGE_MODE(1),.FUSE_MODE(0),.W_RGB(192),.W_DOLP(64),
            .EDGE_INV(0),.BORDER(1),.LB_W(IMG_WIDTH),.LB_DEPTH(2048),.LB_AW(11)) u_edge(
            .clk(clk),.rst_n(core_rst_n),.y_in(polar_y),.dolp_in(polar_dolp_unused),
            .vin(polar_de),.hs_in(polar_hs),.vs_in(polar_vs),.thr_in(EDGE_THRESHOLD),
            .rgb_out(edge_rgb),.y_out(),.e_rgb_out(),.e_dolp_out(),
            .bin_out(),.de_out(edge_de),.hs_out(),.vs_out());
    end else begin:g_no_edge
        assign edge_rgb=24'd0;assign edge_de=1'b0;
    end endgenerate

    assign busy=(state!=ST_IDLE);
    // 每次grant只服务当前短阶段。释放后必须等grant撤销再申请下一阶段。
    assign request=(state==ST_READ_ISSUE)||(state==ST_READ_WAIT)||
                   (state==ST_WRITE_ISSUE)||(state==ST_VERIFY_ISSUE)||(state==ST_VERIFY_WAIT);
    assign rd_en=request&&grant&&ddr_ready&&(!abort_active||abort_after_verify)&&
                  ((state==ST_READ_ISSUE&&read_issued<read_total)||
                   (state==ST_VERIFY_ISSUE&&verify_issued<write_total));
    assign wr_en=request&&grant&&ddr_ready&&(state==ST_WRITE_ISSUE&&write_index<write_total)&&
                  (!abort_active||abort_after_verify||write_index!=0);
    always @* begin
        if(state==ST_VERIFY_ISSUE||state==ST_VERIFY_WAIT)expected_index=verify_returned;
        else expected_index=write_index;
        case(expected_index)
            0:expected_word=angle0_words[383:256];
            1:expected_word=angle0_words[255:128];
            2:expected_word=angle0_words[127:0];
            3:expected_word=angle45_words[383:256];
            4:expected_word=angle45_words[255:128];
            5:expected_word=angle45_words[127:0];
            6:expected_word=angle90_words[383:256];
            7:expected_word=angle90_words[255:128];
            8:expected_word=angle90_words[127:0];
            9:expected_word=angle135_words[383:256];
            10:expected_word=angle135_words[255:128];
            default:expected_word=angle135_words[127:0];
        endcase
    end
    assign wr_data=expected_word;

    reg [24:0] addr_comb,base_comb;
    always @* begin
        addr_comb=25'd0;base_comb=25'd0;
        if(state==ST_READ_ISSUE)begin
            if(!compute_latched)
                addr_comb=src_latched+({20'd0,read_issued[1:0]}<<3);
            else begin
                case(read_issued/3)
                    0:base_comb=ANGLE0_BASE;
                    1:base_comb=ANGLE45_BASE;
                    2:base_comb=ANGLE90_BASE;
                    default:base_comb=ANGLE135_BASE;
                endcase
                addr_comb=base_comb+offset_latched+({23'd0,(read_issued%3)}<<3);
            end
        end else if(state==ST_VERIFY_ISSUE)begin
            if(!compute_latched)
                addr_comb=dst_latched+({21'd0,verify_issued[1:0]}<<3);
            else if(verify_issued<3)
                addr_comb=DOLP_BASE+offset_latched+({21'd0,verify_issued}<<3);
            else if(verify_issued<6)
                addr_comb=AOP_BASE+offset_latched+({21'd0,(verify_issued-4'd3)}<<3);
            else if(verify_issued<9)
                addr_comb=FUSION_BASE+offset_latched+({21'd0,(verify_issued-4'd6)}<<3);
            else addr_comb=EDGE_BASE+offset_latched+({21'd0,(verify_issued-4'd9)}<<3);
        end else if(state==ST_WRITE_ISSUE)begin
            if(!compute_latched)
                addr_comb=dst_latched+({21'd0,write_index[1:0]}<<3);
            else if(write_index<3)
                addr_comb=DOLP_BASE+offset_latched+({21'd0,write_index}<<3);
            else if(write_index<6)
                addr_comb=AOP_BASE+offset_latched+({21'd0,(write_index-4'd3)}<<3);
            else if(write_index<9)
                addr_comb=FUSION_BASE+offset_latched+({21'd0,(write_index-4'd6)}<<3);
            else addr_comb=EDGE_BASE+offset_latched+({21'd0,(write_index-4'd9)}<<3);
        end
    end
    assign addr=addr_comb;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=ST_IDLE;compute_latched<=0;src_latched<=0;dst_latched<=0;offset_latched<=0;
            after_release<=AFTER_READ_FEED;read_total<=0;read_issued<=0;read_returned<=0;
            write_total<=0;write_index<=0;verify_issued<=0;verify_returned<=0;verify_attempts<=0;
            blocks_started<=0;abort_seen<=0;abort_after_verify<=0;
            verify_mismatch<=0;
            feed_index<=0;raw_count<=0;fused_count<=0;edge_count<=0;
            raw_seen<=0;fusion_seen<=0;edge_seen<=0;
            fusion_pixel<=0;edge_pixel<=0;core_age<=0;
            column_block<=0;compute_frame_start<=0;compute_line_start<=0;
            angle0_words<=0;angle45_words<=0;angle90_words<=0;angle135_words<=0;
            done<=0;error<=0;owner_release<=0;abort_ack<=0;reset_required<=0;
        end else begin
            done<=0;owner_release<=0;abort_ack<=0;
            if(!abort_active)abort_seen<=0;
            if(rd_en&&state==ST_READ_ISSUE)read_issued<=read_issued+1'b1;

            // 命令计数与数据返回计数独立，允许二者在同一时钟各自前进。
            if(rd_valid)begin
                if(state==ST_READ_ISSUE||state==ST_READ_WAIT||state==ST_ABORT_READ_DRAIN)begin
                    read_returned<=read_returned+1'b1;
                    if(compute_latched)begin
                        case(read_returned/3)
                            0:angle0_words<={angle0_words[255:0],rd_data};
                            1:angle45_words<={angle45_words[255:0],rd_data};
                            2:angle90_words<={angle90_words[255:0],rd_data};
                            default:angle135_words<={angle135_words[255:0],rd_data};
                        endcase
                    end
                    else angle0_words<={angle0_words[255:0],rd_data};
                end else if(state==ST_VERIFY_ISSUE||state==ST_VERIFY_WAIT)begin
                    verify_returned<=verify_returned+1'b1;
                    if(rd_data!==expected_word)verify_mismatch<=1'b1;
                end
            end

            if(abort_active&&!abort_seen)begin
                abort_seen<=1'b1;
                case(state)
                    ST_IDLE:begin abort_ack<=1'b1; end
                    ST_READ_ISSUE,ST_READ_WAIT:state<=ST_ABORT_READ_DRAIN;
                    ST_RELEASE_WAIT:state<=ST_ABORT_RELEASE;
                    ST_FEED,ST_CORE_WAIT,ST_BUILD,ST_PRE_FRAME,ST_PRE_GAP,ST_PRE_LINE:
                        state<=ST_ABORT_LOCAL;
                    ST_WRITE_ISSUE:if(wr_en)begin
                        abort_after_verify<=1'b1;
                        if(write_index==write_total-1'b1)begin
                            write_index<=write_index+1'b1;verify_issued<=0;verify_returned<=0;
                            verify_mismatch<=0;state<=ST_VERIFY_ISSUE;
                        end else write_index<=write_index+1'b1;
                    end else if(write_index==0)begin owner_release<=1'b1;state<=ST_ABORT_RELEASE;end
                    else abort_after_verify<=1'b1;
                    ST_VERIFY_WAIT:begin
                        abort_after_verify<=1'b1;
                        if(rd_valid&&verify_returned==write_total-1'b1)begin
                            if(!verify_mismatch&&rd_data===expected_word)begin
                                error<=0;owner_release<=1'b1;state<=ST_FINISH_WAIT;
                            end else if(verify_attempts+1'b1>=VERIFY_MAX_PASSES)begin
                                verify_attempts<=VERIFY_MAX_PASSES;error<=1'b1;
                                reset_required<=1'b1;state<=ST_TERMINAL;
                            end else begin
                                verify_attempts<=verify_attempts+1'b1;
                                verify_issued<=0;verify_returned<=0;verify_mismatch<=0;
                                owner_release<=1'b1;state<=ST_RETRY_RELEASE;
                            end
                        end
                    end
                    ST_VERIFY_ISSUE,ST_RETRY_RELEASE,ST_FINISH_WAIT:
                        abort_after_verify<=1'b1;
                    ST_TERMINAL:begin error<=1'b1;reset_required<=1'b1;end
                    default:begin error<=1'b1;reset_required<=1'b1;state<=ST_TERMINAL;end
                endcase
            end else if(state==ST_TERMINAL)begin
                error<=1'b1;reset_required<=1'b1;
            end else case(state)
                ST_IDLE:if(start)begin
                    if(blocks_started>=BLOCK_LIMIT)begin
                        error<=1'b1;reset_required<=1'b1;state<=ST_TERMINAL;
                    end else begin
                    blocks_started<=blocks_started+1'b1;
                    compute_latched<=op_compute;src_latched<=source_addr;dst_latched<=dest_addr;
                    offset_latched<=block_offset;read_total<=op_compute?5'd12:5'd3;
                    read_issued<=0;read_returned<=0;
                    write_total<=op_compute?(ENABLE_EDGE?4'd12:4'd9):4'd3;
                    write_index<=0;verify_issued<=0;verify_returned<=0;verify_attempts<=0;
                    verify_mismatch<=0;feed_index<=0;
                    raw_count<=0;fused_count<=0;edge_count<=0;angle0_words<=0;angle45_words<=0;
                    raw_seen<=0;fusion_seen<=0;edge_seen<=0;core_age<=0;
                    angle90_words<=0;angle135_words<=0;
                    if(op_compute&&ENABLE_EDGE)begin
                        if(block_offset==0)begin column_block<=0;compute_frame_start<=1;compute_line_start<=1;end
                        else begin compute_frame_start<=0;compute_line_start<=(column_block==0);end
                    end else begin compute_frame_start<=0;compute_line_start<=0;end
                    error<=0;abort_after_verify<=0;state<=ST_READ_ISSUE;
                    end
                end
                ST_READ_ISSUE:if(read_issued==read_total)state<=ST_READ_WAIT;
                ST_READ_WAIT:if(read_returned==read_total||
                                (rd_valid&&read_returned==read_total-1'b1))begin
                    owner_release<=1;after_release<=compute_latched?AFTER_READ_FEED:AFTER_READ_WRITE;
                    state<=ST_RELEASE_WAIT;
                end
                ST_RELEASE_WAIT:if(!grant)begin
                    if(after_release==AFTER_READ_FEED)begin
                        feed_index<=0;
                        if(ENABLE_EDGE&&compute_frame_start)state<=ST_PRE_FRAME;
                        else if(ENABLE_EDGE&&compute_line_start)state<=ST_PRE_LINE;
                        else state<=ST_FEED;
                    end
                    else begin write_index<=0;state<=ST_WRITE_ISSUE;end
                end
                ST_PRE_FRAME:state<=ST_PRE_GAP;
                ST_PRE_GAP:state<=ST_PRE_LINE;
                ST_PRE_LINE:state<=ST_FEED;
                ST_FEED:if(core_ready)begin
                    raw_seen<=0;fusion_seen<=0;edge_seen<=0;core_age<=0;
                    state<=ST_CORE_WAIT;
                end
                ST_CORE_WAIT:begin
                    core_age<=core_age+1'b1;
                    if(polar_de)begin raw_seen<=1;raw_count<=raw_count+1'b1;end
                    if(fusion_de)begin
                        fusion_seen<=1;fusion_pixel<=fusion_rgb;fused_count<=fused_count+1'b1;
                    end
                    if(ENABLE_EDGE && edge_de)begin
                        edge_seen<=1;edge_pixel<=edge_rgb;edge_count<=edge_count+1'b1;
                    end
                    if(raw_seen && fusion_seen && (!ENABLE_EDGE || edge_seen))begin
                        // The head is consumed only after all results are present.
                        // Append its output at the tail; the next unread source
                        // pixel remains at the head. After 16 commits the same
                        // four buffers contain complete output pages.
                        angle0_words<={angle0_words[359:0],{3{polar_dolp_unused}}};
                        angle45_words<={angle45_words[359:0],polar_aop_rgb};
                        angle90_words<={angle90_words[359:0],fusion_pixel};
                        angle135_words<={angle135_words[359:0],edge_pixel};
                        if(feed_index==15)begin feed_index<=16;state<=ST_BUILD;end
                        else begin feed_index<=feed_index+1'b1;state<=ST_FEED;end
                    end else if(core_age==63)begin
                        // A missing local result must not hang the DDR client.
                        error<=1;reset_required<=1;state<=ST_TERMINAL;
                    end
                end
                // 保留这一拍，让末笔结果的非阻塞写入完成，且DDR发命令时刻不变。
                ST_BUILD:begin write_index<=0;state<=ST_WRITE_ISSUE;end
                ST_WRITE_ISSUE:if(wr_en)begin
                    write_index<=write_index+1'b1;
                    if(write_index==write_total-1'b1)begin
                        verify_issued<=0;verify_returned<=0;verify_mismatch<=0;state<=ST_VERIFY_ISSUE;
                    end
                end
                ST_VERIFY_ISSUE:begin
                    if(rd_en)verify_issued<=verify_issued+1'b1;
                    if(verify_issued==write_total||
                       (rd_en&&verify_issued==write_total-1'b1))state<=ST_VERIFY_WAIT;
                end
                ST_VERIFY_WAIT:begin
                    if(rd_valid&&verify_returned==write_total-1'b1)begin
                        // 最后一个读回值也须在本拍比较通过后才能完成。
                        if(!verify_mismatch&&rd_data===expected_word)begin
                            error<=0;owner_release<=1;state<=ST_FINISH_WAIT;
                        end else begin
                            if(verify_attempts+1'b1>=VERIFY_MAX_PASSES)begin
                                verify_attempts<=VERIFY_MAX_PASSES;error<=1'b1;
                                reset_required<=1'b1;state<=ST_TERMINAL;
                            end else begin
                                verify_attempts<=verify_attempts+1'b1;
                                verify_issued<=0;verify_returned<=0;verify_mismatch<=0;
                                owner_release<=1;state<=ST_RETRY_RELEASE;
                            end
                        end
                    end
                end
                // 本轮回包已收齐：保持结果缓存，等实际grant撤销后再申请下一轮核验。
                ST_RETRY_RELEASE:if(!grant)state<=ST_VERIFY_ISSUE;
                ST_FINISH_WAIT:if(!grant)begin
                    if(abort_after_verify)begin
                        abort_ack<=1'b1;abort_after_verify<=0;state<=ST_IDLE;
                    end else begin
                        if(compute_latched&&ENABLE_EDGE)begin
                            if(column_block>=BLOCKS_PER_LINE-1)column_block<=0;
                            else column_block<=column_block+1'b1;
                        end
                        done<=1;state<=ST_IDLE;
                    end
                end
                ST_ABORT_READ_DRAIN:if(read_returned>=read_issued||
                    (rd_valid&&read_returned+1'b1>=read_issued))begin
                    owner_release<=1'b1;state<=ST_ABORT_RELEASE;
                end
                ST_ABORT_RELEASE:if(!grant)begin abort_ack<=1'b1;state<=ST_IDLE;end
                ST_ABORT_LOCAL:begin
                    raw_seen<=0;fusion_seen<=0;edge_seen<=0;core_age<=0;
                    read_issued<=0;read_returned<=0;verify_issued<=0;verify_returned<=0;
                    angle0_words<=0;angle45_words<=0;angle90_words<=0;angle135_words<=0;
                    abort_ack<=1'b1;state<=ST_IDLE;
                end
                ST_ERROR_HOLD:begin error<=1;reset_required<=1;state<=ST_TERMINAL;end
                default:begin error<=1;reset_required<=1;state<=ST_TERMINAL;end
            endcase
        end
    end
endmodule
