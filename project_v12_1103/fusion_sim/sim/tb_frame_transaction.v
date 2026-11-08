`timescale 1ns/1ps
module tb_frame_transaction;
 reg pc=0,dc=0;always #6.667 pc=~pc;always #7.5 dc=~dc;
 reg rst_n=0,vs=0,de=0,hs=0,hold_return=0;
 reg[3:0]source_mode=5;
 wire rd,pread;wire[24:0]addr;wire[23:0]data;
 wire[3:0]pixel_mode,ddr_mode;wire fv,result;
 wire[9:0]credit;wire[8:0]fill;wire pending,busy,underflow;
 reg rv=0;reg[127:0]rdata=0;
 integer queued=0,returns=0,q=0,normal=0,black=0,cycles=0;
 reg old_ack_request;
 reg[7:0] expected_de=0;
 wire[23:0]rgb;wire ode,ohs,ovs;
 reg[2:0]valid_pipe=0;
 wire mde,mvs,mhs;wire[23:0]mdata;
 integer px=0;
 always @(posedge pc)if(vs || !de)px<=0;else px<=px+1;
 video_out #(.USE_EXTERNAL_SOURCE(1),.FRAME_WORDS(6),.BURST_WORDS(3),
  .ENABLE_UNDERFLOW_GUARD(1),.ENABLE_DISPLAY_PAGE_GUARD(1),.ENABLE_FRAME_TRANSACTION(1)) vo(
  .I_rst_n(rst_n),.I_ddr_clk(dc),.O_video_out_rd_busy(busy),.I_video_in_wr_busy(1'b0),
  .I_video_out_rp(2'd0),.O_ddr_user_rd_en(rd),.O_ddr_user_addr(addr),.I_ddr_user_ready(1'b1),
  .I_ddr_user_rd_valid(rv),.I_ddr_user_rd_data(rdata),.I_dsi_clk(pc),
  .I_video_vsync(vs),.I_video_rd_en(pread),.O_vdieo_data(data),
  .I_source_base(25'd0),.I_source_mode(source_mode),.I_source_is_result(1'b0),.I_source_valid(1'b1),
  .O_frame_mode(ddr_mode),.O_result_source_active(result),.O_fifo_fill(fill),.O_read_credit(credit),
  .O_frame_pending(pending),.O_underflow(underflow),.O_display_page_mask(),
  .O_pixel_mode(pixel_mode),.O_pixel_frame_valid(fv),.O_pixel_result_active());
 always @(posedge dc)begin
  rv<=0;
  if(!rst_n)begin queued=0;returns=0;end
  else begin
   if(rd)queued=queued+1;
   if(!hold_return && returns<queued)begin rv<=1;rdata<={16{8'h80}};returns=returns+1;end
  end
 end
 hdmi_mixer #(.IMG_WIDTH(32),.IMG_HEIGHT(1)) mixer(
  .I_clk(pc),.I_rst_n(rst_n),.I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),
  .I_video_user(de && px==0),.I_video_last(de && px==31),.I_debug_status(4'd0),
  .O_video_rd_en(pread),.I_video_rd_data(data),.O_hdmi_vsync(mvs),.O_hdmi_hsync(mhs),
  .O_hdmi_de(mde),.O_hdmi_data(mdata));
 always @(posedge pc)begin
  valid_pipe<={valid_pipe[1:0],fv};
 end
 video_algorithm_display #(.IMG_WIDTH(32),.IMG_HEIGHT(1),.EXTERNAL_RENDER_MODE(1),.ENABLE_FRAME_GUARD(1)) display(
  .clk(pc),.rst_n(rst_n),.key0_n(1'b1),.key1_n(1'b1),.threshold_edit(1'b0),
  .rgb_in(mdata),.de_in(mde),.hs_in(mhs),.vs_in(mvs),
  .rgb_out(rgb),.de_out(ode),.hs_out(ohs),.vs_out(ovs),.render_mode_in(pixel_mode),
  .frame_valid_in(valid_pipe[2]),.bank_run(rst_n),.mode_active(),.mode_pending_out(),
  .polar_capture_pulse(),.polar_restart_pulse(),.bin_threshold_active(),.edge_threshold_active(),
  .bright_gain_active(),.contrast_gain_active(),.threshold_edit_active());
 task tick;begin @(negedge pc);end endtask
 task start_frame;begin vs=1;repeat(4)tick;vs=0;end endtask
 task pixels;input integer expect_black;integer j;
  begin
   for(j=0;j<32;j=j+1)begin de=1;tick;end
   de=0;repeat(14)tick;
  end
 endtask
 always @(negedge pc)if(rst_n && ode)begin
  if(q==1)begin if(rgb!==24'h808080)$fatal(1,"normal pixel mismatch %h",rgb);normal=normal+1;end
  if(q==2)begin if(rgb!==0)$fatal(1,"late frame leaked transformed pixels %h",rgb);black=black+1;end
 end
 initial begin
  repeat(5)tick;rst_n=1;repeat(300)tick;
  start_frame;repeat(100)tick;q=1;pixels(0);q=0;
  if(normal!=32 || pixel_mode!=5)$fatal(1,"normal admission failed n=%0d mode=%0d",normal,pixel_mode);
  // Launch a frame whose reads remain outstanding into the following frame.
  hold_return=1;start_frame;repeat(70)tick;
  source_mode=4;start_frame;repeat(15)tick;
  q=2;de=1;repeat(10)tick;hold_return=0;repeat(22)tick;
  de=0;repeat(14)tick;q=0;
  if(black!=32 || pixel_mode!=5)$fatal(1,"late ACK changed frame mode or pixel count");
  start_frame;repeat(100)tick;
  if(!fv)$fatal(1,"next matching frame not admissible");
  pixels(0);
  if(pixel_mode!=4)$fatal(1,"timely next mode missing");
  // A new ticket supersedes a committable old candidate on the same DDR edge.
  // Only an actually activated candidate may consume the ACK mailbox.
  @(negedge dc);
  force vo.S_frame_pending=1'b1;force vo.S_pending_selected=1'b1;
  force vo.S_ticket_received=1'b1;
  old_ack_request=vo.u_frame_ack.request;
  @(posedge dc);#1;
  if(vo.u_frame_ack.request!==old_ack_request)
    $fatal(1,"new frame boundary emitted an ACK for a non-activated old candidate");
  release vo.S_frame_pending;release vo.S_pending_selected;release vo.S_ticket_received;
  $display("PASS tb_frame_transaction atomic mode, late ACK whole-frame black, next-frame recovery");$finish;
 end
 initial begin #1000000;$fatal(1,"frame test timeout");end
endmodule
