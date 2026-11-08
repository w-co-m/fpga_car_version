`timescale 1ns/1ps
module tb_polar_abort;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0,abort_req=0,op_compute=0,grant=0,rd_valid=0;
    reg [127:0] rd_data=0;
    wire busy,done,error,request,owner_release,rd_en,wr_en,abort_ack,reset_required;
    wire [24:0] addr; wire [127:0] wr_data;
    polar_block_engine dut(.clk(clk),.rst_n(rst_n),.start(start),.op_compute(op_compute),
        .source_addr(25'd1000),.dest_addr(25'd4000),.block_offset(25'd0),
        .busy(busy),.done(done),.error(error),.request(request),.grant(grant),
        .owner_release(owner_release),.ddr_ready(1'b1),.rd_en(rd_en),.wr_en(wr_en),
        .addr(addr),.wr_data(wr_data),.rd_valid(rd_valid),.rd_data(rd_data),
        .abort_req(abort_req),.abort_ack(abort_ack),.reset_required(reset_required));

    integer reads=0,writes=0,timeout=0;
    always @(posedge clk) begin
        if(rd_en) reads<=reads+1;
        if(wr_en) writes<=writes+1;
        if(owner_release) grant<=0;
        else if(request) grant<=1;
        rd_valid<=rd_en;
    end
    task start_job(input integer compute);
        begin @(negedge clk);op_compute=compute;start=1;@(negedge clk);start=0;end
    endtask
    task wait_ack;
        begin timeout=0;while(!abort_ack&&timeout<100)begin @(negedge clk);timeout=timeout+1;end
             if(!abort_ack)$fatal(1,"abort acknowledgement timeout, state=%0d",dut.state);end
    endtask
    reg c_rst_n=0,capture_pulse=0,restart_pulse=0,frame_start=0,good_frame=0;
    reg [1:0] live_page=0; reg [3:0] page_valid=4'hf;
    reg result_source_active=0,block_busy=0,block_done=0,block_error=0;
    reg block_abort_ack=0,block_reset_required=0;
    wire display_pause,capture_busy,compute_busy,ready,cap_error,block_start,block_compute,block_abort_req;
    wire [1:0] angle; wire [24:0] source_addr,dest_addr,block_offset;
    polar_capture_ctrl #(.FRAME_BLOCKS(1),.SETTLE_FRAMES(0)) ctrl(
        .clk(clk),.rst_n(c_rst_n),.capture_pulse(capture_pulse),.restart_pulse(restart_pulse),
        .frame_start(frame_start),.good_frame(good_frame),.live_page(live_page),.page_valid(page_valid),
        .result_source_active(result_source_active),.block_busy(block_busy),.block_done(block_done),
        .block_error(block_error),.block_abort_ack(block_abort_ack),.block_reset_required(block_reset_required),
        .display_pause(display_pause),.angle(angle),.capture_busy(capture_busy),.compute_busy(compute_busy),
        .ready(ready),.error(cap_error),.block_start(block_start),.block_compute(block_compute),
        .block_abort_req(block_abort_req),.source_addr(source_addr),.dest_addr(dest_addr),.block_offset(block_offset));

    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        start_job(0);
        wait(reads==1); @(negedge clk); abort_req=1;
        // Let the already accepted read return; no second read may be issued.
        wait_ack();
        if(reads!=1 || done || busy || writes!=0)begin
            $display("READ ABORT reads=%0d done=%b busy=%b writes=%0d state=%0d ack=%b returned=%0d issued=%0d grant=%b",reads,done,busy,writes,dut.state,abort_ack,dut.read_returned,dut.read_issued,grant);
            $fatal(1,"read abort did not drain only the accepted read");
        end
        @(negedge clk);abort_req=0;repeat(2)@(negedge clk);

        start_job(1);
        wait(dut.state==dut.ST_FEED); @(negedge clk);abort_req=1;
        wait_ack();
        if(writes!=0 || done || reset_required)$fatal(1,"compute abort wrote data or terminalized");
        @(negedge clk);abort_req=0;repeat(2)@(negedge clk);

        start_job(0);
        // Cancel before the first write is accepted.
        wait(dut.state==dut.ST_WRITE_ISSUE); @(negedge clk); abort_req=1;
        wait_ack();
        if(writes!=0 || done)$fatal(1,"pre-write abort was not clean");

        @(negedge clk);abort_req=0;repeat(2)@(negedge clk);
        start_job(0);
        wait(dut.state==dut.ST_WRITE_ISSUE && dut.write_index==dut.write_total-1 && wr_en);
        @(negedge clk); abort_req=1;
        wait_ack();
        if(writes!=3 || done || reset_required)begin
            $display("MID ABORT writes=%0d done=%b reset=%b state=%0d ack=%b read=%0d/%0d verify=%0d/%0d retry=%0d",writes,done,reset_required,dut.state,abort_ack,dut.read_returned,dut.read_issued,dut.verify_returned,dut.verify_issued,dut.verify_attempts);
            $fatal(1,"mid-write abort did not finish and verify the full block");
        end

        @(negedge clk);abort_req=0;repeat(2)@(negedge clk);
        start_job(0);
        timeout=0;while(!done&&timeout<200)begin @(negedge clk);timeout=timeout+1;end
        if(!done || error || reset_required || writes!=6)$fatal(1,"new block did not complete normally after soft cancellation");

        @(negedge clk);start_job(0);
        wait(dut.state==dut.ST_VERIFY_WAIT && dut.verify_returned==dut.write_total-1 && rd_valid);
        @(negedge clk);abort_req=1;wait_ack();
        if(writes!=9 || done || reset_required)$fatal(1,"verify-phase abort did not finish verification safely");
        @(negedge clk);abort_req=0;repeat(2)@(negedge clk);start_job(0);
        timeout=0;while(!done&&timeout<200)begin @(negedge clk);timeout=timeout+1;end
        if(!done || error || reset_required || writes!=12)$fatal(1,"fresh block failed after verify-phase cancellation");
        $display("PASS tb_polar_abort");$finish;
    end
    initial begin
        repeat(3)@(negedge clk);c_rst_n=1;
        @(negedge clk);ctrl.ready=1;ctrl.angle=2;block_busy=1;restart_pulse=1;
        @(negedge clk);restart_pulse=0;
        if(ready||!block_abort_req||!display_pause)$fatal(1,"KEY2 failed to invalidate results and request block abort");
        block_abort_ack=1;@(negedge clk);block_abort_ack=0;
        if(block_abort_req||display_pause||angle!=0||ready||cap_error)$fatal(1,"KEY2 acknowledgement did not reset the whole capture group");

        @(negedge clk);ctrl.state=7;ctrl.angle=3;ctrl.block_index=0;ctrl.ready=0;block_busy=0;
        block_done=1;block_error=1;
        @(negedge clk);block_done=0;block_error=0;
        if(!cap_error||ready||!display_pause||!compute_busy||angle!=3)$fatal(1,"block error lost priority to successful completion");
        @(negedge clk);c_rst_n=0;repeat(2)@(negedge clk);c_rst_n=1;
        @(negedge clk);ctrl.state=7;ctrl.angle=3;ctrl.block_index=0;ctrl.ready=0;
        block_done=1;block_reset_required=1;
        @(negedge clk);block_done=0;block_reset_required=0;
        if(!cap_error||ready||!display_pause||angle!=3)$fatal(1,"reset_required lost priority to successful completion");
        $display("PASS polar_capture_abort_priority");
    end
    initial begin #100000;$fatal(1,"abort regression timeout");end
endmodule
