`timescale 1ns/1ps
module tb_algo_motion_small;
    localparam W=19, H=2;
    reg clk=0, rst_n=0, enable_in=1;
    reg [23:0] rgb_in=0; reg [7:0] y_in=0;
    reg de_in=0, hs_in=0, vs_in=0; reg [7:0] threshold_in=0;
    wire [23:0] rgb_out; wire [7:0] mask_out; wire bin_out;
    wire motion_detected; wire [($clog2(W*H+1))-1:0] motion_pixel_cnt;
    wire ref_ready,de_out,hs_out,vs_out;
    integer row,col;
    reg [7:0] value;
    always #5 clk=~clk;

    algo_motion #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.DS_LOG2(4),.MOTION_CNT(1)) dut(.*);

    task pulse_vs(input integer width);
      integer k;
      begin
        @(negedge clk); vs_in=1;
        for(k=0;k<width;k=k+1) @(posedge clk);
        @(negedge clk); vs_in=0;
        repeat(2) @(posedge clk);
      end
    endtask

    task drive_pixel(input [7:0] data, input expected_motion);
      begin
        @(negedge clk); de_in=1; y_in=data; rgb_in={data,data,data};
        @(posedge clk); #1;
        @(negedge clk); de_in=0;
        @(posedge clk); #1;
        if (de_out !== 1'b1 || mask_out !== (expected_motion ? 8'hFF : 8'h00) || bin_out !== expected_motion)
          $fatal(1,"two-stage mask/sync mismatch expected motion=%b mask=%h de=%b",expected_motion,mask_out,de_out);
        if (rgb_out !== (expected_motion ? 24'hFF0000 : {data,data,data}))
          $fatal(1,"RGB passthrough/highlight mismatch expected=%h got=%h",(expected_motion ? 24'hFF0000 : {data,data,data}),rgb_out);
      end
    endtask

    task fill_frame(input integer pattern);
      integer r,c;
      reg [7:0] d;
      begin
        for(r=0;r<H;r=r+1) begin
          for(c=0;c<W;c=c+1) begin
            d=20;
            case(pattern)
              1: if(c==0) d=52;
              2: begin if(c==0) d=52; if(c==5) d=200; end
              3: if(c==0) d=84;
              4: if(c==0) d=115;
              default: d=20;
            endcase
            drive_pixel(d, ((pattern==1 || pattern==4) && (c<16) && ref_ready));
          end
        end
        @(negedge clk); de_in=0;
      end
    endtask

    initial begin
      repeat(3) @(posedge clk); rst_n=1;
      pulse_vs(5);
      fill_frame(0); pulse_vs(1);
      if(!ref_ready) $fatal(1,"complete first frame did not prepare reference");
      threshold_in=0;
      fill_frame(1); pulse_vs(1);
      if(motion_pixel_cnt!==32) $fatal(1,"exact-threshold/block coverage count=%0d expected32",motion_pixel_cnt);
      if(!motion_detected) $fatal(1,"motion threshold count did not assert");
      fill_frame(2); pulse_vs(1);
      if(motion_pixel_cnt!==0 || motion_detected) $fatal(1,"same representative samples must suppress unsampled changes count=%0d detected=%b",motion_pixel_cnt,motion_detected);
      threshold_in=33;
      fill_frame(3); pulse_vs(1);
      if(motion_pixel_cnt!==0) $fatal(1,"threshold33 accepted diff32");
      threshold_in=31;
      fill_frame(4); pulse_vs(1);
      if(motion_pixel_cnt!==32) $fatal(1,"threshold31 did not accept diff31: %0d",motion_pixel_cnt);
      @(negedge clk); de_in=1; y_in=8'd9; rgb_in=24'h090909;
      @(posedge clk); @(negedge clk); de_in=0;
      pulse_vs(1);
      if(ref_ready) $fatal(1,"incomplete frame left ref_ready asserted");
      fill_frame(0); pulse_vs(1);
      if(!ref_ready || motion_pixel_cnt!==0) $fatal(1,"post-incomplete complete frame did not warm cleanly");
      enable_in=0; repeat(3) @(posedge clk);
      if(ref_ready) $fatal(1,"disable did not clear reference validity");
      enable_in=1;
      fill_frame(1);
      pulse_vs(1);
      if(ref_ready) $fatal(1,"re-enabled midstream without fresh frame boundary");
      fill_frame(0); pulse_vs(1);
      if(!ref_ready) $fatal(1,"reference not reacquired after enable and complete frame");
      $display("PASS tb_algo_motion_small");
      $finish;
    end
endmodule








