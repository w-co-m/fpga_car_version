`timescale 1ns/1ps
module tb_nine_modes;
 reg clk=0,rst_n=0,k0=1,k1=1,de=0,hs=0,vs=0;reg [23:0] rgb=24'h406080;
 wire [23:0] out; wire od,oh,ov; wire [3:0] mode;
 integer errors=0,m,i; reg [23:0] wanted;
 always #5 clk=~clk;
 video_algorithm_display #(.ALGO_COUNT(9),.CLK_HZ(1000),.DEBOUNCE_CYCLES(3),.IMG_WIDTH(8)) dut(.clk(clk),.rst_n(rst_n),.threshold_edit(1'b0), .bin_threshold_active(), .edge_threshold_active(), .threshold_edit_active(), .key0_n(k0),.key1_n(k1),.rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),.rgb_out(out),.de_out(od),.hs_out(oh),.vs_out(ov),.mode_active(mode));
 video_status_osd osd(.bin_threshold_active(8'd128), .edge_threshold_active(8'd32), .threshold_edit_active(1'b0),
.clk(clk),.rst_n(rst_n),.rgb_in(out),.de_in(od),.hs_in(oh),.vs_in(ov),.mode_active(mode),.rgb_out(),.de_out(),.hs_out(),.vs_out());
 task tick;begin @(negedge clk);end endtask
 task press;input integer prev;begin if(prev)k0=0;else k1=0;repeat(15)tick;k0=1;k1=1;repeat(15)tick;end endtask
 task commit;begin de=0;repeat(10)tick;vs=1;repeat(3000)tick;vs=0;repeat(10)tick;end endtask
 task expect;input integer n;begin if(mode!==n)begin errors=errors+1;$display("FAIL mode got=%d wanted=%d",mode,n);end end endtask
 task pixels;
  begin
   de=1;repeat(8)tick;
   case(mode)
    0:wanted=rgb;1:wanted=24'h5a5a5a;2:wanted=0;3:wanted=0;
    4:wanted=24'h6d8dad;5:wanted=24'h2d4d6d;
    6:wanted=rgb;7:wanted=24'h5a5a5a;8:wanted=24'h5a5a5a;
   endcase
   if(!od || out!==wanted)begin errors=errors+1;$display("FAIL mode %d output %h expected %h",mode,out,wanted);end
   de=0;repeat(8)tick;
  end
 endtask
 initial begin
  repeat(5)tick;rst_n=1;repeat(300)tick;commit;expect(0);
  for(m=0;m<9;m=m+1)begin
   // Each branch remains warm during selection; identical rows also check frame restart borders.
   for(i=0;i<4;i=i+1)pixels;
   de=1;press(0);expect(m);commit;expect((m+1)%9);
  end
  press(1);commit;expect(8);
  for(m=8;m>0;m=m-1)begin press(1);commit;expect(m-1);end
  if(osd.mode_char(4,0)!="B" || osd.mode_char(5,7)!="T" || osd.mode_char(6,5)!="Q" || osd.mode_char(7,4)!="E" || osd.mode_char(8,5)!="E")begin errors=errors+1;$display("FAIL OSD new mode names");end
  $display("NINE MODES RESULT errors=%0d",errors);if(errors)$fatal(1,"nine modes failed");$finish;
 end
 initial begin #1000000;$fatal(1,"nine modes timeout");end
endmodule
