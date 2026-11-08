`timescale 1ns/1ps
module tb_ddr_recovery;
 reg clk=0; always #10 clk=~clk;
 reg por_n=0,base_ready=1,calibrated=0,fault=0,heartbeat=0;
 wire ctrl_n,clients_n; wire[1:0]status;
 integer i;
 ddr_recovery_supervisor #(.RESET_CYCLES(5),.CAL_TIMEOUT_CYCLES(50),
  .HEARTBEAT_TIMEOUT_CYCLES(20)) dut(
  .clk(clk),.por_n(por_n),.base_ready(base_ready),.calibrated(calibrated),
  .ddr_fault(fault),.ddr_heartbeat(heartbeat),
  .controller_reset_n(ctrl_n),.clients_reset_n(clients_n),.status(status));
 task tick;begin @(posedge clk);#1;end endtask
 task boot;begin
  por_n=0;calibrated=0;fault=0;repeat(3)tick;por_n=1;
  wait(ctrl_n);repeat(4)tick;
  if(clients_n)$fatal(1,"clients released before calibration");
  calibrated=1;wait(clients_n);tick;
  if(status!=0)$fatal(1,"RUN status missing");
 end endtask
 initial begin
  boot;
  fault=1;wait(!ctrl_n);fault=0;calibrated=0;
  if(clients_n || status!=1)$fatal(1,"fault did not reset all DDR clients");
  wait(ctrl_n);calibrated=1;wait(clients_n);
  fault=1;wait(status==2);tick;
  if(ctrl_n||clients_n)$fatal(1,"second fault must lock both resets");
  boot;
  // A stopped DDR clock can leave calibrated HIGH. No heartbeat still faults.
  wait(!ctrl_n);calibrated=0;wait(ctrl_n);
  // Automatic recovery which cannot calibrate locks instead of reboot looping.
  wait(status==2);repeat(10)tick;
  if(ctrl_n||clients_n)$fatal(1,"calibration timeout not locked");
  boot;
  for(i=0;i<80;i=i+1)begin heartbeat=~heartbeat;repeat(5)tick;end
  if(status!=0 || !clients_n)$fatal(1,"live heartbeat spuriously reset");
  $display("PASS tb_ddr_recovery one retry, calibration, dead DDR clock, stable run");$finish;
 end
 initial begin #100000;$fatal(1,"recovery timeout");end
endmodule
