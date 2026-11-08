`timescale 1ns/1ps
// 模块作用：将数据和 DE/HS/VS 同步延迟 DELAY 级，供不同算法对齐。
// DATA_WIDTH 默认 27，算法库覆盖为 24；DELAY 必须非负，0 时为组合直连。
module video_delay #(parameter DATA_WIDTH=27,parameter DELAY=1)(input wire clk,input wire rst_n,input wire [DATA_WIDTH-1:0] data_in,input wire de_in,input wire hs_in,input wire vs_in,output wire [DATA_WIDTH-1:0] data_out,output wire de_out,output wire hs_out,output wire vs_out);
 // 零延迟分支没有寄存器，复位不会强制清零其输出；有延迟分支才具有流水复位。
 generate if(DELAY==0) begin: g_bypass
  assign data_out=data_in; assign de_out=de_in; assign hs_out=hs_in; assign vs_out=vs_in;
 end else begin: g_pipe
  // data_pipe 与三个同步信号流水链长度相同，保持每个像素与其标志对应。
  reg [DATA_WIDTH-1:0] data_pipe[0:DELAY-1]; reg [DELAY-1:0] de_pipe,hs_pipe,vs_pipe; integer i;
  always @(posedge clk or negedge rst_n) begin
   if(!rst_n) for(i=0;i<DELAY;i=i+1) begin data_pipe[i]<=0;de_pipe[i]<=0;hs_pipe[i]<=0;vs_pipe[i]<=0;end
   else begin data_pipe[0]<=data_in;de_pipe[0]<=de_in;hs_pipe[0]<=hs_in;vs_pipe[0]<=vs_in;for(i=1;i<DELAY;i=i+1)begin data_pipe[i]<=data_pipe[i-1];de_pipe[i]<=de_pipe[i-1];hs_pipe[i]<=hs_pipe[i-1];vs_pipe[i]<=vs_pipe[i-1];end end
  end
  assign data_out=data_pipe[DELAY-1];assign de_out=de_pipe[DELAY-1];assign hs_out=hs_pipe[DELAY-1];assign vs_out=vs_pipe[DELAY-1];
 end endgenerate
endmodule
