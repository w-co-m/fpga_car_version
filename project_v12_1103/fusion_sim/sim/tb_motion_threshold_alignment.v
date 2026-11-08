`timescale 1ns/1ps
// A frame-committed control must follow the same two gray-input stages as VS.
module tb_motion_threshold_alignment;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,de=0,vs=0;
    reg [23:0] rgb=24'h282828;
    reg [7:0] threshold=8;
    algo_bank #(.IMG_WIDTH(16),.IMG_HEIGHT(1),.LB_DEPTH(16),.LB_AW(4),
        .MOTION_DYNAMIC_THRESHOLD(1),.MOTION_MIN_PIX(1)) dut(
        .clk(clk),.rst_n(rst_n),.rgb_in(rgb),.de_in(de),.hs_in(1'b0),.vs_in(vs),.mode(4'd14),
        .bin_threshold_in(8'd128),.edge_threshold_in(8'd32),.bright_gain_in(8'd24),
        .contrast_gain_in(8'd24),.color_debug_in(1'b0),.motion_threshold_in(threshold),
        .rgb_out(),.de_out(),.hs_out(),.vs_out());
    task frame;
        input [7:0] gray;
        input [7:0] next_threshold;
        integer x;
        begin
            for(x=0;x<16;x=x+1) begin
                @(negedge clk);de=1;vs=0;rgb={gray,gray,gray};
            end
            // VS is immediately after the final source pixel. Emulate the
            // controller's NBA threshold commit at this edge.
            @(negedge clk);de=0;vs=1;
            @(posedge clk);threshold<=next_threshold;
            @(negedge clk);vs=0;
            repeat(6) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        @(negedge clk);vs=1;
        @(negedge clk);vs=0;
        repeat(6) @(negedge clk);
        frame(40,8);
        if(!dut.u_motion.ref_ready) $fatal(1,"warmup failed");
        frame(48,9);
        if(dut.u_motion.motion_pixel_cnt!=16)
            $fatal(1,"next-frame threshold changed previous final block count=%0d expected16",
                dut.u_motion.motion_pixel_cnt);
        frame(56,9);
        if(dut.u_motion.motion_pixel_cnt!=0) $fatal(1,"new frame did not use threshold9");
        $display("PASS tb_motion_threshold_alignment");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
