`timescale 1ns/1ps
module tb_review_io_guard;
 reg cam=0,ddr=0; always #5 cam=~cam; always #7 ddr=~ddr;
 reg rst_n=0,fs=0,valid=0; reg [127:0] data=0; reg ready=1;
 wire busy,we,frame_ddr,good; wire[1:0] rp;wire[24:0] addr;wire[127:0] wdata;wire[3:0] page_valid;
 integer accepted=0, writes=0, checked_writes=0, check_content=0, good_frames=0, bad_published=0, i;
 video_in #(.FRAME_WORDS(4),.BURST_WORDS(2),.REQUIRE_COMPLETE_FRAME(1),.ENABLE_DISPLAY_PAGE_GUARD(1)) dut(
 .I_rst_n(rst_n),.I_camera_clk(cam),.I_camera_frame_start(fs),.I_camera_valid(valid),.I_camera_data(data),.I_mipi_rx_error(1'b0),
 .I_ddr_clk(ddr),.I_display_pause(1'b0),.I_video_out_rd_busy(1'b0),.O_video_in_wr_busy(busy),.O_video_out_rp(rp),
 .O_ddr_user_wr_en(we),.O_ddr_user_addr(addr),.O_ddr_user_wr_data(wdata),.I_ddr_user_ready(ready),.O_frame_start_ddr(frame_ddr),
 .O_page_valid(page_valid),.I_display_page_mask(4'b0000),.O_good_frame_ddr(good));
 always @(posedge cam) if(rst_n && dut.S_camera_accept) accepted=accepted+1;
 always @(posedge ddr) if(rst_n && we) begin
  writes=writes+1;
  if(check_content) begin
   if(wdata!==128'hA000+(checked_writes%4)) $fatal(1,"clean-page data index %0d got=%h",checked_writes%4,wdata);
   checked_writes=checked_writes+1;
  end
 end
 always @(posedge ddr) if(rst_n && good) good_frames=good_frames+1;
 task pulse_fs; begin @(negedge cam);fs=1;@(negedge cam);fs=0; end endtask
 task pixel(input [127:0] v); begin @(negedge cam);valid=1;data=v;@(negedge cam);valid=0; end endtask
 task wait_flush; begin repeat(24)@(negedge cam); end endtask
 task good_frame; integer n; begin
   pulse_fs();wait_flush();check_content=1;
   for(n=0;n<4;n=n+1) pixel(128'hA000+n);
   repeat(24)@(negedge cam);
   pulse_fs();wait_flush();repeat(20)@(negedge ddr);check_content=0;
 end endtask
 initial begin
  repeat(6)@(negedge cam);rst_n=1;repeat(12)@(negedge cam);
  // A valid beat coincident with SOF arrives during the FIFO reset window;
  // it must poison this frame instead of publishing a short shifted page.
  @(negedge cam);fs=1;valid=1;data=128'hDEAD;@(negedge cam);
  if(!dut.S_camera_bad) $fatal(1,"SOF-coincident data was silently discarded without poisoning its frame");
  fs=0;valid=0;wait_flush();
  pixel(128'hA000);pixel(128'hA001);pixel(128'hA002);pixel(128'hA003);repeat(8)@(negedge cam);
  pulse_fs();wait_flush();repeat(20)@(negedge ddr);
  if(good_frames!=0 || page_valid!=0) $fatal(1,"same-edge early data frame was published good=%0d pages=%b",good_frames,page_valid);
  // A clean frame after the rejected one must be published with exact data.
  good_frame();
  if(good_frames!=1 || page_valid==0 || checked_writes!=4) $fatal(1,"clean recovery failed good=%0d pages=%b writes=%0d",good_frames,page_valid,checked_writes);
  // A frame with FIFO-full overflow is invalid as a whole and cannot publish.
  ready=0; pulse_fs();wait_flush();
  for(i=0;i<12;i=i+1)pixel(128'hB000+i);
  ready=1;repeat(20)@(negedge ddr);pulse_fs();wait_flush();repeat(20)@(negedge ddr);
  if(good_frames!=1) $fatal(1,"overflow frame published good=%0d",good_frames);
  good_frame();
  if(good_frames!=2 || checked_writes!=8) $fatal(1,"second clean recovery failed good=%0d writes=%0d",good_frames,checked_writes);
  $display("PASS tb_review_io_guard accepted=%0d writes=%0d good=%0d",accepted,checked_writes,good_frames);$finish;
 end
 initial begin #1000000;$fatal(1,"tb_review_io_guard timeout");end
endmodule

module tb_mc_watchdog;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,wr=0,rd=0,app_rdy=0,wdf_rdy=0,rd_valid=0;
 reg [24:0] addr=25'h123;reg[127:0] wdata=128'h12345678;reg[127:0] retdata=0;
 wire user_ready,idle,rv,en,wren,wend,reset_required;wire[24:0] app_addr;wire[2:0] cmd;wire[127:0] wd,rd_data;wire[15:0] mask;
 integer i;
 mc_to_user_interface #(.STALL_LIMIT(16)) dut(.I_clk(clk),.I_rst_n(rst_n),.I_ddr_user_wr_en(wr),.I_ddr_user_rd_en(rd),
 .I_ddr_user_addr(addr),.I_ddr_user_wr_data(wdata),.O_ddr_user_ready(user_ready),.O_queue_idle(idle),.O_ddr_user_rd_valid(rv),.O_ddr_user_rd_data(rd_data),
 .O_mc_app_en(en),.O_mc_app_addr(app_addr),.O_mc_app_cmd(cmd),.I_mc_app_rdy(app_rdy),.O_mc_app_wdf_wren(wren),.O_mc_app_wdf_data(wd),
 .O_mc_app_wdf_end(wend),.O_mc_app_wdf_mask(mask),.I_mc_app_wdf_rdy(wdf_rdy),.I_mc_app_rd_data(retdata),
 .I_mc_app_rd_data_end(rd_valid),.I_mc_app_rd_data_valid(rd_valid),.reset_required(reset_required));
 task user_write;begin @(negedge clk);wr=1;@(negedge clk);wr=0;end endtask
 task reset_dut;begin rst_n=0;repeat(4)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);end endtask
 initial begin
  reset_dut(); user_write();
  wait(en);@(negedge clk);app_rdy=1;@(negedge clk);app_rdy=0;
  if(!wren || en) $fatal(1,"AW/W split handshake state incorrect en=%b wren=%b empty=%b addr_done=%b",en,wren,dut.S_fifo_empty,dut.S_addr_accepted);
  repeat(5)@(negedge clk);wdf_rdy=1;@(negedge clk);wdf_rdy=0;repeat(3)@(negedge clk);
  if(reset_required || !idle || mask!==16'd0 || dut.STALL_COUNT_WIDTH!=4) $fatal(1,"separated AW/W handshake, 16-bit mask, or counter width failed");
  // Simultaneous read+write is a protocol fault and must enqueue neither.
  @(negedge clk);wr=1;rd=1;@(negedge clk);wr=0;rd=0;repeat(2)@(negedge clk);
  if(!reset_required || en || wren) $fatal(1,"simultaneous read/write was not sticky-faulted");
  reset_dut();
  // Fault and the current head's final handshakes share an edge. The next
  // queued head has never asserted VALID and must remain quarantined.
  addr=25'd100;user_write();addr=25'd200;user_write();
  @(negedge clk);app_rdy=1;wdf_rdy=1;wr=1;rd=1;
  @(negedge clk);app_rdy=0;wdf_rdy=0;wr=0;rd=0;repeat(2)@(negedge clk);
  if(!reset_required || en || wren || app_addr!==25'd100)
    $fatal(1,"fault on head completion exposed an unpresented next command");
  reset_dut();
  // Command head stalls on W; return traffic must not mask its deadline.
  user_write();
  for(i=0;i<20;i=i+1)begin @(negedge clk);rd_valid=1;retdata=i;end
  rd_valid=0;
  if(!reset_required) $fatal(1,"command head timeout was masked by unrelated read activity");
  if(!en || !wren || user_ready || app_addr!==addr || wd!==wdata)
    $fatal(1,"fault withdrew or changed the pending AW/W VALID payload");
  @(negedge clk);app_rdy=1;@(negedge clk);app_rdy=0;
  if(en || !wren || !reset_required || app_addr!==addr || wd!==wdata)
    $fatal(1,"fault did not preserve W VALID after the current AW handshake");
  @(negedge clk);wdf_rdy=1;@(negedge clk);wdf_rdy=0;repeat(2)@(negedge clk);
  if(en || wren || idle || !reset_required || dut.S_fifo_empty)
    $fatal(1,"fault popped/advanced the completed head without full reset");
  $display("PASS tb_mc_watchdog");$finish;
 end
 initial begin #10000;$fatal(1,"tb_mc_watchdog timeout");end
endmodule

module tb_hdmi_reset;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,de=0,vs=0;
 hdmi_tx dut(.I_pixel_clk(clk),.I_serial_clk(clk),.I_rst(rst),.I_key_in(1'b0),.I_edid_read_trig(1'b0),
  .O_edid_read_valid(),.O_edid_read_data(),.I_video_rgb_enable(1'b1),.I_video_in_de(de),.I_video_in_vs(vs),
  .I_video_in_user(1'b0),.I_video_in_valid(1'b0),.I_video_in_last(1'b0),.O_video_in_ready(),.I_video_in_data(24'd0),
  .I_audio_valid(1'b0),.I_audio_left_data(24'd0),.I_audio_right_data(24'd0),.I_i2s_BCLK(1'b0),.I_i2s_LRCK(1'b0),.I_i2s_DOUT(1'b0),
  .O_ddc_scl(),.IO_ddc_sda(),.O_hdmi_clk_p(),.O_hdmi_tx_p(),.O_tmds_ch0_p(),.O_tmds_ch1_p(),.O_tmds_ch2_p(),.O_tmds_clk_p());
 initial begin
  #2 rst=0;@(negedge clk);de=1;vs=1;@(posedge clk);#1;
  if(dut.I_video_in_de_r1!==1 || dut.I_video_in_vs_r1!==1)$fatal(1,"HDMI reset setup failed");
  rst=1;#1;
  if(dut.I_video_in_de_r1!==0 || dut.I_video_in_vs_r1!==0)$fatal(1,"HDMI DE/VS stages did not asynchronously reset");
  $display("PASS tb_hdmi_reset");$finish;
 end
 initial begin #200;$fatal(1,"tb_hdmi_reset timeout");end
endmodule

module I2S_receiver(input I_clk,I_rst,I_i2s_BCLK,I_i2s_LRCK,I_i2s_DOUT,output O_audio_valid,output[23:0] O_audio_left_data,O_audio_right_data);
 assign O_audio_valid=1'b0;assign O_audio_left_data=24'd0;assign O_audio_right_data=24'd0;
endmodule
module audio_arc_calculate #(parameter ACR_N=6144)(input I_clk,I_rst,I_audio_valid,output O_acr_valid,output[19:0] O_acr_cts,O_acr_n);
 assign O_acr_valid=1'b0;assign O_acr_cts=20'd0;assign O_acr_n=20'd0;
endmodule
module key_remove_shakes(input I_clk,I_rst_n,I_key_in,output O_key_trig_out);assign O_key_trig_out=1'b0;endmodule
module hdmi_1_4b_transmitter_core_wrapper #(
 parameter DEVICE="PH1P",HTOTAL=1650,HSA=40,HFP=110,HBP=220,HACTIVE=1280,VTOTAL=750,VSA=5,VFP=5,VBP=20,VACTIVE=720,
 parameter VIDEO_VIC=4,VIDEO_TPG="Disable",VIDEO_FORMAT="RGB",AUDIO_SAMPLE_RATE="48K",IIC_SCL_DIV=125
)(input I_pixel_clk,I_rst,I_edid_read_trig,output O_edid_read_valid,output[7:0] O_edid_read_data,
 input I_axis_s_user,I_axis_s_valid,I_axis_s_last,input[23:0] I_axis_s_data,output O_axis_s_ready,
 input I_audio_valid,input[23:0] I_audio_left_data,I_audio_right_data,input I_acr_valid,input[19:0] I_acr_cts,I_acr_n,
 output O_video_locked,O_ddc_scl,inout IO_ddc_sda,output[9:0] O_ch0_tmds_data,O_ch1_tmds_data,O_ch2_tmds_data,O_clk_tmds_data);
 assign O_edid_read_valid=1'b0;assign O_edid_read_data=8'd0;assign O_axis_s_ready=1'b1;assign O_video_locked=1'b0;
 assign O_ddc_scl=1'b1;assign O_ch0_tmds_data=10'd0;assign O_ch1_tmds_data=10'd0;assign O_ch2_tmds_data=10'd0;assign O_clk_tmds_data=10'd0;
endmodule
module hdmi_phy_wrapper #(parameter DEVICE="PH1P")(input I_pixel_clk,I_serial_clk,I_rst,input[9:0] I_tmds_channel_0,I_tmds_channel_1,I_tmds_channel_2,I_tmds_channel_clk,output O_tmds_ch0_p,O_tmds_ch1_p,O_tmds_ch2_p,O_tmds_clk_p);
 assign O_tmds_ch0_p=1'b0;assign O_tmds_ch1_p=1'b0;assign O_tmds_ch2_p=1'b0;assign O_tmds_clk_p=1'b0;
endmodule

