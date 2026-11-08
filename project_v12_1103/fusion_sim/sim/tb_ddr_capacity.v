`timescale 1ns/1ps
module tb_ddr_capacity;
reg clk=0,rst=0,vs=0,appready=0,rv=0; reg [127:0] rd=0;
wire re,ready,en,rvalid;wire [24:0] ra,aa;wire [127:0] rdata;wire [2:0] cmd;
integer tick=0,req=0,acc=0,ret=0,dropped=0,max_pending=0;
integer due[0:9999],wr=0,rr=0;
always #5 clk=~clk;
video_out vo(.I_rst_n(rst),.I_ddr_clk(clk),.O_video_out_rd_busy(),.I_video_in_wr_busy(1'b0),.I_video_out_rp(2'd1),.O_ddr_user_rd_en(re),.O_ddr_user_addr(ra),.I_ddr_user_ready(ready),.I_ddr_user_rd_valid(rvalid),.I_ddr_user_rd_data(rdata),.I_dsi_clk(clk),.I_video_vsync(vs),.I_video_rd_en(1'b0),.O_vdieo_data());
mc_to_user_interface mc(.I_clk(clk),.I_rst_n(rst),.I_ddr_user_wr_en(1'b0),.I_ddr_user_rd_en(re),.I_ddr_user_addr(ra),.I_ddr_user_wr_data(128'd0),.O_ddr_user_ready(ready),.O_ddr_user_rd_valid(rvalid),.O_ddr_user_rd_data(rdata),.O_mc_app_en(en),.O_mc_app_addr(aa),.O_mc_app_cmd(cmd),.I_mc_app_rdy(appready),.O_mc_app_wdf_wren(),.O_mc_app_wdf_data(),.O_mc_app_wdf_end(),.O_mc_app_wdf_mask(),.I_mc_app_wdf_rdy(1'b1),.I_mc_app_rd_data(rd),.I_mc_app_rd_data_end(1'b1),.I_mc_app_rd_data_valid(rv));
always @(negedge clk) begin
 tick=tick+1; appready=rst && ((tick%4)==0) && ((wr-rr)<4); rv=0;
 if(rr<wr && tick>=due[rr] && (tick%4)==2) begin rv=1;rd=rr+1;rr=rr+1; end
end
always @(posedge clk) begin
 if(re) req=req+1;
 if(en && appready) begin due[wr]=tick+400;wr=wr+1;acc=acc+1; end
 if(rv) begin ret=ret+1;if(vo.U_w128_d512_fifo.full_flag)dropped=dropped+1;end
 if((wr-rr)>max_pending)max_pending=wr-rr;
end
initial begin
 repeat(5)@(negedge clk);rst=1;vs=1;repeat(20)@(negedge clk);vs=0;
 repeat(140000)@(negedge clk);
 $display("CAPACITY req=%0d accepted=%0d returns=%0d stored=%0d dropped=%0d max_pending=%0d",req,acc,ret,vo.S_fifo_wr_num,dropped,max_pending);
 if(dropped || req!=480 || acc!=480 || ret!=480 || vo.S_fifo_wr_num!=480) $fatal(1,"FAIL tb_ddr_capacity overflow or missing responses");
 $display("PASS tb_ddr_capacity");$finish;
end
endmodule

