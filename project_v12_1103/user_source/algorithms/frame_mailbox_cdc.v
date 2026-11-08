`timescale 1ns/1ps
// Event mailbox: unlike a state synchronizer, equal consecutive payloads are events.
// Both sides share an asynchronous reset source; each domain releases it locally.
module frame_mailbox_cdc #(parameter WIDTH=16)(
 input wire src_clk,src_rst_n,src_valid,
 input wire[WIDTH-1:0]src_data,
 output wire src_ready,
 input wire dst_clk,dst_rst_n,
 output reg dst_valid,
 output reg[WIDTH-1:0]dst_data
);
 reg[WIDTH-1:0]payload;
 reg request,acknowledge;
 (* async_reg="true" *) reg ack_1,ack_2,req_1,req_2;
 assign src_ready=(ack_2==request);
 always @(posedge src_clk or negedge src_rst_n)
  if(!src_rst_n)begin payload<=0;request<=0;ack_1<=0;ack_2<=0;end
  else begin
   ack_1<=acknowledge;ack_2<=ack_1;
   if(src_valid && src_ready)begin payload<=src_data;request<=~request;end
  end
 always @(posedge dst_clk or negedge dst_rst_n)
  if(!dst_rst_n)begin dst_valid<=0;dst_data<=0;req_1<=0;req_2<=0;acknowledge<=0;end
  else begin
   req_1<=request;req_2<=req_1;dst_valid<=0;
   if(req_2!=acknowledge)begin dst_data<=payload;dst_valid<=1;acknowledge<=req_2;end
  end
endmodule
