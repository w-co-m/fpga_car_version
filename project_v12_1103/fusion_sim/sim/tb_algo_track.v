`timescale 1ns/1ps
module tb_algo_track;
  reg clk=0, rst_n=0, enable_in=1;
  reg [23:0] rgb_in=24'h123456;
  reg de_in=0, hs_in=0, vs_in=0;
  reg [10:0] dx0=0, dx1=0;
  reg [9:0] dy0=0, dy1=0;
  reg det_valid=0, mot_in=0;
  wire [10:0] tx0,tx1;
  wire [9:0] ty0,ty1;
  wire valid; wire [4:0] lost;
  wire [23:0] rgb_out; wire [7:0] y_out;
  wire bin_out,de_out,hs_out,vs_out;
  always #5 clk=~clk;

  algo_track #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.OSD_EN(0)) dut (
    .clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),
    .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.enable_in(enable_in),
    .det_x_min(dx0),.det_x_max(dx1),.det_y_min(dy0),.det_y_max(dy1),
    .det_valid(det_valid),.mot_in(mot_in),.trk_x_min(tx0),.trk_x_max(tx1),
    .trk_y_min(ty0),.trk_y_max(ty1),.trk_valid(valid),.lost_cnt(lost),
    .rgb_out(rgb_out),.y_out(y_out),.bin_out(bin_out),.de_out(de_out),
    .hs_out(hs_out),.vs_out(vs_out));

  reg rst1=0, en1=1, vs1=1, dv1=0, de_tiny=0;
  reg [3:0] ax0=0,ax1=0,ay0=0,ay1=0;
  wire [2:0] bx0,bx1; wire [1:0] by0,by1; wire v1; wire [4:0] l1;
  wire [23:0] c1; wire [7:0] yy1; wire bb1,de1,hh1,vv1;
  algo_track #(.IMG_WIDTH(8),.IMG_HEIGHT(4),.DET_XW(4),.DET_YW(4),.LOST_MAX(1),.SNAP_DIST(0),.OSD_EN(0),.VS_ACTIVE_LOW(1)) tiny (
    .clk(clk),.rst_n(rst1),.rgb_in(24'hA1B2C3),
    .de_in(de_tiny),.hs_in(1'b0),.vs_in(vs1),.enable_in(en1),
    .det_x_min(ax0),.det_x_max(ax1),.det_y_min(ay0),.det_y_max(ay1),
    .det_valid(dv1),.mot_in(1'b0),.trk_x_min(bx0),.trk_x_max(bx1),
    .trk_y_min(by0),.trk_y_max(by1),.trk_valid(v1),.lost_cnt(l1),
    .rgb_out(c1),.y_out(yy1),.bin_out(bb1),.de_out(de1),.hs_out(hh1),.vs_out(vv1));

  task tick; begin @(posedge clk); #1; end endtask
  task frame; integer i; begin
    vs_in=1; repeat(15) tick(); vs_in=0; repeat(3) tick();
  end endtask
  task tiny_frame; begin
    vs1=0; repeat(15) tick(); vs1=1; repeat(3) tick();
  end endtask
  task expect_main;
    input [10:0] x0,x1e;
    input [9:0] y0,y1e;
    input ve;
    input [4:0] le;
    begin
      if ({tx0,tx1,ty0,ty1,valid,lost} !== {x0,x1e,y0,y1e,ve,le})
        $fatal(1,"main state got [%0d,%0d,%0d,%0d] valid=%b lost=%0d",tx0,tx1,ty0,ty1,valid,lost);
    end
  endtask
  integer i,j;
  initial begin
    repeat(3) tick(); rst_n=1; rst1=1; repeat(2) tick();
    // RGB888 and sidebands emerge exactly two rising edges later.
    rgb_in=24'hA5C37E; de_in=1; hs_in=1;
    tick(); if (rgb_out !== 24'h123456 || de_out !== 0) $fatal(1,"pixel advanced before two clocks");
    tick(); if (rgb_out !== 24'hA5C37E || de_out !== 1 || y_out !== 0 || bin_out !== 0 || hs_out !== 1)
      $fatal(1,"RGB888/sideband two-clock alignment failed");
    de_in=0; hs_in=0; tick();

    // A multi-cycle VS level is one event: first lock only once.
    dx0=1050; dx1=1054; dy0=520; dy1=524; det_valid=1;
    frame(); expect_main(1050,1054,520,524,1,0);

    // A 15-clock VS level is one update event, not 15 repeated smooth steps.
    dx0=1058; dx1=1062; dy0=528; dy1=532; frame();
    expect_main(1052,1056,522,526,1,0);

    // Actual round-to-nearest: ±1/4 remains in the dead zone; ±2/4 moves one.
    dx0=1053; dx1=1057; dy0=523; dy1=527; frame();
    expect_main(1052,1056,522,526,1,0);
    dx0=1050; dx1=1054; dy0=520; dy1=524; frame();
    expect_main(1051,1055,521,525,1,0);

    // SNAP boundary is strict: exactly 64 center pixels smooths; 65 snaps.
    dx0=1115; dx1=1119; dy0=521; dy1=525; frame();
    expect_main(1067,1071,521,525,1,0);
    dx0=1180; dx1=1184; frame(); expect_main(1180,1184,521,525,1,0);

    // Fourteen misses hold; miss 15 drops. Reacquisition snaps immediately.
    det_valid=0;
    for (i=1;i<=14;i=i+1) begin frame(); expect_main(1180,1184,521,525,1,i); end
    frame(); expect_main(1180,1184,521,525,0,0);
    det_valid=1; dx0=1026; dx1=1030; dy0=513; dy1=517; frame();
    expect_main(1026,1030,513,517,1,0);

    // Invalid boxes count as misses, and disabling clears stale state.
    dx0=40; dx1=20; frame(); expect_main(1026,1030,513,517,1,1);
    enable_in=0; repeat(2) tick(); expect_main(0,0,0,0,0,0);
    if (rgb_out !== 24'hA5C37E) $fatal(1,"disabled mode did not preserve the RGB888 source image");
    enable_in=1; det_valid=1; dx0=1100; dx1=1104; dy0=600; dy1=604;
    frame(); expect_main(1100,1104,600,604,1,0);

    // LOST_MAX=1 drops on its first miss; VS high is sampled only once.
    ax0=2; ax1=4; ay0=1; ay1=2; dv1=1; tiny_frame();
    if (!v1 || bx0!=2 || bx1!=4 || by0!=1 || by1!=2) $fatal(1,"tiny initial lock failed");
    // SNAP_DIST=0 disables snapping; a two-pixel displacement smooths by one.
    ax0=0; ax1=2; tiny_frame();
    if (!v1 || bx0!=1 || bx1!=3) $fatal(1,"SNAP_DIST=0 smoothing failed");
    // Restore the original box and check green edge plus the bbox mask alignment.
    ax0=2; ax1=4; tiny_frame();
    tiny_frame();
    for (i=0;i<8;i=i+1) begin de_tiny=1; tick(); end
    for (i=0;i<3;i=i+1) tick();
    de_tiny=0; tick();
    if (c1 !== 24'h00FF00 || yy1 !== 8'hff || bb1 !== 1'b1)
      $fatal(1,"green frame/mask output failed: rgb=%h y=%h bin=%b",c1,yy1,bb1);
    dv1=0; tiny_frame(); if (v1 || l1!=0) $fatal(1,"LOST_MAX=1 boundary failed valid=%b lost=%0d",v1,l1);

    // Counter uses DE and dimensions, including 1280th-column row wrap.
    // VS edge resets once even though VS remains high for multiple clocks.
    vs_in=1; repeat(15) tick(); if (dut.xc!==0 || dut.yc!==0) $fatal(1,"VS reset failed");
    vs_in=0; tick();
    for (i=0;i<1280;i=i+1) begin de_in=1; tick(); end
    de_in=0; if (dut.xc!==0 || dut.yc!==1) $fatal(1,"1280-column wrap failed x=%0d y=%0d",dut.xc,dut.yc);
    for (i=1;i<720;i=i+1) begin
      for (j=0;j<1280;j=j+1) begin de_in=1; tick(); end
    end
    de_in=0; if (dut.xc!==0 || dut.yc!==0) $fatal(1,"last row/height wrap failed");
    de_in=1; tick(); if (dut.xc!==1 || dut.yc!==0) $fatal(1,"post-wrap pixel coordinate failed");
    de_in=0; vs_in=1; repeat(15) tick(); if (dut.xc!==0 || dut.yc!==0) $fatal(1,"multi-cycle VS retriggered coordinates");

    $display("PASS tb_algo_track"); $finish;
  end
endmodule
