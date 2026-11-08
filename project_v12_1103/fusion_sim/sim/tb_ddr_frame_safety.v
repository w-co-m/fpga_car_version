`timescale 1ns/1ps
module tb_ddr_frame_safety;
reg clk=0;always #5 clk=~clk;
reg rst=0,fs=0,cv=0,wr_ready=1;
reg [127:0] camera_data=0;
wire in_busy,in_we;wire[1:0] camera_rp;wire[24:0] in_addr;wire[127:0] in_data;
integer writes=0,empty_reads=0,new_writes=0,phase=0,i,before_abort;
video_in vin(.I_rst_n(rst),.I_camera_clk(clk),.I_camera_frame_start(fs),.I_camera_valid(cv),
 .I_camera_data(camera_data),.I_mipi_rx_error(1'b0),.I_ddr_clk(clk),.I_display_pause(1'b0),
 .I_video_out_rd_busy(1'b0),.O_video_in_wr_busy(in_busy),.O_video_out_rp(camera_rp),
 .O_ddr_user_wr_en(in_we),.O_ddr_user_addr(in_addr),.O_ddr_user_wr_data(in_data),.I_ddr_user_ready(wr_ready));
always @(posedge clk) if(rst)begin
 if(vin.S_fifo_rd_en && vin.U_w128_d512_fifo.empty_flag)empty_reads=empty_reads+1;
 if(in_we)begin
  writes=writes+1;
  if(!in_busy)$fatal(1,"write tail released arbitration early");
  if(phase==2)$fatal(1,"old capture continued after frame reset");
  if(phase==3)begin
   if(in_addr!==25'd7000000+new_writes*8 || in_data!==128'h123456789abcdef)
      $fatal(1,"new capture address/data mismatch addr=%0d index=%0d",in_addr,new_writes);
   new_writes=new_writes+1;
  end
 end
end
task camera_frame;begin @(negedge clk);fs=1;@(negedge clk);fs=0;repeat(25)@(negedge clk);end endtask
task camera_pixels;begin
 @(negedge clk);cv=1;camera_data=128'h123456789abcdef;
 repeat(240)@(negedge clk);cv=0;
end endtask

reg vs=0,block_reads=1,app_ready=1,retvalid=0;
reg[1:0] rp=1;reg[127:0] retdata=0;
wire out_busy,re,user_ready,user_valid,app_en;wire[24:0] ra,aa;
wire[127:0] user_data;wire[2:0] cmd;
integer tick=0,issued=0,accepted=0,returned=0,head=0,tail=0,new_reads=0,old_dropped=0;
integer due[0:4095];reg[24:0] qaddr[0:4095];reg monitor_new=0;
video_out vout(.I_rst_n(rst),.I_ddr_clk(clk),.O_video_out_rd_busy(out_busy),.I_video_in_wr_busy(block_reads),
 .I_video_out_rp(rp),.O_ddr_user_rd_en(re),.O_ddr_user_addr(ra),.I_ddr_user_ready(user_ready),
 .I_ddr_user_rd_valid(user_valid),.I_ddr_user_rd_data(user_data),.I_dsi_clk(clk),.I_video_vsync(vs),
 .I_video_rd_en(1'b0),.O_vdieo_data());
// Capture and display are exercised independently here; no illegal simultaneous
// read/write commands are injected into the shared application interface.
mc_to_user_interface mc(.I_clk(clk),.I_rst_n(rst),.I_ddr_user_wr_en(1'b0),.I_ddr_user_rd_en(re),
 .I_ddr_user_addr(ra),.I_ddr_user_wr_data(128'd0),.O_ddr_user_ready(user_ready),
 .O_ddr_user_rd_valid(user_valid),.O_ddr_user_rd_data(user_data),.O_mc_app_en(app_en),
 .O_mc_app_addr(aa),.O_mc_app_cmd(cmd),.I_mc_app_rdy(app_ready),.O_mc_app_wdf_wren(),
 .O_mc_app_wdf_data(),.O_mc_app_wdf_end(),.O_mc_app_wdf_mask(),.I_mc_app_wdf_rdy(1'b1),
 .I_mc_app_rd_data(retdata),.I_mc_app_rd_data_end(retvalid),.I_mc_app_rd_data_valid(retvalid));
always @(negedge clk)begin
 tick=tick+1;retvalid=0;
 if(head<tail && tick>=due[head])begin retvalid=1;retdata={103'd0,qaddr[head]};head=head+1;end
end
always @(posedge clk)if(rst)begin
 if(re)issued=issued+1;
 if(app_en && app_ready)begin due[tail]=tick+80;qaddr[tail]=aa;tail=tail+1;accepted=accepted+1;end
 if(user_valid)returned=returned+1;
 if(vout.S_video_frame_start && rp==2)monitor_new=1;
 if(monitor_new && user_valid && user_data[24:0]<14000000)old_dropped=old_dropped+1;
 if(monitor_new && vout.U_w128_d512_fifo.we)begin
  if(user_data[24:0]!==25'd14000000+new_reads*8)
    $fatal(1,"stale/out-of-order frame data addr=%0d expected=%0d",user_data[24:0],14000000+new_reads*8);
  new_reads=new_reads+1;
 end
end
task display_frame;begin @(negedge clk);vs=1;repeat(4)@(negedge clk);vs=0;end endtask
initial begin
 repeat(6)@(negedge clk);rst=1;
 // Wait for the two destination-clock reset release stages before sending SOF.
 repeat(4)@(negedge clk);
 camera_frame();camera_pixels();
 wait(writes>=11);@(negedge clk);wr_ready=0;repeat(3)@(negedge clk);
 before_abort=writes;camera_frame();phase=2;wr_ready=1;repeat(270)@(negedge clk);
 if(writes!=before_abort || empty_reads!=0)$fatal(1,"stale capture writes or empty reads");
 phase=3;camera_pixels();repeat(280)@(negedge clk);
 if(new_writes!=240 || empty_reads!=0)$fatal(1,"capture failed to recover writes=%0d empty=%0d",new_writes,empty_reads);
 phase=4;display_frame();block_reads=0;
 wait(issued>=100);@(negedge clk);app_ready=0;rp=2;display_frame();
 repeat(200)@(negedge clk);app_ready=1;
 wait(new_reads>=240);repeat(600)@(negedge clk);
 if(old_dropped==0 || new_reads!=480 || accepted!=returned || vout.S_read_credit!=0)
   $fatal(1,"drain/restart incomplete old=%0d new=%0d accepted=%0d returned=%0d credit=%0d",old_dropped,new_reads,accepted,returned,vout.S_read_credit);
 $display("PASS tb_ddr_frame_safety: capture recovered 240 words, discarded %0d old returns, new frame 480 ordered words",old_dropped);
 $finish;
end
initial begin #2000000;$fatal(1,"frame safety timeout");end
endmodule
