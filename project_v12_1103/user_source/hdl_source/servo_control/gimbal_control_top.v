`timescale 1ns/1ps
module gimbal_control_top #(
    parameter integer CLK_HZ = 100000000,
    parameter integer DEBOUNCE_CYCLES = CLK_HZ/50,
    parameter integer STARTUP_CYCLES = CLK_HZ/2,
    parameter integer FRAME_US = 20000,
    parameter integer PAN_STOP_US = 1500,
    parameter integer PAN_POS_US = 1732,
    parameter integer PAN_NEG_US = 1268,
    parameter integer PAN_DIR_INVERT = 0,
    parameter integer PAN_JOG_MS = 300,
    parameter integer TILT_HOME_DEG = 90,
    parameter integer TILT_MIN_DEG = 80,
    parameter integer TILT_MAX_DEG = 100,
    parameter integer TILT_DIR_INVERT = 0,
    parameter integer TILT_STEP_US = 5,
    parameter integer PAN_TEST_ONLY = 1,
    parameter integer PAN_USE_VENDOR_MAP = 1,
    parameter integer AUTO_IMAGE_W=1280,AUTO_IMAGE_H=720,
    parameter integer AUTO_PAN_DEADBAND=48,AUTO_PAN_HYST=16,AUTO_PAN_FAR_PIX=192,
    parameter integer AUTO_PAN_NEAR_US=120,AUTO_PAN_FAR_US=160,
    parameter integer AUTO_TILT_DEADBAND=36,AUTO_TILT_STEP_US=2,
    parameter integer AUTO_TIMEOUT_CYCLES=CLK_HZ/5,
    parameter integer PAN_SPEED = 66
) (
    input wire clk,
    input wire arst_n,
    input wire key2_n,
    input wire auto_cancel,
    input wire target_update,target_mode_e,target_valid,
    input wire [$clog2(AUTO_IMAGE_W)-1:0] target_cx,
    input wire [$clog2(AUTO_IMAGE_H)-1:0] target_cy,
    output wire auto_armed,auto_live,
    output wire O_servo_pan_pwm,
    output wire O_servo_tilt_pwm
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_sync;
    wire rst_n = reset_sync[1];
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) reset_sync <= 2'b00;
        else reset_sync <= {reset_sync[0], 1'b1};
    end
    wire key2_press, frame_tick;
    wire [15:0] pan_us,tilt_us,manual_pan_us,manual_tilt_us,auto_pan_us,auto_tilt_us;
    // A single PWM generator owns both output pins.
    assign pan_us=target_mode_e ? auto_pan_us : manual_pan_us;
    assign tilt_us=target_mode_e ? auto_tilt_us : manual_tilt_us;
    wire ready, jog_active;
    // Existing 20-ms filter, with release-before-arm after reset.
    motor_key_filter #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_key2 (
        .clk(clk), .rst_n(rst_n), .key_n(key2_n), .press(key2_press)
    );
    gimbal_test_ctrl #(
        .STARTUP_CYCLES(STARTUP_CYCLES), .FRAME_US(FRAME_US),
        .PAN_STOP_US(PAN_STOP_US), .PAN_POS_US(PAN_POS_US), .PAN_NEG_US(PAN_NEG_US),
        .PAN_DIR_INVERT(PAN_DIR_INVERT), .PAN_JOG_MS(PAN_JOG_MS),
        .TILT_HOME_DEG(TILT_HOME_DEG), .TILT_MIN_DEG(TILT_MIN_DEG),
        .TILT_MAX_DEG(TILT_MAX_DEG), .TILT_DIR_INVERT(TILT_DIR_INVERT),
        .TILT_STEP_US(TILT_STEP_US), .PAN_TEST_ONLY(PAN_TEST_ONLY),
        .PAN_USE_VENDOR_MAP(PAN_USE_VENDOR_MAP), .PAN_SPEED(PAN_SPEED)
    ) u_test (
        .clk(clk), .rst_n(rst_n && !target_mode_e), .key_press(key2_press && !target_mode_e), .frame_tick(frame_tick),
        .pan_us(manual_pan_us), .tilt_us(manual_tilt_us), .ready(ready), .jog_active(jog_active)
    );
    localparam integer TILT_A_US=500+(((TILT_DIR_INVERT!=0 ? 180-TILT_MIN_DEG : TILT_MIN_DEG)*2000+90)/180);
    localparam integer TILT_B_US=500+(((TILT_DIR_INVERT!=0 ? 180-TILT_MAX_DEG : TILT_MAX_DEG)*2000+90)/180);
    localparam integer TILT_HOME_US=500+(((TILT_DIR_INVERT!=0 ? 180-TILT_HOME_DEG : TILT_HOME_DEG)*2000+90)/180);
    gimbal_auto_ctrl #(.CLK_HZ(CLK_HZ),.STARTUP_CYCLES(STARTUP_CYCLES),
        .TIMEOUT_CYCLES(AUTO_TIMEOUT_CYCLES),.IMG_W(AUTO_IMAGE_W),.IMG_H(AUTO_IMAGE_H),
        .PAN_STOP_US(PAN_STOP_US),.PAN_DIR_INVERT(PAN_DIR_INVERT),.TILT_DIR_INVERT(TILT_DIR_INVERT),
        .PAN_DEADBAND(AUTO_PAN_DEADBAND),.PAN_HYST(AUTO_PAN_HYST),.PAN_FAR_PIX(AUTO_PAN_FAR_PIX),
        .PAN_NEAR_US(AUTO_PAN_NEAR_US),.PAN_FAR_US(AUTO_PAN_FAR_US),
        .TILT_DEADBAND(AUTO_TILT_DEADBAND),.TILT_STEP_US(AUTO_TILT_STEP_US),
        .TILT_MIN_US(TILT_A_US<TILT_B_US?TILT_A_US:TILT_B_US),
        .TILT_MAX_US(TILT_A_US>TILT_B_US?TILT_A_US:TILT_B_US),.TILT_HOME_US(TILT_HOME_US)) u_auto(
        .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.key_press(key2_press),.auto_cancel(auto_cancel),
        .target_update(target_update),.mode_e(target_mode_e),.target_valid(target_valid),
        .target_cx(target_cx),.target_cy(target_cy),.manual_tilt_us(manual_tilt_us),
        .pan_us(auto_pan_us),.tilt_us(auto_tilt_us),.armed(auto_armed),.target_live(auto_live),.timed_out());
    // Pan uses the vendor's 1..2-ms speed range; tilt retains 0.5..2.5 ms.
    servo_pwm_dual #(
        .CLK_HZ(CLK_HZ), .FRAME_US(FRAME_US), .PAN_RESET_US(PAN_STOP_US),
        .PAN_MIN_PULSE_US(1000), .PAN_MAX_PULSE_US(2000),
        .TILT_MIN_PULSE_US(500), .TILT_MAX_PULSE_US(2500)
    ) u_pwm (
        .clk(clk), .rst_n(rst_n), .pan_us(pan_us), .tilt_us(tilt_us),
        .pan_pwm(O_servo_pan_pwm), .tilt_pwm(O_servo_tilt_pwm), .frame_tick(frame_tick)
    );
endmodule
