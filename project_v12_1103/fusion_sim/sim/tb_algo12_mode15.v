`timescale 1ns/1ps
module tb_algo12_mode15;
    localparam W=192, H=96, LAT=5;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg [3:0] mode=15;
    reg [23:0] rgb_in=24'h123456;
    reg de_in=0, hs_in=0, vs_in=0;
    wire [23:0] rgb_out;
    wire de_out, hs_out, vs_out;
    integer sample=0, checks=0, green_lock=0, green_step1=0, green_step2=0;
    integer green_relock=0, yellow_hold=0, clear_seen=0;
    integer qx[0:LAT-1], qy[0:LAT-1], qframe[0:LAT-1];
    reg qde[0:LAT-1], qhs[0:LAT-1], qvs[0:LAT-1];
    integer qi, x, y, f, scene, left;
    reg [23:0] p;

    algo_bank #(.COLOR_DET_RULE(5),.IMG_WIDTH(W),.IMG_HEIGHT(H),.LB_DEPTH(W),.LB_AW(8)) dut(
        .clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.mode(mode),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),
        .bin_threshold_in(8'd128),.edge_threshold_in(8'd32),
        .rgb_out(rgb_out),.de_out(de_out),.hs_out(hs_out),.vs_out(vs_out));

    task tick;
        input [23:0] pixel;
        input d,h,v;
        input integer px,py,frame_id;
        begin
            @(negedge clk);
            rgb_in=pixel; de_in=d; hs_in=h; vs_in=v;
            qx[sample%LAT]=px; qy[sample%LAT]=py; qframe[sample%LAT]=frame_id;
            qde[sample%LAT]=d; qhs[sample%LAT]=h; qvs[sample%LAT]=v;
            @(posedge clk); #1;
            if (rst_n && sample>=LAT-1) begin
                qi=(sample+1)%LAT;
                if ({de_out,hs_out,vs_out} !== {qde[qi],qhs[qi],qvs[qi]})
                    $fatal(1,"mode15 RGB888 sync must align at five clocks sample=%0d",sample);
                checks=checks+1;
                if (qde[qi] && qx[qi]==20 && qy[qi]==48 && qframe[qi]==2 && rgb_out==24'h00ff00) green_lock=green_lock+1;
                if (qde[qi] && qx[qi]==20 && qy[qi]==48 && qframe[qi]==3 && rgb_out==24'h00ff00) green_step1=green_step1+1;
                if (qde[qi] && qx[qi]==21 && qy[qi]==48 && qframe[qi]==4 && rgb_out==24'h00ff00) green_step2=green_step2+1;
                if (qde[qi] && qx[qi]==104 && qy[qi]==48 && qframe[qi]==7 && rgb_out==24'h00ff00) green_relock=green_relock+1;
                if (qde[qi] && qx[qi]==104 && qy[qi]==48 && qframe[qi]==9 && rgb_out==24'hffff00) yellow_hold=yellow_hold+1;
                if (qde[qi] && qx[qi]==104 && qy[qi]==48 && qframe[qi]==23 && rgb_out==24'h123456) clear_seen=clear_seen+1;
            end
            sample=sample+1;
        end
    endtask

    task frame;
        input integer frame_id, target_scene, target_left;
        integer xx,yy;
        begin
            repeat(3) tick(24'h123456,0,0,1,0,0,frame_id);
            repeat(3) tick(24'h123456,0,0,0,0,0,frame_id);
            for(yy=0;yy<H;yy=yy+1) begin
                for(xx=0;xx<W;xx=xx+1) begin
                    p=(target_scene && xx>=target_left && xx<target_left+16 && yy>=44 && yy<60) ? 24'hf00000 : 24'h123456;
                    tick(p,1,(xx<3),0,xx,yy,frame_id);
                end
                repeat(2) tick(24'h123456,0,1,0,0,yy,frame_id);
                tick(24'h123456,0,0,0,0,yy,frame_id);
            end
            repeat(8) tick(24'h123456,0,0,0,0,0,frame_id);
        end
    endtask

    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        frame(0,0,0);
        frame(1,1,20);
        frame(2,1,20);
        frame(3,1,24);
        frame(4,1,24);
        frame(5,1,24);
        frame(6,1,104);
        frame(7,1,104);
        for(f=8;f<=23;f=f+1) frame(f,0,0);
        if(green_lock!=1) $fatal(1,"mode15 did not draw green box on detected red target after frame lock");
        if(green_step1!=1 || green_step2!=1) $fatal(1,"mode15 tracking did not smooth the moved target one pixel per frame step");
        if(green_relock!=1) $fatal(1,"mode15 did not snap to a far-away reacquired target");
        if(yellow_hold!=1) $fatal(1,"mode15 did not show yellow dashed box during lost-frame hold");
        if(clear_seen!=1) $fatal(1,"mode15 did not clear the box on the 15th lost frame");
        $display("PASS tb_algo12_mode15: bank mode15 RGB888, 5-clock RGB/sync, lock/smooth/relock/yellow hold/15-miss clear checks=%0d",checks);
        $finish;
    end
    initial begin #100000000;$fatal(1,"mode15 integration timeout");end
endmodule
