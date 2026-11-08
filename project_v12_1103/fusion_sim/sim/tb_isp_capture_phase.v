`timescale 1ns/1ps
module awb_gain_divider(input clk,rst_n,start,input[31:0]sum_g32,den32,output reg[19:0]gain20,output reg valid);
 always @(posedge clk or negedge rst_n)if(!rst_n)begin gain20<=0;valid<=0;end else begin gain20<=20'h10000;valid<=start;end
endmodule
module blk_mem_gen_zhenghe(input clka,wea,input[10:0]addra,input[31:0]dia,input clkb,input[10:0]addrb,output reg[31:0]dob);
 reg[31:0]m[0:2047];always@(posedge clka)if(wea)m[addra]<=dia;always@(posedge clkb)dob<=m[addrb];
endmodule
module blk_mem_gen_demosaic(input clka,wea,input[10:0]addra,input[32:0]dia,input clkb,input[10:0]addrb,output reg[32:0]dob);
 reg[32:0]m[0:2047];always@(posedge clka)if(wea)m[addra]<=dia;always@(posedge clkb)dob<=m[addrb];
endmodule
module blk_mem_gen_awb_delay_signal(input clka,wea,input[10:0]addra,input[95:0]dia,input clkb,input[10:0]addrb,output reg[95:0]dob);
 reg[95:0]m[0:2047];always@(posedge clka)if(wea)m[addra]<=dia;always@(posedge clkb)dob<=m[addrb];
endmodule
module tb_isp_capture_phase #(parameter integer DDR_PHASE=-1);
 reg clk=0;always #5 clk=~clk;
 wire packer_probe_done;tb_pack_probe packer_probe(clk,packer_probe_done);
 reg ddr_clk=0;integer seed=32'h61018,phase_ns;
 initial begin
  if(DDR_PHASE<0)phase_ns=$random(seed)&7;else phase_ns=DDR_PHASE;
  if(phase_ns<0||phase_ns>7)$fatal(1,"DDR_PHASE must be -1 or 0..7");
  #(phase_ns);forever #4 ddr_clk=~ddr_clk;
 end
 reg rst_n=0,valid=0,user=0,last=0;reg[39:0]raw=0;
 wire outvalid,outuser,outlast;wire[127:0]outdata;
 isp_top #(.ENABLE_POLAR_FIXED_GAIN(1)) isp(
  .axi4s_video_aclk(clk),.I_rst_n(rst_n),.I_polar_fixed_gain(1'b1),.I_tlast(last),.I_tuser(user),.I_tdata(raw),.I_tvalid(valid),.I_tdest(10'd0),
  .O_tready(1'b1),.O_tdata(outdata),.O_tlast(outlast),.O_tuser(outuser),.O_tvalid(outvalid),.I_tready());
 reg inject_mode=0,inject_fs=0,inject_valid=0;reg[127:0]inject_data=0;
 wire cam_fs=inject_mode?inject_fs:outuser;
 wire cam_valid=inject_mode?inject_valid:outvalid;
 wire[127:0]cam_data=inject_mode?inject_data:outdata;
 wire in_busy,ddr_we,frame_start_ddr,good_frame;wire[1:0]write_page;wire[24:0]ddr_addr;
 wire[127:0]ddr_wdata;wire[3:0]page_valid;
 video_in #(.FRAME_WORDS(172800),.BURST_WORDS(240),.REQUIRE_COMPLETE_FRAME(1),.ENABLE_DISPLAY_PAGE_GUARD(1)) capture(
  .I_rst_n(rst_n),.I_camera_clk(clk),.I_camera_frame_start(cam_fs),.I_camera_valid(cam_valid),.I_camera_data(cam_data),.I_mipi_rx_error(1'b0),
  .I_ddr_clk(ddr_clk),.I_display_pause(1'b0),.I_video_out_rd_busy(1'b0),.O_video_in_wr_busy(in_busy),.O_video_out_rp(),.O_ddr_user_wr_en(ddr_we),
  .O_ddr_user_addr(ddr_addr),.O_ddr_user_wr_data(ddr_wdata),.I_ddr_user_ready(1'b1),.O_frame_start_ddr(frame_start_ddr),
  .O_page_valid(page_valid),.I_display_page_mask(4'b0000),.O_good_frame_ddr(good_frame));
 reg[127:0] expected[0:345599];integer expected_head=0,expected_tail=0;
 integer frames=0,words=0,checked=0,errors=0,k,px,py,ch,good_pages=0,page_write_count=0;
 integer test_ramp=0,expected_ramp=0,monitor_ddr=0,frameuser_gap=0;
 reg[127:0]want;
 function[7:0] sample;input integer x,yy;
  begin if(test_ramp)sample=8+x/16+yy/16;else if(yy%2==0)sample=x%2==0?20:60;else sample=x%2==0?60:100;end
 endfunction
 function integer mirror_x;input integer x;begin mirror_x=x<0?1:(x>=1280?1278:x);end endfunction
 function integer mirror_y;input integer y;begin mirror_y=y<0?1:(y>=720?718:y);end endfunction
 function integer raw_at;input integer x,y;begin raw_at=sample(mirror_x(x),mirror_y(y));end endfunction
 function integer avg2;input integer x0,y0,x1,y1;begin avg2=(raw_at(x0,y0)+raw_at(x1,y1))>>1;end endfunction
 function integer avg4;input integer x0,y0,x1,y1,x2,y2,x3,y3;begin avg4=(raw_at(x0,y0)+raw_at(x1,y1)+raw_at(x2,y2)+raw_at(x3,y3))>>2;end endfunction
 function[7:0] rgb_channel;input integer x,y,ch;
 begin
  if(!expected_ramp)case(ch)0:rgb_channel=100;1:rgb_channel=60;default:rgb_channel=20;endcase
  else if(y%2==0 && x%2==0)case(ch)
   0:rgb_channel=avg4(x-1,y-1,x+1,y-1,x-1,y+1,x+1,y+1);
   1:rgb_channel=avg4(x-1,y,x+1,y,x,y-1,x,y+1);default:rgb_channel=raw_at(x,y);endcase
  else if(y%2==1 && x%2==1)case(ch)
   0:rgb_channel=raw_at(x,y);1:rgb_channel=avg4(x-1,y,x+1,y,x,y-1,x,y+1);
   default:rgb_channel=avg4(x-1,y-1,x+1,y-1,x-1,y+1,x+1,y+1);endcase
  else if(y%2==0)case(ch)
   0:rgb_channel=avg2(x,y-1,x,y+1);1:rgb_channel=raw_at(x,y);default:rgb_channel=avg2(x-1,y,x+1,y);endcase
  else case(ch)
   0:rgb_channel=avg2(x-1,y,x+1,y);1:rgb_channel=raw_at(x,y);default:rgb_channel=avg2(x,y-1,x,y+1);endcase
 end endfunction
 always @(negedge clk)if(rst_n)begin
  if(outuser)begin
   if(outvalid) $fatal(1,"ISP frameuser must precede valid data");
   if(frames>0 && words!=172800)$fatal(1,"ISP previous packed frame words=%0d",words);
   frames=frames+1;words=0;expected_ramp=(frames==2);monitor_ddr=1;frameuser_gap=1;
  end
  if(outvalid)begin
   if(frames==0)$fatal(1,"packed data before frame start");
   if(frameuser_gap)frameuser_gap=0;
   for(k=0;k<16;k=k+1)begin
    px=((words*16+k)/3)%1280;py=((words*16+k)/3)/1280;ch=(words*16+k)%3;
    want[127-k*8 -:8]=rgb_channel(px,py,ch);
   end
   if(outdata!==want)begin if(errors<5)$display("FAIL ISP pack word=%0d got=%h want=%h",words,outdata,want);errors=errors+1;end
   expected[expected_tail]=outdata;expected_tail=expected_tail+1;
   words=words+1;checked=checked+1;
  end
 end
 always @(negedge ddr_clk)if(rst_n && monitor_ddr && ddr_we)begin
  if(expected_head>=expected_tail)$fatal(1,"DDR write preceded expected ISP word addr=%0d",ddr_addr);
  if(ddr_wdata!==expected[expected_head])$fatal(1,"DDR capture order/content mismatch index=%0d got=%h want=%h",expected_head,ddr_wdata,expected[expected_head]);
  expected_head=expected_head+1;page_write_count=page_write_count+1;
 end
 always @(posedge ddr_clk)if(rst_n && good_frame)begin
  if(page_write_count!=172800)$fatal(1,"published page length=%0d expected=172800",page_write_count);
  good_pages=good_pages+1;page_write_count=0;
 end
 task inject_bad_early_frame;begin
  inject_mode=1;
  @(negedge clk);inject_fs=1;inject_valid=1;inject_data=128'hdeadbeef;
  @(negedge clk);inject_fs=0;inject_valid=0;
  repeat(4)@(negedge clk);
  @(negedge clk);inject_valid=1;inject_data=128'hbad00001;
  repeat(3)@(negedge clk);inject_valid=0;
  @(negedge clk);inject_fs=1;@(negedge clk);inject_fs=0;
  repeat(32)@(negedge clk);inject_mode=0;
 end endtask
 integer f,y,g;
 initial begin
  repeat(10)@(negedge clk);rst_n=1;repeat(12)@(negedge clk);
  inject_bad_early_frame();
  for(f=0;f<2;f=f+1)begin
   test_ramp=f;
   for(y=0;y<720;y=y+1)begin
    for(g=0;g<320;g=g+1)begin
     raw={sample(g*4+3,y),2'b00,sample(g*4+2,y),2'b00,sample(g*4+1,y),2'b00,sample(g*4,y),2'b00};
     valid=1;user=y==0&&g==0;last=g==319;@(negedge clk);
     valid=0;user=0;last=0;@(negedge clk);if(g%4==3)repeat(2)@(negedge clk);
    end
    repeat(900)@(negedge clk);
   end
   repeat(600)@(negedge clk);
  end
  repeat(2000)@(negedge clk);
  // Close the second real ISP frame so video_in can publish its complete page.
  inject_mode=1;inject_fs=1;inject_valid=0;@(negedge clk);inject_fs=0;repeat(2000)@(negedge ddr_clk);
  if(frames!=2||checked!=345600||errors!=0||!packer_probe_done)$fatal(1,"FAIL ISP output frames=%0d words=%0d errors=%0d probe=%b",frames,checked,errors,packer_probe_done);
  if(expected_head!=345600||expected_tail!=345600||good_pages!=2||page_valid==0||page_write_count!=0)
    $fatal(1,"FAIL capture pages=%0d valid=%b writes=%0d expected=%0d/%0d",good_pages,page_valid,page_write_count,expected_head,expected_tail);
  $display("PASS tb_isp_capture_phase actual ISP/AWB/packer/video_in, early-bad recovery, 2 full ordered pages, phase=%0d",phase_ns);$finish;
 end
 initial begin #40000000;$fatal(1,"ISP capture phase timeout");end
endmodule

module tb_pack_probe(input clk,output reg done=0);
 reg rst_n=0,valid=0,user=0;reg[95:0] data=0;wire fs,pvalid;wire[127:0] pdata;
 data_96bit_to_128bit dut(.I_clk(clk),.I_rst_n(rst_n),.I_96b_frame_start(user),.I_96b_valid(valid),.I_96b_data(data),
  .O_128b_frame_start(fs),.O_128b_valid(pvalid),.O_128b_data(pdata));
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  repeat(2)begin @(negedge clk);valid=1;data=96'h112233445566778899aabbcc;end
  @(negedge clk);valid=0;#1;
  if(dut.S_cnt!==2)$fatal(1,"packer reset probe failed to enter partial group");
  rst_n=0;#1;
  if(pvalid!==0||fs!==0||dut.S_cnt!==0||dut.S_96b_valid_1d!==0)$fatal(1,"packer asynchronous reset did not clear phase and outputs");
  @(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  user=1;valid=1;data=96'h0102030405060708090a0b0c;@(negedge clk);user=0;
  data=96'h1112131415161718191a1b1c;@(negedge clk);
  if(!pvalid||pdata!==128'h0102030405060708090a0b0c11121314)$fatal(1,"packer reset first phase mismatch %h",pdata);
  data=96'h2122232425262728292a2b2c;@(negedge clk);
  if(!pvalid||pdata!==128'h15161718191a1b1c2122232425262728)$fatal(1,"packer reset second phase mismatch %h",pdata);
  data=96'h3132333435363738393a3b3c;@(negedge clk);
  if(!pvalid||pdata!==128'h292a2b2c3132333435363738393a3b3c)$fatal(1,"packer reset third phase mismatch %h",pdata);
  done=1;
 end
endmodule
