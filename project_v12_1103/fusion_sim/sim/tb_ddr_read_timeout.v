`timescale 1ns/1ps
module tb_ddr_read_timeout;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,vi_wr=0,rd_valid=0,bg_request=0,bg_rd=0;
 reg[9:0]vo_credit=0;
 wire fault,grant,re,we;
 polar_ddr_arbiter #(.STALL_LIMIT(16)) dut(
  .clk(clk),.rst_n(rst_n),.calibrated(1'b1),.queue_idle(1'b1),.user_ready(1'b1),
  .rd_valid(rd_valid),.rd_data(128'd0),.vi_busy(vi_wr),.vi_wr_en(vi_wr),.vi_addr(25'd0),.vi_data(128'd0),
  .vo_busy(1'b0),.vo_rd_en(1'b0),.vo_frame_pending(1'b0),.vo_fill(9'd400),.vo_credit(vo_credit),.vo_addr(25'd0),
  .bg_request(bg_request),.bg_release(1'b0),.bg_rd_en(bg_rd),.bg_wr_en(1'b0),.bg_addr(25'd0),.bg_data(128'd0),
  .bg_grant(grant),.live_ready(),.bg_ready(),.vo_return_valid(),.bg_return_valid(),.return_data(),
  .wr_en(we),.rd_en(re),.addr(),.wr_data(),.reset_required(fault));
 task tick;begin @(negedge clk);end endtask
 initial begin
  repeat(3)tick;rst_n=1;vo_credit=1;vi_wr=1;
  repeat(20)tick;
  if(!fault || re || we)$fatal(1,"VI writes masked missing VO response");
  rst_n=0;vi_wr=0;vo_credit=0;repeat(3)tick;rst_n=1;bg_request=1;
  wait(grant);tick;bg_rd=1;tick;bg_rd=0;repeat(20)tick;
  if(!fault || !grant || dut.bg_credit!=1)$fatal(1,"BG timeout prematurely released ownership");
  $display("PASS tb_ddr_read_timeout independent VO/BG timers, quarantined ownership");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
