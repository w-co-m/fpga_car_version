`timescale 1ns/1ps
module tb_fusion_osd;
reg clk=0,rst=0,de=0,vs=0,hs=0,armed=0,live=0;always #5 clk=~clk;
wire [23:0] rgb;wire dout,hout,vout;
video_status_osd #(.DECIMAL_COUNTER(1),.GIMBAL_STATUS_ENABLE(1)) dut(
 .clk(clk),.rst_n(rst),.rgb_in(24'h123456),.de_in(de),.hs_in(hs),.vs_in(vs),
 .mode_active(4'hF),.bin_threshold_active(8'd128),.edge_threshold_active(8'd32),
 .bright_gain_active(8'd24),.contrast_gain_active(8'd24),.threshold_edit_active(1'b0),
 .polar_angle(2'd0),.polar_capture_busy(1'b0),.polar_compute_busy(1'b0),.polar_ready(1'b0),
 .polar_error(1'b0),.ddr_state(2'd0),.motion_threshold_active(8'd8),
 .gimbal_armed(armed),.gimbal_live(live),.rgb_out(rgb),.de_out(dout),.hs_out(hout),.vs_out(vout));
integer checks=0,x,y,i,n;reg pd=0,pv=0,ph=0;reg [23:0] expected_bcd;
always @(posedge clk)begin #1;if(rst)begin
 if(dout!==pd || vout!==pv || hout!==ph)$fatal(1,"OSD sync is not two clocks");
 checks++;end pd=de;pv=vs;ph=hs;end
task tick(input bit d,input bit v);begin @(negedge clk);de=d;vs=v;@(posedge clk);#2;end endtask
task boundary;begin repeat(8)tick(0,1);repeat(8)tick(0,0);end endtask
task count_check(input integer seed);
 integer a,j,q;reg [23:0] b;
 begin
  // Independent decimal decomposition seeds every carry length and wraparound.
  q=seed;b=0;for(j=0;j<6;j++)begin b[j*4+:4]=q%10;q=q/10;end
  @(negedge clk);dut.frame_bcd=b;
  boundary;
  a=(seed+1)%1000000;q=0;b=0;
  for(j=0;j<6;j++)begin b[j*4+:4]=a%10;a=a/10;end
  if(dut.frame_bcd!==b)$fatal(1,"BCD frame carry/wide VS seed=%0d got=%h want=%h",seed,dut.frame_bcd,b);
 end
endtask
task tile(input bit a,input bit l,input [23:0] color);
 begin
  armed=a;live=l;boundary;
  for(y=0;y<22;y++)begin
   for(x=0;x<600;x++)begin
    tick(1,0);
    // Output at this edge is the preceding pixel, owing to the two registers.
    if(y==20 && x>=559 && x<=577)begin
     if(x>=561 && x<=576)begin if(rgb!==color)$fatal(1,"tile color/position x=%0d got=%h",x,rgb);end
     else if(rgb!==24'h123456)$fatal(1,"tile overruns its boundary");
    end
   end
   tick(0,0);tick(0,0);
  end
 end
endtask
initial begin
 repeat(4)tick(0,0);rst=1;repeat(4)tick(0,0);
 for(n=0;n<20;n++)count_check(n);
 count_check(98);count_check(99);count_check(998);count_check(999);count_check(9998);
 count_check(9999);count_check(99998);count_check(99999);count_check(999998);count_check(999999);
 tile(0,0,24'h808080);tile(1,0,24'h00ffff);tile(1,1,24'h00ff00);
 $display("PASS tb_fusion_osd checks=%0d errors=0",checks);$finish;
end
initial begin #2000000;$fatal(1,"OSD test timeout");end
endmodule
