`timescale 1ns/1ps
// Pan: continuous-rotation speed command. Tilt: bounded position command.
// Only fresh detections drive motion; the yellow display hold box never does.
module gimbal_auto_ctrl #(
    parameter integer CLK_HZ=100000000, STARTUP_CYCLES=CLK_HZ/2,
    parameter integer TIMEOUT_CYCLES=CLK_HZ/5,
    parameter integer IMG_W=1280, IMG_H=720, XW=$clog2(IMG_W), YW=$clog2(IMG_H),
    parameter integer PAN_STOP_US=1500, PAN_DIR_INVERT=0, TILT_DIR_INVERT=0,
    parameter integer PAN_DEADBAND=48, PAN_HYST=16, PAN_FAR_PIX=192,
    parameter integer PAN_NEAR_US=120, PAN_FAR_US=160,
    parameter integer TILT_DEADBAND=36, TILT_STEP_US=2,
    parameter integer TILT_MIN_US=1389, TILT_MAX_US=1611, TILT_HOME_US=1500
)(
    input wire clk,rst_n,frame_tick,key_press,auto_cancel,
    input wire target_update,mode_e,target_valid,
    input wire [XW-1:0] target_cx,
    input wire [YW-1:0] target_cy,
    input wire [15:0] manual_tilt_us,
    output reg [15:0] pan_us,tilt_us,
    output reg armed,
    output wire target_live,
    output wire timed_out
);
    localparam SW=STARTUP_CYCLES>1?$clog2(STARTUP_CYCLES+1):1;
    localparam TW=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES+1):1;
    reg [SW-1:0] startup;
    reg [TW-1:0] age;
    reg [1:0] pan_direction; // 0 stop, 1 increasing pulse, 2 decreasing pulse
    wire ready=(startup==0);
    assign timed_out=(age>=TIMEOUT_CYCLES);
    assign target_live=mode_e && target_valid && !timed_out;
    wire [XW:0] xmag=target_cx>=IMG_W/2 ? target_cx-IMG_W/2 : IMG_W/2-target_cx;
    wire xpos=(target_cx>=IMG_W/2) ^ (PAN_DIR_INVERT!=0);
    wire ypos=(target_cy>=IMG_H/2) ^ (TILT_DIR_INVERT!=0);
    wire [YW:0] ymag=target_cy>=IMG_H/2 ? target_cy-IMG_H/2 : IMG_H/2-target_cy;
    wire xmove=xmag>(PAN_DEADBAND+((pan_direction==0)?PAN_HYST:0));
    wire [15:0] pan_delta=xmag>PAN_FAR_PIX ? PAN_FAR_US : PAN_NEAR_US;
    function [15:0] clamp_tilt;
        input [15:0] v;
        begin clamp_tilt=v<TILT_MIN_US?TILT_MIN_US:v>TILT_MAX_US?TILT_MAX_US:v;end
    endfunction
    // synthesis translate_off
    initial begin
        if(TIMEOUT_CYCLES<1 || STARTUP_CYCLES<0 || TILT_STEP_US<1 ||
           TILT_MIN_US>TILT_HOME_US || TILT_HOME_US>TILT_MAX_US ||
           PAN_STOP_US-PAN_FAR_US<1000 || PAN_STOP_US+PAN_FAR_US>2000 ||
           PAN_NEAR_US<1 || PAN_NEAR_US>PAN_FAR_US)
            $fatal(1,"Invalid automatic gimbal parameters");
    end
    // synthesis translate_on
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            startup<=STARTUP_CYCLES;age<=TIMEOUT_CYCLES;
            pan_us<=PAN_STOP_US;tilt_us<=TILT_HOME_US;armed<=0;pan_direction<=0;
        end else begin
            if(startup!=0) startup<=startup-1'b1;
            if(target_update) age<=0;
            else if(age<TIMEOUT_CYCLES) age<=age+1'b1;
            // Enter E disarmed. KEY2 toggles automatic following in E.
            // Leaving E or losing video requires a new explicit KEY2 start.
            if(!mode_e || timed_out || !ready || auto_cancel) armed<=0;
            else if(key_press) armed<=~armed;

            if(!mode_e) tilt_us<=clamp_tilt(manual_tilt_us);
            if(!armed || !ready || !target_live || key_press || auto_cancel) begin
                pan_us<=PAN_STOP_US;pan_direction<=0;
            end else if(frame_tick) begin
                if(!xmove) begin pan_us<=PAN_STOP_US;pan_direction<=0;end
                else begin
                    pan_us<=xpos ? PAN_STOP_US+pan_delta : PAN_STOP_US-pan_delta;
                    pan_direction<=xpos ? 1 : 2;
                end
                if(ymag>TILT_DEADBAND) begin
                    if(ypos) tilt_us<=tilt_us>=TILT_MAX_US-TILT_STEP_US ? TILT_MAX_US : tilt_us+TILT_STEP_US;
                    else tilt_us<=tilt_us<=TILT_MIN_US+TILT_STEP_US ? TILT_MIN_US : tilt_us-TILT_STEP_US;
                end
            end
        end
    end
endmodule
