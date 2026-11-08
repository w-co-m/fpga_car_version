`timescale 1ns/1ps
// One frame snapshot, held unchanged until the receiver acknowledges it.
// Both domains must use this common asynchronous reset (not independent resets).
module track_target_cdc #(
    parameter XW=11, YW=10
)(
    input wire arst_n, src_clk, dst_clk,
    input wire src_send, src_mode_e, src_valid,
    input wire [XW-1:0] src_cx,
    input wire [YW-1:0] src_cy,
    input wire [YW-1:0] src_height,
    output reg dst_update, dst_mode_e, dst_valid,
    output reg [XW-1:0] dst_cx,
    output reg [YW-1:0] dst_cy,
    output reg [YW-1:0] dst_height
);
    localparam PW=2+XW+2*YW;
    (* ASYNC_REG="TRUE" *) reg [1:0] src_reset, dst_reset;
    wire srst_n=src_reset[1], drst_n=dst_reset[1];
    always @(posedge src_clk or negedge arst_n)
        if(!arst_n) src_reset<=0; else src_reset<={src_reset[0],1'b1};
    always @(posedge dst_clk or negedge arst_n)
        if(!arst_n) dst_reset<=0; else dst_reset<={dst_reset[0],1'b1};
    reg [PW-1:0] payload_hold;
    reg request,ack;
    (* ASYNC_REG="TRUE" *) reg ack_meta,ack_sync;
    (* ASYNC_REG="TRUE" *) reg req_meta,req_sync;
    (* ASYNC_REG="TRUE" *) reg [PW-1:0] data_meta,data_sync;
    reg pending;
    always @(posedge src_clk or negedge srst_n) begin
        if(!srst_n) begin payload_hold<=0;request<=0;ack_meta<=0;ack_sync<=0;end
        else begin
            ack_meta<=ack;ack_sync<=ack_meta;
            // Busy snapshots are dropped; at 60 Hz the handshake completes
            // thousands of times sooner than the next frame.
            if(src_send && request==ack_sync) begin
                payload_hold<={src_mode_e,src_valid,src_cx,src_cy,src_height};
                request<=~request;
            end
        end
    end
    always @(posedge dst_clk or negedge drst_n) begin
        if(!drst_n) begin
            req_meta<=0;req_sync<=0;data_meta<=0;data_sync<=0;
            ack<=0;pending<=0;dst_update<=0;dst_mode_e<=0;dst_valid<=0;dst_cx<=0;dst_cy<=0;dst_height<=0;
        end else begin
            req_meta<=request;req_sync<=req_meta;
            data_meta<=payload_hold;data_sync<=data_meta;
            dst_update<=0;
            if(pending) begin
                {dst_mode_e,dst_valid,dst_cx,dst_cy,dst_height}<=data_sync;
                dst_update<=1;ack<=req_sync;pending<=0;
            end else if(req_sync!=ack) pending<=1;
        end
    end
endmodule
