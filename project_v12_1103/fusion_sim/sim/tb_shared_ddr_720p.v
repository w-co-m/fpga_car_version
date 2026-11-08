`timescale 1ns/1ps
`include "ddr_page_map.vh"
module tb_shared_ddr_720p;
    localparam integer FRAME_WORDS = 172800;
    localparam integer FRAME_PIXELS = 1280 * 720;
    localparam integer BURST_WORDS = 240;
    localparam [24:0] PAGE0 = `DDR_MAP_LIVE0_BASE;
    localparam [24:0] PAGE1 = `DDR_MAP_LIVE1_BASE;

    reg rst_n = 1'b0;
    reg ddr_clk = 1'b0, camera_clk = 1'b0, pixel_clk = 1'b0;
    reg vtc_rst_n = 1'b0;
    reg manual_video_vsync = 1'b0, use_vtc_vsync = 1'b0;
    always #5 ddr_clk = ~ddr_clk;
    always #35.5 camera_clk = ~camera_clk;
    always #6.6665 pixel_clk = ~pixel_clk;

    reg camera_frame_start = 1'b0, camera_valid = 1'b0;
    reg [127:0] camera_data = 128'd0;
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
    wire [3:0] camera_guard_mask = vo_page_mask | 4'b0001;
    wire [23:0] pixel_data;
    wire [3:0] frame_mode;
    wire result_active, underflow;

    wire vtc_vs, vtc_hs, vtc_de, vtc_user, vtc_last;
    wire display_vsync = use_vtc_vsync ? ~vtc_vs : manual_video_vsync;
    wire video_rd_en, hdmi_de;
    wire [23:0] hdmi_data;
    uivtc #(.H_ActiveSize(1280), .H_FrameSize(1650), .H_SyncStart(1390),
        .H_SyncEnd(1430), .V_ActiveSize(720), .V_FrameSize(750),
        .V_SyncStart(725), .V_SyncEnd(730)) u_vtc(
        .I_vtc_rstn(vtc_rst_n), .I_vtc_clk(pixel_clk), .O_vtc_vs(vtc_vs),
        .O_vtc_hs(vtc_hs), .O_vtc_de_valid(vtc_de), .O_vtc_user(vtc_user),
        .O_vtc_last(vtc_last));

    wire live_ready;
    wire vo_return_valid, bg_return_valid;
    wire [127:0] return_data;
    wire shared_wr_en, shared_rd_en;
    wire [24:0] shared_addr;
    wire [127:0] shared_wr_data;
    reg [127:0] read_data = 128'd0;
    reg read_valid = 1'b0;

    reg mc_ready = 1'b0;
    reg service_enable = 1'b0;
    reg [15:0] lfsr = 16'h4d3b;
    always @(posedge ddr_clk) begin
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        mc_ready <= service_enable && (lfsr[2:0] != 3'b000);
    end

    function [23:0] pixel_value;
        input integer pixel_index;
        begin pixel_value = pixel_index + 1; end
    endfunction

    function [127:0] frame_word;
        input integer word_index;
        integer b, byte_index, pixel_index, component;
        reg [23:0] color;
        begin
            frame_word = 128'd0;
            for (b = 0; b < 16; b = b + 1) begin
                byte_index = word_index * 16 + b;
                pixel_index = byte_index / 3;
                component = byte_index % 3;
                color = pixel_value(pixel_index);
                frame_word[127 - b*8 -: 8] = color[23 - component*8 -: 8];
            end
        end
    endfunction

    video_in #(.FRAME_WORDS(FRAME_WORDS), .BURST_WORDS(BURST_WORDS),
        .REQUIRE_COMPLETE_FRAME(1), .ENABLE_DISPLAY_PAGE_GUARD(1)) u_vi(
        .I_rst_n(rst_n), .I_camera_clk(camera_clk),
        .I_camera_frame_start(camera_frame_start), .I_camera_valid(camera_valid),
        .I_camera_data(camera_data), .I_mipi_rx_error(1'b0), .I_ddr_clk(ddr_clk),
        .I_display_pause(1'b0), .I_video_out_rd_busy(vo_busy),
        .O_video_in_wr_busy(vi_busy), .O_video_out_rp(video_out_rp),
        .O_ddr_user_wr_en(vi_wr_en), .O_ddr_user_addr(vi_addr),
        .O_ddr_user_wr_data(vi_data), .I_ddr_user_ready(live_ready),
        .O_frame_start_ddr(), .O_page_valid(page_valid),
        .I_display_page_mask(camera_guard_mask), .O_good_frame_ddr(good_frame));

    video_out #(.USE_EXTERNAL_SOURCE(1), .FRAME_WORDS(FRAME_WORDS),
        .BURST_WORDS(BURST_WORDS), .ENABLE_UNDERFLOW_GUARD(1),
        .ENABLE_DISPLAY_PAGE_GUARD(1)) u_vo(
        .I_rst_n(rst_n), .I_ddr_clk(ddr_clk), .O_video_out_rd_busy(vo_busy),
        .I_video_in_wr_busy(vi_busy), .I_video_out_rp(video_out_rp),
        .O_ddr_user_rd_en(vo_rd_en), .O_ddr_user_addr(vo_addr),
        .I_ddr_user_ready(live_ready), .I_ddr_user_rd_valid(vo_return_valid),
        .I_ddr_user_rd_data(return_data), .I_dsi_clk(pixel_clk),
        .I_video_vsync(display_vsync), .I_video_rd_en(video_rd_en && vtc_rst_n),
        .O_vdieo_data(pixel_data), .I_source_base(PAGE0), .I_source_mode(4'd0),
        .I_source_is_result(1'b0), .I_source_valid(1'b1),
        .O_frame_mode(frame_mode), .O_result_source_active(result_active),
        .O_fifo_fill(vo_fill), .O_read_credit(vo_credit),
        .O_frame_pending(frame_pending), .O_underflow(underflow),
        .O_display_page_mask(vo_page_mask));

    hdmi_mixer #(.IMG_WIDTH(1280), .IMG_HEIGHT(720)) u_mixer(
        .I_clk(pixel_clk), .I_rst_n(rst_n), .I_video_vsync(vtc_vs),
        .I_video_hsync(vtc_hs), .I_video_de(vtc_de), .I_video_user(vtc_user),
        .I_video_last(vtc_last), .I_debug_status(4'd0),
        .I_video_rd_data(pixel_data), .O_video_rd_en(video_rd_en),
        .O_hdmi_de(hdmi_de), .O_hdmi_hsync(), .O_hdmi_vsync(), .O_hdmi_data(hdmi_data));

    polar_ddr_arbiter #(.MIN_DISPLAY_FILL(320)) u_arbiter(
        .clk(ddr_clk), .rst_n(rst_n), .calibrated(1'b1), .queue_idle(1'b1),
        .user_ready(mc_ready), .rd_valid(read_valid), .rd_data(read_data),
        .vi_busy(vi_busy), .vi_wr_en(vi_wr_en), .vi_addr(vi_addr), .vi_data(vi_data),
        .vo_busy(vo_busy), .vo_rd_en(vo_rd_en), .vo_frame_pending(frame_pending),
        .vo_fill(vo_fill), .vo_credit(vo_credit), .vo_addr(vo_addr),
        .bg_request(1'b0), .bg_release(1'b0), .bg_rd_en(1'b0), .bg_wr_en(1'b0),
        .bg_addr(25'd0), .bg_data(128'd0), .bg_grant(), .live_ready(live_ready),
        .bg_ready(), .vo_return_valid(vo_return_valid), .bg_return_valid(bg_return_valid),
        .return_data(return_data), .wr_en(shared_wr_en), .rd_en(shared_rd_en),
        .addr(shared_addr), .wr_data(shared_wr_data));

    // Model only the two live pages. Indexing uses full 25-bit addresses in 16-bit units.
    reg [127:0] memory [0:2*FRAME_WORDS-1];
    localparam integer MAX_DISPLAY_READS = 3 * FRAME_WORDS;
    reg [127:0] expected_reads [0:MAX_DISPLAY_READS-1];
    integer response_due [0:MAX_DISPLAY_READS-1];
    reg [127:0] response_data [0:MAX_DISPLAY_READS-1];
    integer response_write = 0, response_read = 0;
    integer cycle = 0, writes = 0, reads = 0, returned_reads = 0;
    integer reads_during_capture = 0, published_frames = 0;
    integer pixels = 0, frame_started = 0, active_frames = 0;
    integer scored_frame_active = 0, reads_during_scored_overlap = 0;
    reg camera_active = 1'b0;
    integer display_frame_count = 0, last_display_frame_count = 0;
    integer frame_read_word = 0;
    integer i, slot, word_offset, next_due, latency;
    integer prev_vs = 0;

    always @(posedge display_vsync) display_frame_count = display_frame_count + 1;

    always @(posedge ddr_clk) begin
        cycle = cycle + 1;
        read_valid <= 1'b0;
        if (display_frame_count != last_display_frame_count) begin
            last_display_frame_count = display_frame_count;
            frame_read_word = 0;
        end
        if (good_frame) begin
            published_frames = published_frames + 1;
            if (writes != FRAME_WORDS)
                $fatal(1, "published before full frame completed writes=%0d", writes);
        end

        if (shared_wr_en && shared_rd_en)
            $fatal(1, "DDR accepted read and write together");
        if (rst_n && !camera_guard_mask[0])
            $fatal(1, "display source page 0 lost its camera write guard mask=%b", camera_guard_mask);

        if (shared_wr_en) begin
            if (shared_addr >= PAGE1 && shared_addr < PAGE1 + `DDR_MAP_FRAME_SPAN) begin
                slot = 1;
                word_offset = (shared_addr - PAGE1) >> 3;
            end else if (shared_addr >= PAGE0 && shared_addr < PAGE0 + `DDR_MAP_FRAME_SPAN) begin
                slot = 0;
                word_offset = (shared_addr - PAGE0) >> 3;
            end else $fatal(1, "write outside live pages addr=%0d", shared_addr);
            if (shared_addr[2:0] != 0 || word_offset >= FRAME_WORDS)
                $fatal(1, "misaligned/out-of-range write addr=%0d offset=%0d", shared_addr, word_offset);
            if (slot != 1)
                $fatal(1, "camera write touched active display page addr=%0d", shared_addr);
            if (writes >= FRAME_WORDS)
                $fatal(1, "camera wrote beyond complete frame");
            if (shared_addr != PAGE1 + writes*8)
                $fatal(1, "camera address/order mismatch index=%0d addr=%0d", writes, shared_addr);
            if (shared_wr_data !== frame_word(writes))
                $fatal(1, "camera payload mismatch index=%0d got=%h expected=%h", writes, shared_wr_data, frame_word(writes));
            memory[FRAME_WORDS + word_offset] <= shared_wr_data;
            writes = writes + 1;
        end

        if (shared_rd_en) begin
            if (!vo_page_mask[0])
                $fatal(1, "display issued a read before page 0 became write guarded");
            if (writes > 0 && writes < FRAME_WORDS && vi_busy)
                $fatal(1, "display DDR service overlapped an active camera burst");
            if (reads >= MAX_DISPLAY_READS || response_write >= MAX_DISPLAY_READS)
                $fatal(1, "full-frame expected-read queue capacity exceeded reads=%0d", reads);
            if (shared_addr >= PAGE0 && shared_addr < PAGE0 + `DDR_MAP_FRAME_SPAN) begin
                slot = 0;
                word_offset = (shared_addr - PAGE0) >> 3;
            end else if (shared_addr >= PAGE1 && shared_addr < PAGE1 + `DDR_MAP_FRAME_SPAN) begin
                slot = 1;
                word_offset = (shared_addr - PAGE1) >> 3;
            end else $fatal(1, "read outside live pages addr=%0d", shared_addr);
            if (shared_addr[2:0] != 0 || word_offset >= FRAME_WORDS)
                $fatal(1, "misaligned/out-of-range read addr=%0d offset=%0d", shared_addr, word_offset);
            if (slot != 0)
                $fatal(1, "display read left active page 0 addr=%0d", shared_addr);
            if (frame_read_word >= FRAME_WORDS || shared_addr != PAGE0 + frame_read_word*8)
                $fatal(1, "display address/order mismatch frame=%0d word=%0d addr=%0d", display_frame_count, frame_read_word, shared_addr);
            expected_reads[reads] = memory[word_offset];
            latency = 3 + ((lfsr[7:3] ^ lfsr[12:8]) % 13);
            next_due = cycle + latency;
            if (response_write != 0 && next_due < response_due[response_write-1])
                next_due = response_due[response_write-1];
            response_due[response_write] = next_due;
            response_data[response_write] = memory[word_offset];
            response_write = response_write + 1;
            reads = reads + 1;
            frame_read_word = frame_read_word + 1;
            if (writes > 0 && writes < FRAME_WORDS)
                reads_during_capture = reads_during_capture + 1;
            if (camera_active && scored_frame_active)
                reads_during_scored_overlap = reads_during_scored_overlap + 1;
        end

        if (response_read < response_write && response_due[response_read] <= cycle &&
            (lfsr[1:0] != 2'b00)) begin
            read_data <= response_data[response_read];
            read_valid <= 1'b1;
            response_read = response_read + 1;
        end

        if (vo_return_valid) begin
            if (returned_reads >= reads)
                $fatal(1, "DDR returned an unrequested display word");
            if (return_data !== expected_reads[returned_reads])
                $fatal(1, "display response order/data mismatch index=%0d", returned_reads);
            returned_reads = returned_reads + 1;
        end
    end

    always @(posedge pixel_clk) begin
        #1;
        if (vtc_rst_n) begin
            if (vtc_vs && !prev_vs) begin
                active_frames = active_frames + 1;
            end
            if (vtc_user) begin
                frame_started = 1;
                scored_frame_active = 1;
            end
            if (hdmi_de && frame_started && active_frames == 1) begin
                if (pixels >= FRAME_PIXELS)
                    $fatal(1, "more than one active frame counted");
                if (hdmi_data !== pixel_value(pixels))
                    $fatal(1, "720p pixel mismatch index=%0d got=%h raw=%h expected=%h fifo=%h cnt=%0d empty=%b reads=%0d returns=%0d", pixels, hdmi_data, pixel_data, pixel_value(pixels), u_vo.S_fifo_rd_data, u_vo.S_fifo_rd_cnt, u_vo.S_fifo_empty, reads, returned_reads);
                pixels = pixels + 1;
                if (pixels == FRAME_PIXELS) scored_frame_active = 0;
            end
            if (frame_started && active_frames == 1 && u_vo.O_underflow)
                $fatal(1, "video_out underflow active_frame=%0d pixels=%0d requested=%0d returned=%0d fill=%0d credit=%0d pending=%b", active_frames, pixels, reads, returned_reads, vo_fill, vo_credit, frame_pending);
            prev_vs = vtc_vs;
        end
    end

    task start_camera_frame;
        begin
            @(negedge camera_clk); camera_frame_start = 1'b1;
            @(negedge camera_clk); camera_frame_start = 1'b0;
            repeat (24) @(posedge camera_clk);
        end
    endtask

    task send_camera_frame;
        integer n;
        begin
            for (n = 0; n < FRAME_WORDS; n = n + 1) begin
                @(negedge camera_clk);
                camera_valid = 1'b1;
                camera_data = frame_word(n);
            end
            @(negedge camera_clk); camera_valid = 1'b0; camera_data = 128'd0;
        end
    endtask

    task capture_camera_frame_during_blank;
        begin
            wait (vtc_vs === 1'b1);
            start_camera_frame();
            camera_active = 1'b1;
            send_camera_frame();
            camera_active = 1'b0;
        end
    endtask

    initial begin
        if (FRAME_PIXELS * 3 != FRAME_WORDS * 16)
            $fatal(1, "FRAME_WORDS does not encode 16 RGB888 pixels per three DDR words");
        for (i = 0; i < FRAME_WORDS; i = i + 1) begin
            memory[i] = frame_word(i);
            memory[FRAME_WORDS+i] = 128'd0;
        end
        repeat (8) @(posedge ddr_clk);
        rst_n = 1'b1;
        repeat (30) @(posedge ddr_clk);
        service_enable = 1'b1;
        @(negedge pixel_clk); manual_video_vsync = 1'b1;
        repeat (2) @(negedge pixel_clk); manual_video_vsync = 1'b0;
        begin : wait_for_display_selection
            integer timeout;
            timeout = 0;
            while ((frame_pending || !vo_page_mask[0]) && timeout < 2000) begin
                @(posedge ddr_clk); timeout = timeout + 1;
            end
            if (frame_pending || !vo_page_mask[0]) $fatal(1, "display source page 0 was not selected");
            while (vo_fill < 320 && timeout < 12000) begin
                @(posedge ddr_clk); timeout = timeout + 1;
            end
            if (vo_fill < 320) $fatal(1, "display prefill did not reach 320 words");
        end
        vtc_rst_n = 1'b1;
        fork
            capture_camera_frame_during_blank();
            begin : align_real_vtc_sync
                wait (vtc_vs === 1'b1);
                @(negedge pixel_clk); use_vtc_vsync = 1'b1;
            end
        join

        begin : wait_for_camera_complete
            integer timeout;
            timeout = 0;
            while (writes < FRAME_WORDS && timeout < 300000) begin
                @(posedge ddr_clk); timeout = timeout + 1;
            end
            if (writes != FRAME_WORDS) $fatal(1, "camera write timeout %0d/%0d", writes, FRAME_WORDS);
        end
        if (page_valid[1] || published_frames != 0)
            $fatal(1, "page published before next frame boundary page_valid=%b published=%0d", page_valid, published_frames);

        start_camera_frame();
        if (!page_valid[1] || published_frames != 1)
            $fatal(1, "complete page was not published at frame boundary page_valid=%b published=%0d", page_valid, published_frames);

        begin : wait_for_display_frame
            integer timeout;
            timeout = 0;
            while (pixels < FRAME_PIXELS && timeout < 4000000) begin
                @(posedge pixel_clk); timeout = timeout + 1;
            end
            if (pixels != FRAME_PIXELS) $fatal(1, "active display pixel timeout %0d/%0d", pixels, FRAME_PIXELS);
        end
        repeat (40) @(posedge ddr_clk);
        if (reads < FRAME_WORDS || reads > MAX_DISPLAY_READS || returned_reads != reads)
            $fatal(1, "full display read count mismatch requested=%0d returned=%0d", reads, returned_reads);
        if (reads_during_capture < BURST_WORDS)
            $fatal(1, "insufficient display service during camera frame reads=%0d", reads_during_capture);
        if (reads_during_scored_overlap < BURST_WORDS)
            $fatal(1, "insufficient display service during scored-frame/camera overlap reads=%0d", reads_during_scored_overlap);
        if (response_read != response_write)
            $fatal(1, "read response queue not drained requested=%0d returned=%0d", response_write, response_read);
        $display("PASS tb_shared_ddr_720p words=%0d pixels=%0d writes=%0d reads=%0d returned=%0d reads_during_camera=%0d reads_during_scored_overlap=%0d published=%0d page_valid=%b", FRAME_WORDS, pixels, writes, reads, returned_reads, reads_during_capture, reads_during_scored_overlap, published_frames, page_valid);
        $display("MODEL behavioral DDR: ready gate 7/8 ordered_latency=3..15 cycles active_timing=1280x720@1650x750 camera_period=71ns (14.08M words/s, 75.1MPix/s) ddr_period=10ns pixel_period=13.333ns");
        $finish;
    end

    initial begin
        #100000000;
        $fatal(1, "tb_shared_ddr_720p global timeout");
    end
endmodule
