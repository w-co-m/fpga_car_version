`timescale 1ns/1ps
// 模块作用：原图直通分支，RGB 与 DE/HS/VS 同步寄存一次，总延迟 1 级。
// 名称为直通，但不是零延迟连线；算法库还会补齐到公共延迟。
module algo_passthrough(input wire clk,input wire rst_n,input wire [23:0] rgb_in,input wire de_in,input wire hs_in,input wire vs_in,output reg [23:0] rgb_out,output reg de_out,output reg hs_out,output reg vs_out);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin rgb_out<=0; de_out<=0; hs_out<=0; vs_out<=0; end
  else begin rgb_out<=rgb_in; de_out<=de_in; hs_out<=hs_in; vs_out<=vs_in; end
 end
endmodule
