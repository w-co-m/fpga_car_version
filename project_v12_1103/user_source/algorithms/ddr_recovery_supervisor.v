`timescale 1ns/1ps
// This supervisor survives DDR/PHY clock loss. Only SW0/POR resets its retry budget.
module ddr_recovery_supervisor #(
 parameter integer RESET_CYCLES=50000,
 parameter integer CAL_TIMEOUT_CYCLES=50000000,
 parameter integer HEARTBEAT_TIMEOUT_CYCLES=5000000
)(
 input wire clk,por_n,base_ready,calibrated,ddr_fault,ddr_heartbeat,
 output wire controller_reset_n,clients_reset_n,
 output wire [1:0] status
);
 localparam BOOT=0,CALIBRATE=1,RUN=2,RESTART=3,LOCKED=4;
 localparam RW=(RESET_CYCLES<2)?1:$clog2(RESET_CYCLES);
 localparam CW=(CAL_TIMEOUT_CYCLES<2)?1:$clog2(CAL_TIMEOUT_CYCLES);
 localparam HW=(HEARTBEAT_TIMEOUT_CYCLES<2)?1:$clog2(HEARTBEAT_TIMEOUT_CYCLES);
 reg[2:0]state;
 reg retry_used,heartbeat_seen;
 reg[RW-1:0]reset_count;
 reg[CW-1:0]cal_count;
 reg[HW-1:0]heartbeat_count;
 reg[2:0]cal_high_count,cal_low_count;
 (* async_reg="true" *) reg ready_1,ready_2,cal_1,cal_2,fault_1,fault_2,hb_1,hb_2;
 always @(posedge clk or negedge por_n)
  if(!por_n)begin ready_1<=0;ready_2<=0;cal_1<=0;cal_2<=0;fault_1<=0;fault_2<=0;hb_1<=0;hb_2<=0;end
  else begin
   ready_1<=base_ready;ready_2<=ready_1;cal_1<=calibrated;cal_2<=cal_1;
   fault_1<=ddr_fault;fault_2<=fault_1;hb_1<=ddr_heartbeat;hb_2<=hb_1;
  end
 assign controller_reset_n=por_n && ready_2 && (state==CALIBRATE || state==RUN);
 assign clients_reset_n=controller_reset_n && state==RUN;
 assign status=(state==LOCKED)?2'd2:(state==RUN)?2'd0:2'd1;
 always @(posedge clk or negedge por_n)begin
  if(!por_n)begin
   state<=BOOT;retry_used<=0;reset_count<=0;cal_count<=0;
   heartbeat_count<=0;heartbeat_seen<=0;cal_high_count<=0;cal_low_count<=0;
  end else if(state==LOCKED)begin
   state<=LOCKED;
  end else if(!ready_2)begin
   state<=BOOT;reset_count<=0;cal_count<=0;heartbeat_count<=0;
   cal_high_count<=0;cal_low_count<=0;heartbeat_seen<=hb_2;
  end else begin
   case(state)
    BOOT,RESTART:begin
     cal_count<=0;cal_high_count<=0;cal_low_count<=0;
     heartbeat_count<=0;heartbeat_seen<=hb_2;
     if(reset_count==RESET_CYCLES-1)begin state<=CALIBRATE;reset_count<=0;end
     else reset_count<=reset_count+1'b1;
    end
    CALIBRATE:begin
     heartbeat_seen<=hb_2;heartbeat_count<=0;
     if(cal_2)begin
      if(cal_high_count==3)begin state<=RUN;cal_high_count<=0;cal_low_count<=0;end
      else cal_high_count<=cal_high_count+1'b1;
     end else cal_high_count<=0;
     if(cal_count==CAL_TIMEOUT_CYCLES-1)begin
      cal_high_count<=0;reset_count<=0;
      if(retry_used)state<=LOCKED;
      else begin retry_used<=1;state<=RESTART;end
     end else cal_count<=cal_count+1'b1;
    end
    RUN:begin
     cal_count<=0;
     if(cal_2)cal_low_count<=0;
     else if(cal_low_count!=4)cal_low_count<=cal_low_count+1'b1;
     if(hb_2!=heartbeat_seen)begin heartbeat_seen<=hb_2;heartbeat_count<=0;end
     else if(heartbeat_count!=HEARTBEAT_TIMEOUT_CYCLES-1)heartbeat_count<=heartbeat_count+1'b1;
     if(fault_2 || cal_low_count==3 || heartbeat_count==HEARTBEAT_TIMEOUT_CYCLES-1)begin
      reset_count<=0;cal_high_count<=0;
      if(retry_used)state<=LOCKED;
      else begin retry_used<=1;state<=RESTART;end
     end
    end
    LOCKED:; // Both controller and clients stay reset; HDMI/OSD remain alive.
    default:state<=LOCKED;
   endcase
  end
 end
endmodule
