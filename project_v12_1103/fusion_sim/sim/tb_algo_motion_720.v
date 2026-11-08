`timescale 1ns/1ps
module tb_algo_motion_720;
    localparam W=1280, H=720;
    reg clk=0, rst_n=0, enable_in=1;
    reg [23:0] rgb_in=0; reg [7:0] y_in=0;
    reg de_in=0, hs_in=0, vs_in=0; reg [7:0] threshold_in=0;
    wire [23:0] rgb_out; wire [7:0] mask_out; wire bin_out;
    wire motion_detected; wire [($clog2(W*H+1))-1:0] motion_pixel_cnt;
    wire ref_ready,de_out,hs_out,vs_out;
    integer row,col;
    always #5 clk=~clk;

    algo_motion #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.DS_LOG2(4),.MOTION_CNT(1)) dut(.*);

    task pulse_vs;
      begin
        @(negedge clk); vs_in=1; @(posedge clk);
        @(negedge clk); vs_in=0; repeat(2) @(posedge clk);
      end
    endtask

    task fill_frame(input [7:0] data);
      begin
        for(row=0;row<H;row=row+1) begin
          for(col=0;col<W;col=col+1) begin
            @(negedge clk); de_in=1; y_in=data; rgb_in={data,data,data};
            @(posedge clk);
          end
        end
        @(negedge clk); de_in=0;
      end
    endtask

    initial begin
      repeat(3) @(posedge clk); rst_n=1;
      pulse_vs(); fill_frame(8); pulse_vs();
      if(!ref_ready || motion_pixel_cnt!==0) $fatal(1,"first 720p frame did not warm reference");
      if(dut.ref_ram[0]!==8 || dut.ref_ram[57599]!==8)
        $fatal(1,"720p reference address range did not include first and final words");
      fill_frame(128); pulse_vs();
      if(!ref_ready || motion_pixel_cnt!==20'd921600 || !motion_detected)
        $fatal(1,"720p full-count/width/address failure: ref=%b count=%0d detected=%b",ref_ready,motion_pixel_cnt,motion_detected);
      if(dut.ref_ram[57599]!==128)
        $fatal(1,"last reference address did not update on the next complete frame");
      fill_frame(128); pulse_vs();
      if(motion_pixel_cnt!==0) $fatal(1,"unchanged 720p frame reported motion");
      $display("PASS tb_algo_motion_720 count=%0d",motion_pixel_cnt);
      $finish;
    end
endmodule
