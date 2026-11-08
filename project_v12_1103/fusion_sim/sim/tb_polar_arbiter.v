`timescale 1ns/1ps
module tb_polar_arbiter;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,cal=0,idle=1,ready=1,rv=0;
    reg vb=0,vwe=0,ob=0,ore=0,pending=0;
    reg [8:0] fill=0;reg [9:0] credit=0;
    reg req=0,rel=0,bre=0,bwe=0;
    wire grant,lr,br,vr,bvr,we,re;wire[24:0]addr;wire[127:0]data,ret;
    integer errors=0;
    polar_ddr_arbiter dut(.clk(clk),.rst_n(rst_n),.calibrated(cal),.queue_idle(idle),.user_ready(ready),.rd_valid(rv),.rd_data(128'h1234),
        .vi_busy(vb),.vi_wr_en(vwe),.vi_addr(25'd8),.vi_data(128'h55),.vo_busy(ob),.vo_rd_en(ore),.vo_frame_pending(pending),.vo_fill(fill),.vo_credit(credit),.vo_addr(25'd16),
        .bg_request(req),.bg_release(rel),.bg_rd_en(bre),.bg_wr_en(bwe),.bg_addr(25'd24),.bg_data(128'h66),.bg_grant(grant),.live_ready(lr),.bg_ready(br),
        .vo_return_valid(vr),.bg_return_valid(bvr),.return_data(ret),.wr_en(we),.rd_en(re),.addr(addr),.wr_data(data));
    task tick; begin @(negedge clk);end endtask
    task no_grant;begin repeat(2)tick;if(grant)begin $display("FAIL unsafe grant");errors=errors+1;end end endtask
    initial begin
        repeat(3)tick;rst_n=1;req=1;fill=400;no_grant;cal=1;fill=100;no_grant;
        fill=400;credit=1;rv=1;no_grant;
        credit=0;rv=0;vb=1;no_grant;vb=0;ob=1;no_grant;ob=0;idle=0;no_grant;idle=1;
        wait(grant);tick;
        if(lr || !br)begin $display("FAIL ready owner");errors=errors+1;end
        bre=1;tick;bre=0;rel=1;req=0;tick;rel=0;repeat(3)tick;
        if(!grant)begin $display("FAIL abandoned outstanding read");errors=errors+1;end
        rv=1;#1;if(!bvr || vr)begin $display("FAIL wrong return owner");errors=errors+1;end
        tick;rv=0;idle=0;repeat(3)tick;
        if(!grant)begin $display("FAIL ignored command queue");errors=errors+1;end
        idle=1;wait(!grant);tick;rv=1;#1;
        if(bvr || !vr)begin $display("FAIL live return route");errors=errors+1;end
        rv=0;ore=1;#1;if(!re || addr!=16)errors=errors+1;ore=0;vwe=1;#1;if(!we || addr!=8 || data!=128'h55)errors=errors+1;
        $display("tb_polar_arbiter %s errors=%0d",errors==0?"PASS":"FAIL",errors);$finish;
    end
    initial begin #100000;$display("FAIL arbiter timeout");$finish;end
endmodule
