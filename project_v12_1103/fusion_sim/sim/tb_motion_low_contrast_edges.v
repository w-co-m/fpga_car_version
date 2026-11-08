`timescale 1ns/1ps
module tb_motion_low_contrast_edges;
    localparam W=19,H=2;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=1,de=0,hs=0,vs=0;
    reg [7:0] value=40;
    wire [23:0] out;
    wire od,oh,ov,detected,ready;
    wire [5:0] count;
    wire [7:0] mask;
    integer red_count=0;
    algo_motion #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.BLOCK_MEAN_MODE(1),
        .DIFF_THR(8),.MOTION_CNT(1),.STATUS_OSD(0)) dut(
        .clk(clk),.rst_n(rst_n),.enable_in(enable),.rgb_in({value,value,value}),.y_in(value),
        .de_in(de),.hs_in(hs),.vs_in(vs),.threshold_in(8'd0),
        .rgb_out(out),.mask_out(mask),.bin_out(),.motion_detected(detected),
        .motion_pixel_cnt(count),.ref_ready(ready),.de_out(od),.hs_out(oh),.vs_out(ov));
    always @(posedge clk) begin
        #1;
        if(od && out==24'hff0000) red_count=red_count+1;
        if(od && mask!==8'd0 && mask!==8'd255) $fatal(1,"unknown mask from uninitialized RAM");
    end
    task idle;
        input integer n;integer j;
        begin for(j=0;j<n;j=j+1) begin @(negedge clk);de=0;hs=0;vs=0;end end
    endtask
    task reset;
        begin rst_n=0;idle(5);rst_n=1;idle(5);end
    endtask
    task frame;
        input integer scene;
        integer x,y;
        begin
            @(negedge clk);de=0;vs=1;red_count=0;
            // No blank clock between VS and first active pixel.
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W;x=x+1) begin
                    @(negedge clk);de=1;vs=0;hs=(x==0);value=40;
                    if(scene==1 && x==18) value=64;
                    if(scene==2 && x<16) value=56;
                    if(scene==3 && x==18) value=61; // tail mean47, below8
                    // Sparse DE exercises accumulation only on valid pixels.
                    if(x%3==1) idle(1);
                end
                idle(1);
            end
            idle(4);
        end
    endtask
    initial begin
        reset;frame(0);frame(0);
        if(!ready || red_count || count) $fatal(1,"reference warmup/first-block prefetch");
        frame(1);frame(1);
        if(red_count!=6 || count!=6 || !detected || dut.ref_ram[3][7:0]!=48)
            $fatal(1,"partial tail/last pixel red=%0d count=%0d ready=%b",red_count,count,ready);
        frame(1);if(red_count || count || detected) $fatal(1,"stationary tail retains stale mask");
        reset;frame(0);frame(0);frame(2);frame(2);
        if(red_count!=32 || count!=32 || !detected) $fatal(1,"first block after VS missed");
        reset;frame(0);frame(0);frame(3);frame(3);
        if(red_count || count || detected) $fatal(1,"tail mean rounded below threshold accepted");
        // An incomplete frame invalidates all partially overwritten records.
        @(negedge clk);vs=1;de=0;
        repeat(10) begin @(negedge clk);vs=0;de=1;value=120;end
        idle(2);frame(0);
        if(ready || red_count || count || detected) $fatal(1,"invalid frame leaked stale flags");
        frame(0);if(!ready || red_count || count) $fatal(1,"post-invalid warmup failed");
        enable=0;idle(4);
        if(ready || detected) $fatal(1,"disable did not clear history");
        enable=1;frame(0);frame(0);
        if(!ready || red_count || count) $fatal(1,"reenable leaked old mask");
        $display("PASS tb_motion_low_contrast_edges");$finish;
    end
    initial begin #3000000;$fatal(1,"timeout");end
endmodule
