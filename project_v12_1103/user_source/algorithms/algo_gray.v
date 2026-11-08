`timescale 1ns/1ps
// 模块作用：RGB888 转 8 位灰度，rgb_out 三通道相同，y_out 提供独立灰度值。
// 总延迟 2 级；GRAY_MODE=0 为加权灰度，1/2 为移位加法近似。
module algo_gray #(parameter GRAY_MODE=0)(input wire clk,input wire rst_n,input wire [23:0] rgb_in,input wire de_in,input wire hs_in,input wire vs_in,output reg [23:0] rgb_out,output reg [7:0] y_out,output reg de_out,output reg hs_out,output reg vs_out);
 // 颜色分量先零扩展到 16 位，保留加权计算需要的位宽。默认权重为 77、150、29。
 wire [15:0] r={8'd0,rgb_in[23:16]},g={8'd0,rgb_in[15:8]},b={8'd0,rgb_in[7:0]};
 wire [15:0] sum=(GRAY_MODE==1)?(r+(g<<1)+b):(GRAY_MODE==2)?((r<<1)+(g<<2)+g+b):(r*16'd77+g*16'd150+b*16'd29);
 // 默认公式 Y=(77R+150G+29B+128)>>8；ROUND 在移位前加入，实现舍入。
 localparam SHIFT=(GRAY_MODE==1)?2:((GRAY_MODE==2)?3:8);
 localparam [15:0] ROUND=16'd1<<(SHIFT-1);
 // 第一级寄存加权和与时序；第二级输出灰度，并将上一拍时序送到输出。
 reg [15:0] sum_r; reg de_r,hs_r,vs_r;
 wire [7:0] y_next=sum_r>>SHIFT;
 // 非阻塞赋值使 y_next 使用上一拍 sum_r，因此 RGB、y_out 与输出 DE 同拍对应。
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin sum_r<=0;de_r<=0;hs_r<=0;vs_r<=0;y_out<=0;rgb_out<=0;de_out<=0;hs_out<=0;vs_out<=0; end
  else begin sum_r<=sum+ROUND;de_r<=de_in;hs_r<=hs_in;vs_r<=vs_in;y_out<=y_next;rgb_out<={y_next,y_next,y_next};de_out<=de_r;hs_out<=hs_r;vs_out<=vs_r; end
 end
endmodule
