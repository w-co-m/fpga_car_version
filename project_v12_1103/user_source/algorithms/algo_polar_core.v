`timescale 1ns/1ps
// Four observations of one coordinate; accept de_in only while ready_out.
// Twelve CORDIC rotations and eight division bits reuse one register set.
// Numerical scaling/truncation matches algorithm7v2. HS/VS tag accepted data.
module algo_polar_core #(
    parameter integer DOLP_S0_MIN=16,
    parameter integer AOP_MAG_MIN=8,
    parameter [7:0] AOP_DOLP_MIN=8'd16
)(
    input wire clk,rst_n,
    input wire [7:0] i0,i45,i90,i135,
    input wire [23:0] rgb0,rgb45,rgb90,rgb135,
    input wire de_in,hs_in,vs_in,
    output reg [7:0] dolp_out,aop_out,
    output wire [23:0] aop_rgb_out,
    output reg [23:0] rgb_unpol_out,
    output reg [7:0] y_unpol_out,
    output reg de_out,hs_out,vs_out,
    output wire ready_out
);
    localparam [2:0] IDLE=0,LOAD=1,ROTATE=2,MAGNITUDE=3,
                     DIV_LOAD=4,DIVIDE=5,PUBLISH=6;
    reg [2:0] state;
    reg [3:0] iteration;
    reg [2:0] div_bit;
    reg [9:0] s0;
    reg signed [9:0] s1,s2;
    reg signed [12:0] x,y;
    reg signed [15:0] z;
    reg [1:0] signs;
    reg zero_vector,weak_signal,weak_angle,overflow;
    reg [23:0] mean_rgb,mag_product;
    reg [16:0] remainder,trial;
    reg [7:0] quotient,angle;
    reg tag_h,tag_v,aop_display_valid;
    assign ready_out=rst_n && state==IDLE;
    function [7:0] mean4(input [7:0] a,b,c,d);
        reg [9:0] sum;
        begin sum={2'b0,a}+{2'b0,b}+{2'b0,c}+{2'b0,d};mean4=sum[9:2];end
    endfunction
    function [15:0] atab(input [3:0] i);
        begin
            case(i)
                0:atab=1024;1:atab=605;2:atab=319;3:atab=162;
                4:atab=81;5:atab=41;6:atab=20;7:atab=10;
                8:atab=5;9:atab=3;10:atab=1;11:atab=1;
                default:atab=0;
            endcase
        end
    endfunction
    function [23:0] aop_hue(input [7:0] a);
        reg [2:0] seg;
        reg [7:0] t,fr;
        begin
            if(a<43)begin seg=0;t=a;end
            else if(a<86)begin seg=1;t=a-43;end
            else if(a<129)begin seg=2;t=a-86;end
            else if(a<172)begin seg=3;t=a-129;end
            else if(a<215)begin seg=4;t=a-172;end
            else begin seg=5;t=a-215;end
            fr=(t<<2)+(t<<1);
            case(seg)
                0:aop_hue={8'd255,fr,8'd0};
                1:aop_hue={8'd255-fr,8'd255,8'd0};
                2:aop_hue={8'd0,8'd255,fr};
                3:aop_hue={8'd0,8'd255-fr,8'd255};
                4:aop_hue={fr,8'd0,8'd255};
                default:aop_hue={8'd255,8'd0,8'd255-fr};
            endcase
        end
    endfunction
    // Suppress unreliable orientation; numerical AoP still uses neutral 128.
    assign aop_rgb_out=aop_display_valid ? aop_hue(aop_out) : 24'd0;
    wire [7:0] s1_abs=s1[9] ? (~s1[7:0]+8'd1) : s1[7:0];
    wire signed [12:0] xs=x>>>iteration,ys=y>>>iteration;
    wire [12:0] mag_q4=mag_product[20:8];
    wire signed [15:0] half_angle=z>>>1;
    wire signed [15:0] phi=signs[1] ?
        (signs[0] ? (-16'sd2048-half_angle) : (16'sd2048-half_angle)) : half_angle;
    wire signed [15:0] folded=(phi>2048) ? (phi-16'sd4096) :
        ((phi<=-2048) ? (phi+16'sd4096) : phi);
    wire [15:0] angle_sum=folded+16'sd2056;
    wire [15:0] shifted_angle=angle_sum>>4;
    wire angle_weak=zero_vector || (mag_q4<(AOP_MAG_MIN<<4));
    wire [7:0] angle8=angle_weak ? 8'd128 :
        ((shifted_angle>255) ? 8'd255 : shifted_angle[7:0]);
    wire [16:0] numerator={mag_q4,4'b0};
    wire [17:0] limit=({8'b0,s0}<<8)-{8'b0,s0};
    wire [7:0] result_dolp=weak_signal ? 8'd0 : (overflow ? 8'd255 : quotient);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;iteration<=0;div_bit<=0;s0<=0;s1<=0;s2<=0;
            x<=0;y<=0;z<=0;signs<=0;zero_vector<=0;mean_rgb<=0;
            mag_product<=0;remainder<=0;trial<=0;quotient<=0;angle<=128;
            weak_signal<=0;weak_angle<=0;overflow<=0;tag_h<=0;tag_v<=0;
            dolp_out<=0;aop_out<=128;rgb_unpol_out<=0;y_unpol_out<=0;
            de_out<=0;hs_out<=0;vs_out<=0;aop_display_valid<=0;
        end else begin
            de_out<=0;hs_out<=0;vs_out<=0;
            case(state)
                IDLE:if(de_in)begin
                    s0<={2'b0,i0}+{2'b0,i90};
                    s1<=$signed({2'b0,i0})-$signed({2'b0,i90});
                    s2<=$signed({2'b0,i45})-$signed({2'b0,i135});
                    mean_rgb<={mean4(rgb0[23:16],rgb45[23:16],rgb90[23:16],rgb135[23:16]),
                               mean4(rgb0[15:8],rgb45[15:8],rgb90[15:8],rgb135[15:8]),
                               mean4(rgb0[7:0],rgb45[7:0],rgb90[7:0],rgb135[7:0])};
                    tag_h<=hs_in;tag_v<=vs_in;state<=LOAD;
                end
                LOAD:begin
                    x<={3'b0,s1_abs,2'b0};y<=$signed({s2[9],s2,2'b0});z<=0;
                    signs<={s1[9],s2[9]};zero_vector<=(s1==0 && s2==0);
                    iteration<=0;state<=ROTATE;
                end
                ROTATE:begin
                    if(xs!=0 || ys!=0)begin
                        if(y>0)begin x<=x+ys;y<=y-xs;z<=z+$signed(atab(iteration));end
                        else begin x<=x-ys;y<=y+xs;z<=z-$signed(atab(iteration));end
                    end
                    if(iteration==11)state<=MAGNITUDE;
                    else iteration<=iteration+1'b1;
                end
                MAGNITUDE:begin
                    // Preserve 24-bit arithmetic and allow mapping to a spare DSP.
                    mag_product<={11'b0,x}*16'd622;state<=DIV_LOAD;
                end
                DIV_LOAD:begin
                    angle<=angle8;weak_angle<=angle_weak;
                    remainder<=numerator;trial<={7'b0,s0}<<7;
                    quotient<=0;div_bit<=7;
                    weak_signal<=(s0==0 || s0<DOLP_S0_MIN);
                    overflow<=({1'b0,numerator}>limit);state<=DIVIDE;
                end
                DIVIDE:begin
                    if(remainder>=trial)begin
                        remainder<=remainder-trial;quotient<={quotient[6:0],1'b1};
                    end else quotient<={quotient[6:0],1'b0};
                    trial<=trial>>1;
                    if(div_bit==0)state<=PUBLISH;
                    else div_bit<=div_bit-1'b1;
                end
                PUBLISH:begin
                    dolp_out<=result_dolp;aop_out<=angle;
                    rgb_unpol_out<=mean_rgb;y_unpol_out<=s0>>1;
                    aop_display_valid<=!weak_signal && !weak_angle && result_dolp>=AOP_DOLP_MIN;
                    de_out<=1;hs_out<=tag_h;vs_out<=tag_v;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
