`timescale 1ns/1ps
module tb_fusion_tracking;
reg pc=0,cc=0,rst=0;always #6.667 pc=~pc;always #5 cc=~cc;
reg [23:0] rgb=0;reg de=0,vs=0,hs=0,k2=1,frame_valid=1,bank_run=1,cam_good=0;
reg [1:0] keys=3;
wire [3:0] mode;wire upd,tvalid;wire [4:0] lost;
wire [6:0] x0,x1,y0,y1;wire [7:0] xs={1'b0,x0}+{1'b0,x1},ys={1'b0,y0}+{1'b0,y1};
wire du,dm,dv,armed,live,camera_alive;wire [6:0] cx,cy;wire pp,tp;
video_algorithm_display #(.IMG_WIDTH(128),.IMG_HEIGHT(72),.DEBOUNCE_CYCLES(1),.ENABLE_FRAME_GUARD(1)) app(
 .clk(pc),.rst_n(rst),.key0_n(keys[0]),.key1_n(keys[1]),.threshold_edit(1'b0),
 .frame_valid_in(frame_valid),.bank_run(bank_run),.render_mode_in(4'd0),
 .mode_active(mode),.mode_pending_out(),.polar_capture_pulse(),.polar_restart_pulse(),
 .bin_threshold_active(),.edge_threshold_active(),.bright_gain_active(),.contrast_gain_active(),
 .motion_threshold_active(),.threshold_edit_active(),.rgb_in(rgb),.de_in(de),.hs_in(hs),.vs_in(vs),
 .rgb_out(),.de_out(),.hs_out(),.vs_out(),.trk_update(upd),.trk_valid(tvalid),.trk_lost_cnt(lost),
 .trk_x_min(x0),.trk_x_max(x1),.trk_y_min(y0),.trk_y_max(y1));
track_target_cdc #(.XW(7),.YW(7)) cdc(
 .arst_n(rst),.src_clk(pc),.dst_clk(cc),.src_send(upd),.src_mode_e(mode==15),
 .src_valid(tvalid&&lost==0&&frame_valid&&bank_run),.src_cx(xs[7:1]),.src_cy(ys[7:1]),
 .dst_update(du),.dst_mode_e(dm),.dst_valid(dv),.dst_cx(cx),.dst_cy(cy));
camera_activity_watchdog #(.CLK_HZ(1000000),.TIMEOUT_MS(200)) camera_wd(
 .arst_n(rst),.camera_clk(pc),.camera_good_frame(cam_good),.ctrl_clk(cc),.camera_alive(camera_alive));
gimbal_control_top #(.CLK_HZ(1000000),.DEBOUNCE_CYCLES(1),.STARTUP_CYCLES(0),.PAN_TEST_ONLY(0),
 .AUTO_IMAGE_W(128),.AUTO_IMAGE_H(72),.AUTO_PAN_DEADBAND(8),.AUTO_PAN_HYST(2),
 .AUTO_PAN_FAR_PIX(32),.AUTO_TILT_DEADBAND(4),.AUTO_TIMEOUT_CYCLES(1000000)) g(
 .clk(cc),.arst_n(rst),.key2_n(k2),.target_update(du),.target_mode_e(dm),.target_valid(dv&&camera_alive),
 .target_cx(cx),.target_cy(cy),.auto_armed(armed),.auto_live(live),.O_servo_pan_pwm(pp),.O_servo_tilt_pwm(tp));
integer i,x,y,checks=0,updates=0;
always @(posedge pc)begin #1;if(upd)updates++;end
task pix(input bit d,input bit v,input [23:0] color);
 begin @(negedge pc);de=d;vs=v;rgb=color;@(posedge pc);#1;end
endtask
task boundary;begin repeat(8)pix(0,1,0);repeat(30)pix(0,0,0);end endtask
task picture(input bit target,input bit camera_event=1);
 begin
  for(y=0;y<72;y++)begin
   for(x=0;x<128;x++)pix(1,0,(target&&x>=96&&x<=111&&y>=48&&y<=63)?24'hff0000:24'h202020);
   repeat(80)pix(0,0,0);
  end
  cam_good=camera_event;pix(0,0,0);cam_good=0;boundary;
 end
endtask
task ck(input bit b,input string s);begin checks++;if(!b)$fatal(1,"%s",s);end endtask
task keypress(input integer index);begin keys[index]=0;repeat(10)pix(0,0,0);keys[index]=1;repeat(10)pix(0,0,0);end endtask
initial begin
 repeat(5)pix(0,0,0);rst=1;repeat(300)pix(0,0,0);boundary;
 keypress(0);ck(mode==0,"mode waits for frame boundary");boundary;
 ck(mode==15,"B9 previous from RAW enters F TRACK");
 picture(1);picture(1);repeat(30)pix(0,0,0);
 ck(dm&&dv&&cx==103&&cy==55,"CCL+tracker+CDC coherent target");
 ck(!armed&&g.pan_us==1500,"F entry is disarmed");
 k2=0;repeat(10)pix(0,0,0);k2=1;
 repeat(45000)@(negedge cc);
 ck(armed&&g.u_pwm.pan_latched==1660&&g.tilt_us>1500,"both axes follow actual image target");
 picture(0);repeat(30)pix(0,0,0);
 ck(app.u_bank.u_color_detect.bbox_valid&&!app.u_bank.u_color_detect.bbox_fresh,"D display holds without new measurement");
 ck(tvalid&&lost==1&&!dv,"first miss immediately invalidates steering while F holds box");
 repeat(25000)@(negedge cc);ck(g.u_pwm.pan_latched==1500,"held rectangle cannot drive pan");
 picture(1);repeat(45000)@(negedge cc);ck(live&&g.u_pwm.pan_latched==1660,"nearby target reacquired");
 frame_valid=0;boundary;repeat(25000)@(negedge cc);
 ck(!dv&&!live&&g.u_pwm.pan_latched==1500,"invalid DDR frame inhibits steering");
 frame_valid=1;picture(1);picture(1);repeat(25000)@(negedge cc);
 ck(live,"valid stream resumes");
 // Repeated target pixels/HDMI frames are not camera progress.
 for(i=0;i<12;i++)picture(1,0);
 repeat(25000)@(negedge cc);
 ck(!camera_alive&&!live&&g.u_pwm.pan_latched==1500,"frozen camera stops despite repeated target images");
 picture(1);repeat(25000)@(negedge cc);ck(camera_alive&&live,"good camera frame clears stale-image inhibit");
 keypress(1);boundary;repeat(25000)@(negedge cc);
 ck(mode==0&&!dm&&!armed&&g.u_pwm.pan_latched==1500,"leaving F cancels auto and stops");
 keypress(0);boundary;ck(mode==15&&!armed,"reentry requires explicit arming");
 $display("PASS tb_fusion_tracking checks=%0d updates=%0d errors=0",checks,updates);$finish;
end
initial begin #15000000;$fatal(1,"fusion link timeout");end
endmodule
