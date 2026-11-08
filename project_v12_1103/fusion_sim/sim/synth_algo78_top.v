// 仅用于独立综合：把内部四角度总线分时加载，避免把244个逻辑端口当作板外引脚。
// 不参与正式design_top_wrapper，不代表实现了摄像头采集或DDR四帧控制。
module synth_algo78_top(
    input wire clk,rst_n,
    input wire [23:0] sample_rgb,
    input wire [7:0] sample_i,thr_in,
    input wire [1:0] phase,
    input wire load,hs_in,vs_in,
    output wire [23:0] polar_rgb_out,rgb_out,
    output wire [7:0] polar_y_out,polar_dolp_out,polar_aop_out,y_out,dolp_out,aop_out,
    output wire polar_de_out,polar_hs_out,polar_vs_out,bin_out,de_out,hs_out,vs_out
);
    reg [23:0] rgb0,rgb45,rgb90;
    reg [7:0] i0,i45,i90;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin rgb0<=0;rgb45<=0;rgb90<=0;i0<=0;i45<=0;i90<=0;end
        else if(load)case(phase)
            0:begin rgb0<=sample_rgb;i0<=sample_i;end
            1:begin rgb45<=sample_rgb;i45<=sample_i;end
            2:begin rgb90<=sample_rgb;i90<=sample_i;end
            default:begin end
        endcase
    end
    algo_polar_fusion u_chain(
        .clk(clk),.rst_n(rst_n),.rgb0(rgb0),.rgb45(rgb45),.rgb90(rgb90),.rgb135(sample_rgb),
        .i0(i0),.i45(i45),.i90(i90),.i135(sample_i),
        .de_in(load && phase==3),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
        .polar_rgb_out(polar_rgb_out),.polar_y_out(polar_y_out),.polar_dolp_out(polar_dolp_out),.polar_aop_out(polar_aop_out),
        .polar_de_out(polar_de_out),.polar_hs_out(polar_hs_out),.polar_vs_out(polar_vs_out),
        .rgb_out(rgb_out),.y_out(y_out),.dolp_out(dolp_out),.aop_out(aop_out),.bin_out(bin_out),
        .de_out(de_out),.hs_out(hs_out),.vs_out(vs_out));
endmodule
