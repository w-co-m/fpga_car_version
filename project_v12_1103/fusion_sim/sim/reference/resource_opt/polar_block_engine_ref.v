`timescale 1ns/1ps
// 偏振后台块引擎：每次处理16个连续RGB888像素（384 bit / 3个128 bit DDR字）。
// DDR地址以16 bit为单位，因此相邻128 bit字地址相差8；偏移量由上层按块提供。
// 只在grant且ready时发出单拍命令。读返回按顺序计数；写后逐字读回全部内容，
// 用于覆盖DDR命令队列尚未完成物理写入的情况。计算期间释放DDR所有权。
module polar_block_engine_ref #(
    parameter [24:0] ANGLE0_BASE = 25'd23000000,
    parameter [24:0] ANGLE45_BASE = 25'd24400000,
    parameter [24:0] ANGLE90_BASE = 25'd25800000,
    parameter [24:0] ANGLE135_BASE = 25'd27200000,
    parameter [24:0] DOLP_BASE = 25'd28600000,
    parameter [24:0] AOP_BASE = 25'd30000000,
    parameter [24:0] FUSION_BASE = 25'd31400000,
    parameter integer ENABLE_EDGE = 0,
    parameter integer IMG_WIDTH = 1280,
    parameter [24:0] EDGE_BASE = 25'd4000000,
    parameter [7:0] EDGE_THRESHOLD = 8'd24
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
    input wire [127:0] rd_data
);
    localparam [3:0] ST_IDLE=0, ST_READ_ISSUE=1, ST_READ_WAIT=2,
        ST_RELEASE_WAIT=3, ST_FEED=4, ST_CORE_WAIT=5, ST_BUILD=6,
        ST_WRITE_ISSUE=7, ST_VERIFY_ISSUE=8, ST_VERIFY_WAIT=9,
        ST_FINISH_WAIT=10, ST_ERROR_HOLD=11, ST_PRE_FRAME=12,
        ST_PRE_GAP=13, ST_PRE_LINE=14, ST_RETRY_RELEASE=15;
    localparam AFTER_READ_FEED=1'b0, AFTER_READ_WRITE=1'b1;

    reg [3:0] state;
    reg compute_latched;
    reg [24:0] src_latched,dst_latched,offset_latched;
    reg after_release;
    reg [4:0] read_total,read_issued,read_returned;
    reg [3:0] write_total,write_index,verify_issued,verify_returned;
    reg [11:0] verify_attempts;
    reg verify_mismatch;
    reg [4:0] feed_index,raw_count,fused_count;
    reg [4:0] edge_count;
    localparam integer BLOCKS_PER_LINE=IMG_WIDTH/16;
    localparam integer COL_W=(BLOCKS_PER_LINE<2)?1:$clog2(BLOCKS_PER_LINE);
    reg [COL_W-1:0] column_block;
    reg compute_frame_start,compute_line_start;
    reg [383:0] angle0_words,angle45_words,angle90_words,angle135_words;
    reg [383:0] dolp_words,aop_words,fusion_words,edge_words;
    reg [127:0] expected_words[0:8];
    reg [127:0] expected_word;
    reg [3:0] expected_index;
    integer word_i;

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

    wire [23:0] polar_rgb_unused,fusion_rgb,edge_rgb;
    wire [7:0] polar_y,polar_dolp_unused,polar_aop_unused;
    wire polar_de,polar_hs,polar_vs,edge_de;
    wire edge_hs_in=(state==ST_PRE_LINE);
    wire edge_vs_in=(state==ST_PRE_FRAME);
    wire [7:0] fusion_y_unused,fusion_dolp,fusion_aop;
    wire fusion_bin_unused,fusion_de,fusion_hs_unused,fusion_vs_unused;
    algo_polar_fusion u_polar_fusion(
        .clk(clk),.rst_n(rst_n),.i0(i0_in),.i45(i45_in),.i90(i90_in),.i135(i135_in),
        .rgb0(rgb0_in),.rgb45(rgb45_in),.rgb90(rgb90_in),.rgb135(rgb135_in),
        .de_in(state==ST_FEED),.hs_in(ENABLE_EDGE?edge_hs_in:1'b0),
        .vs_in(ENABLE_EDGE?edge_vs_in:1'b0),.thr_in(8'h40),
        .polar_rgb_out(polar_rgb_unused),.polar_y_out(polar_y),
        .polar_dolp_out(polar_dolp_unused),.polar_aop_out(polar_aop_unused),
        .polar_de_out(polar_de),.polar_hs_out(polar_hs),.polar_vs_out(polar_vs),
        .rgb_out(fusion_rgb),.y_out(fusion_y_unused),.dolp_out(fusion_dolp),
        .aop_out(fusion_aop),.bin_out(fusion_bin_unused),.de_out(fusion_de),
        .hs_out(fusion_hs_unused),.vs_out(fusion_vs_unused));

    generate if(ENABLE_EDGE)begin:g_edge
        algo_edge_polar #(.EDGE_MODE(1),.FUSE_MODE(0),.W_RGB(192),.W_DOLP(64),
            .EDGE_INV(0),.BORDER(1),.LB_W(IMG_WIDTH),.LB_DEPTH(2048),.LB_AW(11)) u_edge(
            .clk(clk),.rst_n(rst_n),.y_in(polar_y),.dolp_in(polar_dolp_unused),
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
    assign rd_en=request&&grant&&ddr_ready&&
                  ((state==ST_READ_ISSUE&&read_issued<read_total)||
                   (state==ST_VERIFY_ISSUE&&verify_issued<write_total));
    assign wr_en=request&&grant&&ddr_ready&&(state==ST_WRITE_ISSUE&&write_index<write_total);
    always @* begin
        if(state==ST_VERIFY_ISSUE||state==ST_VERIFY_WAIT)expected_index=verify_returned;
        else expected_index=write_index;
        case(expected_index)
            0:expected_word=expected_words[0];1:expected_word=expected_words[1];
            2:expected_word=expected_words[2];3:expected_word=expected_words[3];
            4:expected_word=expected_words[4];5:expected_word=expected_words[5];
            6:expected_word=expected_words[6];7:expected_word=expected_words[7];
            8:expected_word=expected_words[8];9:expected_word=edge_words[383:256];
            10:expected_word=edge_words[255:128];default:expected_word=edge_words[127:0];
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
            verify_mismatch<=0;
            feed_index<=0;raw_count<=0;fused_count<=0;edge_count<=0;
            column_block<=0;compute_frame_start<=0;compute_line_start<=0;
            angle0_words<=0;angle45_words<=0;angle90_words<=0;angle135_words<=0;
            dolp_words<=0;aop_words<=0;fusion_words<=0;edge_words<=0;done<=0;error<=0;owner_release<=0;
            for(word_i=0;word_i<9;word_i=word_i+1)expected_words[word_i]<=0;
        end else begin
            done<=0;owner_release<=0;
            if(rd_en&&state==ST_READ_ISSUE)read_issued<=read_issued+1'b1;

            // 命令计数与数据返回计数独立，允许二者在同一时钟各自前进。
            if(rd_valid)begin
                if(state==ST_READ_ISSUE||state==ST_READ_WAIT)begin
                    read_returned<=read_returned+1'b1;
                    if(!compute_latched)expected_words[read_returned]<=rd_data;
                    else case(read_returned/3)
                        0:angle0_words<={angle0_words[255:0],rd_data};
                        1:angle45_words<={angle45_words[255:0],rd_data};
                        2:angle90_words<={angle90_words[255:0],rd_data};
                        default:angle135_words<={angle135_words[255:0],rd_data};
                    endcase
                end else if(state==ST_VERIFY_ISSUE||state==ST_VERIFY_WAIT)begin
                    verify_returned<=verify_returned+1'b1;
                    if(rd_data!==expected_word)verify_mismatch<=1'b1;
                end
            end

            case(state)
                ST_IDLE:if(start)begin
                    compute_latched<=op_compute;src_latched<=source_addr;dst_latched<=dest_addr;
                    offset_latched<=block_offset;read_total<=op_compute?5'd12:5'd3;
                    read_issued<=0;read_returned<=0;
                    write_total<=op_compute?(ENABLE_EDGE?4'd12:4'd9):4'd3;
                    write_index<=0;verify_issued<=0;verify_returned<=0;verify_attempts<=0;
                    verify_mismatch<=0;feed_index<=0;
                    raw_count<=0;fused_count<=0;edge_count<=0;angle0_words<=0;angle45_words<=0;
                    angle90_words<=0;angle135_words<=0;dolp_words<=0;aop_words<=0;fusion_words<=0;
                    edge_words<=0;
                    if(op_compute&&ENABLE_EDGE)begin
                        if(block_offset==0)begin column_block<=0;compute_frame_start<=1;compute_line_start<=1;end
                        else begin compute_frame_start<=0;compute_line_start<=(column_block==0);end
                    end else begin compute_frame_start<=0;compute_line_start<=0;end
                    error<=0;state<=ST_READ_ISSUE;
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
                ST_FEED:begin
                    angle0_words<={angle0_words[359:0],24'd0};
                    angle45_words<={angle45_words[359:0],24'd0};
                    angle90_words<={angle90_words[359:0],24'd0};
                    angle135_words<={angle135_words[359:0],24'd0};
                    if(feed_index==15)begin feed_index<=16;state<=ST_CORE_WAIT;end
                    else feed_index<=feed_index+1'b1;
                end
                ST_CORE_WAIT:begin
                    if(polar_de&&raw_count<16)raw_count<=raw_count+1'b1;
                    if(fusion_de&&fused_count<16)begin
                        dolp_words<={dolp_words[359:0],{3{fusion_dolp}}};
                        aop_words<={aop_words[359:0],{3{fusion_aop}}};
                        fusion_words<={fusion_words[359:0],fusion_rgb};
                        fused_count<=fused_count+1'b1;
                    end
                    if(ENABLE_EDGE&&edge_de&&edge_count<16)begin
                        edge_words<={edge_words[359:0],edge_rgb};edge_count<=edge_count+1'b1;
                    end
                    if(ENABLE_EDGE)begin
                        if((raw_count==16||(polar_de&&raw_count==15))&&
                           (fused_count==16||(fusion_de&&fused_count==15))&&
                           (edge_count==16||(edge_de&&edge_count==15)))state<=ST_BUILD;
                    end else if(fusion_de&&fused_count==15)begin
                        if(raw_count==16||(polar_de&&raw_count==15))state<=ST_BUILD;
                        else begin error<=1;state<=ST_ERROR_HOLD;end
                    end
                end
                ST_BUILD:begin
                    expected_words[0]<=dolp_words[383:256];expected_words[1]<=dolp_words[255:128];
                    expected_words[2]<=dolp_words[127:0];expected_words[3]<=aop_words[383:256];
                    expected_words[4]<=aop_words[255:128];expected_words[5]<=aop_words[127:0];
                    expected_words[6]<=fusion_words[383:256];expected_words[7]<=fusion_words[255:128];
                    expected_words[8]<=fusion_words[127:0];write_index<=0;state<=ST_WRITE_ISSUE;
                end
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
                            if(verify_attempts!=12'hfff)verify_attempts<=verify_attempts+1'b1;
                            else error<=1'b1;
                            verify_issued<=0;verify_returned<=0;verify_mismatch<=0;
                            owner_release<=1;state<=ST_RETRY_RELEASE;
                        end
                    end
                end
                // 本轮回包已收齐：保持结果缓存，等实际grant撤销后再申请下一轮核验。
                ST_RETRY_RELEASE:if(!grant)state<=ST_VERIFY_ISSUE;
                ST_FINISH_WAIT:if(!grant)begin
                    if(compute_latched&&ENABLE_EDGE)begin
                        if(column_block>=BLOCKS_PER_LINE-1)column_block<=0;
                        else column_block<=column_block+1'b1;
                    end
                    done<=1;state<=ST_IDLE;
                end
                ST_ERROR_HOLD:error<=1;
                default:begin error<=1;state<=ST_ERROR_HOLD;end
            endcase
        end
    end
endmodule
