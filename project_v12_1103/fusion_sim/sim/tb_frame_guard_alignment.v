`timescale 1ns/1ps
module tb_frame_guard_alignment;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,bank_run=1,valid=1,de=0,hs=0,vs=0;
 reg[3:0]mode=0;reg[23:0]rgb=0;
 wire[23:0]out,ref_rgb;wire od,oh,ov,rd,rh,rv;
 integer m,x,y,n,checked=0;reg compare=0,check_black=0;
 video_algorithm_display #(.IMG_WIDTH(32),.IMG_HEIGHT(16),.EXTERNAL_RENDER_MODE(1),.ENABLE_FRAME_GUARD(1)) dut(
  .clk(clk),.rst_n(rst_n),.key0_n(1'b1),.key1_n(1'b1),.threshold_edit(1'b0),
  .rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),.render_mode_in(mode),
  .frame_valid_in(valid),.bank_run(bank_run),.rgb_out(out),.de_out(od),.hs_out(oh),.vs_out(ov));
 video_algorithm_display #(.IMG_WIDTH(32),.IMG_HEIGHT(16),.EXTERNAL_RENDER_MODE(1)) reference(
  .clk(clk),.rst_n(rst_n),.key0_n(1'b1),.key1_n(1'b1),.threshold_edit(1'b0),
  .rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),.render_mode_in(mode),
  .rgb_out(ref_rgb),.de_out(rd),.hs_out(rh),.vs_out(rv));
 task tick;begin @(negedge clk);end endtask
 task frame;integer xx,yy;begin
  vs=1;repeat(4)tick;vs=0;repeat(2000)tick;
  for(yy=0;yy<16;yy=yy+1)begin
   de=1;for(xx=0;xx<32;xx=xx+1)begin rgb={8'hd0,xx[7:0],yy[7:0]};tick;end
   de=0;hs=1;repeat(8)tick;hs=0;repeat(8)tick;
  end
  repeat(10)tick;
 end endtask
 always @(negedge clk)if(compare)begin
  if({od,oh,ov}!=={rd,rh,rv})$fatal(1,"independent sync mismatch mode=%0d",mode);
  if(od)begin
   if(check_black)begin if(out!==0)$fatal(1,"invalid/reset frame RGB leaked mode=%0d out=%h",mode,out);end
   else if(out!==ref_rgb)$fatal(1,"guard changed normal algorithm pixel mode=%0d got=%h ref=%h",mode,out,ref_rgb);
   checked=checked+1;
  end
 end
 initial begin
  repeat(5)tick;rst_n=1;repeat(300)tick;frame;compare=1;
  for(m=0;m<16;m=m+1)begin mode=m;frame;end
  mode=5;valid=0;check_black=1;frame;
  // Hard recovery must not remove HDMI active-video strobes.
  bank_run=0;frame;
  if(dut.u_mode.contrast_gain_active!==8'd24)$fatal(1,"DDR reset changed key gain");
  bank_run=1;repeat(300)tick;frame;
  compare=0;
  $display("PASS tb_frame_guard_alignment mode0..15 zero-difference, invalid RGB black, HDMI timing alive (%0d pixels)",checked);$finish;
 end
 initial begin #2000000;$fatal(1,"alignment timeout");end
endmodule
