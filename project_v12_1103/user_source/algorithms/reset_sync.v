`timescale 1ns/1ps
// 公共复位：异步断言，目标时钟连续两个上升沿后同步释放。
// 时钟停止时保持复位；不能用尚未启动的输出时钟来复位其时钟发生器。
module reset_sync(input wire clk,input wire async_rst_n,output wire rst_n);
    (* async_reg="true" *) reg [1:0] release_ff;
    always @(posedge clk or negedge async_rst_n) begin
        if(!async_rst_n) release_ff <= 2'b00;
        else release_ff <= {release_ff[0],1'b1};
    end
    assign rst_n=release_ff[1];
endmodule
