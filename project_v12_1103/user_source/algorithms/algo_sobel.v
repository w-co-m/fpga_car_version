`timescale 1ns/1ps
// 模块作用：灰度化→3×3 行窗口→有符号梯度→幅值阈值，输出黑白边缘。
// 总流水延迟 5 级；行缓存另需图像历史，窗口中心为当前输入位置左上方一像素。
module algo_sobel #(parameter IMG_WIDTH=1280,parameter LB_DEPTH=2048,parameter LB_AW=11,parameter EDGE_THRESHOLD=8'd32,parameter VS_ACTIVE_LOW=0,parameter BORDER=1,parameter DYNAMIC_THRESHOLD=0)(input wire clk,input wire rst_n,input wire [23:0] rgb_in,input wire [7:0] threshold_in,input wire de_in,input wire hs_in,input wire vs_in,output reg [23:0] rgb_out,output reg de_out,output reg hs_out,output reg vs_out);
 wire [23:0] gray_rgb;wire [7:0] y;wire de_g,hs_g,vs_g;
 algo_gray u_gray(.clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.rgb_out(gray_rgb),.y_out(y),.de_out(de_g),.hs_out(hs_g),.vs_out(vs_g));
 // p00～p22 按上、中、下三行排列；p22 是当前像素，p11 是窗口中心。
 wire [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;wire de_w,hs_w,vs_w;
 line_buffer_3x3 #(.DW(8),.LB_W(IMG_WIDTH),.LB_DEPTH(LB_DEPTH),.LB_AW(LB_AW),.BORDER(BORDER),.VS_ACTIVE_LOW(VS_ACTIVE_LOW)) u_window(.clk(clk),.rst_n(rst_n),.din(y),.de_in(de_g),.hs_in(hs_g),.vs_in(vs_g),.p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),.p20(p20),.p21(p21),.p22(p22),.de_out(de_w),.hs_out(hs_w),.vs_out(vs_w),.col_out(),.row_out());
 // Sobel 核的两侧按 1、2、1 加权。10 位无符号和可容纳最大 1020。
 wire [9:0] right_sum={2'b0,p02}+({2'b0,p12}<<1)+{2'b0,p22};
 wire [9:0] left_sum={2'b0,p00}+({2'b0,p10}<<1)+{2'b0,p20};
 wire [9:0] top_sum={2'b0,p00}+({2'b0,p01}<<1)+{2'b0,p02};
 wire [9:0] bottom_sum={2'b0,p20}+({2'b0,p21}<<1)+{2'b0,p22};
 // 差值可为负，需 11 位有符号数；gy 采用上行减下行，取绝对值后方向符号不影响结果。
 wire signed [10:0] gx={1'b0,right_sum}-{1'b0,left_sum};
 wire signed [10:0] gy={1'b0,top_sum}-{1'b0,bottom_sum};
 reg signed [10:0] gx_r,gy_r;reg de_r,hs_r,vs_r;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin gx_r<=0;gy_r<=0;de_r<=0;hs_r<=0;vs_r<=0;end
  else begin gx_r<=gx;gy_r<=gy;de_r<=de_w;hs_r<=hs_w;vs_r<=vs_w;end
 end
 // 负数取二进制补码得到绝对值，再用 |Gx|+|Gy| 近似梯度幅值。
 wire [10:0] abs_x=gx_r[10]?(~gx_r+11'd1):gx_r[10:0];
 wire [10:0] abs_y=gy_r[10]?(~gy_r+11'd1):gy_r[10:0];
 wire [10:0] magnitude=abs_x+abs_y;
 // magnitude[10:3] 相当于右移 3 位，再与 EDGE_THRESHOLD 比较。
 // 输出只有黑/白；阈值越高，通常保留的边缘越少。
 // 输入阈值经过四拍，与灰度两拍、窗口一拍、梯度一拍对应；最终输出仍为五拍。
 reg [7:0] threshold_pipe [0:3];
 integer threshold_i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   for(threshold_i=0;threshold_i<4;threshold_i=threshold_i+1)
    threshold_pipe[threshold_i]<=EDGE_THRESHOLD;
  end else begin
   threshold_pipe[0]<=threshold_in;
   for(threshold_i=1;threshold_i<4;threshold_i=threshold_i+1)
    threshold_pipe[threshold_i]<=threshold_pipe[threshold_i-1];
  end
 end
 wire edge_on=(magnitude[10:3]>=(DYNAMIC_THRESHOLD ? threshold_pipe[3] : EDGE_THRESHOLD));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin rgb_out<=0;de_out<=0;hs_out<=0;vs_out<=0;end
  else begin rgb_out<=edge_on?24'hFFFFFF:24'h000000;de_out<=de_r;hs_out<=hs_r;vs_out<=vs_r;end
 end
endmodule
