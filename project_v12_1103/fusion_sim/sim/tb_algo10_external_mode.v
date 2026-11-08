`timescale 1ns/1ps
// 验证实际backend状态CDC和外部渲染选择；video_out帧确认由ack_mode建模。
module tb_algo10_external_mode;
    // Frozen legacy rule-5 single-frame contract; production rule-6 has its own regressions.
    defparam display.u_bank.COLOR_DET_RULE=5;

    reg pixel=0,ddr=0,camera=0;
    always #5 pixel=~pixel;
    always #7 ddr=~ddr;
    always #11 camera=~camera;
    reg rst_n=0,k0=1,k1=1;
    reg [23:0] rgb=0;
    reg de=0,hs=0,vs=0;
    reg [3:0] ack_mode=0;
    wire [3:0] pending,active,render,source_mode;
    wire capture,restart,edit_active;
    wire [7:0] bin_thr,edge_thr;
    wire [23:0] out;
    wire od,oh,ov;
    wire [24:0] base;
    wire result_source,source_valid;
    integer samples=0,checks=0,captures=0,restarts=0,x,y,i;
    reg [23:0] expected[0:4095];
    reg ed[0:4095],eh[0:4095],ev[0:4095];
    reg [23:0] p;

    video_algorithm_display #(.ALGO_COUNT(14),.IMG_WIDTH(8),.DEBOUNCE_CYCLES(3),
        .ENABLE_POLAR_CONTROL(1),.EXTERNAL_RENDER_MODE(1)) display(
        .clk(pixel),.rst_n(rst_n),.key0_n(k0),.key1_n(k1),.threshold_edit(1'b0),
        .rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),.rgb_out(out),
        .de_out(od),.hs_out(oh),.vs_out(ov),.mode_active(active),.mode_pending_out(pending),
        .render_mode_in(render),.polar_capture_pulse(capture),.polar_restart_pulse(restart),
        .bin_threshold_active(bin_thr),.edge_threshold_active(edge_thr),.threshold_edit_active(edit_active));
    polar_video_backend #(.FRAME_BLOCKS(3),.IMG_WIDTH(16),.ENABLE_POLAR_EDGE(1),.REQUIRE_GOOD_SETTLE(1)) backend(
        .pixel_clk(pixel),.ddr_clk(ddr),.camera_clk(camera),.rst_n(rst_n),
        .requested_mode(pending),.capture_pulse(capture),.restart_pulse(restart),
        .camera_frame_start(1'b0),.camera_good_frame(1'b0),.live_page(2'd1),.page_valid(4'b0010),
        .displayed_mode(ack_mode),.displayed_result(1'b0),
        .vo_busy(1'b0),.vo_frame_pending(1'b0),.vo_fill(9'd400),.vo_credit(10'd0),
        .vo_rd_en(1'b0),.vo_addr(25'd0),.vi_busy(1'b0),.vi_wr_en(1'b0),.vi_addr(25'd0),.vi_data(128'd0),
        .calibrated(1'b1),.queue_idle(1'b1),.user_ready(1'b1),.user_rd_valid(1'b0),.user_rd_data(128'd0),
        .display_pause(),.background_owner(),.live_ready(),.vo_return_valid(),.user_wr_en(),.user_rd_en(),
        .user_addr(),.user_wr_data(),.source_base(base),.source_mode(source_mode),
        .source_is_result(result_source),.source_valid(source_valid),.render_mode(render),
        .polar_angle(),.polar_capture_busy(),.polar_compute_busy(),.polar_ready(),.polar_error(),.fixed_white_balance());
    always @(posedge pixel)begin
        if(capture)captures=captures+1;
        if(restart)restarts=restarts+1;
    end
    task tick;
        input [23:0] data;
        input d,h,v;
        input [23:0] want;
        begin
            @(negedge pixel);rgb=data;de=d;hs=h;vs=v;
            expected[samples]=want;ed[samples]=d;eh[samples]=h;ev[samples]=v;
            @(posedge pixel);#1;
            if(samples>=10)begin
                if(out!==expected[samples-4] || od!==ed[samples-4] || oh!==eh[samples-4] || ov!==ev[samples-4])
                    $fatal(1,"external render mismatch sample=%0d active=%0d render=%0d got=%h want=%h",samples,active,render,out,expected[samples-4]);
                checks=checks+1;
            end
            samples=samples+1;
        end
    endtask
    task blanks;
        input integer n;
        input v;
        integer j;
        begin for(j=0;j<n;j=j+1)tick(24'h123456,0,0,v,24'h123456);end
    endtask
    task press;
        input previous;
        begin
            @(negedge pixel);if(previous)k0=0;else k1=0;
            blanks(18,0);
            @(negedge pixel);k0=1;k1=1;
            blanks(15,0);
        end
    endtask
    task frame;
        input integer scene;
        input draw_box;
        reg [23:0] want;
        begin
            blanks(25,1);blanks(3,0);
            for(y=0;y<6;y=y+1)begin
                for(x=0;x<8;x=x+1)begin
                    if(scene==2)p=24'hC82028;
                    else if(scene==1 && x>=2 && x<=5 && y>=1 && y<=4)p=24'hC82028;
                    else p=24'h123456;
                    want=(draw_box && x>=2 && x<=5 && y>=1 && y<=4)?24'h00ff00:p;
                    tick(p,1,0,0,want);
                end
                tick(24'h123456,0,1,0,24'h123456);
                tick(24'h123456,0,1,0,24'h123456);
                tick(24'h123456,0,0,0,24'h123456);
            end
            blanks(8,0);
        end
    endtask
    initial begin
        repeat(4)@(negedge pixel);rst_n=1;blanks(20,0);
        frame(1,0);
        press(1); // 0 -> 13，尚未到VS提交。
        if(pending!=13 || active!=0)$fatal(1,"pending selection/commit");
        frame(1,0); // active=13，实际DDR帧确认仍0，必须继续原图。
        if(active!=13 || render!=0 || source_mode!=13 || result_source || !source_valid || base!=7000000)
            $fatal(1,"external frame authority or live source incorrect");
        @(negedge ddr);ack_mode=13;
        blanks(30,0);frame(1,1);
        if(render!=13)$fatal(1,"source acknowledgment did not reach renderer");
        for(i=0;i<4;i=i+1)press(1); // 13 -> 9
        @(negedge ddr);ack_mode=9;
        blanks(30,0);frame(2,0); // 偏振预览含红图，不能污染检测框。
        if(render!=9 || result_source)$fatal(1,"polar preview source");
        for(i=0;i<4;i=i+1)press(0); // 9 -> 13
        @(negedge ddr);ack_mode=13;
        blanks(30,0);frame(0,0);
        if(render!=13 || active!=13 || captures || restarts || result_source || base!=7000000)
            $fatal(1,"return-to-COLORBOX state");
        $display("PASS tb_algo10_external_mode: backend CDC, delayed frame acknowledgment, live page, no polar stale box, %0d checks",checks);
        $finish;
    end
    initial begin #1000000;$fatal(1,"external mode timeout");end
endmodule
