`timescale 1ns/1ps
// Microsecond clock-enable, shared 20-ms frame, registered push-pull signals.
// Commands latch only at frame boundaries; a mid-frame stop cannot cut a pulse.
module servo_pwm_dual #(
    parameter integer CLK_HZ = 100000000,
    parameter integer FRAME_US = 20000,
    parameter integer MIN_PULSE_US = 500,
    parameter integer MAX_PULSE_US = 2500,
    parameter integer PAN_RESET_US = 1500,
    parameter integer TILT_RESET_US = 1500,
    parameter integer PAN_MIN_PULSE_US = MIN_PULSE_US,
    parameter integer PAN_MAX_PULSE_US = MAX_PULSE_US,
    parameter integer TILT_MIN_PULSE_US = MIN_PULSE_US,
    parameter integer TILT_MAX_PULSE_US = MAX_PULSE_US
) (
    input wire clk,
    input wire rst_n,
    input wire [15:0] pan_us,
    input wire [15:0] tilt_us,
    output reg pan_pwm,
    output reg tilt_pwm,
    output wire frame_tick
);
    localparam integer CYCLES_PER_US = (CLK_HZ >= 1000000) ? CLK_HZ / 1000000 : 1;
    localparam integer UW = (CYCLES_PER_US > 1) ? $clog2(CYCLES_PER_US) : 1;
    localparam integer FW = (FRAME_US > 1) ? $clog2(FRAME_US) : 1;
    reg [UW-1:0] us_div;
    reg [FW-1:0] frame_us_count;
    reg [15:0] pan_latched, tilt_latched;
    reg frame_active;
    wire us_tick = (us_div == CYCLES_PER_US-1);
    assign frame_tick = rst_n && us_tick && (frame_us_count == FRAME_US-1);

    function [15:0] clamp_pan;
        input [15:0] command_us;
        begin
            if (command_us < PAN_MIN_PULSE_US) clamp_pan = PAN_MIN_PULSE_US;
            else if (command_us > PAN_MAX_PULSE_US) clamp_pan = PAN_MAX_PULSE_US;
            else clamp_pan = command_us;
        end
    endfunction
    function [15:0] clamp_tilt;
        input [15:0] command_us;
        begin
            if (command_us < TILT_MIN_PULSE_US) clamp_tilt = TILT_MIN_PULSE_US;
            else if (command_us > TILT_MAX_PULSE_US) clamp_tilt = TILT_MAX_PULSE_US;
            else clamp_tilt = command_us;
        end
    endfunction

    // synthesis translate_off
    initial begin
        if (CLK_HZ < 1000000 || CLK_HZ % 1000000 != 0)
            $fatal(1, "CLK_HZ must be a positive integer multiple of 1 MHz");
        if (FRAME_US < 2 || FRAME_US > 65535)
            $fatal(1, "FRAME_US must be 2..65535");
        if (PAN_MIN_PULSE_US < 1 || PAN_MIN_PULSE_US > PAN_MAX_PULSE_US || PAN_MAX_PULSE_US >= FRAME_US)
            $fatal(1, "Invalid pan pulse range");
        if (TILT_MIN_PULSE_US < 1 || TILT_MIN_PULSE_US > TILT_MAX_PULSE_US || TILT_MAX_PULSE_US >= FRAME_US)
            $fatal(1, "Invalid tilt pulse range");
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            us_div <= 0;
            frame_us_count <= 0;
            pan_latched <= clamp_pan(PAN_RESET_US);
            tilt_latched <= clamp_tilt(TILT_RESET_US);
            frame_active <= 1'b0;
            pan_pwm <= 1'b0;
            tilt_pwm <= 1'b0;
        end else if (us_tick) begin
            us_div <= 0;
            if (frame_us_count == FRAME_US-1) begin
                frame_us_count <= 0;
                pan_latched <= clamp_pan(pan_us);
                tilt_latched <= clamp_tilt(tilt_us);
                frame_active <= 1'b1;
                pan_pwm <= 1'b1;
                tilt_pwm <= 1'b1;
            end else begin
                frame_us_count <= frame_us_count + 1'b1;
                // Start only at the first complete frame boundary after reset.
                if (frame_active) begin
                    pan_pwm <= (frame_us_count + 1'b1 < pan_latched);
                    tilt_pwm <= (frame_us_count + 1'b1 < tilt_latched);
                end
            end
        end else us_div <= us_div + 1'b1;
    end
endmodule
