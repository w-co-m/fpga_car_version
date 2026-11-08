`timescale 1ns/1ps

// Streaming 3x3 window: two line memories and three horizontal shift rows.
// 模块作用：两行存储加三组水平移位寄存器，构造连续像素流的 3×3 窗口。
// 当前窗口只使用已到达像素：行 y-2/y-1/y，列 x-2/x-1/x，不读取未来像素。
// 每行 DE 必须连续，行长不超过 LB_DEPTH；LB_W 当前未参与行结束判断。
module line_buffer_3x3 #(parameter DW=8, parameter LB_W=1280, parameter LB_DEPTH=2048, parameter LB_AW=11, parameter BORDER=1, parameter VS_ACTIVE_LOW=0)(
 input wire clk,input wire rst_n,input wire [DW-1:0] din,input wire de_in,input wire hs_in,input wire vs_in,
 output wire [DW-1:0] p00,p01,p02,p10,p11,p12,p20,p21,p22,
 output wire de_out,output wire hs_out,output wire vs_out,output wire [10:0] col_out,output wire [10:0] row_out
);
 localparam [DW-1:0] ZERO={DW{1'b0}};
 // 两块行存储不整体复位，便于推断 RAM；帧首通过有效行判断屏蔽旧数据。
 reg [DW-1:0] line1[0:LB_DEPTH-1],line2[0:LB_DEPTH-1];
 reg [DW-1:0] d1,d2;
 reg [LB_AW-1:0] x;
 // 同步 RAM 预取下一列；消隐时预取第 0 列，为下一行第一个像素准备历史数据。
 wire [LB_AW-1:0] read_a=de_in?(x+1'b1):{LB_AW{1'b0}};
 always @(posedge clk) begin
  if(de_in) line1[x]<=din;
  d1<=line1[read_a];
  if(de_in) line2[x]<=d1;
  d2<=line2[read_a];
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) x<=0;
  else if(de_in) x<=x+1'b1;
  else x<=0;
 end
 // DE 上升沿识别新行；观察到有效 VS 后，下一行从行号 0 开始。
 // VS_ACTIVE_LOW 决定有效 VS 电平；in_vblank 仅检测 VS 有效电平，不覆盖全部垂直消隐。
 reg de_prev;
 reg [10:0] row_idx;
 reg vs_seen;
 wire in_vblank=VS_ACTIVE_LOW?~vs_in:vs_in;
 wire line_start=de_in&~de_prev;
 wire [10:0] row_now=line_start?(vs_seen?11'd0:row_idx+11'd1):row_idx;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin de_prev<=0;row_idx<=0;vs_seen<=0;end
  else begin
   de_prev<=de_in;
   if(in_vblank) vs_seen<=1'b1;
   if(line_start) begin
    if(vs_seen) begin row_idx<=0;vs_seen<=0;end
    else row_idx<=row_idx+1'b1;
   end
  end
 end
 // 前两行不足时按 BORDER 补边：非零复制已有边界像素，0 则补零。
 wire row1_valid=(row_now>=1);
 wire row2_valid=(row_now>=2);
 wire [DW-1:0] row0=din;
 wire [DW-1:0] row1=row1_valid?d1:(BORDER?row0:ZERO);
 wire [DW-1:0] row2=row2_valid?d2:(BORDER?(row1_valid?d1:row0):ZERO);
 // 每组保留三个相邻列。移位只在 DE=1 时进行；行首残留列由后面的 h 函数修正。
 reg [DW-1:0] s0[0:2],s1[0:2],s2[0:2];
 reg [LB_AW-1:0] xc;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   s0[0]<=0;s0[1]<=0;s0[2]<=0;s1[0]<=0;s1[1]<=0;s1[2]<=0;s2[0]<=0;s2[1]<=0;s2[2]<=0;xc<=0;
  end else begin
   xc<=x;
   if(de_in) begin
    s0[0]<=s0[1];s0[1]<=s0[2];s0[2]<=row0;
    s1[0]<=s1[1];s1[1]<=s1[2];s1[2]<=row1;
    s2[0]<=s2[1];s2[1]<=s2[2];s2[2]<=row2;
   end
  end
 end
 // 左边界处理：第 0 列缺两列，第 1 列缺一列，选择复制边界或补零。
 function [DW-1:0] h;
  input [DW-1:0] leftv,midv,rightv;
  input [1:0] pos;
  begin
   case(pos)
    2'd2:h=rightv;
    2'd1:h=(xc>=1)?midv:(BORDER?rightv:ZERO);
    default:h=(xc>=2)?leftv:(BORDER?((xc==1)?midv:rightv):ZERO);
   endcase
  end
 endfunction
 // 窗口排列：p00 p01 p02 / p10 p11 p12 / p20 p21 p22。
 // 中心对应 (x-1,y-1)，输出有效时序跟随 (x,y)，与居中卷积相比内容右移、下移各一像素。
 assign p00=h(s2[0],s2[1],s2[2],0),p01=h(s2[0],s2[1],s2[2],1),p02=h(s2[0],s2[1],s2[2],2);
 assign p10=h(s1[0],s1[1],s1[2],0),p11=h(s1[0],s1[1],s1[2],1),p12=h(s1[0],s1[1],s1[2],2);
 assign p20=h(s0[0],s0[1],s0[2],0),p21=h(s0[0],s0[1],s0[2],1),p22=h(s0[0],s0[1],s0[2],2);
 reg hs_d,vs_d,de_d;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin hs_d<=0;vs_d<=0;de_d<=0;end
  else begin hs_d<=hs_in;vs_d<=vs_in;de_d<=de_in;end
 end
 // 坐标是窗口右下角当前像素的位置，不是中心坐标；输出固定 11 位。
 assign de_out=de_d,hs_out=hs_d,vs_out=vs_d,col_out={1'b0,xc},row_out=row_idx;
endmodule
