// Test-only port model. Encrypted DDR controller and DDR physical timing are not simulated.
module ddr2(
 input ref_clk,sys_rst_n,apb_pclk,apb_prst_n,
 output dhi_clk,cfg_clk,ddrphy_rst_n,ddrphy_rdy,
 input [24:0] paxi_awaddr,paxi_araddr,
 input paxi_awvalid,paxi_arvalid,paxi_wvalid,paxi_wlast,paxi_rready,
 input [127:0] paxi_wdata,
 input [15:0] paxi_wstrb,
 output paxi_awready,paxi_arready,paxi_wready,
 output [127:0] paxi_rdata,
 output paxi_rlast,paxi_rvalid,
 output ddr_ck_p,ddr_ck_n,ddr_cke,ddr_odt,ddr_cs_n,ddr_ras_n,ddr_cas_n,ddr_we_n,
 output [1:0] ddr_ba,
 output [12:0] ddr_addr,
 inout [1:0] ddr_dqs_p,ddr_dqs_n,ddr_dm,
 inout [15:0] ddr_dq);
reg aw_ready=0,w_ready=0,ar_ready=0,r_valid=0,r_last=0;
reg [127:0] r_data=0;
assign dhi_clk=ref_clk;
assign cfg_clk=ref_clk;
assign ddrphy_rst_n=sys_rst_n;
assign ddrphy_rdy=sys_rst_n;
assign paxi_awready=aw_ready;
assign paxi_wready=w_ready;
assign paxi_arready=ar_ready;
assign paxi_rdata=r_data;
assign paxi_rlast=r_last;
assign paxi_rvalid=r_valid;
endmodule
