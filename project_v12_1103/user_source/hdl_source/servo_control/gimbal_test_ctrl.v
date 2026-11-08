`timescale 1ns/1ps
// PAN_TEST_ONLY=1: alternate bounded positive/negative pan jogs on KEY2.
// PAN_TEST_ONLY=0: original tilt-low/high/home, pan-positive/negative, idle.
// A confirmed press during a jog requests neutral; full PWM pulses are retained.
module gimbal_test_ctrl #(
    parameter integer STARTUP_CYCLES = 50000000,
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
    parameter integer PAN_SPEED = 66
) (
    input wire clk,
    input wire rst_n,
    input wire key_press,
    input wire frame_tick,
    output reg [15:0] pan_us,
    output reg [15:0] tilt_us,
    output wire ready,
    output reg jog_active
);
    localparam integer SW = (STARTUP_CYCLES > 1) ? $clog2(STARTUP_CYCLES+1) : 1;
    localparam integer JOG_FRAMES_RAW = (PAN_JOG_MS*1000 + FRAME_US-1) / FRAME_US;
    localparam integer JOG_FRAMES = (JOG_FRAMES_RAW < 1) ? 1 : JOG_FRAMES_RAW;
    localparam integer JW = (JOG_FRAMES > 1) ? $clog2(JOG_FRAMES+1) : 1;

    // Vendor TIM4 runs at 2 us/count: 750 neutral, 800+s / 700+s motion.
    // At neutral=1500 this is exactly 1600+2*s / 1400+2*s microseconds.
    // PAN_STOP_US shifts the whole map for measured neutral calibration.
    function integer speed_pulse;
        input integer speed;
        integer bounded_speed;
        begin
            if (speed > 200) bounded_speed = 200;
            else if (speed < -200) bounded_speed = -200;
            else bounded_speed = speed;
            if (bounded_speed > 0) speed_pulse = PAN_STOP_US + 100 + 2*bounded_speed;
            else if (bounded_speed < 0) speed_pulse = PAN_STOP_US - 100 + 2*bounded_speed;
            else speed_pulse = PAN_STOP_US;
        end
    endfunction
    localparam integer SPEED_MAG = (PAN_SPEED < 0) ? -PAN_SPEED : PAN_SPEED;
    localparam integer MAPPED_POS_US = (PAN_USE_VENDOR_MAP != 0) ? speed_pulse(SPEED_MAG) : PAN_POS_US;
    localparam integer MAPPED_NEG_US = (PAN_USE_VENDOR_MAP != 0) ? speed_pulse(-SPEED_MAG) : PAN_NEG_US;
    localparam integer POS_US = (PAN_DIR_INVERT != 0) ? MAPPED_NEG_US : MAPPED_POS_US;
    localparam integer NEG_US = (PAN_DIR_INVERT != 0) ? MAPPED_POS_US : MAPPED_NEG_US;

    function integer angle_pulse;
        input integer angle;
        integer bounded_angle, physical_angle;
        begin
            if (angle < TILT_MIN_DEG) bounded_angle = TILT_MIN_DEG;
            else if (angle > TILT_MAX_DEG) bounded_angle = TILT_MAX_DEG;
            else bounded_angle = angle;
            physical_angle = (TILT_DIR_INVERT != 0) ? 180-bounded_angle : bounded_angle;
            angle_pulse = 500 + (physical_angle*2000 + 90)/180;
        end
    endfunction
    localparam integer HOME_US = angle_pulse(TILT_HOME_DEG);
    localparam integer LOW_US = angle_pulse(TILT_MIN_DEG);
    localparam integer HIGH_US = angle_pulse(TILT_MAX_DEG);
    reg [SW-1:0] startup_count;
    reg [JW-1:0] jog_frames_left;
    reg [2:0] test_step;
    reg [15:0] tilt_target;
    assign ready = rst_n && (startup_count == 0);

    // synthesis translate_off
    initial begin
        if (FRAME_US <= 0 || PAN_JOG_MS <= 0 || STARTUP_CYCLES < 0)
            $fatal(1, "Invalid gimbal timing parameters");
        if (PAN_USE_VENDOR_MAP != 0 && (SPEED_MAG < 1 || SPEED_MAG > 200))
            $fatal(1, "PAN_SPEED magnitude must be 1..200");
        if (TILT_MIN_DEG < 0 || TILT_MAX_DEG > 180 || TILT_MIN_DEG > TILT_MAX_DEG || TILT_STEP_US < 1)
            $fatal(1, "Invalid tilt limits/slew");
        if (PAN_STOP_US < 1000 || PAN_STOP_US > 2000 || POS_US < 500 || POS_US > 2500 || NEG_US < 500 || NEG_US > 2500)
            $fatal(1, "Invalid pan pulse parameters");
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            startup_count <= STARTUP_CYCLES;
            test_step <= 0;
            jog_frames_left <= 0;
            jog_active <= 1'b0;
            pan_us <= PAN_STOP_US;
            tilt_target <= HOME_US;
            tilt_us <= HOME_US;
        end else begin
            if (startup_count != 0) startup_count <= startup_count - 1'b1;
            if (frame_tick) begin
                if (tilt_us < tilt_target) begin
                    if (tilt_target - tilt_us <= TILT_STEP_US) tilt_us <= tilt_target;
                    else tilt_us <= tilt_us + TILT_STEP_US;
                end else if (tilt_us > tilt_target) begin
                    if (tilt_us - tilt_target <= TILT_STEP_US) tilt_us <= tilt_target;
                    else tilt_us <= tilt_us - TILT_STEP_US;
                end
            end
            if (ready) begin
                if (jog_active) begin
                    if (key_press) begin
                        pan_us <= PAN_STOP_US;
                        jog_active <= 1'b0;
                        jog_frames_left <= 0;
                    end else if (frame_tick) begin
                        if (jog_frames_left <= 1) begin
                            pan_us <= PAN_STOP_US;
                            jog_active <= 1'b0;
                            jog_frames_left <= 0;
                        end else jog_frames_left <= jog_frames_left - 1'b1;
                    end
                end else if (key_press) begin
                    if (PAN_TEST_ONLY != 0) begin
                        // Keep tilt at home throughout this diagnostic mode.
                        pan_us <= test_step[0] ? NEG_US : POS_US;
                        test_step <= test_step[0] ? 3'd0 : 3'd1;
                        jog_frames_left <= JOG_FRAMES;
                        jog_active <= 1'b1;
                    end else begin
                        case (test_step)
                            0: begin tilt_target <= LOW_US; test_step <= 1; end
                            1: begin tilt_target <= HIGH_US; test_step <= 2; end
                            2: begin tilt_target <= HOME_US; test_step <= 3; end
                            3: begin
                                pan_us <= POS_US;
                                jog_frames_left <= JOG_FRAMES;
                                jog_active <= 1'b1;
                                test_step <= 4;
                            end
                            4: begin
                                pan_us <= NEG_US;
                                jog_frames_left <= JOG_FRAMES;
                                jog_active <= 1'b1;
                                test_step <= 5;
                            end
                            default: begin
                                pan_us <= PAN_STOP_US;
                                tilt_target <= HOME_US;
                                test_step <= 0;
                            end
                        endcase
                    end
                end
            end
        end
    end
endmodule
