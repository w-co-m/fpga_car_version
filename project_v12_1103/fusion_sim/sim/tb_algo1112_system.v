`timescale 1ns/1ps
// 实际按键→算法库→OSD链路，16个模式环回及逐像素参考。
module tb_algo1112_system;
    // Frozen legacy rule-5 single-frame contract; production rule-6 has its own regressions.
    defparam display.u_bank.COLOR_DET_RULE=5;
    // Frozen original point-sampled motion overlay; production mean-mode has dedicated tests.
    defparam display.u_bank.MOTION_BLOCK_MEAN=0;
    defparam display.u_bank.MOTION_THRESHOLD=32;
    defparam display.u_bank.MOTION_DYNAMIC_THRESHOLD=0;

 localparam W=32,H=16,LAT=7;
 reg clk=0; always #5 clk=~clk;
 reg rst=0,k0=1,k1=1,edit=0,de=0,hs=0,vs=0;
 reg [23:0] rgb=0;
 wire [23:0] bank_rgb,out;
 wire bd,bh,bv,od,oh,ov,cap,restart,edit_active;
 wire [3:0] active,pending;
 wire [7:0] bthr,ethr;
 integer samples=0,checks=0,n,idx,x,y,caps=0,restarts=0;
 reg checking=0;
 reg [23:0] expect_rgb[0:32767];
 reg ed[0:32767],eh[0:32767],ev[0:32767];
 reg [47:0] motion_name="MOTION";
 reg [63:0] track_name="TRACK   ";
 // 不覆写ALGO_COUNT，检查公共集成默认值包含mode15 TRACK。
 video_algorithm_display #(.CLK_HZ(1000),.DEBOUNCE_CYCLES(3),.IMG_WIDTH(W),.IMG_HEIGHT(H),.ENABLE_POLAR_CONTROL(1)) display(
  .clk(clk),.rst_n(rst),.key0_n(k0),.key1_n(k1),.threshold_edit(edit),
  .rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),.rgb_out(bank_rgb),.de_out(bd),.hs_out(bh),.vs_out(bv),
  .mode_active(active),.mode_pending_out(pending),.render_mode_in(4'd0),
  .polar_capture_pulse(cap),.polar_restart_pulse(restart),.bin_threshold_active(bthr),.edge_threshold_active(ethr),.threshold_edit_active(edit_active));
 video_status_osd osd(.clk(clk),.rst_n(rst),.rgb_in(bank_rgb),.de_in(bd),.hs_in(bh),.vs_in(bv),
  .mode_active(active),.bin_threshold_active(bthr),.edge_threshold_active(ethr),.threshold_edit_active(edit_active),
  .polar_angle(2'd0),.polar_capture_busy(1'b0),.polar_compute_busy(1'b0),.polar_ready(1'b0),.polar_error(1'b0),
  .rgb_out(out),.de_out(od),.hs_out(oh),.vs_out(ov));
 always @(posedge clk)begin if(cap)caps=caps+1;if(restart)restarts=restarts+1;end
 task tick;
 input [23:0] p,want;input d,h,v;
 begin
  @(negedge clk);rgb=p;de=d;hs=h;vs=v;
  expect_rgb[samples]=want;ed[samples]=d;eh[samples]=h;ev[samples]=v;
  @(posedge clk);#1;
  if(checking && samples>=LAT-1)begin
   idx=samples-LAT+1;
   if({od,oh,ov}!=={ed[idx],eh[idx],ev[idx]})$fatal(1,"new mode sync alignment sample=%0d mode=%0d",samples,active);
   if(ed[idx] && out!==expect_rgb[idx])$fatal(1,"new mode pixel sample=%0d mode=%0d got=%h want=%h",samples,active,out,expect_rgb[idx]);
   checks=checks+1;
  end
  samples=samples+1;
 end endtask
 task blank;input integer count,v;integer j;begin for(j=0;j<count;j=j+1)tick(0,0,0,0,v);end endtask
 task press;input previous;begin
  @(negedge clk);if(previous)k0=0;else k1=0;
  blank(18,0);@(negedge clk);k0=1;k1=1;blank(18,0);
 end endtask
 task change;input previous;input [3:0] wanted;begin
  press(previous);
  if(pending!==wanted)$fatal(1,"pending16 mode wanted=%0d got=%0d",wanted,pending);
  blank(6,1);blank(8,0);
  if(active!==wanted)$fatal(1,"active16 mode wanted=%0d got=%0d",wanted,active);
 end endtask
 function box_edge;input integer xx,yy;begin
  box_edge=xx>=5 && xx<=10 && yy>=5 && yy<=10 && (xx<7 || xx>8 || yy<7 || yy>8);
 end endfunction
 task frame;input integer scene,render;reg [23:0] p,w;begin
  blank(6,1);blank(8,0);
  for(y=0;y<H;y=y+1)begin
   for(x=0;x<W;x=x+1)begin
    p=24'h123456;
    if(scene==1 && y==0 && x<16)p=24'hffffff;
    if(scene==2 && x>=5 && x<=10 && y>=5 && y<=10)p=24'hf00000;
    w=p;
    if(render==1 && y==0 && x<16)w=24'hff0000;
    if(render==2 && box_edge(x,y))w=24'h00ff00;
    tick(p,w,1,x<3,0);
   end
   blank(3+(y%3),0);
  end
  blank(10,0);
 end endtask
 initial begin
  blank(5,0);rst=1;blank(12,0);
  if(display.ALGO_COUNT!==16)$fatal(1,"default ALGO_COUNT must be 16");
  change(1,15);change(0,0);
  for(n=1;n<=15;n=n+1)change(0,n[3:0]);
  change(0,0);
  for(n=15;n>=0;n=n-1)change(1,n[3:0]);
  for(n=0;n<6;n=n+1)if(osd.mode_char(14,n)!==motion_name[(5-n)*8+:8])$fatal(1,"MOTION glyph missing index=%0d",n);
  for(n=0;n<8;n=n+1)if(osd.mode_char(15,n)!==track_name[(7-n)*8+:8])$fatal(1,"TRACK label glyph missing index=%0d",n);
  if(osd.mode_char(14,6)!=32 || osd.mode_char(15,8)!=32)$fatal(1,"label padding");
  edit=1;blank(18,0);press(0);press(1);
  if(active!=0 || pending!=0 || caps || restarts || bthr!=128 || ethr!=32)$fatal(1,"mode wrap/SW1 controls changed");
  edit=0;blank(18,0);change(1,15);change(1,14);
  edit=1;blank(18,0);press(0);press(1);
  if(active!=14 || pending!=14 || caps || restarts || bthr!=128 || ethr!=32)$fatal(1,"MOTION SW1 controls changed");
  edit=0;blank(18,0);
  checking=1;samples=0;
  frame(0,0);frame(0,0);frame(1,1);frame(1,0);
  // 偏振结果返回后，第一完整帧只预热，即使内容改变也不高亮。
  checking=0;
  for(n=13;n>=9;n=n-1)change(1,n[3:0]);
  edit=1;blank(18,0);press(0);press(1);
  if(active!=9 || pending!=9 || caps!=1 || restarts!=1 || bthr!=128 || ethr!=32)$fatal(1,"polar SW1 capture/restart scope changed");
  edit=0;blank(18,0);
  frame(2,0);
  for(n=10;n<=14;n=n+1)change(0,n[3:0]);
  checking=1;samples=0;frame(1,0);frame(1,0);
  checking=0;change(0,15);change(0,0);checking=1;samples=0;
  frame(2,0);frame(0,0);
  checking=0;for(n=1;n<=13;n=n+1)change(0,n[3:0]);checking=1;samples=0;
  frame(2,0);frame(2,2); // mode13 publishes the first-frame bbox, then draws it.
  if(checks<4000)$fatal(1,"too few integration pixel checks");
  $display("PASS tb_algo1112_system: 16-mode forward/back wrap, TRACK label, SW1 scope, MOTION warmup/polar invalidation, pixel reference, 7-cycle OSD chain checks=%0d",checks);
  $finish;
 end
 initial begin #2000000;$fatal(1,"algo1112 system timeout");end
endmodule
