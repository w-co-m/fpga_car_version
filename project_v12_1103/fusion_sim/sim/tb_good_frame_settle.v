`timescale 1ns/1ps
// 采集后必须等新的好帧，不能把坏帧期间保留的旧RP当成下一角度。
module tb_good_frame_settle;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,capture=0,frame=0,good=0;
    wire pause,busy,compbusy,ready,error,start,op;
    wire[1:0]angle;wire[24:0]src,dest,offset;
    integer k,starts=0;
    polar_capture_ctrl #(.FRAME_BLOCKS(1),.SETTLE_FRAMES(3)
`ifdef GOOD_SETTLE_AVAILABLE
        ,.REQUIRE_GOOD_SETTLE(1)
`endif
    ) dut(.clk(clk),.rst_n(rst_n),.capture_pulse(capture),.restart_pulse(1'b0),
        .frame_start(frame),
`ifdef GOOD_SETTLE_AVAILABLE
        .good_frame(good),
`endif
        .live_page(2'd0),.page_valid(4'h1),.result_source_active(1'b0),
        .block_busy(1'b0),.block_done(1'b0),.block_error(1'b0),
        .display_pause(pause),.angle(angle),.capture_busy(busy),.compute_busy(compbusy),
        .ready(ready),.error(error),.block_start(start),.block_compute(op),
        .source_addr(src),.dest_addr(dest),.block_offset(offset));
    always @(posedge clk)if(start)begin
        starts=starts+1;
        if(src!=0 || dest!=23000000 || op || error)$fatal(1,"fresh source did not enter copy");
    end
    task boundary;
        input is_good;
        begin @(negedge clk);frame=1;good=is_good;@(negedge clk);frame=0;good=0;repeat(3)@(negedge clk);end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;@(negedge clk);capture=1;@(negedge clk);capture=0;
        for(k=0;k<7;k=k+1)begin
            boundary(0);
            if(pause || start || !busy)$fatal(1,"old good page accepted after bad camera frames");
        end
        boundary(1);boundary(0);boundary(1);
        if(pause)$fatal(1,"settle advanced on bad frame");
        boundary(1);if(!pause)$fatal(1,"three new good frames did not freeze");
        boundary(0);wait(starts==1);
        $display("PASS tb_good_frame_settle: old valid page held through errors, three new good frames required");$finish;
    end
    initial begin #200000;$fatal(1,"good settle timeout");end
endmodule
