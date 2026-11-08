`timescale 1ns/1ps
module tb_hdmi_vtc_stream #(parameter FRAME_TRANSACTION=0);
reg dc=0,pc=0,rst=0,rv=0,appready=0;always #7.5 dc=~dc;always #6.6665 pc=~pc;
wire vs,hs,de,user,last,pread,busy,re,pending,uf;
wire [24:0] addr,ma; wire mc_ready,me,mrv;wire [127:0] mrd;wire [2:0] cmd;wire [23:0] raw,rgb;wire ode;wire [8:0] fill;wire [9:0] credit;
reg [127:0] rdata=0;integer cycle=0, issued=0,returned=0,reads=0,pixels=0,errors=0,frames=0,x=0,y=0;
integer due[0:599999];reg [24:0] ads[0:599999];integer qwr=0,qrd=0;
integer app_stalls=0,max_outstanding=0,outstanding=0,read_cmds=0,max_credit=0;reg [24:0] previous_addr=0;integer first_pixel_bad=0;
function [127:0] wd;input [24:0] a;integer bitn,pixn,byteidx;reg [23:0] v;begin
for(bitn=0;bitn<128;bitn=bitn+1) begin byteidx=(a/8)*16+bitn/8;pixn=byteidx/3;v=pixn+1;wd[127-bitn]=v[23-(byteidx%3)*8-(bitn%8)];end
end endfunction
uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),.V_ActiveSize(720),.V_FrameSize(750),.V_SyncStart(725),.V_SyncEnd(730)) vtc(.I_vtc_rstn(rst),.I_vtc_clk(pc),.O_vtc_vs(vs),.O_vtc_hs(hs),.O_vtc_de_valid(de),.O_vtc_user(user),.O_vtc_last(last));
video_out #(.USE_EXTERNAL_SOURCE(1),.ENABLE_UNDERFLOW_GUARD(1),.ENABLE_DISPLAY_PAGE_GUARD(1),.ENABLE_FRAME_TRANSACTION(FRAME_TRANSACTION)) vo(.I_rst_n(rst),.I_ddr_clk(dc),.O_video_out_rd_busy(busy),.I_video_in_wr_busy(1'b0),.I_video_out_rp(2'd0),.O_ddr_user_rd_en(re),.O_ddr_user_addr(addr),.I_ddr_user_ready(mc_ready),.I_ddr_user_rd_valid(mrv),.I_ddr_user_rd_data(mrd),.I_dsi_clk(pc),.I_video_vsync(~vs),.I_video_rd_en(pread),.O_vdieo_data(raw),.I_source_base(25'd0),.I_source_mode(4'd0),.I_source_is_result(1'b0),.I_source_valid(1'b1),.O_fifo_fill(fill),.O_read_credit(credit),.O_frame_pending(pending),.O_underflow(uf),.O_frame_mode(),.O_result_source_active(),.O_display_page_mask());
hdmi_mixer #(.IMG_WIDTH(1280),.IMG_HEIGHT(720)) mixer(.I_clk(pc),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),.I_debug_status(4'd0),.O_video_rd_en(pread),.I_video_rd_data(raw),.O_hdmi_de(ode),.O_hdmi_hsync(),.O_hdmi_vsync(),.O_hdmi_data(rgb));
mc_to_user_interface mc(.I_clk(dc),.I_rst_n(rst),.I_ddr_user_wr_en(1'b0),.I_ddr_user_rd_en(re),.I_ddr_user_addr(addr),.I_ddr_user_wr_data(128'd0),.O_ddr_user_ready(mc_ready),.O_queue_idle(),.O_ddr_user_rd_valid(mrv),.O_ddr_user_rd_data(mrd),.O_mc_app_en(me),.O_mc_app_addr(ma),.O_mc_app_cmd(cmd),.I_mc_app_rdy(appready),.O_mc_app_wdf_wren(),.O_mc_app_wdf_data(),.O_mc_app_wdf_end(),.O_mc_app_wdf_mask(),.I_mc_app_wdf_rdy(1'b1),.I_mc_app_rd_data(rdata),.I_mc_app_rd_data_end(1'b1),.I_mc_app_rd_data_valid(rv));
always @(posedge pc) if(rst && user) begin $display("FIRST_PIXEL user=%b de=%b mixer_y=%0d pread=%b",user,de,mixer.S_y,pread); if(de && !pread) begin first_pixel_bad=1; $display("ERROR: first user/de pixel was not requested"); end end
always @(posedge dc) if(rst) begin cycle=cycle+1;if(me && !appready)app_stalls=app_stalls+1;if(me && appready)begin if(cmd==3'd1)begin if(read_cmds>0 && ma!=0 && ma!==(previous_addr+25'd8))begin errors=errors+1;$display("ERROR: DDR read address discontinuity previous=%0d current=%0d",previous_addr,ma);end previous_addr=ma;read_cmds=read_cmds+1;end due[qwr]=cycle+40;ads[qwr]=ma;qwr=qwr+1;issued=issued+1;outstanding=issued-returned;if(outstanding>max_outstanding)max_outstanding=outstanding;if(credit>max_credit)max_credit=credit;end end
always @(negedge dc) begin appready=(cycle%11)!=0;rv=0;if(qrd<qwr && due[qrd]<=cycle && cycle%7!=0)begin rv=1;rdata=wd(ads[qrd]);qrd=qrd+1;returned=returned+1;end outstanding=issued-returned;if(outstanding>max_outstanding)max_outstanding=outstanding;end
reg oldvs=0,oldde=0;
always @(posedge pc) begin #1;if(rst)begin
if(vs&&!oldvs)begin frames=frames+1;$display("FRAME %0d pixels=%0d errors=%0d reads=%0d uf=%b fill=%0d",frames,pixels,errors,issued,uf,fill);x=0;y=0;end
if(ode)begin if(frames>=1)begin pixels=pixels+1;if(rgb!==(y*1280+x+1))begin if(errors<10)$display("MISMATCH frame=%0d x=%0d y=%0d got=%h expect=%h",frames,x,y,rgb,y*1280+x+1);errors=errors+1;end end x=x+1;end
if(oldde&&!ode)begin x=0;y=y+1;end
oldde=ode;oldvs=vs;
if(frames==3)begin $display("RESULT frames=%0d errors=%0d pixels=%0d issued=%0d returned=%0d",frames,errors,pixels,issued,returned);$display("DDR_MODEL stalls=%0d max_outstanding=%0d max_credit=%0d read_cmds=%0d",app_stalls,max_outstanding,max_credit,read_cmds);if(errors!=0)$fatal(1,"FAIL tb_hdmi_vtc_stream errors=%0d",errors);if(pixels!=1843200)$fatal(1,"FAIL active pixel count=%0d",pixels);if(issued!=346080 || returned!=issued || read_cmds!=issued)$fatal(1,"FAIL DDR request/return count issued=%0d returned=%0d cmd=%0d",issued,returned,read_cmds);if(app_stalls==0 || max_outstanding==0 || max_credit==0)$fatal(1,"FAIL DDR backpressure/latency/credit coverage");if(first_pixel_bad)$fatal(1,"FAIL synchronous user/de first pixel");if(uf)$fatal(1,"FAIL video_out underflow");$display("PASS tb_hdmi_vtc_stream: two full VTC frames, 1843200 golden pixels, DDR model backpressure and latency covered without underflow");$finish;end end end
initial begin #100;rst=1;#60000000;$fatal(1,"timeout");end
endmodule



