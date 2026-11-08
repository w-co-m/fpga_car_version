`timescale 1ns/1ps
module tb_target_cdc;
reg sc=0,dc=0,rst=0;always #6.667 sc=~sc;always #5 dc=~dc;
reg send=0,mode=0,valid=0;reg [10:0] x=0;reg [9:0] y=0;
wire update,dm,dv;wire [10:0] dx;wire [9:0] dy;
track_target_cdc d(.arst_n(rst),.src_clk(sc),.dst_clk(dc),.src_send(send),.src_mode_e(mode),
 .src_valid(valid),.src_cx(x),.src_cy(y),.dst_update(update),.dst_mode_e(dm),.dst_valid(dv),.dst_cx(dx),.dst_cy(dy));
reg [22:0] expected[0:511];integer wr=0,rd=0,checks=0,i;
always @(posedge sc) if(d.srst_n && send && d.request==d.ack_sync) begin
 expected[wr]={mode,valid,x,y};wr=wr+1;
end
always @(posedge dc) begin
 #1;if(rst&&update)begin
  checks++;if(rd>=wr||{dm,dv,dx,dy}!==expected[rd])$fatal(1,"torn or reordered CDC snapshot %d",rd);
  rd++;
 end
end
initial begin
 repeat(4)@(negedge sc);rst=1;repeat(8)@(negedge sc);
 for(i=0;i<200;i++)begin
  wait(d.request==d.ack_sync);@(negedge sc);
  mode=i[0];valid=i[1];x=(i*37)%1280;y=(i*53)%720;send=1;
  @(negedge sc);send=0;
  // Change the input bus while busy: the held packet must remain intact.
  x=~x;y=~y;mode=~mode;valid=~valid;
  repeat(i%4)@(negedge sc);
 end
 repeat(20)@(negedge sc);
 if(rd!=200||wr!=200)$fatal(1,"missing CDC packets %d/%d",rd,wr);
 rst=0;repeat(3)@(negedge sc);rst=1;repeat(8)@(negedge sc);
 if(dm||dv||dx||dy)$fatal(1,"CDC reset state");
 mode=1;valid=1;x=1279;y=719;send=1;@(negedge sc);send=0;
 repeat(20)@(negedge sc);
 if(rd!=201||dx!=1279||dy!=719)$fatal(1,"CDC reset recovery");
 $display("PASS tb_target_cdc checks=%0d errors=0",checks+2);$finish;
end
initial begin #1000000;$fatal(1,"CDC timeout");end
endmodule
