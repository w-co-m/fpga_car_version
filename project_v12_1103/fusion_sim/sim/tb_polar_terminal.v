`timescale 1ns/1ps
module tb_polar_terminal;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0,grant=0,rd_valid=0;
    wire busy,done,error,request,owner_release,rd_en,wr_en,abort_ack,reset_required;
    wire [24:0] addr; wire [127:0] wr_data;
    reg [127:0] rd_data=0;
    polar_block_engine #(.VERIFY_MAX_PASSES(4096),.BLOCK_LIMIT(67108864)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.op_compute(1'b0),
        .source_addr(25'd1000),.dest_addr(25'd4000),.block_offset(25'd0),
        .busy(busy),.done(done),.error(error),.request(request),.grant(grant),
        .owner_release(owner_release),.ddr_ready(1'b1),.rd_en(rd_en),.wr_en(wr_en),
        .addr(addr),.wr_data(wr_data),.rd_valid(rd_valid),.rd_data(rd_data),
        .abort_req(1'b0),.abort_ack(abort_ack),.reset_required(reset_required));
    reg limit_start=0,limit_abort_req=0;
    wire limit_busy,limit_done,limit_error,limit_request,limit_release,limit_rd_en,limit_wr_en;
    wire limit_abort_ack,limit_reset_required;
    wire [24:0] limit_addr; wire [127:0] limit_wr_data;
    polar_block_engine #(.BLOCK_LIMIT(1)) limit_engine(
        .clk(clk),.rst_n(rst_n),.start(limit_start),.op_compute(1'b0),
        .source_addr(25'd1000),.dest_addr(25'd4000),.block_offset(25'd0),
        .busy(limit_busy),.done(limit_done),.error(limit_error),.request(limit_request),.grant(1'b0),
        .owner_release(limit_release),.ddr_ready(1'b1),.rd_en(limit_rd_en),.wr_en(limit_wr_en),
        .addr(limit_addr),.wr_data(limit_wr_data),.rd_valid(1'b0),.rd_data(128'd0),
        .abort_req(limit_abort_req),.abort_ack(limit_abort_ack),.reset_required(limit_reset_required));
    integer cycles=0,reads=0,writes=0;
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(rd_en) reads<=reads+1;
        if(wr_en) writes<=writes+1;
        if(rd_en)rd_data<=(dut.state==8||dut.state==9)?128'h1:128'h0;
        if(owner_release) grant<=0; else if(request) grant<=1;
        rd_valid<=rd_en;
    end
    initial begin
        repeat(3)@(negedge clk);rst_n=1;@(negedge clk);start=1;@(negedge clk);start=0;
        wait(reset_required);
        if(!error || done || !busy || writes!=3 || reads!=12291 || dut.verify_attempts!=4096 || cycles>100000)
            $fatal(1,"verification mismatch did not terminalize after bounded attempts: err=%b done=%b busy=%b writes=%0d reads=%0d cycles=%0d",error,done,busy,writes,reads,cycles);
        @(negedge clk);
        if(!reset_required || !error || !busy || request || rd_en || wr_en)
            $fatal(1,"terminal engine did not remain locked");
        @(negedge clk);limit_start=1;@(negedge clk);limit_start=0;
        wait(limit_busy);@(negedge clk);limit_abort_req=1;wait(limit_abort_ack);
        @(negedge clk);limit_abort_req=0;repeat(2)@(negedge clk);
        limit_start=1;@(negedge clk);limit_start=0;wait(limit_reset_required);
        if(!limit_error||!limit_busy||limit_request||limit_rd_en||limit_wr_en)
            $fatal(1,"BLOCK_LIMIT did not enter a safe terminal lock");
        $display("PASS tb_polar_terminal cycles=%0d",cycles);$finish;
    end
    initial begin #3000000;$display("TERMINAL TIMEOUT state=%0d req=%b grant=%b issued=%0d returned=%0d attempts=%0d error=%b reset=%b",dut.state,request,grant,dut.verify_issued,dut.verify_returned,dut.verify_attempts,error,reset_required);$fatal(1,"terminal regression timeout");end
endmodule
