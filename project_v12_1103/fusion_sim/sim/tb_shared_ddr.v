`timescale 1ns/1ps
module tb_shared_ddr #(parameter integer CAPTURE_MODE=1);
    localparam integer FRAME_WORDS=480;
    localparam integer BURST_WORDS=240;
    reg rst_n=0;
    reg ddr_clk=0, camera_clk=0, dsi_clk=0;
    always #5 ddr_clk=~ddr_clk;
    always #7 camera_clk=~camera_clk;
    always #2 dsi_clk=~dsi_clk;

    reg camera_frame_start=0, camera_valid=0;
    reg video_vsync=0;
    reg [127:0] camera_data=0;
    wire vi_busy, vi_wr_en;
    wire [24:0] vi_addr;
    wire [127:0] vi_data;
    wire [1:0] video_out_rp;
    wire [3:0] page_valid;
    wire good_frame;

    wire vo_busy, vo_rd_en;
    wire [24:0] vo_addr;
    wire [8:0] vo_fill;
    wire [9:0] vo_credit;
    wire frame_pending;
    wire [3:0] vo_page_mask;
    wire [3:0] display_page_mask = vo_page_mask | 4'b0001;
    wire [23:0] pixel_data;
    wire [3:0] frame_mode;
    wire result_active, underflow;

    reg mc_ready=0;
    reg service_enable=0;
    reg [15:0] lfsr=16'h1ace;
    always @(posedge ddr_clk) begin
        lfsr <= {lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
        mc_ready <= service_enable && (lfsr[1:0] != 2'b00);
    end

    wire live_ready;
    wire vo_return_valid, bg_return_valid;
    wire [127:0] return_data;
    wire shared_wr_en, shared_rd_en;
    wire [24:0] shared_addr;
    wire [127:0] shared_wr_data;
    reg [127:0] memory [0:4095];
    reg [127:0] read_data=0;
    reg read_valid=0;
    reg read_pending=0;
    reg [24:0] pending_addr=0;
    reg [127:0] pending_data=0;
    reg [127:0] expected_reads [0:2047];
    integer writes=0, reads=0, returned_reads=0, reads_between_bursts=0, published_frames=0;
    integer i;
    integer expected_base;

    video_in #(.FRAME_WORDS(FRAME_WORDS),.BURST_WORDS(BURST_WORDS),
        .REQUIRE_COMPLETE_FRAME(CAPTURE_MODE),.ENABLE_DISPLAY_PAGE_GUARD(CAPTURE_MODE)) u_vi(
        .I_rst_n(rst_n),.I_camera_clk(camera_clk),.I_camera_frame_start(camera_frame_start),
        .I_camera_valid(camera_valid),.I_camera_data(camera_data),.I_mipi_rx_error(1'b0),
        .I_ddr_clk(ddr_clk),.I_display_pause(1'b0),.I_video_out_rd_busy(vo_busy),
        .O_video_in_wr_busy(vi_busy),.O_video_out_rp(video_out_rp),
        .O_ddr_user_wr_en(vi_wr_en),.O_ddr_user_addr(vi_addr),.O_ddr_user_wr_data(vi_data),
        .I_ddr_user_ready(live_ready),.O_frame_start_ddr(),.O_page_valid(page_valid),
        .I_display_page_mask(display_page_mask),.O_good_frame_ddr(good_frame));

    video_out #(.USE_EXTERNAL_SOURCE(1),.FRAME_WORDS(960),.BURST_WORDS(BURST_WORDS),
        .ENABLE_UNDERFLOW_GUARD(0),.ENABLE_DISPLAY_PAGE_GUARD(1)) u_vo(
        .I_rst_n(rst_n),.I_ddr_clk(ddr_clk),.O_video_out_rd_busy(vo_busy),
        .I_video_in_wr_busy(vi_busy),.I_video_out_rp(video_out_rp),
        .O_ddr_user_rd_en(vo_rd_en),.O_ddr_user_addr(vo_addr),.I_ddr_user_ready(live_ready),
        .I_ddr_user_rd_valid(vo_return_valid),.I_ddr_user_rd_data(return_data),
        .I_dsi_clk(dsi_clk),.I_video_vsync(video_vsync),.I_video_rd_en(1'b1),
        .O_vdieo_data(pixel_data),.I_source_base(25'd0),.I_source_mode(4'd0),
        .I_source_is_result(1'b0),.I_source_valid(1'b1),.O_frame_mode(frame_mode),
        .O_result_source_active(result_active),.O_fifo_fill(vo_fill),.O_read_credit(vo_credit),
        .O_frame_pending(frame_pending),.O_underflow(underflow),.O_display_page_mask(vo_page_mask));

    polar_ddr_arbiter #(.MIN_DISPLAY_FILL(320)) u_arbiter(
        .clk(ddr_clk),.rst_n(rst_n),.calibrated(1'b1),.queue_idle(1'b1),
        .user_ready(mc_ready),.rd_valid(read_valid),.rd_data(read_data),
        .vi_busy(vi_busy),.vi_wr_en(vi_wr_en),.vi_addr(vi_addr),.vi_data(vi_data),
        .vo_busy(vo_busy),.vo_rd_en(vo_rd_en),.vo_frame_pending(frame_pending),
        .vo_fill(vo_fill),.vo_credit(vo_credit),.vo_addr(vo_addr),
        .bg_request(1'b0),.bg_release(1'b0),.bg_rd_en(1'b0),.bg_wr_en(1'b0),
        .bg_addr(25'd0),.bg_data(128'd0),.bg_grant(),.live_ready(live_ready),.bg_ready(),
        .vo_return_valid(vo_return_valid),.bg_return_valid(bg_return_valid),
        .return_data(return_data),.wr_en(shared_wr_en),.rd_en(shared_rd_en),
        .addr(shared_addr),.wr_data(shared_wr_data));

    always @(posedge ddr_clk) begin
        if (good_frame) published_frames <= published_frames + 1;
        read_valid <= read_pending;
        read_pending <= 1'b0;
        if (read_pending) read_data <= pending_data;
        if (shared_wr_en && shared_rd_en)
            $fatal(1,"shared DDR accepted read and write intents together");
        if (shared_rd_en) begin
            if (shared_addr != reads*8)
                $fatal(1,"display read address mismatch index=%0d got=%0d expected=%0d",reads,shared_addr,reads*8);
            if (reads >= 2048) $fatal(1,"read expectation queue overflow");
            expected_reads[reads] <= memory[shared_addr[14:3]];
            read_pending <= 1'b1;
            pending_addr <= shared_addr;
            pending_data <= memory[shared_addr[14:3]];
            reads <= reads + 1;
            if (writes >= BURST_WORDS && writes < FRAME_WORDS)
                reads_between_bursts <= reads_between_bursts + 1;
        end
        if (vo_return_valid) begin
            if (returned_reads >= reads)
                $fatal(1,"display returned more words than were requested");
            if (return_data !== expected_reads[returned_reads])
                $fatal(1,"display return data/order mismatch index=%0d got=%h expected=%h",returned_reads,return_data,expected_reads[returned_reads]);
            returned_reads <= returned_reads + 1;
        end
        if (shared_wr_en) begin
            if (shared_addr != expected_base + writes*8)
                $fatal(1,"write address mismatch index=%0d got=%0d expected=%0d",writes,shared_addr,expected_base+writes*8);
            if (shared_wr_data !== {32'hcafe0000,32'd0,writes[31:0],32'h55aa55aa})
                $fatal(1,"write data order mismatch index=%0d data=%h",writes,shared_wr_data);
            memory[shared_addr[14:3]] <= shared_wr_data;
            writes <= writes + 1;
        end
    end

    task pulse_camera_frame_start;
        integer timeout;
        begin
            @(negedge camera_clk); camera_frame_start=1'b1;
            @(negedge camera_clk); camera_frame_start=1'b0;
            // A normal frame starts only after both FIFO reset domains are ready.
            // Early data rejection is covered separately by tb_review_io_guard.
            timeout=0;
            while (!u_vi.S_camera_capture_open && timeout < 100) begin
                @(negedge camera_clk); timeout=timeout+1;
            end
            if (!u_vi.S_camera_capture_open)
                $fatal(1,"camera FIFO reset guard did not open");
        end
    endtask

    task send_frame_words;
        integer n;
        begin
            for(n=0;n<FRAME_WORDS;n=n+1) begin
                @(negedge camera_clk);
                camera_valid=1'b1;
                camera_data={32'hcafe0000,32'd0,n[31:0],32'h55aa55aa};
            end
            @(negedge camera_clk); camera_valid=1'b0; camera_data=0;
        end
    endtask

    initial begin
        for(i=0;i<4096;i=i+1) memory[i]={4{32'hdecafbad ^ i}};
        expected_base = CAPTURE_MODE ? 7000000 : 0;
        repeat(8) @(posedge ddr_clk); rst_n=1'b1;
        repeat(40) @(posedge ddr_clk);
        pulse_camera_frame_start();
        send_frame_words();
        service_enable=1'b1;
        begin : wait_for_first_burst
            integer timeout;
            timeout=0;
            while(writes < 32 && timeout < 3000) begin
                @(posedge ddr_clk); timeout=timeout+1;
            end
            if(writes < 32) $fatal(1,"camera burst did not start");
        end
        @(negedge dsi_clk); video_vsync=1'b1;
        repeat (12) @(negedge dsi_clk);
        video_vsync=1'b0;

        begin : wait_for_writes
            integer timeout;
            timeout=0;
            while(writes < FRAME_WORDS && timeout < 30000) begin
                @(posedge ddr_clk); timeout=timeout+1;
            end
            if(writes != FRAME_WORDS)
                $fatal(1,"write timeout: got %0d of %0d",writes,FRAME_WORDS);
        end
        $display("diag writes=%0d reads=%0d between=%0d vi_busy=%b vo_busy=%b vo_trig=%b vo_valid=%b ready=%b frame_pending=%b fifo_ready=%b fill=%0d credit=%0d frame_count=%0d",writes,reads,reads_between_bursts,vi_busy,vo_busy,u_vo.S_ddr_rd_trig,u_vo.S_ddr_rd_valid,u_vo.S_fifo_ready,frame_pending,u_vo.S_fifo_ready,vo_fill,vo_credit,u_vo.S_frame_read_count);
        if(reads_between_bursts == 0)
            $fatal(1,"display received no DDR service between camera bursts (starvation)");

        if(CAPTURE_MODE) begin
            pulse_camera_frame_start();
            if(!page_valid[1] || published_frames == 0)
                $fatal(1,"complete frame was not published on guarded page 1 page_valid=%b good=%b",page_valid,good_frame);
        end
        begin : wait_for_read_returns
            integer timeout;
            timeout=0;
            while(returned_reads < reads && timeout < 1000) begin
                @(posedge ddr_clk); timeout=timeout+1;
            end
            if(returned_reads != reads)
                $fatal(1,"display return count mismatch requested=%0d returned=%0d",reads,returned_reads);
        end
        if(reads == 0) $fatal(1,"display read path received no service");
        rst_n=1'b0;
        #1;
        if(vi_busy || vo_busy || page_valid != 0) $fatal(1,"reset did not clear DDR ownership/page state");
        $display("PASS mode=%0d writes=%0d display_reads=%0d between_bursts=%0d page_valid=%b",CAPTURE_MODE,writes,reads,reads_between_bursts,page_valid);
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1,"testbench timeout");
    end
endmodule

// 正式回归分别验证完整帧保护分支和兼容例程分支。
module tb_shared_ddr_complete;
    tb_shared_ddr #(.CAPTURE_MODE(1)) test();
endmodule
module tb_shared_ddr_legacy;
    tb_shared_ddr #(.CAPTURE_MODE(0)) test();
endmodule
