`timescale 1ns/1ps
module tb_fresh_regions;
    localparam W=256,H=64;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,de=0,vs=0,hit=0;
    reg [7:0] x=0;
    reg [5:0] y=0;
    wire [7:0] x0,x1;
    wire [5:0] y0,y1;
    wire valid,overflow,fresh;
    integer held_invalid=0;
    wire [14:0] hits;
    integer f,xx,yy,overflow_seen=0;
    red_region_selector #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.XW(8),.YW(6),.HIT_W(15)) dut(
        .clk(clk),.rst_n(rst_n),.enable_in(1'b1),.frame_start(vs),.de_in(de),.hit_in(hit),
        .x_in(x),.y_in(y),.x_min(x0),.x_max(x1),.y_min(y0),.y_max(y1),
        .valid(valid),.measurement_valid(fresh),.hits(hits),.overflow(overflow));
    always @(posedge clk) if(overflow) overflow_seen=overflow_seen+1;
    task idle;
        input integer n;integer j;
        begin for(j=0;j<n;j=j+1) begin @(negedge clk);de=0;vs=0;hit=0;end end
    endtask
    task reset;
        begin rst_n=0;idle(8);rst_n=1;idle(8);overflow_seen=0;end
    endtask
    task frame;
        input integer scene;
        begin
            @(negedge clk);vs=1;de=0;hit=0;idle(4);
            if(scene==1 && overflow_seen>0)begin
                if(fresh)$fatal(1,"overflow frame falsely published as a new measurement");
                if(valid)held_invalid=held_invalid+1;
            end
            for(yy=0;yy<H;yy=yy+1) begin
                for(xx=0;xx<W;xx=xx+1) begin
                    @(negedge clk);de=1;x=xx;y=yy;hit=0;
                    // Max 32 runs share a root through a filled top/bottom row.
                    if(scene==0 && yy>=4 && yy<=12)
                        hit=(yy==4 || yy==12 || xx%8<2);
                    // 43 separate runs: fail closed rather than union/drop labels.
                    if(scene==1 && yy>=4 && yy<=12) hit=(xx%6<2);
                    // Label pool overflow without a run-list overflow (20 runs).
                    if(scene==2 && yy>=4 && yy<=12) hit=(xx<240 && xx%12<4);
                    // More than 15 total blobs, but at most one is active at a
                    // time: expired labels must be recycled, not exhaust a frame.
                    if(scene==3 && yy%3!=2 && xx>=8 && xx<=15) hit=1;
                    if(scene==4 && xx>=248 && yy>=16) hit=1;
                end
                idle(370);
            end
            idle(370);
        end
    endtask
    initial begin
        reset;
        for(f=0;f<4;f=f+1) frame(0);
        if(overflow_seen || !valid || x0!=0 || x1!=255 || y0!=4 || y1!=12 || hits!=960)
            $fatal(1,"32-run join/merge failed overflow=%0d valid=%b bbox=%0d,%0d,%0d,%0d hits=%0d",
                overflow_seen,valid,x0,x1,y0,y1,hits);
        for(f=0;f<5;f=f+1) frame(1);
        if(!overflow_seen || valid || held_invalid==0) $fatal(1,"overflow must immediately invalidate freshness before held bbox expires");
        reset;for(f=0;f<4;f=f+1) frame(2);
        if(!overflow_seen || valid) $fatal(1,"label overflow published invalid measurement");
        reset;for(f=0;f<4;f=f+1) frame(3);
        if(overflow_seen || !valid) $fatal(1,"component retirement/reuse failed");
        reset;for(f=0;f<4;f=f+1) frame(4);
        if(overflow_seen || !valid || x0!=248 || x1!=255 || y0!=16 || y1!=63 || hits!=384)
            $fatal(1,"right/bottom final run lost");
        $display("PASS tb_fresh_regions held_invalid=%0d",held_invalid);$finish;
    end
    initial begin #30000000;$fatal(1,"timeout");end
endmodule
