`timescale 1ns/1ps
// 慢速状态总线的双向toggle握手。源端保持payload到目的端确认，
// 不能把每一位独立2FF后直接拼接成可能撕裂的mode/angle/status。
module polar_status_cdc #(parameter WIDTH=4)(
    input wire src_clk, src_rst_n,
    input wire [WIDTH-1:0] src_data,
    input wire dst_clk, dst_rst_n,
    output reg [WIDTH-1:0] dst_data
);
    reg [WIDTH-1:0] payload;
    reg request, acknowledge;
    (* async_reg="true" *) reg ack_1, ack_2, req_1, req_2;
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin payload<=0; request<=0; ack_1<=0; ack_2<=0; end
        else begin
            ack_1<=acknowledge; ack_2<=ack_1;
            if (ack_2 == request && payload != src_data) begin
                payload<=src_data; request<=~request;
            end
        end
    end
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin req_1<=0; req_2<=0; acknowledge<=0; dst_data<=0; end
        else begin
            req_1<=request; req_2<=req_1;
            if (req_2 != acknowledge) begin
                dst_data<=payload;
                acknowledge<=req_2;
            end
        end
    end
endmodule

// 经过20ms按键消抖的命令，相邻脉冲远大于跨域握手延迟。
module polar_pulse_cdc(
    input wire src_clk, src_rst_n, src_pulse,
    input wire dst_clk, dst_rst_n,
    output wire dst_pulse
);
    reg toggle;
    (* async_reg="true" *) reg sync_1, sync_2;
    reg seen;
    always @(posedge src_clk or negedge src_rst_n)
        if (!src_rst_n) toggle<=0;
        else if (src_pulse) toggle<=~toggle;
    always @(posedge dst_clk or negedge dst_rst_n)
        if (!dst_rst_n) begin sync_1<=0; sync_2<=0; seen<=0; end
        else begin sync_1<=toggle; sync_2<=sync_1; seen<=sync_2; end
    assign dst_pulse = sync_2 ^ seen;
endmodule
