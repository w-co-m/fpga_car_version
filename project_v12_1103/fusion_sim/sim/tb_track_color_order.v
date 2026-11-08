`timescale 1ns/1ps
module tb_track_color_order;
  reg clk=0, rst_n=0, enable=1;
  reg [23:0] rgb=0;
  reg de=0, hs=0, vs=0;
  reg [7:0] thr=8'd32;
  wire [23:0] c_rgb, t_rgb; wire [7:0] c_y, t_y;
  wire c_bin, t_bin, c_de, c_hs, c_vs, t_de, t_hs, t_vs;
  wire [2:0] bx0,bx1,tx0,tx1;
  wire [1:0] by0,by1,ty0,ty1;
  wire c_valid,t_valid; wire [5:0] hits; wire [4:0] lost;
  always #5 clk=~clk;

  algo_color_detect #(.IMG_WIDTH(8),.IMG_HEIGHT(4),.MIN_PIX(1)) color (
    .clk(clk),.rst_n(rst_n),.enable_in(enable),.rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),.thr_in(thr),
    .rgb_out(c_rgb),.y_out(c_y),.bin_out(c_bin),.de_out(c_de),.hs_out(c_hs),.vs_out(c_vs),
    .bbox_x_min(bx0),.bbox_x_max(bx1),.bbox_y_min(by0),.bbox_y_max(by1),.bbox_valid(c_valid),.hit_cnt(hits));
  algo_track #(.IMG_WIDTH(8),.IMG_HEIGHT(4),.DET_XW(3),.DET_YW(2),.OSD_EN(0)) track (
    .clk(clk),.rst_n(rst_n),.rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),.enable_in(enable),
    .det_x_min(bx0),.det_x_max(bx1),.det_y_min(by0),.det_y_max(by1),.det_valid(c_valid),.mot_in(1'b0),
    .trk_x_min(tx0),.trk_x_max(tx1),.trk_y_min(ty0),.trk_y_max(ty1),.trk_valid(t_valid),.lost_cnt(lost),
    .rgb_out(t_rgb),.y_out(t_y),.bin_out(t_bin),.de_out(t_de),.hs_out(t_hs),.vs_out(t_vs));

  task tick; begin @(posedge clk); #1; end endtask
  task frame_start; input integer cycles; integer n; begin
    vs=1; for (n=0;n<cycles;n=n+1) tick(); vs=0; repeat(2) tick();
  end endtask
  task stream_rect; input integer x0,x1,y0,y1; integer x,y; begin
    for (y=0;y<4;y=y+1) begin
      for (x=0;x<8;x=x+1) begin
        de=1;
        if (x>=x0 && x<=x1 && y>=y0 && y<=y1) rgb=24'hFF0000;
        else rgb=24'h000000;
        tick();
      end
      de=0; rgb=0; tick();
    end
  end endtask

  initial begin
    repeat(3) tick(); rst_n=1; repeat(2) tick();
    frame_start(5);                 // consume empty frame and arm both modules
    stream_rect(2,4,1,2);
    vs=1; tick();                   // frame_start rises
    tick();                         // color publishes new bbox from frame_start1
    if (!c_valid || bx0!=2 || bx1!=4 || by0!=1 || by1!=2)
      $fatal(1,"color detector did not publish the expected first bbox");
    if (t_valid) $fatal(1,"tracker consumed bbox before color frame_start1 publish");
    tick();                         // delayed tracker event consumes the new bbox
    if (!t_valid || tx0!=2 || tx1!=4 || ty0!=1 || ty1!=2)
      $fatal(1,"tracker missed the newly published bbox: x=%0d..%0d y=%0d..%0d",tx0,tx1,ty0,ty1);
    repeat(3) tick(); vs=0; repeat(2) tick();

    stream_rect(4,6,1,2);
    vs=1; repeat(5) tick();         // one edge despite five VS-high clocks
    if (!c_valid || bx0!=4 || bx1!=6) $fatal(1,"color detector second bbox failed");
    if (!t_valid || tx0!=3 || tx1!=5 || ty0!=1 || ty1!=2)
      $fatal(1,"tracker repeated update during VS level or missed bbox: x=%0d..%0d",tx0,tx1);
    $display("PASS tb_track_color_order"); $finish;
  end
endmodule
