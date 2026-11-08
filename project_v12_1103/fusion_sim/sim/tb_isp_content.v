// RAM substitutes: synchronous one-cycle read, NBA read-before-write, NOREG; vendor primitives/timing are not modeled.
`timescale 1ns/1ps
module blk_mem_gen_zhenghe(input clka,wea,input [10:0]addra,input[31:0]dia,input clkb,input[10:0]addrb,output reg[31:0]dob);reg[31:0]m[0:2047];always@(posedge clka)if(wea)m[addra]<=dia;always@(posedge clkb)dob<=m[addrb];endmodule
module blk_mem_gen_demosaic(input clka,wea,input [10:0]addra,input[32:0]dia,input clkb,input[10:0]addrb,output reg[32:0]dob);reg[32:0]m[0:2047];always@(posedge clka)if(wea)m[addra]<=dia;always@(posedge clkb)dob<=m[addrb];endmodule
module tb_isp_content;
parameter IMG_WIDTH=1280, IMG_HEIGHT=720, TEST_RAMP=0, DATA_DELAY=50;
localparam GROUPS=IMG_WIDTH/4;
reg clk=0; always #5 clk=~clk;
reg rst=0; reg[39:0] data=0; reg valid=0,last=0,user=0;
wire ready,ov,ol,ou; wire[127:0] rgb;
demosaic #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.data_complete_delay(DATA_DELAY),.BAYER_MODE("BGGR")) dut(
 .I_clk(clk),.I_rst_n(rst),.axi4s_video_tdata(data),.axi4s_video_tdest(10'd0),.axi4s_video_tlast(last),.axi4s_video_tvalid(valid),.axi4s_video_tuser(user),.axi4s_video_tready(ready),.O_tlast(ol),.O_tuser(ou),.O_tvalid(ov),.O_tready(1'b1),.O_tdata(rgb));
integer fr,y,g,q,rows,beats,errors,xx,rr,gg,bb;
reg check_en=0, reset_watch=0;
reg[7:0] actual,expected;
function integer mx(input integer x); begin if(x<0) mx=1; else if(x>=IMG_WIDTH) mx=IMG_WIDTH-2; else mx=x; end endfunction
function integer my(input integer yy); begin if(yy<0) my=1; else if(yy>=IMG_HEIGHT) my=IMG_HEIGHT-2; else my=yy; end endfunction
function [7:0] raw_at(input integer x,input integer yy);
integer ax,ay;
begin ax=mx(x); ay=my(yy); if(TEST_RAMP) raw_at=8+ax/16+ay/16; else if((ay%2)==0) raw_at=((ax%2)==0)?8'd20:8'd60; else raw_at=((ax%2)==0)?8'd60:8'd100; end
endfunction
function [7:0] avg2(input integer x0,input integer y0,input integer x1,input integer y1);
integer s; begin s=raw_at(x0,y0)+raw_at(x1,y1); avg2=s>>1; end endfunction
function [7:0] avg4(input integer x0,input integer y0,input integer x1,input integer y1,input integer x2,input integer y2,input integer x3,input integer y3);
integer s; begin s=raw_at(x0,y0)+raw_at(x1,y1)+raw_at(x2,y2)+raw_at(x3,y3); avg4=s>>2; end endfunction
function [7:0] expected_rgb_chan(input integer x,input integer yy,input integer ch);
begin
 if((yy%2)==0 && (x%2)==0) begin
  if(ch==0) expected_rgb_chan=avg4(x-1,yy-1,x+1,yy-1,x-1,yy+1,x+1,yy+1);
  else if(ch==1) expected_rgb_chan=avg4(x-1,yy,x+1,yy,x,yy-1,x,yy+1);
  else expected_rgb_chan=raw_at(x,yy);
 end else if((yy%2)==1 && (x%2)==1) begin
  if(ch==0) expected_rgb_chan=raw_at(x,yy);
  else if(ch==1) expected_rgb_chan=avg4(x-1,yy,x+1,yy,x,yy-1,x,yy+1);
  else expected_rgb_chan=avg4(x-1,yy-1,x+1,yy-1,x-1,yy+1,x+1,yy+1);
 end else if((yy%2)==0) begin
  if(ch==0) expected_rgb_chan=avg2(x,yy-1,x,yy+1);
  else if(ch==1) expected_rgb_chan=raw_at(x,yy);
  else expected_rgb_chan=avg2(x-1,yy,x+1,yy);
 end else begin
  if(ch==0) expected_rgb_chan=avg2(x-1,yy,x+1,yy);
  else if(ch==1) expected_rgb_chan=raw_at(x,yy);
  else expected_rgb_chan=avg2(x,yy-1,x,yy+1);
 end
end endfunction
always @(negedge clk) if(reset_watch && ov) begin $display("FAIL residual valid after reset"); errors=errors+1; end
always @(negedge clk) if(ov && check_en) begin
 if(ou !== ((rows==0)&&(beats==0))) begin $display("FAIL user frame=%0d row=%0d beat=%0d got=%b",fr,rows,beats,ou); errors=errors+1; end
 if(ol !== (beats==GROUPS-1)) begin $display("FAIL last frame=%0d row=%0d beat=%0d got=%b",fr,rows,beats,ol); errors=errors+1; end
 for(q=0;q<4;q=q+1) begin
   xx=beats*4+q;
   if(TEST_RAMP) begin
    rr=expected_rgb_chan(xx,rows,0); gg=expected_rgb_chan(xx,rows,1); bb=expected_rgb_chan(xx,rows,2);
    if(rgb[q*32 +:24] !== {rr[7:0],gg[7:0],bb[7:0]}) begin if(errors<20) $display("FAIL RGB frame=%0d row=%0d beat=%0d pixel=%0d got=%h expected=%h",fr,rows,beats,q,rgb[q*32 +:24],{rr[7:0],gg[7:0],bb[7:0]}); errors=errors+1; end
   end else if(rgb[q*32 +:24] !== 24'h643c14) begin if(errors<20) $display("FAIL RGB frame=%0d row=%0d beat=%0d pixel=%0d got=%h expected=643c14",fr,rows,beats,q,rgb[q*32 +:24]); errors=errors+1; end
   if(((rows%2)==0) && ((xx%2)==0)) actual=rgb[q*32 +:8];
   else if(((rows%2)==1) && ((xx%2)==1)) actual=rgb[q*32+16 +:8];
   else actual=rgb[q*32+8 +:8];
   expected=raw_at(xx,rows);
   if(actual !== expected) begin if(errors<20) $display("FAIL direct frame=%0d row=%0d beat=%0d x=%0d got=%0d expected=%0d",fr,rows,beats,xx,actual,expected); errors=errors+1; end
 end
 beats=beats+1; if(ol) begin rows=rows+1; beats=0; end
end
initial begin errors=0; fr=0; rows=0; beats=0; repeat(5) @(negedge clk); rst=1; repeat(5) @(negedge clk);
 fr=-1;
 for(y=0;y<3;y=y+1) begin
  for(g=0;g<GROUPS;g=g+1) begin
   data={raw_at(g*4+3,y),2'b00,raw_at(g*4+2,y),2'b00,raw_at(g*4+1,y),2'b00,raw_at(g*4,y),2'b00};
   valid=1;last=(g==GROUPS-1);user=(y==0 && g==0);@(negedge clk);valid=0;last=0;user=0;@(negedge clk);if((g%4)==3) repeat(2) @(negedge clk);
  end
  repeat(900) @(negedge clk);
 end
 repeat(30) @(negedge clk); rst=0; valid=0;last=0;user=0; repeat(5) @(negedge clk); rst=1; reset_watch=1; repeat(40) @(negedge clk); reset_watch=0; check_en=1; fr=0; repeat(5) @(negedge clk);
 for(fr=0;fr<2;fr=fr+1) begin rows=0; beats=0;
  for(y=0;y<IMG_HEIGHT;y=y+1) begin
   for(g=0;g<GROUPS;g=g+1) begin
    data={raw_at(g*4+3,y),2'b00,raw_at(g*4+2,y),2'b00,raw_at(g*4+1,y),2'b00,raw_at(g*4,y),2'b00};
    valid=1; last=(g==GROUPS-1); user=(y==0 && g==0); @(negedge clk); valid=0;last=0;user=0;@(negedge clk); if((g%4)==3) repeat(2) @(negedge clk);
   end
   repeat(900) @(negedge clk);
  end
  repeat(400) @(negedge clk);
  $display("FRAME frame=%0d rows=%0d trailing=%0d",fr,rows,beats);
  if(rows!=IMG_HEIGHT || beats!=0) begin $display("FAIL count rows=%0d trailing=%0d expected=%0d x %0d",rows,beats,IMG_HEIGHT,GROUPS); errors=errors+1; end
 end
 $display("ISP_CONTENT errors=%0d",errors); if(errors==0) $display("ISP_CONTENT PASS"); $finish;
end
endmodule
