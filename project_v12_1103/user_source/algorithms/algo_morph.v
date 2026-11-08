// 算法6：3x3 形态学腐蚀/膨胀，RGB888 输入，灰度 min/max 输出。
// 四级流水：algo_gray(2) + line_buffer_3x3(1) + 形态学输出寄存(1)。
// 比较树仍在单周期内完成；目标时钟 75 MHz 时须以综合/布局布线时序报告确认。
`timescale 1ns/1ps

module algo_morph #(
    parameter GRAY_MODE   = 0,
    parameter DW          = 8,
    parameter BIN_INPUT   = 0,
    parameter MORPH_OP    = 1,
    parameter OP_FROM_THR = 1,
    parameter SE_CROSS    = 0,
    parameter BORDER      = 1,
    parameter LB_W        = 1280,
    parameter LB_DEPTH    = 2048,
    parameter LB_AW       = 11,
    parameter VS_ACTIVE_LOW = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [23:0] rgb_in,
    input  wire        de_in,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire [7:0]  thr_in,
    output reg  [23:0] rgb_out,
    output reg  [7:0]  y_out,
    output reg         bin_out,
    output reg         de_out,
    output reg         hs_out,
    output reg         vs_out
);
    wire [7:0] y_g;
    wire de_g, hs_g, vs_g;

    algo_gray #(.GRAY_MODE(GRAY_MODE)) u_gray (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(), .y_out(y_g), .de_out(de_g), .hs_out(hs_g), .vs_out(vs_g)
    );

    reg [7:0] thr_s1, thr_s2, thr_s3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            thr_s1 <= 0; thr_s2 <= 0; thr_s3 <= 0;
        end else begin
            thr_s1 <= thr_in;
            thr_s2 <= thr_s1;
            thr_s3 <= thr_s2;
        end
    end

    wire [7:0] bin_thr = {thr_s2[7:1], 1'b0};
    wire y_bin = (y_g >= bin_thr);
    wire [DW-1:0] din_lb = (DW == 1) ? y_bin :
                            (BIN_INPUT ? (y_bin ? 8'hff : 8'h00) : y_g);

    wire [DW-1:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    wire de_w, hs_w, vs_w;
    line_buffer_3x3 #(
        .DW(DW), .LB_W(LB_W), .LB_DEPTH(LB_DEPTH), .LB_AW(LB_AW),
        .BORDER(BORDER), .VS_ACTIVE_LOW(VS_ACTIVE_LOW)
    ) u_lb (
        .clk(clk), .rst_n(rst_n), .din(din_lb), .de_in(de_g), .hs_in(hs_g), .vs_in(vs_g),
        .p00(p00), .p01(p01), .p02(p02), .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .de_out(de_w), .hs_out(hs_w), .vs_out(vs_w), .col_out(), .row_out()
    );

    wire op = OP_FROM_THR ? thr_s3[0] : MORPH_OP[0];
    function [DW-1:0] f;
        input [DW-1:0] a, b;
        begin
            f = op ? ((a > b) ? a : b) : ((a < b) ? a : b);
        end
    endfunction

    wire [DW-1:0] res;
    generate
        if (SE_CROSS == 0) begin : g_square
            wire [DW-1:0] r1=f(p00,p01), r2=f(p02,p10), r3=f(p11,p12), r4=f(p20,p21);
            wire [DW-1:0] s1=f(r1,r2), s2=f(r3,r4), t1=f(s1,s2);
            assign res=f(t1,p22);
        end else begin : g_cross
            wire [DW-1:0] c1=f(p01,p21), c2=f(p10,p12);
            assign res=f(f(c1,c2),p11);
        end
    endgenerate

    wire [7:0] res8 = (DW == 1) ? {8{res[0]}} : res;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb_out <= 0; y_out <= 0; bin_out <= 0;
            de_out <= 0; hs_out <= 0; vs_out <= 0;
        end else begin
            y_out <= res8;
            rgb_out <= {res8,res8,res8};
            bin_out <= |res8;
            de_out <= de_w; hs_out <= hs_w; vs_out <= vs_w;
        end
    end
endmodule
