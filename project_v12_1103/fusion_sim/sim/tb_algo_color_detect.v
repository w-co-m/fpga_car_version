`timescale 1ns/1ps
module tb_algo_color_detect;
    localparam W=8, H=8;
    reg clk=0, rst_n=0, enable_in=1;
    reg [23:0] rgb_in=0;
    reg de_in=0, hs_in=0, vs_in=0;
    reg [7:0] thr_in=0;
    always #5 clk=~clk;

    wire [23:0] r_rgb,g_rgb,b_rgb,a_rgb;
    wire [7:0] r_y,g_y,b_y,a_y;
    wire r_bin,g_bin,b_bin,a_bin,r_de,r_hs,r_vs;
    wire [2:0] r_xmin,r_xmax,r_ymin,r_ymax;
    wire r_valid;
    wire [6:0] r_hits;
    algo_color_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_COLOR(0),.MIN_PIX(16)) red
        (.clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
         .rgb_out(r_rgb),.y_out(r_y),.bin_out(r_bin),.de_out(r_de),.hs_out(r_hs),.vs_out(r_vs),
         .bbox_x_min(r_xmin),.bbox_x_max(r_xmax),.bbox_y_min(r_ymin),.bbox_y_max(r_ymax),.bbox_valid(r_valid),.hit_cnt(r_hits));
    algo_color_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_COLOR(1),.MIN_PIX(16)) green
        (.clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
         .rgb_out(g_rgb),.y_out(g_y),.bin_out(g_bin),.de_out(),.hs_out(),.vs_out(),.bbox_x_min(),.bbox_x_max(),.bbox_y_min(),.bbox_y_max(),.bbox_valid(),.hit_cnt());
    algo_color_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_COLOR(2),.MIN_PIX(16)) blue
        (.clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
         .rgb_out(b_rgb),.y_out(b_y),.bin_out(b_bin),.de_out(),.hs_out(),.vs_out(),.bbox_x_min(),.bbox_x_max(),.bbox_y_min(),.bbox_y_max(),.bbox_valid(),.hit_cnt());
    algo_color_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.DET_RULE(1),.MIN_PIX(16)) absolute
        (.clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
         .rgb_out(a_rgb),.y_out(a_y),.bin_out(a_bin),.de_out(),.hs_out(),.vs_out(),.bbox_x_min(),.bbox_x_max(),.bbox_y_min(),.bbox_y_max(),.bbox_valid(),.hit_cnt());

    reg [23:0] qrgb[0:4095];
    reg [7:0] qyr[0:4095];
    reg [7:0] qyg[0:4095];
    reg [7:0] qyb[0:4095];
    reg [7:0] qya[0:4095];
    reg qde[0:4095], qhs[0:4095], qvs[0:4095];
    integer n=0, errors=0, k;
    task tick;
        input [23:0] pix;
        input d,h,v,en;
        input [7:0] threshold;
        input [7:0] er,eg,eb,ea;
        reg [23:0] expected_rgb;
        begin
            @(negedge clk);
            rgb_in=pix; de_in=d; hs_in=h; vs_in=v; enable_in=en; thr_in=threshold;
            qrgb[n]=pix; qyr[n]=er; qyg[n]=eg; qyb[n]=eb; qya[n]=ea;
            qde[n]=d; qhs[n]=h; qvs[n]=v;
            @(posedge clk); #1;
            if (rst_n && n>=2) begin
                k=n-2;
                expected_rgb=qrgb[k];
                if (r_y !== qyr[k] || g_y !== qyg[k] || b_y !== qyb[k] || a_y !== qya[k]) begin
                    $display("mask mismatch sample %0d red=%h/%h green=%h/%h blue=%h/%h abs=%h/%h",k,r_y,qyr[k],g_y,qyg[k],b_y,qyb[k],a_y,qya[k]);
                    errors=errors+1;
                end
                if (r_rgb !== expected_rgb) begin
                    $display("RGB/latency mismatch sample %0d expected=%06h got=%06h",k,expected_rgb,r_rgb);
                    errors=errors+1;
                end
                if (r_de !== qde[k] || r_hs !== qhs[k] || r_vs !== qvs[k]) begin
                    $display("sync mismatch sample %0d",k); errors=errors+1;
                end
            end
            n=n+1;
        end
    endtask

    task check_box;
        input valid;
        input [2:0] xmin,xmax,ymin,ymax;
        input [5:0] hits;
        begin
            if (r_valid !== valid || r_xmin !== xmin || r_xmax !== xmax ||
                r_ymin !== ymin || r_ymax !== ymax || r_hits !== hits) begin
                $display("bbox expected v=%b (%0d,%0d)-(%0d,%0d) hits=%0d got v=%b (%0d,%0d)-(%0d,%0d) hits=%0d",
                  valid,xmin,ymin,xmax,ymax,hits,r_valid,r_xmin,r_ymin,r_xmax,r_ymax,r_hits);
                errors=errors+1;
            end
        end
    endtask

    integer x,y;
    reg [23:0] p;
    reg [7:0] er,eg,eb,ea;
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        // 独立literal阈值边界：红色差31、差32、默认32；再测绿、蓝和绝对上下界。
        tick(24'hC8A964,0,0,0,1,31,8'hff,0,0,0);
        tick(24'hC8A964,0,0,0,1,32,0,0,0,0);
        tick(24'hC8A864,0,0,0,1,32,8'hff,0,0,0);
        tick(24'hC8A864,0,0,0,1,0,8'hff,0,0,0);
        tick(24'h14641E,0,0,0,1,32,0,8'hff,0,0);
        tick(24'h141E64,0,0,0,1,32,0,0,8'hff,0);
        tick(24'hC82080,0,0,0,1,32,8'hff,0,0,8'hff);
        tick(24'hC84080,0,0,0,1,32,8'hff,0,0,8'hff);
        tick(24'hC84180,0,0,0,1,32,8'hff,0,0,0);
        tick(24'h7F0000,0,0,0,1,32,8'hff,0,0,0);
        tick(24'h800000,0,0,0,1,32,8'hff,0,0,8'hff);
        tick(24'h123456,0,0,1,1,32,0,0,8'hff,0);
        tick(24'hFEDCBA,1,1,0,1,32,8'hff,0,0,0);

        // 帧1：15 个目标像素，紧跟 VS；MIN_PIX=16 时拒绝。
        tick(24'h000000,0,0,1,1,32,0,0,0,0);
        tick(24'h000000,0,0,0,1,32,0,0,0,0);
        tick(24'h000000,0,0,0,1,32,0,0,0,0);
        tick(24'hC80000,1,0,0,1,32,8'hff,0,0,8'hff);
        for (x=1;x<15;x=x+1) tick(24'hC80000,1,0,0,1,32,8'hff,0,0,8'hff);
        tick(24'h000000,0,0,1,1,32,0,0,0,0);
        tick(24'h000000,0,0,0,1,32,0,0,0,0);
        check_box(0,0,0,0,0,15);

        // 帧2：四行4像素，共16目标。最后一个DE像素后立即VS，必须包含末像素。
        tick(24'h000000,0,0,1,1,32,0,0,0,0);
        tick(24'h000000,0,0,0,1,32,0,0,0,0);
        for (y=0;y<4;y=y+1) begin
            for (x=0;x<4;x=x+1) tick(24'hC80000,1,0,0,1,32,8'hff,0,0,8'hff);
            if (y<3) begin
                tick(24'h000000,0,0,0,1,32,0,0,0,0);
            end
        end
        tick(24'h000000,0,0,1,1,32,0,0,0,0);
        tick(24'h000000,0,0,1,1,32,0,0,0,0);
        tick(24'h000000,0,0,1,1,32,0,0,0,0);
        tick(24'h000000,0,0,0,1,32,0,0,0,0);
        check_box(1,0,3,0,3,16);

        // 帧3显示上一帧框：边缘绿、中心逐位保留原RGB；HS多拍不应增加y。
        tick(24'h000000,0,1,0,1,32,0,0,0,0);
        tick(24'h000000,0,1,0,1,32,0,0,0,0);
        for (y=0;y<4;y=y+1) begin
            for (x=0;x<4;x=x+1) begin
                p=24'h123450;
                tick(p,1,0,0,1,32,0,0,0,0);
                // 覆盖流水队列中刚入队的期望RGB。四边均为bbox边缘，均着绿。
                qrgb[n-1]=24'h00ff00;
            end
            tick(24'h000000,0,1,0,1,32,0,0,0,0);
            tick(24'h000000,0,1,0,1,32,0,0,0,0);
        end

        // disable清统计/bbox，像素和同步仍走三拍流水；再启用后不能复用旧框。
        tick(24'h123450,1,0,0,0,32,0,0,0,0);
        tick(24'h000000,0,0,0,0,32,0,0,0,0);
        tick(24'h000000,0,0,0,1,32,0,0,0,0);
        tick(24'h000000,0,0,0,1,32,0,0,0,0);
        check_box(0,0,0,0,0,0);
        tick(24'h000000,0,0,1,1,0,0,0,0,0);
        tick(24'h000000,0,0,1,1,0,0,0,0,0);
        tick(24'h000000,0,0,1,1,0,0,0,0,0);
        tick(24'h000000,0,0,0,1,0,0,0,0,0);
        tick(24'h000000,0,0,0,1,0,0,0,0,0);
        tick(24'h000000,0,0,0,1,0,0,0,0,0);
        check_box(0,0,0,0,0,0);
        // 重新启用后收集新帧，确认统计恢复且旧bbox没有残留。
        tick(24'h000000,0,0,1,1,0,0,0,0,0);
        tick(24'h000000,0,0,1,1,0,0,0,0,0);
        tick(24'h000000,0,0,1,1,0,0,0,0,0);
        tick(24'h000000,0,0,0,1,0,0,0,0,0);
        for (y=0;y<4;y=y+1) begin
            for (x=0;x<4;x=x+1) tick(24'hC80000,1,0,0,1,0,8'hff,0,0,8'hff);
            if (y<3) tick(24'h000000,0,0,0,1,0,0,0,0,0);
        end
        tick(24'h000000,0,0,1,1,0,0,0,0,0);
        tick(24'h000000,0,0,1,1,0,0,0,0,0);
        tick(24'h000000,0,0,1,1,0,0,0,0,0);
        tick(24'h000000,0,0,0,1,0,0,0,0,0);
        check_box(1,0,3,0,3,16);

        if (errors==0) $display("[tb_algo_color_detect] PASS: 3-stage RGB/sync, RGB888 thresholds, frame bbox, last-pixel VS, one-frame green box, disable.");
        else $fatal(1,"[tb_algo_color_detect] FAIL: %0d errors",errors);
        $finish;
    end
endmodule
