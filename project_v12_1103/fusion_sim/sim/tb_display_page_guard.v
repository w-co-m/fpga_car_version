`timescale 1ns/1ps
module tb_display_page_guard;
reg clk=0; always #5 clk=~clk;
reg rst=0, fs=0, cv=0, pause=0, wr_ready=1, read_busy=0;
reg [127:0] camera_data=0;
reg [3:0] display_mask=0;
wire busy, wr_en, frame_start, good_frame;
wire [1:0] rp;
wire [3:0] page_valid;
wire [24:0] addr;
wire [127:0] data;
integer page0_writes=0, write_count=0, good_count=0, i;
integer accepted_in_drop=0, drained_in_drop=0, busy_in_drop=0;
reg drop_check=0;
reg [3:0] valid_snapshot;
reg good_last=0;
reg vo_vsync=0, vo_ready=1, vo_rd_valid=0;
reg [24:0] source_base=0;
reg [3:0] source_mode=0;
reg source_result=0, source_valid=0;
wire vo_rd_en, vo_busy, vo_pending, vo_result_active, vo_underflow;
wire [24:0] vo_addr;
wire [3:0] vo_mode, vo_page_mask;
wire [8:0] vo_fill;
wire [9:0] vo_credit;
wire [23:0] pixel;
integer vo_reads=0;

video_in #(.FRAME_WORDS(6), .BURST_WORDS(2), .REQUIRE_COMPLETE_FRAME(1),
           .ENABLE_DISPLAY_PAGE_GUARD(1)) dut(
    .I_rst_n(rst), .I_camera_clk(clk), .I_camera_frame_start(fs),
    .I_camera_valid(cv), .I_camera_data(camera_data), .I_mipi_rx_error(1'b0),
    .I_ddr_clk(clk), .I_display_pause(pause), .I_video_out_rd_busy(read_busy),
    .O_video_in_wr_busy(busy), .O_video_out_rp(rp), .O_ddr_user_wr_en(wr_en),
    .O_ddr_user_addr(addr), .O_ddr_user_wr_data(data), .I_ddr_user_ready(wr_ready),
    .O_frame_start_ddr(frame_start), .O_page_valid(page_valid),
    .I_display_page_mask(display_mask | vo_page_mask), .O_good_frame_ddr(good_frame));

video_out #(.USE_EXTERNAL_SOURCE(1), .FRAME_WORDS(24), .BURST_WORDS(2),
            .ENABLE_DISPLAY_PAGE_GUARD(1)) vo(
    .I_rst_n(rst), .I_ddr_clk(clk), .O_video_out_rd_busy(vo_busy),
    .I_video_in_wr_busy(1'b0), .I_video_out_rp(2'd0),
    .O_ddr_user_rd_en(vo_rd_en), .O_ddr_user_addr(vo_addr),
    .I_ddr_user_ready(vo_ready), .I_ddr_user_rd_valid(vo_rd_valid),
    .I_ddr_user_rd_data(128'd0), .I_dsi_clk(clk), .I_video_vsync(vo_vsync),
    .I_video_rd_en(1'b0), .O_vdieo_data(pixel), .I_source_base(source_base),
    .I_source_mode(source_mode), .I_source_is_result(source_result),
    .I_source_valid(source_valid), .O_frame_mode(vo_mode),
    .O_result_source_active(vo_result_active), .O_fifo_fill(vo_fill),
    .O_read_credit(vo_credit), .O_frame_pending(vo_pending),
    .O_underflow(vo_underflow), .O_display_page_mask(vo_page_mask));

always @(posedge clk) if (rst && wr_en && addr < 25'd7000000)
    page0_writes = page0_writes + 1;
always @(posedge clk) if (rst) begin
    if (wr_en) write_count = write_count + 1;
    if (good_frame) begin
        good_count = good_count + 1;
        if (!frame_start || good_last) $fatal(1,"good-frame pulse mismatch start=%b prior=%b rp=%d",frame_start,good_last,rp);
    end
    good_last = good_frame;
end
always @(posedge clk) if (rst && vo_rd_en) vo_reads = vo_reads + 1;
always @(posedge clk) if (rst && drop_check) begin
    if (dut.S_camera_accept) accepted_in_drop = accepted_in_drop + 1;
    if (dut.g_complete_capture.S_fifo_drop_drain && dut.S_fifo_rd_en) drained_in_drop = drained_in_drop + 1;
    if (busy || wr_en) busy_in_drop = busy_in_drop + 1;
end

task boundary;
begin
    @(negedge clk); fs=1;
    @(negedge clk); fs=0;
    wait(frame_start);
    wait(!dut.S_fifo_rst);
    repeat(6) @(negedge clk);
end
endtask

task vo_frame_boundary;
begin
    @(negedge clk); vo_vsync=1;
    repeat(5) @(negedge clk);
    vo_vsync=0;
    repeat(5) @(negedge clk);
end
endtask

task words;
input integer n;
input [127:0] payload;
begin
    @(negedge clk); cv=1; camera_data=payload;
    repeat(n) @(negedge clk);
    cv=0;
    repeat(30) @(negedge clk);
end
endtask

initial begin
    repeat(6) @(negedge clk); rst=1;
    repeat(40) @(negedge clk);
    if (vo_reads!=0 || vo_page_mask!==0)
        $fatal(1,"VO read/reserved page before a valid source");

    source_valid=1; source_base=25'd7000000; source_mode=4'h3;
    vo_frame_boundary();
    wait(!vo_pending);
    if (vo_page_mask!==4'b0010) $fatal(1,"live source page mask missing: %b",vo_page_mask);

    // Keep one DDR read credit outstanding while two VS events replace pending pages.
    wait(vo_rd_en); @(posedge clk); @(negedge clk); vo_ready=0;
    wait(vo_credit==1);
    source_base=25'd14000000; vo_frame_boundary();
    if (vo_page_mask!==4'b0110) $fatal(1,"active and pending page masks not combined: %b",vo_page_mask);
    source_base=25'd21000000; vo_frame_boundary();
    if (vo_page_mask!==4'b1010) $fatal(1,"new VS did not replace pending page: %b",vo_page_mask);
    @(negedge clk); vo_rd_valid=1;
    @(negedge clk); vo_rd_valid=0;
    wait(!vo_pending);
    if (vo_page_mask!==4'b1000) $fatal(1,"active mask did not switch after old credit drained: %b",vo_page_mask);

    source_result=1; source_base=25'd0; vo_frame_boundary();
    wait(!vo_pending);
    if (vo_page_mask!==0 || !vo_result_active)
        $fatal(1,"result source incorrectly reserved a live page");
    source_result=0; source_valid=0; vo_frame_boundary();
    wait(!vo_pending);
    if (vo_page_mask!==0) $fatal(1,"invalid source retained a page reservation");
    vo_ready=1;
    repeat(30) @(negedge clk);
    if (vo_reads!=1) $fatal(1,"VO issued reads without a valid source: %0d",vo_reads);

    boundary(); words(6,128'h1111); boundary();
    if (rp!==0 || page_valid[0]!==1 || page0_writes!=6)
        $fatal(1,"setup failed rp=%0d valid=%b writes=%0d",rp,page_valid,page0_writes);
    if (good_count!=1) $fatal(1,"good frame publication pulse missing: %0d",good_count);

    // 接入VO真实输出掩码：当前显示源切到已发布的页0后，采集不得再写页0。
    source_valid=1; source_result=0; source_base=25'd0;
    vo_frame_boundary(); wait(!vo_pending);
    if (vo_page_mask!==4'b0001) $fatal(1,"VO did not publish live page0 mask: %b",vo_page_mask);
    display_mask=0;
    for (i=0;i<3;i=i+1) begin words(4,128'h2222); boundary(); end
    if (rp!==0 || page_valid[0]!==1 || page0_writes!=6)
        $fatal(1,"live display page was overwritten rp=%0d valid=%b writes=%0d",rp,page_valid,page0_writes);

    pause=1;
    words(6,128'h3333); boundary();
    if (rp!==0 || page_valid[0]!==1)
        $fatal(1,"pause did not preserve the published page and pointer");
    if (good_count!=1) $fatal(1,"pause incorrectly counted as a good-frame publication");
    pause=0;
    words(6,128'h4444); boundary();
    if (rp===0 || !page_valid[rp])
        $fatal(1,"good frame after pause release was not published");
    if (good_count!=2) $fatal(1,"good-frame pulse count did not match published frames: %0d",good_count);
    if (page0_writes!=6) $fatal(1,"live page received writes while protected");

    display_mask=4'b1111;
    wr_ready=0; read_busy=1;
    boundary();
    i=write_count;
    valid_snapshot=page_valid;
    accepted_in_drop=0; drained_in_drop=0; busy_in_drop=0; drop_check=1;
    words(6,128'h5555);
    drop_check=0;
    if (write_count!=i) $fatal(1,"all-protected drop drained into DDR writes");
    if (page_valid!==valid_snapshot) $fatal(1,"all-protected drop cleared a retained valid page");
    if (accepted_in_drop!=6 || drained_in_drop!=6 || !dut.S_fifo_empty || dut.S_fifo_rd_num!=0)
        $fatal(1,"drop FIFO not fully drained accepted=%0d drained=%0d empty=%b remaining=%0d",accepted_in_drop,drained_in_drop,dut.S_fifo_empty,dut.S_fifo_rd_num);
    if (busy_in_drop!=0 || busy || wr_en)
        $fatal(1,"drop asserted capture busy/write with ready low and reader busy");
    if (good_count!=2) $fatal(1,"drop incorrectly counted as a good-frame publication");
    wr_ready=1; read_busy=0;
    display_mask=0;
    boundary();
    words(6,128'h6666); boundary();
    if (!page_valid[rp]) $fatal(1,"capture did not recover after free page became available");
    $display("PASS display page guard: live page0 remained valid and unchanged");
    $finish;
end
initial begin #100000; $fatal(1,"timeout"); end
endmodule
