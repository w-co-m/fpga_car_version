`timescale 1ns/1ps
module tb_polar_retry_recovery;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,capture=0,frame=0,restart=0;
wire block_busy,block_done,block_error,block_start,block_compute;
wire block_abort_req,block_abort_ack,block_reset_required;
wire [24:0] source_addr,dest_addr,block_offset;
wire ready,error,pause,capbusy,compbusy; wire [1:0] angle;
wire request,release_owner,rd_en,wr_en; wire [24:0] addr; wire [127:0] wr_data;
reg grant=0,rd_valid=0; reg [127:0] rd_data=0;
reg force_bad=1;
reg [127:0] memory[0:20];
integer idx,done_seen=0,copy_done=0,compute_done=0,i;

polar_capture_ctrl #(.FRAME_BLOCKS(1),.SETTLE_FRAMES(0)) ctrl(
 .clk(clk),.rst_n(rst_n),.capture_pulse(capture),.restart_pulse(restart),
 .frame_start(frame),.live_page(2'd0),.page_valid(4'hf),.result_source_active(1'b0),
 .block_busy(block_busy),.block_done(block_done),.block_error(block_error),
 .block_abort_req(block_abort_req),.block_abort_ack(block_abort_ack),.block_reset_required(block_reset_required),
 .display_pause(pause),.angle(angle),.capture_busy(capbusy),.compute_busy(compbusy),
 .ready(ready),.error(error),.block_start(block_start),.block_compute(block_compute),
 .source_addr(source_addr),.dest_addr(dest_addr),.block_offset(block_offset));
polar_block_engine eng(.clk(clk),.rst_n(rst_n),.start(block_start),.op_compute(block_compute),
 .source_addr(source_addr),.dest_addr(dest_addr),.block_offset(block_offset),.busy(block_busy),
 .done(block_done),.error(block_error),.request(request),.grant(grant),.owner_release(release_owner),
 .ddr_ready(1'b1),.rd_en(rd_en),.wr_en(wr_en),.addr(addr),.wr_data(wr_data),
 .rd_valid(rd_valid),.rd_data(rd_data),.abort_req(block_abort_req),
 .abort_ack(block_abort_ack),.reset_required(block_reset_required));

function integer slot;
 input [24:0] a;
 begin
  if(a>=23000000 && a<23000024) slot=(a-23000000)/8;
  else if(a>=24400000 && a<24400024) slot=3+(a-24400000)/8;
  else if(a>=25800000 && a<25800024) slot=6+(a-25800000)/8;
  else if(a>=27200000 && a<27200024) slot=9+(a-27200000)/8;
  else if(a>=28600000 && a<28600024) slot=12+(a-28600000)/8;
  else if(a>=30000000 && a<30000024) slot=15+(a-30000000)/8;
  else if(a>=31400000 && a<31400024) slot=18+(a-31400000)/8;
  else slot=-1;
 end
endfunction

always @(posedge clk) begin
 if(!rst_n) begin grant<=0; rd_valid<=0; end
 else begin
  if(release_owner) grant<=0; else if(request) grant<=1;
  rd_valid<=rd_en;
  if(rd_en) begin
   idx=slot(addr);
   if(eng.state==1) rd_data<={16{8'h60}};
   else if(idx>=0) begin
    if(force_bad && eng.compute_latched && (eng.state==8 || eng.state==9)) rd_data<=memory[idx]^128'h1;
    else rd_data<=memory[idx];
   end else rd_data<=128'h0;
  end
  if(wr_en) begin
   idx=slot(addr);
   if(idx>=0) memory[idx]<=wr_data;
  end
  if(block_done) begin
   done_seen=done_seen+1;
   if(block_compute) compute_done=compute_done+1; else copy_done=copy_done+1;
  end
 end
end

task pulse_frame;
 begin @(negedge clk); frame=1; @(negedge clk); frame=0; end
endtask
task capture_one_angle;
 begin
  @(negedge clk); capture=1; @(negedge clk); capture=0;
  pulse_frame(); pulse_frame();
  wait(block_done); @(negedge clk);
  wait(!capbusy); repeat(2) @(negedge clk);
 end
endtask
task capture_four_angles;
 integer n;
 begin for(n=0;n<4;n=n+1) capture_one_angle(); end
endtask

task wait_compute_done;
 begin wait(ready); repeat(8) @(negedge clk); end
endtask

initial begin
 for(i=0;i<21;i=i+1) memory[i]=0;
 repeat(4) @(negedge clk); rst_n=1;
 capture_four_angles();
 wait(eng.verify_attempts==32);
 $display("TRANSIENT attempts=%0d engine_error=%b",eng.verify_attempts,block_error);
 if(block_error || block_reset_required) $fatal(1,"transient mismatch prematurely terminated");
 @(negedge clk); force_bad=0;
 wait_compute_done();
 $display("RECOVERED ready=%b ctrl_error=%b block_error=%b copies=%0d computes=%0d",
          ready,error,block_error,copy_done,compute_done);
 if(!ready || error || block_error || copy_done!=4 || compute_done!=1)
   $fatal(1,"transient retry did not recover cleanly after four copies and compute");

 @(negedge clk); restart=1; @(negedge clk); restart=0; repeat(3) @(negedge clk);
 if(ready || error || capbusy || compbusy || block_busy)
   $fatal(1,"KEY2 restart did not clear capture state");
 force_bad=0;
 capture_four_angles();
 wait_compute_done();
 $display("RESTARTED ready=%b error=%b done=%0d copies=%0d computes=%0d",
          ready,error,done_seen,copy_done,compute_done);
 if(!ready || error || done_seen!=10 || copy_done!=8 || compute_done!=2)
   $fatal(1,"capture/compute did not run after KEY2 restart");
 // Exercise the real controller -> engine cancellation handshake while copying.
 @(negedge clk);restart=1;@(negedge clk);restart=0;repeat(4)@(negedge clk);
 @(negedge clk);capture=1;@(negedge clk);capture=0;pulse_frame();pulse_frame();
 wait(block_busy && eng.state==1);
 @(negedge clk);restart=1;@(negedge clk);restart=0;
 wait(block_abort_ack);repeat(5)@(negedge clk);
 if(block_busy || capbusy || compbusy || pause || ready || angle!=0 || block_abort_req)
   $fatal(1,"busy KEY2 real capture/engine handshake did not drain and clear");
 if(done_seen!=10)$fatal(1,"cancelled copy published successful done");
 capture_four_angles();wait_compute_done();
 if(done_seen!=15 || copy_done!=12 || compute_done!=3 || error)
   $fatal(1,"new group after busy cancellation did not complete");
 $display("PASS polar retry recovery, copy/compute, restart");
 $finish;
end
initial begin #5000000; $display("TIMEOUT ctrl_state=%0d be_state=%0d angle=%0d busy=%b done=%b error=%b capbusy=%b compute=%b grant=%b request=%b counters=%0d/%0d",ctrl.state,eng.state,angle,block_busy,block_done,block_error,capbusy,compbusy,grant,request,copy_done,compute_done); $fatal(1,"timeout"); end
endmodule


