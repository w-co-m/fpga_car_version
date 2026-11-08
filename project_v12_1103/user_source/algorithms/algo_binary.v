`timescale 1ns/1ps
// 模块作用：先转灰度再阈值判断；默认灰度>=128 输出白色，否则黑色。
// BIN_INV 非零时反相；总延迟为灰度 2 级加判断输出 1 级。
module algo_binary #(parameter GRAY_MODE=0,parameter BIN_THRESHOLD=8'd128,parameter BIN_INV=0, parameter DYNAMIC_THRESHOLD=0)(input wire clk,input wire rst_n,input wire [23:0] rgb_in, input wire [7:0] threshold_in,input wire de_in,input wire hs_in,input wire vs_in,output reg [23:0] rgb_out,output reg de_out,output reg hs_out,output reg vs_out);
 wire [23:0] gray_rgb; wire [7:0] y_gray; wire de_gray,hs_gray,vs_gray;
 algo_gray #(.GRAY_MODE(GRAY_MODE)) u_gray(.clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.rgb_out(gray_rgb),.y_out(y_gray),.de_out(de_gray),.hs_out(hs_gray),.vs_out(vs_gray));
 // DYNAMIC_THRESHOLD=1使用threshold_in；为0时兼容原固定参数接口。
 // white 的异或实现黑白反相；消隐期颜色不作为有效像素使用。
 // 动态阈值随输入像素延迟两拍，与灰度结果对齐；总视频延迟仍为三拍。
 reg [7:0] threshold_s1, threshold_s2; wire white=(y_gray >= (DYNAMIC_THRESHOLD ? threshold_s2 : BIN_THRESHOLD))^(BIN_INV!=0);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin threshold_s1<=BIN_THRESHOLD;threshold_s2<=BIN_THRESHOLD;rgb_out<=0;de_out<=0;hs_out<=0;vs_out<=0; end
  else begin threshold_s1<=threshold_in;threshold_s2<=threshold_s1;rgb_out<=white?24'hFFFFFF:24'h000000;de_out<=de_gray;hs_out<=hs_gray;vs_out<=vs_gray; end
 end
endmodule
