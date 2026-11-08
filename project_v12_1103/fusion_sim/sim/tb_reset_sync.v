`timescale 1ns/1ps
// Catch immediate reset release and failure to reset while a clock is stopped.
module tb_reset_sync;
 reg clk=0,run_clock=0,async_n=0;
 wire local_n;
 integer checks=0;
 always #5 if(run_clock)clk=~clk;
 reset_sync dut(.clk(clk),.async_rst_n(async_n),.rst_n(local_n));
 task check;input want;begin #1;if(local_n!==want)$fatal(1,"reset release want=%b got=%b time=%0t",want,local_n,$time);checks=checks+1;end endtask
 initial begin
  #2;check(0);async_n=1;#17;check(0); // no destination clock, no release
  run_clock=1;@(posedge clk);check(0);@(posedge clk);check(1);
  @(negedge clk);run_clock=0;#2;async_n=0;check(0); // async assertion, no clock
  async_n=1;#17;check(0);run_clock=1;
  @(posedge clk);check(0);@(posedge clk);check(1);
  #2;async_n=0;check(0);#1;async_n=1;
  @(posedge clk);check(0);@(posedge clk);check(1);
  $display("PASS tb_reset_sync checks=%0d: stopped clock, async assertion, two-edge release, relock",checks);$finish;
 end
 initial begin #1000;$fatal(1,"reset sync timeout");end
endmodule
