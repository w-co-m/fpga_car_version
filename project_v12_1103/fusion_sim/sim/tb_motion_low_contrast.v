`timescale 1ns/1ps
// Production bank: a dark, nonemissive object must be visible in the motion mask.
module tb_motion_low_contrast;
    localparam W=128,H=96;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,de=0,hs=0,vs=0;
    reg [23:0] rgb=0;
    wire [23:0] out;
    wire od,oh,ov;
    integer red_pixels=0,green_pixels=0,checks=0,errors=0,dynamic_red_pixels=0;
    reg [7:0] dynamic_threshold=8;
    wire [23:0] dynamic_out;
    wire dynamic_de,dynamic_hs,dynamic_vs;
    reg [23:0] rq[0:4];reg dq[0:4],hq[0:4],vq[0:4];
    integer k;
    algo_bank #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.LB_DEPTH(128),.LB_AW(7)) dut(
        .clk(clk),.rst_n(rst_n),.rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),.mode(4'd14),
        .bin_threshold_in(8'd128),.edge_threshold_in(8'd32),
        .bright_gain_in(8'd24),.contrast_gain_in(8'd24),.color_debug_in(1'b0),
        .rgb_out(out),.de_out(od),.hs_out(oh),.vs_out(ov));
    algo_bank #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.LB_DEPTH(128),.LB_AW(7),
        .MOTION_DYNAMIC_THRESHOLD(1)) dynamic_dut(
        .clk(clk),.rst_n(rst_n),.rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),.mode(4'd14),
        .bin_threshold_in(8'd128),.edge_threshold_in(8'd32),
        .bright_gain_in(8'd24),.contrast_gain_in(8'd24),.color_debug_in(1'b0),
        .motion_threshold_in(dynamic_threshold),
        .rgb_out(dynamic_out),.de_out(dynamic_de),.hs_out(dynamic_hs),.vs_out(dynamic_vs));
    always @(posedge clk) begin
        if(!rst_n) for(k=0;k<5;k=k+1) begin rq[k]<=0;dq[k]<=0;hq[k]<=0;vq[k]<=0;end
        else begin
            rq[0]<=rgb;dq[0]<=de;hq[0]<=hs;vq[0]<=vs;
            for(k=1;k<5;k=k+1) begin rq[k]<=rq[k-1];dq[k]<=dq[k-1];hq[k]<=hq[k-1];vq[k]<=vq[k-1];end
            #1;
            if({od,oh,ov}!=={dq[4],hq[4],vq[4]}) $fatal(1,"mode14 five-clock sync changed");
            if({dynamic_de,dynamic_hs,dynamic_vs}!=={dq[4],hq[4],vq[4]})
                $fatal(1,"dynamic mode14 sync changed");
            if(dynamic_de && dynamic_out==24'hff0000) dynamic_red_pixels=dynamic_red_pixels+1;
            if(od) begin
                if(out==24'hff0000) red_pixels=red_pixels+1;
                else if(out==24'h00ff00) green_pixels=green_pixels+1;
                else if(out!==rq[4]) $fatal(1,"non-mask RGB mutated %h/%h",out,rq[4]);
            end
        end
    end
    task idle;
        input integer n;integer j;
        begin for(j=0;j<n;j=j+1) begin @(negedge clk);de=0;hs=0;vs=0;rgb=0;end end
    endtask
    task reset;
        begin rst_n=0;idle(8);rst_n=1;idle(8);end
    endtask
    task frame;
        input integer scene;
        integer x,y,value;
        begin
            @(negedge clk);de=0;vs=1;rgb=0;red_pixels=0;green_pixels=0;dynamic_red_pixels=0;idle(4);
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W;x=x+1) begin
                    value=40;
                    if(scene==1 && x<64 && y>=48 && y<80) value=56;
                    if(scene==2) value=40+2*((x+y)%3-1);
                    if(scene==3 && x>=16 && x<80 && y>=48 && y<80) value=56;
                    // No x%16==0 sample changes: old point sampling misses all.
                    if(scene==4 && x>=4 && x<12 && y>=48 && y<80) value=56;
                    if(scene==5 && x<64 && y>=48 && y<80) value=48;
                    if(scene==6 && x<64 && y>=48 && y<80) value=47;
                    if(scene==7) begin value=8;if(x<64 && y>=48 && y<80) value=24;end
                    if(scene==8) value=(x%2)?60:20;
                    if(scene==9) value=((x%2)?60:20)+2*((x+y)%3-1);
                    @(negedge clk);de=1;hs=(x==0);rgb={value[7:0],value[7:0],value[7:0]};
                end
                idle(32);
            end
            idle(16);
        end
    endtask
    task expect_motion;
        input integer expected_pixels,expected_flag;
        input [8*48-1:0] label;
        begin
            checks=checks+1;
            if(red_pixels!=expected_pixels || dut.u_motion.motion_pixel_cnt!=expected_pixels ||
               dut.u_motion.motion_detected!==expected_flag[0]) begin
                $display("FAIL %0s red=%0d count=%0d flag=%b expected=%0d/%0d",label,
                    red_pixels,dut.u_motion.motion_pixel_cnt,dut.u_motion.motion_detected,expected_pixels,expected_flag);
                errors=errors+1;
            end
        end
    endtask
    initial begin
        reset;frame(0);frame(0);frame(0);expect_motion(0,0,"static warmup");
        frame(1);frame(1);expect_motion(2048,1,"ordinary dark object delta16");
        frame(1);expect_motion(0,0,"object stops");
        frame(3);frame(3);expect_motion(1024,1,"object moves horizontally");
        frame(3);expect_motion(0,0,"moved object stops");
        reset;frame(0);frame(0);frame(4);frame(4);
        expect_motion(512,0,"object between old sampling points");
        reset;frame(0);frame(0);frame(5);frame(5);expect_motion(2048,1,"exact threshold8");
        reset;frame(0);frame(0);frame(6);frame(6);expect_motion(0,0,"below threshold7");
        reset;frame(0);frame(0);frame(2);frame(2);expect_motion(0,0,"static sensor noise plus/minus2");
        reset;frame(8);frame(8);frame(9);frame(9);expect_motion(0,0,"static texture with small noise");
        reset;frame(0);frame(0);frame(7);frame(7);frame(7);
        expect_motion(0,0,"dark object stationary after illumination settles");
        reset;frame(0);frame(0);dynamic_threshold=7;frame(6);frame(6);
        if(dynamic_red_pixels!=2048 || dynamic_dut.u_motion.motion_pixel_cnt!=2048 || red_pixels!=0)
            $fatal(1,"dynamic motion threshold does not reach detector: dynamic=%0d static=%0d",
                dynamic_red_pixels,red_pixels);
        if(errors) $fatal(1,"MOTION_LOW_CONTRAST errors=%0d checks=%0d",errors,checks);
        $display("PASS tb_motion_low_contrast checks=%0d",checks);$finish;
    end
    initial begin #30000000;$fatal(1,"timeout");end
endmodule
