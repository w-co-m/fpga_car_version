`timescale 1ns/1ps
// Active-low button. A key held during reset cannot start a motor:
// a debounced release is required before the first press is accepted.
module motor_key_filter #(
    parameter integer DEBOUNCE_CYCLES = 2000000
) (
    input wire clk,
    input wire rst_n,
    input wire key_n,
    output reg press
);
    localparam integer CW = (DEBOUNCE_CYCLES > 1) ? $clog2(DEBOUNCE_CYCLES) : 1;
    (* ASYNC_REG = "TRUE" *) reg key_meta;
    (* ASYNC_REG = "TRUE" *) reg key_sync;
    reg stable_n;
    reg armed;
    reg [CW-1:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 1'b0;
            key_sync <= 1'b0;
            stable_n <= 1'b1;
            armed <= 1'b0;
            count <= 0;
            press <= 1'b0;
        end else begin
            key_meta <= key_n;
            key_sync <= key_meta;
            press <= 1'b0;
            if (!armed) begin
                if (!key_sync) count <= 0;
                else if (count == DEBOUNCE_CYCLES-1) begin
                    armed <= 1'b1;
                    count <= 0;
                end else count <= count + 1'b1;
            end else if (key_sync == stable_n) count <= 0;
            else if (count == DEBOUNCE_CYCLES-1) begin
                stable_n <= key_sync;
                count <= 0;
                press <= !key_sync;
            end else count <= count + 1'b1;
        end
    end
endmodule
