`timescale 1ns/1ps
module tb_polar_capture;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, capture=0, restart=0, frame=0, result_active=0;
    reg [1:0] page=2; reg [3:0] valid=15;
    reg busy=0, done=0, block_error=0;
    wire pause, capbusy, compbusy, ready, error, start, op;
    wire abort_req;
    wire abort_ack=abort_req && !busy;
    wire [1:0] angle; wire [24:0] source,dest,offset;
    integer errors=0, copies=0, computes=0, delay_count=0, k;
    reg [24:0] expected_angle;
    polar_capture_ctrl #(.FRAME_BLOCKS(2),.SETTLE_FRAMES(2)) dut(
        .clk(clk),.rst_n(rst_n),.capture_pulse(capture),.restart_pulse(restart),
        .frame_start(frame),.live_page(page),.page_valid(valid),.result_source_active(result_active),
        .block_busy(busy),.block_done(done),.block_error(block_error),.display_pause(pause),
        .block_abort_req(abort_req),.block_abort_ack(abort_ack),.block_reset_required(1'b0),
        .angle(angle),.capture_busy(capbusy),.compute_busy(compbusy),.ready(ready),.error(error),
        .block_start(start),.block_compute(op),.source_addr(source),.dest_addr(dest),.block_offset(offset));
    always @(posedge clk) begin
        done<=0;
        if(start) begin
            if(busy) begin $display("FAIL overlapping block"); errors=errors+1; end
            busy<=1; delay_count<=5;
            if(op) begin
                if(result_active) begin $display("FAIL overwrite displayed result"); errors=errors+1; end
                computes=computes+1;
            end else begin
                copies=copies+1;
                if(source != 25'd14000000+offset || dest != expected_angle+offset || !pause) begin
                    $display("FAIL copy page/source/offset"); errors=errors+1;
                end
            end
        end else if(busy) begin
            if(delay_count==0) begin busy<=0; done<=1; end
            else delay_count<=delay_count-1;
        end
    end
    task tick; begin @(negedge clk); end endtask
    task pulse_frame; begin frame=1; tick; frame=0; repeat(2)tick; end endtask
    task pulse_capture; begin capture=1; tick; capture=0; end endtask
    initial begin
        repeat(3)tick; rst_n=1; repeat(2)tick;
        for(k=0;k<4;k=k+1) begin
            expected_angle=23000000+k*1400000;
            pulse_capture; pulse_frame;
            if(pause)begin $display("FAIL froze before settle");errors=errors+1;end
            pulse_frame;
            if(!pause)begin $display("FAIL did not freeze");errors=errors+1;end
            if(k==3)result_active=1;
            pulse_frame;
            wait(!capbusy); repeat(3)tick;
            if(k<3 && angle!=k+1)begin $display("FAIL angle advance");errors=errors+1;end
        end
        repeat(15)tick;
        if(computes!=0 || ready)begin $display("FAIL premature result write");errors=errors+1;end
        result_active=0; wait(ready); repeat(3)tick;
        if(copies!=8 || computes!=2 || pause)begin $display("FAIL group counts");errors=errors+1;end
        // 新组从0°开始；当前块进行中重启也必须等待块排空。
        expected_angle=23000000; pulse_capture; pulse_frame; pulse_frame; pulse_frame;
        wait(busy); restart=1; tick; restart=0; repeat(2)tick;
        if(!pause || ready)begin $display("FAIL aborted an in-flight copy");errors=errors+1;end
        wait(!busy); repeat(5)tick;
        if(pause || capbusy || compbusy || angle!=0)begin $display("FAIL restart recovery");errors=errors+1;end
        valid=0; pulse_capture; pulse_frame; pulse_frame; pulse_frame; repeat(4)tick;
        if(!error || pause || capbusy)begin $display("FAIL invalid frame capture");errors=errors+1;end
        $display("tb_polar_capture %s errors=%0d",errors==0?"PASS":"FAIL",errors); $finish;
    end
    initial begin #100000; $display("FAIL capture timeout");$finish;end
endmodule
