`timescale 1ns/1ps
module tb_ddr_backpressure;
reg clk=0, rst=0, wr=0, rd=0;
reg [24:0] in_addr=0;
reg [127:0] in_data=0;
wire en,wren,rdy,wrdy,wend,ready,rdvalid,rdend;
wire [24:0] addr;
wire [2:0] cmd;
wire [127:0] data,returned,user_data;
wire [15:0] mask;
wire user_valid;
integer aws=0,ws=0,ars=0,pops=0,cycles=0;
integer exp_aw=0,exp_w=0,exp_ar=0,exp_pop=0;
reg [24:0] awq[0:1023], arq[0:1023];
reg [127:0] wq[0:1023];
reg awstall=0,wstall=0,arstall=0;
reg [24:0] held_aw,held_ar;
reg [127:0] held_w;
integer i;
always #5 clk=~clk;
mc_to_user_interface mc(
 .I_clk(clk),.I_rst_n(rst),.I_ddr_user_wr_en(wr),.I_ddr_user_rd_en(rd),
 .I_ddr_user_addr(in_addr),.I_ddr_user_wr_data(in_data),.O_ddr_user_ready(ready),
 .O_ddr_user_rd_valid(user_valid),.O_ddr_user_rd_data(user_data),
 .O_mc_app_en(en),.O_mc_app_addr(addr),.O_mc_app_cmd(cmd),.I_mc_app_rdy(rdy),
 .O_mc_app_wdf_wren(wren),.O_mc_app_wdf_data(data),.O_mc_app_wdf_end(wend),
 .O_mc_app_wdf_mask(mask),.I_mc_app_wdf_rdy(wrdy),
 .I_mc_app_rd_data(returned),.I_mc_app_rd_data_end(rdend),.I_mc_app_rd_data_valid(rdvalid));
ph1p35_324_ddr_wrapper ddr(
 .I_sys_clk(clk),.I_sys_rst_n(rst),.O_ddr_clk(),.O_init_calib_complete(),
 .I_mc_app_addr(addr),.I_mc_app_cmd(cmd),.I_mc_app_en(en),.I_mc_app_wdf_data(data),
 .I_mc_app_wdf_end(wend),.I_mc_app_wdf_mask(mask[15:0]),.I_mc_app_wdf_wren(wren),
 .O_mc_app_rd_data(returned),.O_mc_app_rd_data_end(rdend),.O_mc_app_rd_data_valid(rdvalid),
 .O_mc_app_rdy(rdy),.O_mc_app_wdf_rdy(wrdy),
 .ddr_addr(),.ddr_ba(),.ddr_cke(),.ddr_odt(),.ddr_cs_n(),.ddr_ras_n(),
 .ddr_cas_n(),.ddr_we_n(),.ddr_ck_p(),.ddr_ck_n(),.ddr_dm(),.ddr_dq(),.ddr_dqs_p(),.ddr_dqs_n());
always @(posedge clk) begin
 cycles=cycles+1;
 if(cycles>5000) $fatal(1,"DDR watchdog");
 if(!rst) begin awstall=0;wstall=0;arstall=0; end
 else begin
  if(awstall && (!ddr.paxi_awvalid || ddr.paxi_awaddr!==held_aw)) $fatal(1,"AW changed while stalled");
  if(wstall && (!ddr.paxi_wvalid || ddr.paxi_wdata!==held_w)) $fatal(1,"W changed while stalled");
  if(arstall && (!ddr.paxi_arvalid || ddr.paxi_araddr!==held_ar)) $fatal(1,"AR changed while stalled");
  awstall=ddr.paxi_awvalid&&!ddr.paxi_awready;held_aw=ddr.paxi_awaddr;
  wstall=ddr.paxi_wvalid&&!ddr.paxi_wready;held_w=ddr.paxi_wdata;
  arstall=ddr.paxi_arvalid&&!ddr.paxi_arready;held_ar=ddr.paxi_araddr;
  if(ddr.paxi_awvalid&&ddr.paxi_awready) begin
   if(aws>=exp_aw || ddr.paxi_awaddr!==awq[aws]) $fatal(1,"AW lost/duplicated/reordered index=%0d",aws);
   aws=aws+1;
  end
  if(ddr.paxi_wvalid&&ddr.paxi_wready) begin
   if(ws>=exp_w || ddr.paxi_wdata!==wq[ws] || !ddr.paxi_wlast || ddr.paxi_wstrb!==0) $fatal(1,"W lost/duplicated/reordered index=%0d",ws);
   ws=ws+1;
  end
  if(ddr.paxi_arvalid&&ddr.paxi_arready) begin
   if(ars>=exp_ar || ddr.paxi_araddr!==arq[ars]) $fatal(1,"AR lost/duplicated/reordered index=%0d",ars);
   ars=ars+1;
  end
  if(mc.S_fifo_rd_en) pops=pops+1;
 end
end
task set_ready;
 input a,w,r;
 begin ddr.u_ddr2.aw_ready=a;ddr.u_ddr2.w_ready=w;ddr.u_ddr2.ar_ready=r;end
endtask
task put;
 input write_op;
 input [24:0] address;
 input [127:0] payload;
 begin
  @(negedge clk);
  if(!ready) $fatal(1,"Unexpected command FIFO almost full");
  if(write_op) begin awq[exp_aw]=address;wq[exp_w]=payload;exp_aw=exp_aw+1;exp_w=exp_w+1; end
  else begin arq[exp_ar]=address;exp_ar=exp_ar+1;end
  exp_pop=exp_pop+1;in_addr=address;in_data=payload;wr=write_op;rd=!write_op;
  @(negedge clk);wr=0;rd=0;
 end
endtask
task drained;
 integer timeout;
 begin
  timeout=0;
  while((aws!=exp_aw||ws!=exp_w||ars!=exp_ar||pops!=exp_pop) && timeout<500) begin @(negedge clk);timeout=timeout+1;end
  repeat(8) @(negedge clk);
  if(aws!=exp_aw||ws!=exp_w||ars!=exp_ar||pops!=exp_pop||!mc.S_fifo_empty) $fatal(1,"DDR lost transaction AW=%0d/%0d W=%0d/%0d AR=%0d/%0d pop=%0d/%0d",aws,exp_aw,ws,exp_w,ars,exp_ar,pops,exp_pop);
 end
endtask
initial begin
 #1 rst=1;#1 rst=0;set_ready(0,0,0);repeat(5) @(negedge clk);rst=1;repeat(5) @(negedge clk);
 // Read readiness must not be borrowed from the write channels.
 set_ready(1,1,0);put(0,25'h100,0);repeat(12) @(negedge clk);
 if(pops!=0 || ars!=0 || !ddr.paxi_arvalid) $fatal(1,"Read popped without ARREADY / VALID depends on READY");
 set_ready(0,0,1);drained;
 // AW accepted first: hold W, never resend AW or pop prematurely.
 set_ready(1,0,1);put(1,25'h200,128'h123456);repeat(12) @(negedge clk);
 if(aws!=1||ws!=0||pops!=1||!ddr.paxi_wvalid) $fatal(1,"Write address-first handshake failed");
 set_ready(0,1,0);drained;
 // W accepted first: hold AW, never resend W.
 set_ready(0,1,0);put(1,25'h300,128'habcdef);repeat(12) @(negedge clk);
 if(aws!=1||ws!=2||pops!=2||!ddr.paxi_awvalid) $fatal(1,"Write data-first handshake failed");
 set_ready(1,0,0);drained;
 // Both VALID signals must be visible while READY is low.
 set_ready(0,0,0);put(1,25'h400,128'hfedcba);repeat(12) @(negedge clk);
 if(!ddr.paxi_awvalid||!ddr.paxi_wvalid||pops!=3) $fatal(1,"Write VALID depends on READY");
 set_ready(1,1,1);drained;
 // Sustain one command per clock and wrap both 512-entry FIFO pointers.
 for(i=0;i<600;i=i+1) begin
  @(negedge clk);
  in_addr=25'h8000+i*16;in_data=128'hface0000+i;
  wr=(i%4!=0);rd=!wr;exp_pop=exp_pop+1;
  if(wr) begin awq[exp_aw]=in_addr;wq[exp_w]=in_data;exp_aw=exp_aw+1;exp_w=exp_w+1;end
  else begin arq[exp_ar]=in_addr;exp_ar=exp_ar+1;end
 end
 @(negedge clk);wr=0;rd=0;drained;
 // Queue mixed reads/writes, then apply deterministic independent backpressure.
 set_ready(0,0,0);
 for(i=0;i<64;i=i+1) put(i%3!=0,25'h1000+i*16,128'h98760000+i);
 for(i=0;i<400;i=i+1) begin @(negedge clk);set_ready(i%4!=0,i%7>=3,i%5==1);end
 set_ready(1,1,1);drained;
 // Read response must pass data, valid and last through the wrapper.
 @(negedge clk);ddr.u_ddr2.r_data=128'h987654321;ddr.u_ddr2.r_valid=1;ddr.u_ddr2.r_last=1;#1;
 if(!user_valid||user_data!==128'h987654321||!rdend) $fatal(1,"Read response forwarding failed");
 @(negedge clk);ddr.u_ddr2.r_valid=0;ddr.u_ddr2.r_last=0;
 // Reset cancels an address-accepted/data-pending transaction without stale output.
 set_ready(1,0,0);put(1,25'h700,128'h777);repeat(8) @(negedge clk);
 rst=0;repeat(5) @(negedge clk);
 aws=0;ws=0;ars=0;pops=0;exp_aw=0;exp_w=0;exp_ar=0;exp_pop=0;
 rst=1;set_ready(1,1,1);repeat(8) @(negedge clk);
 if(en||wren||!mc.S_fifo_empty) $fatal(1,"Reset left stale transaction");
 put(1,25'h800,128'h888);put(0,25'h900,0);drained;
 $display("PASS tb_ddr_backpressure: independent AW/W/AR, stability, mixed queue, read response, reset");
 $finish;
end
endmodule
