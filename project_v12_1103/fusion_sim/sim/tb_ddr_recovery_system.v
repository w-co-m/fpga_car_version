`timescale 1ns/1ps
// Untagged controller responses survive a CLIENT reset. Only a controller reset
// flushes the model's queue, mirroring the hard-recovery boundary.
module tb_ddr_recovery_system;
 reg sc=0,dc=0,pc=0,ddr_running=1;
 always #10 sc=~sc;
 always #7.5 if(ddr_running)dc=~dc;
 always #6.667 pc=~pc;
 reg por_n=0,cal=0,hold_returns=0,camera_on=1;
 wire ctrl_n,clients_n;wire[1:0]status;
 wire data_rst_n=por_n && clients_n;
 reg[3:0]hb_count=0;reg hb=0;
 always @(posedge dc or negedge data_rst_n)
  if(!data_rst_n)begin hb_count<=0;hb<=0;end
  else begin hb_count<=hb_count+1'b1;if(hb_count==3)begin hb_count<=0;hb<=~hb;end end
 wire arb_fault,mc_fault;
 ddr_recovery_supervisor #(.RESET_CYCLES(5),.CAL_TIMEOUT_CYCLES(100),.HEARTBEAT_TIMEOUT_CYCLES(50)) supervisor(
  .clk(sc),.por_n(por_n),.base_ready(1'b1),.calibrated(cal),.ddr_fault(arb_fault|mc_fault),.ddr_heartbeat(hb),
  .controller_reset_n(ctrl_n),.clients_reset_n(clients_n),.status(status));
 integer vtc_count=0;
 always @(posedge pc)if(!por_n)vtc_count<=0;else if(vtc_count==255)vtc_count<=0;else vtc_count<=vtc_count+1;
 wire vs=(vtc_count<4),de=(vtc_count>=100 && vtc_count<132),user=(vtc_count==100),last=(vtc_count==131);
 wire pread,busy,pending,uf;wire[8:0]fill;wire[9:0]credit;wire[23:0]raw,mrgb,rgb;
 wire mde,mhs,mvs,ode,ohs,ovs,fv;wire[3:0]mode;
 wire vr,live_ready,vo_ret,user_we,user_re,user_ready,queue_idle,ret;
 wire[24:0]va,ua,app_addr;wire[127:0]udata,retdata,app_wdata;
 wire app_en,app_wren;wire[2:0]app_cmd;
 integer dc_count=0;always @(posedge dc)dc_count<=dc_count+1;
 wire vi_we=camera_on && !busy && live_ready && dc_count%4==0;
 polar_ddr_arbiter #(.STALL_LIMIT(32)) arb(
  .clk(dc),.rst_n(data_rst_n),.calibrated(cal),.queue_idle(queue_idle),.user_ready(user_ready),.rd_valid(ret),.rd_data(retdata),
  .vi_busy(vi_we),.vi_wr_en(vi_we),.vi_addr(25'd1000000),.vi_data(128'd0),
  .vo_busy(busy),.vo_rd_en(vr),.vo_frame_pending(pending),.vo_fill(fill),.vo_credit(credit),.vo_addr(va),
  .bg_request(1'b0),.bg_release(1'b0),.bg_rd_en(1'b0),.bg_wr_en(1'b0),.bg_addr(25'd0),.bg_data(128'd0),
  .bg_grant(),.live_ready(live_ready),.bg_ready(),.vo_return_valid(vo_ret),.bg_return_valid(),.return_data(),
  .wr_en(user_we),.rd_en(user_re),.addr(ua),.wr_data(udata),.reset_required(arb_fault));
 video_out #(.USE_EXTERNAL_SOURCE(1),.FRAME_WORDS(6),.BURST_WORDS(3),.ENABLE_DISPLAY_PAGE_GUARD(1),
  .ENABLE_UNDERFLOW_GUARD(1),.ENABLE_FRAME_TRANSACTION(1)) vo(
  .I_rst_n(data_rst_n),.I_ddr_clk(dc),.O_video_out_rd_busy(busy),.I_video_in_wr_busy(vi_we),.I_video_out_rp(2'd0),
  .O_ddr_user_rd_en(vr),.O_ddr_user_addr(va),.I_ddr_user_ready(live_ready),.I_ddr_user_rd_valid(vo_ret),.I_ddr_user_rd_data(retdata),
  .I_dsi_clk(pc),.I_video_vsync(vs),.I_video_rd_en(pread),.O_vdieo_data(raw),
  .I_source_base(25'd0),.I_source_mode(4'd0),.I_source_is_result(1'b0),.I_source_valid(clients_n),
  .O_frame_mode(),.O_result_source_active(),.O_fifo_fill(fill),.O_read_credit(credit),.O_frame_pending(pending),
  .O_underflow(uf),.O_display_page_mask(),.O_pixel_mode(mode),.O_pixel_frame_valid(fv),.O_pixel_result_active());
 reg arvalid=0;reg[127:0]ardata=0;
 mc_to_user_interface #(.STALL_LIMIT(64)) mc(
  .I_clk(dc),.I_rst_n(data_rst_n),.I_ddr_user_wr_en(user_we),.I_ddr_user_rd_en(user_re),.I_ddr_user_addr(ua),.I_ddr_user_wr_data(udata),
  .O_ddr_user_ready(user_ready),.O_queue_idle(queue_idle),.O_ddr_user_rd_valid(ret),.O_ddr_user_rd_data(retdata),
  .O_mc_app_en(app_en),.O_mc_app_addr(app_addr),.O_mc_app_cmd(app_cmd),.I_mc_app_rdy(1'b1),
  .O_mc_app_wdf_wren(app_wren),.O_mc_app_wdf_data(app_wdata),.O_mc_app_wdf_end(),.O_mc_app_wdf_mask(),
  .I_mc_app_wdf_rdy(1'b1),.I_mc_app_rd_data(ardata),.I_mc_app_rd_data_end(1'b1),.I_mc_app_rd_data_valid(arvalid),.reset_required(mc_fault));
 hdmi_mixer #(.IMG_WIDTH(32),.IMG_HEIGHT(1)) mixer(
  .I_clk(pc),.I_rst_n(por_n),.I_video_vsync(vs),.I_video_hsync(1'b0),.I_video_de(de),.I_video_user(user),.I_video_last(last),
  .I_debug_status(4'd0),.O_video_rd_en(pread),.I_video_rd_data(raw),.O_hdmi_vsync(mvs),.O_hdmi_hsync(mhs),.O_hdmi_de(mde),.O_hdmi_data(mrgb));
 reg[2:0]valid_pipe=0;
 always @(posedge pc)valid_pipe<={valid_pipe[1:0],fv && clients_n};
 video_algorithm_display #(.IMG_WIDTH(32),.IMG_HEIGHT(1),.EXTERNAL_RENDER_MODE(1),.ENABLE_FRAME_GUARD(1)) display(
  .clk(pc),.rst_n(por_n),.key0_n(1'b1),.key1_n(1'b1),.threshold_edit(1'b0),.rgb_in(mrgb),.de_in(mde),.hs_in(mhs),.vs_in(mvs),
  .rgb_out(rgb),.de_out(ode),.hs_out(ohs),.vs_out(ovs),.render_mode_in(mode),.frame_valid_in(valid_pipe[2]),.bank_run(clients_n));
 integer qwr=0,qrd=0,cal_count=0,total_writes=0,old_packets=0,good_pixels=0,recovery_pixels=0;
 wire model_reset_n=$test$plusargs("LOCAL_RESET_ONLY") ? por_n : ctrl_n;
 always @(posedge dc or negedge model_reset_n)begin
  if(!model_reset_n)begin qwr=0;qrd=0;cal<=0;cal_count=0;arvalid<=0;ardata<=0;end
  else begin
   if(cal_count<4)cal_count=cal_count+1;else cal<=1;
   arvalid<=0;
   if(app_en && app_cmd==1)qwr=qwr+1;
   if(app_wren)total_writes=total_writes+1;
   if(!hold_returns && qrd<qwr)begin arvalid<=1;ardata<={16{8'h80}};qrd=qrd+1;end
  end
 end
 always @(negedge pc)if(por_n && ode)begin
  if(rgb!==24'd0 && rgb!==24'h808080)$fatal(1,"stale/misaligned recovery pixel %h",rgb);
  if(rgb==24'h808080 && clients_n)good_pixels=good_pixels+1;
  if(!clients_n)recovery_pixels=recovery_pixels+1;
 end
 initial begin
  #100;por_n=1;wait(good_pixels>=32);
  hold_returns=1;wait(credit>0);old_packets=credit;wait(!ctrl_n);#1;
  if(clients_n || status!=1 || qwr!=0 || qrd!=0 || arvalid)$fatal(1,"controller boundary failed to flush in-flight packets");
  hold_returns=0;wait(clients_n);good_pixels=0;wait(good_pixels>=32);
  if(total_writes==0 || old_packets==0)$fatal(1,"test did not cover VI traffic and outstanding VO reads");
  // Now lose the DDR clock while calibrated stays high: sys supervisor must lock.
  @(negedge dc);ddr_running=0;wait(status==2);#1;
  if(ctrl_n || clients_n)$fatal(1,"second hard fault did not lock reset boundary");
  #5000;
  if(recovery_pixels==0)$fatal(1,"HDMI DE disappeared during DDR recovery");
  $display("PASS tb_ddr_recovery_system untagged flush, VI traffic, image recovery, HDMI alive, dead-clock lock");$finish;
 end
 initial begin #200000;$display("status=%d ctrl=%b clients=%b arb=%b mc=%b credit=%0d cal=%b good=%0d writes=%0d q=%0d/%0d",status,ctrl_n,clients_n,arb_fault,mc_fault,credit,cal,good_pixels,total_writes,qrd,qwr);$fatal(1,"system recovery timeout");end
endmodule
