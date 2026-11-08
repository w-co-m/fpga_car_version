`timescale 1ns/1ps
// Catch VI/VO/backend/serializer consuming input before local reset release.
module PH1P_LOGIC_ODDR(input clk,rst,d0,d1,output reg q);
 always @(posedge clk or negedge clk or posedge rst)
  if(rst)q<=0;else q<=clk?d0:d1;
endmodule
module tb_reset_domains;
 reg camera=0,ddr=0,pixel=0,serial=0;
 reg crun=0,drun=0,prun=0,srun=0,rst_n=0;
 integer cn=0,dn=0,pn=0,sn=0,checks=0;
 always #7 if(crun)camera=~camera;
 always #9 if(drun)ddr=~ddr;
 always #5 if(prun)pixel=~pixel;
 always #1 if(srun)serial=~serial;
 video_in #(.REQUIRE_COMPLETE_FRAME(1),.ENABLE_DISPLAY_PAGE_GUARD(1)) vi(
  .I_rst_n(rst_n),.I_camera_clk(camera),.I_camera_frame_start(1'b0),.I_camera_valid(1'b1),
  .I_camera_data(128'd0),.I_mipi_rx_error(1'b0),.I_ddr_clk(ddr),.I_display_pause(1'b0),
  .I_video_out_rd_busy(1'b0),.I_ddr_user_ready(1'b0),.I_display_page_mask(4'd0));
 video_out #(.ENABLE_UNDERFLOW_GUARD(1),.ENABLE_DISPLAY_PAGE_GUARD(1)) vo(
  .I_rst_n(rst_n),.I_ddr_clk(ddr),.I_video_in_wr_busy(1'b0),.I_video_out_rp(2'd0),
  .I_ddr_user_ready(1'b0),.I_ddr_user_rd_valid(1'b0),.I_ddr_user_rd_data(128'd0),
  .I_dsi_clk(pixel),.I_video_vsync(1'b0),.I_video_rd_en(1'b1),.I_source_base(25'd0),
  .I_source_mode(4'd13),.I_source_is_result(1'b0),.I_source_valid(1'b0));
 polar_video_backend backend(
  .pixel_clk(pixel),.camera_clk(camera),.ddr_clk(ddr),.rst_n(rst_n),.requested_mode(4'd13),
  .capture_pulse(1'b0),.restart_pulse(1'b0),.camera_frame_start(1'b0),.camera_good_frame(1'b0),
  .live_page(2'd0),.page_valid(4'd0),.displayed_mode(4'd0),.displayed_result(1'b0),
  .vo_busy(1'b0),.vo_frame_pending(1'b0),.vo_fill(9'd0),.vo_credit(10'd0),.vo_rd_en(1'b0),.vo_addr(25'd0),
  .vi_busy(1'b0),.vi_wr_en(1'b0),.vi_addr(25'd0),.vi_data(128'd0),
  .calibrated(1'b0),.queue_idle(1'b1),.user_ready(1'b0),.user_rd_valid(1'b0),.user_rd_data(128'd0));
 lane_lvds_10_1 #(.DEVICE("PH1P")) lane(.I_pixel_clk(pixel),.I_serial_clk(serial),.I_rst(~rst_n),.I_data_in(10'b1010101010),.O_serial_out());
 always @(posedge camera)if(rst_n)begin cn=cn+1;#1;
  if(cn<=2 && vi.S_camera_words_seen!==0)$fatal(1,"VI consumed before local reset release edge=%0d seen=%0d",cn,vi.S_camera_words_seen);
  checks=checks+1;end
 always @(posedge ddr)if(rst_n)begin dn=dn+1;#1;
  if(dn<=2 && vo.S_fifo_rst_cnt!==0)$fatal(1,"VO DDR state released early edge=%0d count=%0d",dn,vo.S_fifo_rst_cnt);
  checks=checks+1;end
 always @(posedge pixel)if(rst_n)begin pn=pn+1;#0.2;
  if(pn<=2 && vo.S_fifo_rd_cnt!==0)$fatal(1,"VO pixel state released early edge=%0d",pn);
  if(pn<=2 && backend.u_mode_cdc.payload!==0)$fatal(1,"backend CDC source released early edge=%0d",pn);
  if(pn<=2 && lane.S_odd_even!==0)$fatal(1,"serializer pixel state released early edge=%0d",pn);
  checks=checks+1;end
 initial begin
  #3;rst_n=1;#20;
  if(vi.S_camera_words_seen!==0 || vo.S_fifo_rd_cnt!==0)$fatal(1,"stopped-clock state changed");
  crun=1;drun=1;prun=1;srun=1;
  wait(cn>=5 && dn>=5 && pn>=5);#2;
  if(vi.S_camera_words_seen<2)$fatal(1,"camera did not resume after release");
  if(backend.u_mode_cdc.payload!==13)$fatal(1,"backend did not resume after release");
  @(negedge camera);crun=0;@(negedge pixel);prun=0;@(negedge ddr);drun=0;@(negedge serial);srun=0;
  #0.3;rst_n=0;#1;
  if(vi.S_camera_words_seen!==0 || vo.S_fifo_rst_cnt!==0 || vo.S_fifo_rd_cnt!==0 ||
     backend.u_mode_cdc.payload!==0 || lane.S_odd_even!==0 || lane.S_shift_data!==0)
   $fatal(1,"clock-stopped async reset did not clear states");
  cn=0;dn=0;pn=0;sn=0;rst_n=1;#20;
  crun=1;prun=1;srun=1;#50; // DDR is stopped: cannot release its state.
  if(vo.S_fifo_rst_cnt!==0)$fatal(1,"stopped DDR released");
  drun=1;wait(cn>=5 && dn>=5 && pn>=5);#2;
  $display("PASS tb_reset_domains checks=%0d: VI/VO/backend/serializer local release, stopped DDR, async reassert",checks);$finish;
 end
 initial begin #3000;$fatal(1,"reset domains timeout");end
endmodule
