`timescale 1ns/1ps
module tb_algo_color_detect_720p;
    localparam W=1280, H=720;
    reg clk=0, rst_n=0, enable_in=1;
    reg [23:0] rgb_in=0;
    reg de_in=0, hs_in=0, vs_in=0;
    reg [7:0] thr_in=0;
    always #5 clk=~clk;

    wire [23:0] rgb_out;
    wire [7:0] y_out;
    wire bin_out,de_out,hs_out,vs_out,bbox_valid;
    wire [10:0] bbox_x_min,bbox_x_max;
    wire [9:0] bbox_y_min,bbox_y_max;
    wire [19:0] hit_cnt;
    algo_color_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.MIN_PIX(16)) dut (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
        .rgb_out(rgb_out),.y_out(y_out),.bin_out(bin_out),.de_out(de_out),.hs_out(hs_out),.vs_out(vs_out),
        .bbox_x_min(bbox_x_min),.bbox_x_max(bbox_x_max),.bbox_y_min(bbox_y_min),.bbox_y_max(bbox_y_max),
        .bbox_valid(bbox_valid),.hit_cnt(hit_cnt));

    reg [23:0] expected_rgb=0;
    reg [7:0] expected_y=0;
    reg expected_bin=0;
    reg [23:0] exp_rgb0=0,exp_rgb1=0,exp_rgb2=0;
    reg [7:0] exp_y0=0,exp_y1=0,exp_y2=0;
    reg exp_bin0=0,exp_bin1=0,exp_bin2=0;
    reg exp_de0=0,exp_de1=0,exp_de2=0;
    reg exp_hs0=0,exp_hs1=0,exp_hs2=0;
    reg exp_vs0=0,exp_vs1=0,exp_vs2=0;
    reg check0=0,check1=0,check2=0;
    integer sample_x=-1,sample_y=-1;
    integer ex0=-1,ex1=-1,ex2=-1,ey0=-1,ey1=-1,ey2=-1;
    integer errors=0, checked=0;
    always @(posedge clk) begin
        exp_rgb0 <= expected_rgb; exp_rgb1 <= exp_rgb0; exp_rgb2 <= exp_rgb1;
        exp_y0 <= expected_y; exp_y1 <= exp_y0; exp_y2 <= exp_y1;
        exp_bin0 <= expected_bin; exp_bin1 <= exp_bin0; exp_bin2 <= exp_bin1;
        exp_de0 <= de_in; exp_de1 <= exp_de0; exp_de2 <= exp_de1;
        exp_hs0 <= hs_in; exp_hs1 <= exp_hs0; exp_hs2 <= exp_hs1;
        exp_vs0 <= vs_in; exp_vs1 <= exp_vs0; exp_vs2 <= exp_vs1;
        ex0 <= sample_x; ex1 <= ex0; ex2 <= ex1;
        ey0 <= sample_y; ey1 <= ey0; ey2 <= ey1;
        check0 <= rst_n; check1 <= check0; check2 <= check1;
        #1;
        if (check2) begin
            checked=checked+1;
            if (rgb_out !== exp_rgb2 || y_out !== exp_y2 || bin_out !== exp_bin2 ||
                de_out !== exp_de2 || hs_out !== exp_hs2 || vs_out !== exp_vs2) begin
                errors=errors+1;
                if (errors<=8) $display("720p stream mismatch check=%0d coord=(%0d,%0d) expected=%06h got=%06h box=(%0d,%0d) span=%b edge=%b box2=%b",checked,ex2,ey2,exp_rgb2,rgb_out,dut.x2,dut.y2,dut.in_span,dut.on_edge,dut.box2);
            end
        end
    end

    task drive;
        input [23:0] pix;
        input d,h,v;
        input [23:0] exp_pix;
        input [7:0] exp_mask;
        begin
            @(negedge clk);
            rgb_in=pix; de_in=d; hs_in=h; vs_in=v;
            expected_rgb=exp_pix; expected_y=exp_mask; expected_bin=(exp_mask!=0);
        end
    endtask

    task check_bbox;
        input valid;
        input [10:0] xmin,xmax;
        input [9:0] ymin,ymax;
        input [19:0] hits;
        begin
            if (bbox_valid !== valid || bbox_x_min !== xmin || bbox_x_max !== xmax ||
                bbox_y_min !== ymin || bbox_y_max !== ymax || hit_cnt !== hits) begin
                $display("720p bbox expected v=%b (%0d,%0d)-(%0d,%0d) hits=%0d; got v=%b (%0d,%0d)-(%0d,%0d) hits=%0d",
                    valid,xmin,ymin,xmax,ymax,hits,bbox_valid,bbox_x_min,bbox_y_min,bbox_x_max,bbox_y_max,hit_cnt);
                errors=errors+1;
            end
        end
    endtask

    integer x,y,k;
    reg [23:0] pix,expected;
    reg [7:0] mask;
    initial begin
        expected_rgb=0; expected_y=0; expected_bin=0;
        repeat(4) @(negedge clk); rst_n=1;
        drive(24'h000000,0,0,1,24'h000000,0);
        drive(24'h000000,0,0,0,24'h000000,0);

        // 完整720p帧1：目标矩形为x=1200..1223,y=650..670，24*21=504像素。
        for (y=0;y<H;y=y+1) begin
            for (x=0;x<W;x=x+1) begin
                sample_x=x; sample_y=y;
                pix=((x>=1200)&&(x<=1223)&&(y>=650)&&(y<=670)) ? 24'hff0000 : 24'h808080;
                mask=((x>=1200)&&(x<=1223)&&(y>=650)&&(y<=670)) ? 8'hff : 8'h00;
                drive(pix,1,0,0,pix,mask);
            end
            // 多拍HS高电平只结束一行一次，y必须由DE下降沿计数。
            drive(24'h000000,0,1,0,24'h000000,0);
            drive(24'h000000,0,1,0,24'h000000,0);
            drive(24'h000000,0,1,0,24'h000000,0);
        end
        drive(24'h000000,0,0,1,24'h000000,0);
        drive(24'h000000,0,0,0,24'h000000,0);
        drive(24'h000000,0,0,0,24'h000000,0);
        check_bbox(1,11'd1200,11'd1223,10'd650,10'd670,20'd504);

        // 完整720p帧2全灰，读取上一帧绿框的空间位置。
        for (y=0;y<H;y=y+1) begin
            for (x=0;x<W;x=x+1) begin
                sample_x=x; sample_y=y;
                expected=24'h808080;
                if ((y==650 || y==651 || y==669 || y==670) && x>=1200 && x<=1223) expected=24'h00ff00;
                else if (y>651 && y<669 && (x==1200 || x==1201 || x==1222 || x==1223)) expected=24'h00ff00;
                drive(24'h808080,1,0,0,expected,0);
            end
            drive(24'h000000,0,1,0,24'h000000,0);
            drive(24'h000000,0,1,0,24'h000000,0);
            drive(24'h000000,0,1,0,24'h000000,0);
        end
        drive(24'h000000,0,0,1,24'h000000,0);
        drive(24'h000000,0,0,0,24'h000000,0);
        repeat(5) @(negedge clk);
        check_bbox(0,0,0,0,0,0);

        if (errors==0) $display("[tb_algo_color_detect_720p] PASS: %0d delayed samples; x=1200..1223, y=650..670, hit count=504, prior-frame box placement.",checked);
        else $fatal(1,"[tb_algo_color_detect_720p] FAIL: %0d errors",errors);
        $finish;
    end
endmodule
