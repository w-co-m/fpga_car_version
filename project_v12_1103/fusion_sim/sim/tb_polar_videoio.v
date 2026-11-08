`timescale 1ns/1ps
module tb_polar_videoio #(parameter ASYNC_CLOCKS = 0);
    reg clk=0; always #5 clk=~clk;
    reg cam_clk_async=0; always #7 cam_clk_async=~cam_clk_async;
    reg pixel_clk_async=0; always #11 pixel_clk_async=~pixel_clk_async;
    wire cam_clk=ASYNC_CLOCKS ? cam_clk_async : clk;
    wire pixel_clk=ASYNC_CLOCKS ? pixel_clk_async : clk;
    reg rst=0, cam_fs=0, cam_valid=0, pause_capture=0;
    reg mipi_error=0;
    reg [127:0] cam_data=0;
    wire vin_busy, vin_we, frame_start_ddr;
    wire [1:0] rp;
    wire [24:0] vin_addr;
    wire [127:0] vin_data;
    wire [3:0] page_valid;
    integer writes_by_page[0:3];
    integer total_writes=0, i;

    video_in #(.FRAME_WORDS(6),.BURST_WORDS(2),.REQUIRE_COMPLETE_FRAME(1)) vin(
        .I_rst_n(rst),.I_camera_clk(cam_clk),.I_camera_frame_start(cam_fs),
        .I_camera_valid(cam_valid),.I_camera_data(cam_data),.I_mipi_rx_error(mipi_error),
        .I_ddr_clk(clk),.I_display_pause(pause_capture),.I_video_out_rd_busy(1'b0),
        .O_video_in_wr_busy(vin_busy),.O_video_out_rp(rp),.O_ddr_user_wr_en(vin_we),
        .O_ddr_user_addr(vin_addr),.O_ddr_user_wr_data(vin_data),.I_ddr_user_ready(1'b1),
        .O_frame_start_ddr(frame_start_ddr),.O_page_valid(page_valid));

    always @(posedge clk) if (rst && vin_we) begin
        total_writes = total_writes + 1;
        if (vin_addr < 7000000) begin
            writes_by_page[0] = writes_by_page[0] + 1;
        end else if (vin_addr < 14000000) begin
            writes_by_page[1] = writes_by_page[1] + 1;
        end else if (vin_addr < 21000000) begin
            writes_by_page[2] = writes_by_page[2] + 1;
        end else begin
            writes_by_page[3] = writes_by_page[3] + 1;
            if (vin_addr >= 21000000+6*8)
                $fatal(1,"page3 write outside bounded frame address: %0d",vin_addr);
        end
        if (vin.S_frame_words_written > 6)
            $fatal(1,"actual frame write counter exceeded FRAME_WORDS");
    end

    task camera_boundary;
        begin
            @(negedge cam_clk); cam_fs=1;
            @(negedge cam_clk); cam_fs=0;
            wait(frame_start_ddr===1'b1);
            wait(vin.S_fifo_rst===1'b0);
            // This stimulus represents a legal complete frame, after the new
            // write-domain reset-release guard. Early data has separate tests.
            wait(vin.S_camera_capture_open===1'b1);
            @(negedge cam_clk);
            repeat(6) @(negedge clk);
        end
    endtask
    task camera_words;
        input integer n;
        integer j;
        begin
            cam_valid=1;
            for(j=0;j<n;j=j+1) begin cam_data=j; @(negedge cam_clk); end
            cam_valid=0;
            repeat(30) @(negedge clk);
        end
    endtask

    reg vs=0, user_ready=0, rd_valid=0, pix_en=0;
    reg [24:0] source_base=23000000;
    reg [3:0] source_mode=0;
    reg source_result=0;
    reg [127:0] rd_data=0;
    wire out_busy, rd_en, result_active, frame_pending, underflow;
    wire [24:0] rd_addr;
    wire [3:0] frame_mode;
    wire [8:0] fifo_fill;
    wire [9:0] read_credit;
    wire [23:0] pixel;
    video_out #(.USE_EXTERNAL_SOURCE(1),.FRAME_WORDS(6),.BURST_WORDS(2),
                .ENABLE_UNDERFLOW_GUARD(1)) vout(
        .I_rst_n(rst),.I_ddr_clk(clk),.O_video_out_rd_busy(out_busy),.I_video_in_wr_busy(1'b0),
        .I_video_out_rp(2'd0),.O_ddr_user_rd_en(rd_en),.O_ddr_user_addr(rd_addr),
        .I_ddr_user_ready(user_ready),.I_ddr_user_rd_valid(rd_valid),.I_ddr_user_rd_data(rd_data),
        .I_dsi_clk(pixel_clk),.I_video_vsync(vs),.I_video_rd_en(pix_en),.O_vdieo_data(pixel),
        .I_source_base(source_base),.I_source_mode(source_mode),.I_source_is_result(source_result),
        .O_frame_mode(frame_mode),.O_result_source_active(result_active),.O_fifo_fill(fifo_fill),
        .O_read_credit(read_credit),.O_frame_pending(frame_pending),.O_underflow(underflow));

    integer requests_base1=0, requests_base2=0;
    always @(posedge clk) if(rst && rd_en) begin
        if(rd_addr >= 23000000 && rd_addr < 24400000) begin
            requests_base1=requests_base1+1;
            if(rd_addr >= 23000000+6*8) $fatal(1,"read crossed FRAME_WORDS boundary");
        end
        if(rd_addr >= 24400000 && rd_addr < 25800000) begin
            requests_base2=requests_base2+1;
            if(rd_addr >= 24400000+6*8) $fatal(1,"second base read crossed frame boundary");
        end
    end

    task display_boundary;
        begin
            @(negedge pixel_clk); vs=1;
            repeat(5) @(negedge pixel_clk);
            vs=0;
            repeat(14) @(negedge pixel_clk);
        end
    endtask
    task return_one;
        begin
            @(negedge clk); rd_valid=1; rd_data=128'h123456789abcdef;
            @(negedge clk); rd_valid=0;
        end
    endtask

    initial begin
        for(i=0;i<4;i=i+1) writes_by_page[i]=0;
        repeat(6) @(negedge clk); rst=1;
        // Input SOF is sent after both domains have completed reset release.
        repeat(4) @(negedge cam_clk);
        repeat(4) @(negedge pixel_clk);

        camera_boundary(); camera_words(6);
        camera_boundary();
        if(page_valid[0]!==1'b1 || rp!==2'd0 || writes_by_page[0]!=6)
            $fatal(1,"full frame wasn't validated page_valid=%b rp=%0d writes=%0d ddr=%0d camera=%0d fifo=%0d empty=%b burst=%b",page_valid,rp,writes_by_page[0],vin.S_frame_words_written,vin.S_camera_words_seen,vin.S_fifo_rd_num,vin.S_fifo_empty,vin.S_ddr_wr_valid);

        camera_words(4); camera_boundary();
        if(page_valid[1]!==1'b0 || writes_by_page[1]!=4)
            $fatal(1,"short frame was marked valid or has wrong write count valid=%b writes=%0d",page_valid,writes_by_page[1]);

        camera_words(7); camera_boundary();
        if(page_valid[2]!==1'b0 || writes_by_page[2]!=6)
            $fatal(1,"excess frame wasn't rejected/capped valid=%b writes=%0d",page_valid,writes_by_page[2]);

        pause_capture=1;
        camera_words(6); camera_boundary();
        camera_words(6); camera_boundary();
        if(writes_by_page[0]!=6 || rp!==2'd0)
            $fatal(1,"pause modified the frozen display page or rp page0writes=%0d rp=%0d",writes_by_page[0],rp);

        // A complete six-word frame with a camera error must stay invalid;
        // the following clean frame must recover validity while display is frozen.
        camera_words(6);
        mipi_error=1;
        camera_boundary();
        mipi_error=0;
        if(page_valid[2]!==1'b0)
            $fatal(1,"complete frame with MIPI error was marked valid mask=%b",page_valid);
        camera_words(6);
        camera_boundary();
        if(page_valid[3]!==1'b1)
            $fatal(1,"clean frame did not restore page validity mask=%b",page_valid);

        // 首个显示帧只读6拍，随后换到结果页时先排空旧credit。
        display_boundary();
        user_ready=1;
        wait(vout.S_frame_read_count==6);
        if(requests_base1!=6 || read_credit!=6)
            $fatal(1,"bounded first source requests=%0d credit=%0d address=%0d pending=%0d",requests_base1,read_credit,rd_addr,vout.S_pending_base_addr);
        user_ready=0; source_base=24400000; source_mode=4'd10; source_result=1;
        display_boundary();
        if(!frame_pending || result_active || rd_addr < 23000000)
            $fatal(1,"source changed before prior read credit drained");
        repeat(5) @(negedge clk);
        if(!frame_pending || result_active)
            $fatal(1,"result source activated before old credit returned");
        repeat(6) return_one();
        wait(!frame_pending);
        if(!result_active || rd_addr!=24400000 || requests_base2!=0)
            $fatal(1,"new result base/mode wasn't latched at drain boundary addr=%0d active=%b",rd_addr,result_active);
        if(frame_mode!=10) $fatal(1,"pixel mode not latched for whole frame mode=%0d",frame_mode);

        pix_en=1;
        repeat(12) @(negedge clk);
        if(!underflow || pixel!==24'd0)
            $fatal(1,"missing FIFO data did not black/flag the current frame underflow=%b pixel=%h empty=%b phase=%0d now=%b bad=%b en=%b",underflow,pixel,vout.S_fifo_empty,vout.S_fifo_rd_cnt,vout.S_pixel_underflow_now,vout.S_pixel_frame_bad,pix_en);
        repeat(8) @(negedge clk);
        if(pixel!==24'd0 || !underflow)
            $fatal(1,"underflow guard failed to keep the rest of the frame black");
        pix_en=0;
        display_boundary();
        if(underflow) $fatal(1,"underflow sticky flag did not clear at VS");

        $display("PASS tb_polar_videoio ASYNC_CLOCKS=%0d: strict frame validity/cap, MIPI recovery, frozen page, external source credit drain, mode, bounded reads and underflow recovery",ASYNC_CLOCKS);
        $finish;
    end
    initial begin #500000; $fatal(1,"tb_polar_videoio timeout"); end
endmodule

module tb_polar_videoio_async;
    tb_polar_videoio #(.ASYNC_CLOCKS(1)) test();
endmodule
