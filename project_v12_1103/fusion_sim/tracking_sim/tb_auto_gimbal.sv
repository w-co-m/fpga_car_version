`timescale 1ns/1ps
module tb_auto_gimbal;
reg clk=0;always #5 clk=~clk;
reg rst=0,ft=0,key=0,up=0,mode=0,valid=0;
reg [10:0] x=640;reg [9:0] y=360;
wire [15:0] pan,tilt,ipan,itilt;wire arm,live,to;
gimbal_auto_ctrl #(.CLK_HZ(1000000),.STARTUP_CYCLES(0),.TIMEOUT_CYCLES(1000)) d(
 .clk(clk),.rst_n(rst),.frame_tick(ft),.key_press(key),.target_update(up),.mode_e(mode),
 .target_valid(valid),.target_cx(x),.target_cy(y),.manual_tilt_us(16'd1500),
 .pan_us(pan),.tilt_us(tilt),.armed(arm),.target_live(live),.timed_out(to));
gimbal_auto_ctrl #(.CLK_HZ(1000000),.STARTUP_CYCLES(0),.TIMEOUT_CYCLES(1000),
 .PAN_DIR_INVERT(1),.TILT_DIR_INVERT(1)) inv(
 .clk(clk),.rst_n(rst),.frame_tick(ft),.key_press(key),.target_update(up),.mode_e(mode),
 .target_valid(valid),.target_cx(x),.target_cy(y),.manual_tilt_us(16'd1500),
 .pan_us(ipan),.tilt_us(itilt),.armed(),.target_live(),.timed_out());
integer checks=0;
task tick;begin @(negedge clk);@(posedge clk);#1;end endtask
task ck(input bit v,input string m);begin checks++;if(!v)$fatal(1,"%s pan=%d tilt=%d",m,pan,tilt);end endtask
task update;begin up=1;tick;up=0;tick;end endtask
task frame;begin ft=1;tick;ft=0;tick;end endtask
task press;begin key=1;tick;key=0;tick;end endtask
initial begin
 repeat(3)tick;rst=1;tick;mode=1;valid=1;update;frame;
 ck(!arm&&pan==1500,"E starts disarmed");press;frame;
 ck(arm&&pan==1500&&tilt==1500,"center holds both axes");
 x=1000;y=500;update;frame;
 ck(pan==1660&&tilt==1502&&ipan==1340&&itilt==1498,"directions and inverted mounting");
 x=700;y=360;update;frame;ck(pan==1620,"moving hysteresis uses inner threshold");
 x=680;frame;ck(pan==1500,"inside deadband stops");x=700;frame;
 ck(pan==1500,"stopped hysteresis prevents chatter");x=710;frame;ck(pan==1620,"outer threshold starts");
 valid=0;update;tick;ck(pan==1500&&tilt==1502&&arm,"miss stops pan and holds tilt immediately");
 valid=1;x=100;y=0;update;frame;ck(pan==1340&&tilt==1500,"reacquisition follows");
 repeat(100) begin update;frame;end
 ck(tilt==1389&&itilt==1611,"both tilt limits clamp");
 x=1279;y=719;repeat(160)begin update;frame;end
 ck(tilt==1611&&itilt==1389,"opposite tilt limits clamp");
 press;frame;ck(!arm&&pan==1500,"KEY2 stops automatic movement");press;frame;ck(arm&&pan==1660,"KEY2 restarts");
 repeat(1002)tick;ck(to&&!arm&&pan==1500,"snapshot watchdog stops and disarms");
 update;frame;ck(!arm&&pan==1500,"video recovery does not auto-arm");
 press;frame;mode=0;tick;ck(!arm&&pan==1500,"mode exit cancels auto");
 mode=1;update;frame;ck(!arm,"reenter E needs KEY2");
 rst=0;tick;ck(!arm&&pan==1500&&tilt==1500,"reset neutral");
 $display("PASS tb_auto_gimbal checks=%0d errors=0",checks);$finish;
end
endmodule
