`timescale 1ns/1ps
module tb_algo_histeq;
 reg clk=0,rst_n=0,de=0,hs=0,vs=0; reg [23:0] rgb=0;
 wire [23:0] out; wire [7:0] yo; wire bo,od,oh,ov;
 integer hist[0:255],map[0:255]; integer f,i,j,y,cdf,cmin,total,errors=0,checked=0;
 integer eqy[0:3]; reg [23:0] eqrgb[0:3]; reg ed[0:3],eh[0:3],ev[0:3];
 always #5 clk=~clk;
 algo_histeq dut(.clk(clk),.rst_n(rst_n),.rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),.thr_in(8'd0),.rgb_out(out),.y_out(yo),.bin_out(bo),.de_out(od),.hs_out(oh),.vs_out(ov));
 function integer gray; input [23:0] r; begin gray=(77*r[23:16]+150*r[15:8]+29*r[7:0]+128)>>8; end endfunction
 function [7:0] sat; input integer n; begin sat=n<0?0:(n>255?255:n); end endfunction
 function [23:0] mapped; input [23:0] r; integer yy,d; begin yy=gray(r); d=map[yy]-yy; mapped={sat(r[23:16]+d),sat(r[15:8]+d),sat(r[7:0]+d)}; end endfunction
 always @(posedge clk) begin
  if(!rst_n) begin for(j=0;j<4;j=j+1) begin eqrgb[j]=0;eqy[j]=0;ed[j]=0;eh[j]=0;ev[j]=0;end end
  else begin
   for(j=3;j>0;j=j-1) begin eqrgb[j]=eqrgb[j-1];eqy[j]=eqy[j-1];ed[j]=ed[j-1];eh[j]=eh[j-1];ev[j]=ev[j-1];end
   eqrgb[0]=mapped(rgb); eqy[0]=map[gray(rgb)]; ed[0]=de;eh[0]=hs;ev[0]=vs;
   #1;
   if({od,oh,ov}!=={ed[3],eh[3],ev[3]}) begin errors=errors+1;$display("FAIL hist sync");end
   if(od) begin checked=checked+1; if(out!==eqrgb[3] || yo!==eqy[3]) begin errors=errors+1;if(errors<10)$display("FAIL hist rgb got=%h expected=%h y=%d/%d",out,eqrgb[3],yo,eqy[3]);end end
  end
 end
 task tick; begin @(negedge clk); end endtask
 task blank; input integer n; begin de=0;rgb=0;repeat(n)tick;end endtask
 task end_frame;
  begin
   blank(10);vs=1;blank(3000);vs=0;blank(10);
   total=0;cmin=0;for(i=0;i<256;i=i+1)total=total+hist[i];
   if(dut.total!==total) begin errors=errors+1;$display("FAIL histogram total=%d expected=%d",dut.total,total);end
    $display("FRAME f=%0d total=%0d uni=%b errors=%0d",f,total,dut.uni,errors); cdf=0;
   for(i=0;i<256;i=i+1) begin
    cdf=cdf+hist[i];if(cmin==0 && hist[i]!=0)cmin=cdf;
    if(total==0 || total==cmin) map[i]=i;
    else if(cmin==0)map[i]=0;
    else begin map[i]=((cdf-cmin)*256)/(total-cmin);if(map[i]>255)map[i]=255;end
   end
   // Uniform frames must make the entire table identity, including bins below the occupied bin.
   if(total!=0 && total==cmin)for(i=0;i<256;i=i+1)map[i]=i;
   for(i=0;i<256;i=i+1)if(dut.mmap[i]!==map[i])begin errors=errors+1;if(errors<10)$display("FAIL map bin=%d got=%d exp=%d",i,dut.mmap[i],map[i]);end
  end
 endtask
 initial begin
  for(i=0;i<256;i=i+1)begin map[i]=i;hist[i]=0;end
  repeat(5)tick;rst_n=1;blank(300);end_frame;
  for(f=0;f<7;f=f+1)begin
   for(i=0;i<256;i=i+1)hist[i]=0;
   for(i=0;i<256;i=i+1)begin
    case(f)
     0:rgb=0;1:rgb={i[7:0],i[7:0],i[7:0]};
     2:rgb=i%2?24'h323232:24'hc8c8c8;
     3:rgb={i[7:0],8'h40,8'hf0};
     4:begin y=100+i%32;rgb={y[7:0],y[7:0],y[7:0]};end
     5:rgb=24'hffffff;default:rgb={i[7:0],i[7:0],i[7:0]};
    endcase
    de=1;hs=i%32==0;hist[gray(rgb)]=hist[gray(rgb)]+1;tick;
    if(i%32==31)begin hs=0;blank(3);end
   end
   end_frame;
  end
  // A full 720p uniform frame detects 19-bit counter overflow.
  for(i=0;i<256;i=i+1)hist[i]=0;
  for(i=0;i<921600;i=i+1)begin de=1;hs=0;rgb=24'h7f7f7f;tick;if(i%1280==1279)blank(3);end
  hist[127]=921600;end_frame;
  $display("HISTEQ RESULT checked=%0d errors=%0d",checked,errors);
  if(errors)$fatal(1,"histeq failed");$finish;
 end
 initial begin #20000000;$fatal(1,"hist timeout");end
endmodule

