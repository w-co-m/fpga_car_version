`timescale 1ns/1ps
// Good camera-frame events originate in DDR clock. Never derive activity from
// HDMI VS: DDR can repeat an old frame indefinitely while the sensor is silent.
module camera_activity_watchdog #(
    parameter integer CLK_HZ=100000000,
    parameter integer TIMEOUT_MS=200
)(
    input wire arst_n,camera_clk,camera_good_frame,ctrl_clk,
    output reg camera_alive
);
    localparam integer LIMIT=(CLK_HZ/1000)*TIMEOUT_MS;
    localparam integer CW=(LIMIT<=1)?1:$clog2(LIMIT+1);
    reg camera_toggle;
    (* async_reg="true" *) reg [1:0] event_sync;
    reg event_seen;
    reg [CW-1:0] age;
    always @(posedge camera_clk or negedge arst_n)
        if(!arst_n)camera_toggle<=0;
        else if(camera_good_frame)camera_toggle<=~camera_toggle;
    always @(posedge ctrl_clk or negedge arst_n)
        if(!arst_n)begin event_sync<=0;event_seen<=0;age<=0;camera_alive<=0;end
        else begin
            event_sync<={event_sync[0],camera_toggle};
            if(event_sync[1]!=event_seen)begin
                event_seen<=event_sync[1];age<=0;camera_alive<=1;
            end else if(age<LIMIT)begin
                age<=age+1'b1;
                if(age==LIMIT-1)camera_alive<=0;
            end
        end
endmodule
