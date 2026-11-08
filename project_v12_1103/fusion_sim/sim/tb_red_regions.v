`timescale 1ns/1ps
// Behavioral reproduction: one selected object, disconnected distractor, hand,
// arbitrary aspect ratio, missing frames, frame-stable overlay and normal RGB.
module tb_red_regions;
    localparam W=72, H=48;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, de=0, hs=0, vs=0, debug_in=0;
    reg [23:0] rgb=0;
    wire [23:0] rgb_out;
    wire de_out,hs_out,vs_out;
    integer errors=0, checks=0;
    algo_bank #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.LB_DEPTH(128),.LB_AW(7)) dut (
        .clk(clk),.rst_n(rst_n),.rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),
        .mode(4'd13),.bin_threshold_in(8'd128),.edge_threshold_in(8'd32),
        .bright_gain_in(8'd24),.contrast_gain_in(8'd24),.color_debug_in(debug_in),
        .rgb_out(rgb_out),.de_out(de_out),.hs_out(hs_out),.vs_out(vs_out));

    reg [23:0] rgb_q[0:4];
    reg de_q[0:4],hs_q[0:4],vs_q[0:4];
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for(i=0;i<5;i=i+1) begin rgb_q[i]<=0;de_q[i]<=0;hs_q[i]<=0;vs_q[i]<=0;end
        end else begin
            rgb_q[0]<=rgb;de_q[0]<=de;hs_q[0]<=hs;vs_q[0]<=vs;
            for(i=1;i<5;i=i+1) begin
                rgb_q[i]<=rgb_q[i-1];de_q[i]<=de_q[i-1];
                hs_q[i]<=hs_q[i-1];vs_q[i]<=vs_q[i-1];
            end
            #1;
            if ({de_out,hs_out,vs_out} !== {de_q[4],hs_q[4],vs_q[4]})
                $fatal(1,"5-cycle sync changed");
            if(de_out && !dut.color_debug_active && rgb_out!==rgb_q[4] && rgb_out!==24'h00ff00)
                $fatal(1,"unexpected pixel mutation");
            if(de_out && dut.color_debug_active &&
               rgb_out!==((rgb_q[4]==24'h998c8d || rgb_q[4]==24'hc82028)?24'h00ff00:24'h000000))
                $fatal(1,"production mask includes hand or loses red");
        end
    end
    task idle;
        input integer n; integer j;
        begin for(j=0;j<n;j=j+1) begin @(negedge clk);de=0;hs=0;vs=0;rgb=0;end end
    endtask
    task reset;
        begin rst_n=0;idle(8);rst_n=1;idle(8);end
    endtask
    task frame;
        input integer scene; input integer offset; input [23:0] color;
        integer x,y;
        begin
            @(negedge clk);vs=1;de=0;rgb=0;
            idle(8);
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W;x=x+1) begin
                    @(negedge clk);de=1;hs=(x==0);rgb=24'h184828;
                    if(scene==0 || scene==3) begin
                        // Hand touches the foam but is not in the red mask.
                        if(x>=32+offset && x<=48+offset && y>=16 && y<=35) rgb=24'hbca084;
                        if(x>=8+offset && x<=31+offset && y>=8 && y<=31) rgb=color;
                    end
                    if(scene==0 || scene==4)
                        if(x>=56 && x<=63 && y>=8 && y<=15) rgb=24'hc82028;
                    if(scene==1 && x>=16 && x<=19 && y>=4 && y<=43) rgb=color;
                    if(scene==2 && x>=8 && x<=31 && y>=8 && y<=31) rgb=color;
                    // Two separate arms join at the bottom: requires label merge.
                    if(scene==5 && y>=8 && y<=31 &&
                       ((x>=8 && x<=15)||(x>=32 && x<=39)||(y>=28 && x>=8 && x<=39))) rgb=color;
                    // Weak textured pink: 25% one-pixel gaps must not split it.
                    if(scene==6 && x>=8 && x<=31 && y>=8 && y<=31 && ((x+y)%4!=0)) rgb=color;
                    if(scene==7 && x>=8 && x<=31 && y==32) rgb=color;
                end
                idle(400);
            end
            idle(400);
        end
    endtask
    task expect_box;
        input integer xmin,xmax,ymin,ymax;
        input [8*50-1:0] label;
        begin
            checks=checks+1;
            if(!dut.color_bbox_valid || dut.color_bbox_x_min!==xmin || dut.color_bbox_x_max!==xmax ||
               dut.color_bbox_y_min!==ymin || dut.color_bbox_y_max!==ymax) begin
                $display("FAIL %0s: valid=%b [%0d,%0d]-[%0d,%0d], expected [%0d,%0d]-[%0d,%0d]",
                    label,dut.color_bbox_valid,dut.color_bbox_x_min,dut.color_bbox_y_min,
                    dut.color_bbox_x_max,dut.color_bbox_y_max,xmin,ymin,xmax,ymax);
                errors=errors+1;
            end
        end
    endtask
    task settle;
        input integer scene; input [23:0] color; integer j;
        begin for(j=0;j<4;j=j+1) frame(scene,0,color);end
    endtask
    initial begin
        reset;settle(0,24'h998c8d);
        expect_box(8,31,8,31,"separate red distractor and unmasked touching hand");
        debug_in=1;frame(0,0,24'h998c8d);debug_in=0;
        frame(0,1,24'h998c8d);frame(0,1,24'h998c8d);
        expect_box(8,31,8,31,"one-pixel jitter deadband");
        frame(4,0,0);frame(4,0,0);
        expect_box(8,31,8,31,"short dropout must not jump to remote red object");
        frame(4,0,0);frame(4,0,0);frame(4,0,0);frame(4,0,0);frame(4,0,0);
        expect_box(56,63,8,15,"reacquire remote object after old target expires");
        reset;settle(3,24'h998c8d);
        frame(7,0,24'h998c8d);frame(7,0,24'h998c8d);
        expect_box(8,31,32,32,"rapid shrink cannot invert min/max deadband");
        reset;settle(1,24'hc82028);expect_box(16,19,4,43,"thin red object has no foam aspect restriction");
        reset;settle(2,24'hc8691e);expect_box(8,31,8,31,"saturated warm red");
        reset;settle(2,24'h3c1818);expect_box(8,31,8,31,"dim saturated red");
        reset;settle(5,24'hc82028);expect_box(8,39,8,31,"two arms merge into one component");
        reset;settle(6,24'h998c8d);expect_box(8,31,8,31,"textured pale pink");
        reset;settle(2,24'hbca084);
        if(dut.color_bbox_valid) begin errors=errors+1;$display("FAIL hand-only false positive");end
        if(errors) $fatal(1,"RED_REGIONS %0d errors in %0d checks",errors,checks);
        $display("PASS tb_red_regions checks=%0d",checks);$finish;
    end
    initial begin #30000000;$fatal(1,"timeout");end
endmodule
