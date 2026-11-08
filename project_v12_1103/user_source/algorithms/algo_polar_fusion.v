`timescale 1ns/1ps
// One in-flight coordinate; hold fusion parameters at the input handshake.
module algo_polar_fusion #(
    parameter integer DOLP_S0_MIN=16,
    parameter integer AOP_MAG_MIN=8,
    parameter FUSION_MODE=0,
    parameter K_DEF=7'd64,
    parameter W_RGB=8'd128,W_DOLP=8'd96,W_AOP=8'd32,
    parameter AOP_HUE=0,
    parameter BIN_THR=8'd128,
    parameter [7:0] AOP_DOLP_MIN=8'd16
)(
    input wire clk,rst_n,
    input wire [7:0] i0,i45,i90,i135,
    input wire [23:0] rgb0,rgb45,rgb90,rgb135,
    input wire de_in,hs_in,vs_in,
    input wire [7:0] thr_in,
    output wire [23:0] polar_rgb_out,polar_aop_rgb_out,
    output wire [7:0] polar_y_out,polar_dolp_out,polar_aop_out,
    output wire polar_de_out,polar_hs_out,polar_vs_out,
    output wire [23:0] rgb_out,
    output wire [7:0] y_out,dolp_out,aop_out,
    output wire bin_out,de_out,hs_out,vs_out,
    output wire ready_out
);
    reg [7:0] threshold_hold;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)threshold_hold<=0;
        else if(de_in && ready_out)threshold_hold<=thr_in;
    algo_polar_core #(.DOLP_S0_MIN(DOLP_S0_MIN),.AOP_MAG_MIN(AOP_MAG_MIN),
                     .AOP_DOLP_MIN(AOP_DOLP_MIN)) u_polar(
        .clk(clk),.rst_n(rst_n),.i0(i0),.i45(i45),.i90(i90),.i135(i135),
        .rgb0(rgb0),.rgb45(rgb45),.rgb90(rgb90),.rgb135(rgb135),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),
        .rgb_unpol_out(polar_rgb_out),.y_unpol_out(polar_y_out),
        .dolp_out(polar_dolp_out),.aop_out(polar_aop_out),.aop_rgb_out(polar_aop_rgb_out),
        .de_out(polar_de_out),.hs_out(polar_hs_out),.vs_out(polar_vs_out),.ready_out(ready_out));
    algo_fusion #(.FUSION_MODE(FUSION_MODE),.K_DEF(K_DEF),.W_RGB(W_RGB),
        .W_DOLP(W_DOLP),.W_AOP(W_AOP),.AOP_HUE(AOP_HUE),.BIN_THR(BIN_THR)) u_fusion(
        .clk(clk),.rst_n(rst_n),.rgb_unpol_in(polar_rgb_out),.y_unpol_in(polar_y_out),
        .dolp_in(polar_dolp_out),.aop_in(polar_aop_out),
        .vin(polar_de_out),.hs_in(polar_hs_out),.vs_in(polar_vs_out),.thr_in(threshold_hold),
        .rgb_out(rgb_out),.y_out(y_out),.dolp_out(dolp_out),.aop_out(aop_out),.bin_out(bin_out),
        .de_out(de_out),.hs_out(hs_out),.vs_out(vs_out));
endmodule
