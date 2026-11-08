`timescale 1ns/1ps
module tb_gimbal_pwm_integration;
reg clk=0;always #5 clk=~clk;
reg rst=0,key_n=1,mode=0,valid=0,heartbeat=1;
reg [10:0] cx=1000;reg [9:0] cy=360;
wire pp,tp,armed,live;reg upd=0;integer cycles=0,checks=0,pc=0,tc=0,pexp=0,texp=0;
reg ppold=0,tpold=0;
gimbal_control_top #(.CLK_HZ(1000000),.DEBOUNCE_CYCLES(3),.STARTUP_CYCLES(0),
 .PAN_TEST_ONLY(0),.AUTO_TIMEOUT_CYCLES(100000)) d(
 .clk(clk),.arst_n(rst),.key2_n(key_n),.target_update(upd),.target_mode_e(mode),
 .target_valid(valid),.target_cx(cx),.target_cy(cy),.auto_armed(armed),.auto_live(live),
 .O_servo_pan_pwm(pp),.O_servo_tilt_pwm(tp));
always @(negedge clk)begin cycles++;upd=heartbeat&&(cycles%10000==0);end
always @(posedge clk)begin
 #1;
 if(!rst)begin pc=0;tc=0;ppold=0;tpold=0;end
 else begin
  if(pp&&!ppold)begin pc=0;pexp=d.u_pwm.pan_latched;end
  if(tp&&!tpold)begin tc=0;texp=d.u_pwm.tilt_latched;end
  if(pp)pc++;if(tp)tc++;
  if(!pp&&ppold)begin checks++;if(pc!=pexp)$fatal(1,"pan truncated/glitched: %d expected %d",pc,pexp);end
  if(!tp&&tpold)begin checks++;if(tc!=texp)$fatal(1,"tilt truncated/glitched: %d expected %d",tc,texp);end
  ppold=pp;tpold=tp;
 end
end
task waitcl(input integer n);begin repeat(n)@(negedge clk);end endtask
task key;begin key_n=0;waitcl(12);key_n=1;waitcl(12);end endtask
task ck(input bit v,input string s);begin checks++;if(!v)$fatal(1,"%s",s);end endtask
initial begin
 waitcl(10);rst=1;waitcl(50);key;waitcl(500000);
 ck(d.manual_tilt_us==1389,"manual tilt-low step retained");
 key;waitcl(1000000);ck(d.manual_tilt_us==1611,"manual tilt-high step retained");
 key;waitcl(500000);ck(d.manual_tilt_us==1500,"manual home retained");
 key;waitcl(25000);ck(d.manual_pan_us==1732,"manual vendor-map pan retained");
 mode=1;valid=1;waitcl(25000);ck(!armed&&d.pan_us==1500,"enter E cancels manual jog");
 key;waitcl(45000);ck(armed&&d.u_pwm.pan_latched==1660,"automatic command reaches real PWM");
 // Invalidate in the middle of a pulse. It must still complete at its old width.
 @(posedge pp);waitcl(100);valid=0;waitcl(25000);
 ck(d.u_pwm.pan_latched==1500&&armed,"miss neutralizes next complete PWM");
 valid=1;cx=100;waitcl(45000);ck(d.u_pwm.pan_latched==1340,"automatic reverse PWM");
 heartbeat=0;waitcl(130000);ck(!armed&&d.u_pwm.pan_latched==1500,"video watchdog reaches PWM");
 heartbeat=1;waitcl(25000);ck(!armed,"watchdog recovery stays disarmed");
 key;waitcl(25000);mode=0;waitcl(45000);
 ck(!armed&&d.u_pwm.pan_latched==1500,"leaving E clears auto and stale manual jog");
 $display("PASS tb_gimbal_pwm_integration checks=%0d errors=0",checks);$finish;
end
initial begin #30000000;$fatal(1,"integration timeout");end
endmodule
