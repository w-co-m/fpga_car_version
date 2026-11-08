`timescale 1ns/1ps
// Actual demosaic/AWB/RAM-delay/packing chain. Only RAM primitives and the
// gain kernel are modeled; fixed unity gain isolates packing from adaptive AWB.
// True adaptive gain arithmetic is covered by tb_awb_real_equiv separately.
module awb_gain_divider(input clk,rst_n,start,input[31:0]sum_g32,den32,output reg[19:0]gain20,output reg valid);
 always @(posedge clk or negedge rst_n)if(!rst_n)begin gain20<=0;valid<=0;end else begin gain20<=20'h10000;valid<=start;end
endmodule
module blk_mem_gen_zhenghe(input clka,wea,input[10:0]addra,input[31:0]dia,input clkb,input[10:0]addrb,output reg[31:0]dob);
 reg[31:0]m[0:2047];always@(posedge clka)if(wea)m[addra]<=dia;always@(posedge clkb)dob<=m[addrb];
endmodule
module blk_mem_gen_demosaic(input clka,wea,input[10:0]addra,input[32:0]dia,input clkb,input[10:0]addrb,output reg[32:0]dob);
 reg[32:0]m[0:2047];always@(posedge clka)if(wea)m[addra]<=dia;always@(posedge clkb)dob<=m[addrb];
endmodule
module blk_mem_gen_awb_delay_signal(input clka,wea,input[10:0]addra,input[95:0]dia,input clkb,input[10:0]addrb,output reg[95:0]dob);
 reg[95:0]m[0:2047];always@(posedge clka)if(wea)m[addra]<=dia;always@(posedge clkb)dob<=m[addrb];
endmodule
module tb_isp_pack;
 parameter TEST_RAMP=0;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,valid=0,user=0,last=0;reg[39:0]raw=0;
 wire outvalid,outuser,outlast;wire[127:0]outdata;
 integer f,y,g,k,px,py,ch,frames=0,words=0,errors=0,checked=0;
 reg[127:0]want;
 isp_top #(.ENABLE_POLAR_FIXED_GAIN(1)) dut(
  .axi4s_video_aclk(clk),.I_rst_n(rst_n),.I_polar_fixed_gain(1'b1),
  .I_tlast(last),.I_tuser(user),.I_tdata(raw),.I_tvalid(valid),.I_tdest(10'd0),.O_tready(1'b1),
  .O_tdata(outdata),.O_tlast(outlast),.O_tuser(outuser),.O_tvalid(outvalid),.I_tready());
 function[7:0] sample;input integer x,yy;
  begin if(TEST_RAMP)sample=8+x/16+yy/16;else if(yy%2==0)sample=x%2==0?20:60;else sample=x%2==0?60:100;end
 endfunction
 function integer mirror_x;input integer x;begin mirror_x=x<0?1:(x>=1280?1278:x);end endfunction
 function integer mirror_y;input integer y;begin mirror_y=y<0?1:(y>=720?718:y);end endfunction
 function integer raw_at;input integer x,y;begin raw_at=sample(mirror_x(x),mirror_y(y));end endfunction
 function integer avg2;input integer x0,y0,x1,y1;begin avg2=(raw_at(x0,y0)+raw_at(x1,y1))>>1;end endfunction
 function integer avg4;input integer x0,y0,x1,y1,x2,y2,x3,y3;begin avg4=(raw_at(x0,y0)+raw_at(x1,y1)+raw_at(x2,y2)+raw_at(x3,y3))>>2;end endfunction
 function[7:0] rgb_channel;input integer x,y,ch;
 begin
  if(!TEST_RAMP)case(ch)0:rgb_channel=100;1:rgb_channel=60;default:rgb_channel=20;endcase
  else if(y%2==0 && x%2==0)case(ch)
   0:rgb_channel=avg4(x-1,y-1,x+1,y-1,x-1,y+1,x+1,y+1);
   1:rgb_channel=avg4(x-1,y,x+1,y,x,y-1,x,y+1);default:rgb_channel=raw_at(x,y);endcase
  else if(y%2==1 && x%2==1)case(ch)
   0:rgb_channel=raw_at(x,y);1:rgb_channel=avg4(x-1,y,x+1,y,x,y-1,x,y+1);
   default:rgb_channel=avg4(x-1,y-1,x+1,y-1,x-1,y+1,x+1,y+1);endcase
  else if(y%2==0)case(ch)
   0:rgb_channel=avg2(x,y-1,x,y+1);1:rgb_channel=raw_at(x,y);default:rgb_channel=avg2(x-1,y,x+1,y);endcase
  else case(ch)
   0:rgb_channel=avg2(x-1,y,x+1,y);1:rgb_channel=raw_at(x,y);default:rgb_channel=avg2(x,y-1,x,y+1);endcase
 end endfunction
 always @(negedge clk)if(rst_n)begin
  if(outuser)begin
   if(frames>0 && words!=172800)$fatal(1,"ISP previous packed frame words=%0d",words);
   frames=frames+1;words=0;
  end
  if(outvalid)begin
   if(frames==0)$fatal(1,"packed data before frame start");
   for(k=0;k<16;k=k+1)begin
    px=((words*16+k)/3)%1280;py=((words*16+k)/3)/1280;ch=(words*16+k)%3;
    want[127-k*8 -:8]=rgb_channel(px,py,ch);
   end
   if(outdata!==want)begin if(errors<5)$display("FAIL ISP pack word=%0d got=%h want=%h",words,outdata,want);errors=errors+1;end
   words=words+1;checked=checked+1;
  end
 end
 initial begin
  repeat(10)@(negedge clk);rst_n=1;repeat(10)@(negedge clk);
  for(f=0;f<2;f=f+1)begin
   for(y=0;y<720;y=y+1)begin
    for(g=0;g<320;g=g+1)begin
     raw={sample(g*4+3,y),2'b00,sample(g*4+2,y),2'b00,sample(g*4+1,y),2'b00,sample(g*4,y),2'b00};
     valid=1;user=y==0&&g==0;last=g==319;@(negedge clk);
     valid=0;user=0;last=0;@(negedge clk);if(g%4==3)repeat(2)@(negedge clk);
    end
    repeat(900)@(negedge clk);
   end
   repeat(600)@(negedge clk);
   $display("ISP_PACK frame=%0d words=%0d errors=%0d",f,words,errors);
   if(words!=172800)$fatal(1,"FAIL ISP packed frame words=%0d expected172800",words);
  end
  if(frames!=2||checked!=345600||errors!=0)$fatal(1,"FAIL ISP pack frames=%0d words=%0d errors=%0d",frames,checked,errors);
  $display("PASS tb_isp_pack: actual ISP/AWB/RAM/packer, two exact frames, 345600 RGB888 words, RAMP=%0d",TEST_RAMP);$finish;
 end
 initial begin #40000000;$fatal(1,"ISP pack timeout");end
endmodule
