`timescale 1ns/1ps
// 按键到视频输出/OSD的完整连接检查；控制器边界与饱和行为由独立TB覆盖。
module tb_threshold_display;
 reg clk=0,rst_n=0,k0=1,k1=1,edit=0,de=0,hs=0,vs=0;
 reg [23:0] rgb=24'h808080;
 wire [23:0] out;wire od,oh,ov;wire [3:0] mode;
 wire [7:0] bin_thr,edge_thr;wire edit_active;
 always #5 clk=~clk;
 video_algorithm_display #(.CLK_HZ(1000),.DEBOUNCE_CYCLES(3),.IMG_WIDTH(8)) dut(
  .clk(clk),.rst_n(rst_n),.key0_n(k0),.key1_n(k1),.threshold_edit(edit),
  .rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),
  .rgb_out(out),.de_out(od),.hs_out(oh),.vs_out(ov),.mode_active(mode),
  .bin_threshold_active(bin_thr),.edge_threshold_active(edge_thr),.threshold_edit_active(edit_active));
 video_status_osd osd(.clk(clk),.rst_n(rst_n),.rgb_in(out),.de_in(od),.hs_in(oh),.vs_in(ov),
  .mode_active(mode),.bin_threshold_active(bin_thr),.edge_threshold_active(edge_thr),.threshold_edit_active(edit_active),
  .rgb_out(),.de_out(),.hs_out(),.vs_out());
 task tick;begin @(negedge clk);end endtask
 task press;input previous;begin if(previous)k0=0;else k1=0;repeat(18)tick;k0=1;k1=1;repeat(18)tick;end endtask
 task commit;begin de=0;repeat(10)tick;vs=1;repeat(12)tick;vs=0;repeat(12)tick;end endtask
 task flat_pixels;input [23:0] wanted;integer y;begin
  for(y=0;y<4;y=y+1)begin
   de=1;repeat(8)tick;
   if(!od || out!==wanted)$fatal(1,"pixel got=%h wanted=%h mode=%d bin=%d edge=%d",out,wanted,mode,bin_thr,edge_thr);
   de=0;repeat(8)tick;
  end
 end endtask
 task osd_digits;input [23:0] digits;begin
  if({osd.text_char(3,8,mode,0,bin_thr,edge_thr,edit_active,0,0,0,0,0,2'd0),
      osd.text_char(3,9,mode,0,bin_thr,edge_thr,edit_active,0,0,0,0,0,2'd0),
      osd.text_char(3,10,mode,0,bin_thr,edge_thr,edit_active,0,0,0,0,0,2'd0)}!==digits)
      $fatal(1,"OSD threshold digits do not match active threshold");
 end endtask
 integer n;
 function [23:0] digits_for; input integer value; begin
  digits_for[23:16]=(value/100)+8'd48;
  digits_for[15:8]=((value/10)%10)+8'd48;
  digits_for[7:0]=(value%10)+8'd48;
 end endfunction
 initial begin
  repeat(5)tick;rst_n=1;repeat(20)tick;
  if(bin_thr!==128 || edge_thr!==32)$fatal(1,"reset defaults");
  press(0);commit;press(0);commit;
  if(mode!==2)$fatal(1,"select binary");
  flat_pixels(24'hffffff);osd_digits("128");
  edit=1;repeat(20)tick;de=1;press(0);
  if(bin_thr!==128 || mode!==2)$fatal(1,"threshold changed within active frame");
  commit; if(bin_thr!==129 || mode!==2 || edge_thr!==32)$fatal(1,"binary threshold routing got bin=%0d edge=%0d expected=129/32",bin_thr,edge_thr);
  flat_pixels(24'h000000);osd_digits("129");
  if(osd.text_char(3,18,mode,0,bin_thr,edge_thr,edit_active,0,0,0,0,0,2'd0)!="T")$fatal(1,"OSD KEY:THR");
  edit=0;repeat(20)tick;press(0);commit;
  if(mode!==3)$fatal(1,"select Sobel");flat_pixels(24'h000000);
  edit=1;repeat(20)tick;
  for(n=0;n<32;n=n+1)begin
   press(1);commit;
   if(edge_thr!==(31-n) || bin_thr!==129 || mode!==3)$fatal(1,"Sobel decrement %0d got=%0d",n,edge_thr);
   osd_digits(digits_for(31-n));
  end
  if(edge_thr!==0 || bin_thr!==129 || mode!==3)$fatal(1,"Sobel threshold routing");
  flat_pixels(24'hffffff);osd_digits("000");
  edit=0;repeat(20)tick;press(1);commit;
  if(mode!==2 || bin_thr!==129)$fatal(1,"saved binary threshold");
  flat_pixels(24'h000000);osd_digits("129");
  rst_n=0;repeat(5)tick;
  if(mode!==0 || bin_thr!==128 || edge_thr!==32)$fatal(1,"reset restores thresholds");
  osd_digits("---");
  $display("PASS tb_threshold_display: binary/Sobel pixels, frame commit, saved values, dynamic OSD, reset");
  $finish;
 end
 initial begin #200000;$fatal(1,"threshold display timeout");end
endmodule
