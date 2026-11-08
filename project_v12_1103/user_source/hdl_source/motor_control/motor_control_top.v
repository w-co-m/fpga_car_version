`timescale 1ns/1ps
module motor_control_top #(
    parameter integer CLK_HZ = 100000000,
    parameter integer PWM_HZ = 10000,
    parameter integer DEBOUNCE_CYCLES = CLK_HZ/50,
    parameter integer STARTUP_CYCLES = CLK_HZ/2,
    parameter integer COAST_CYCLES = (CLK_HZ/10)*3,
    parameter integer RAMP_PWM_PERIODS = PWM_HZ/100,
    parameter integer A_INVERT = 0,
    parameter integer B_INVERT = 0,
    parameter integer AUTO_IMAGE_W = 1280,
    parameter integer AUTO_HEIGHT_MIN = 24,
    parameter integer AUTO_HEIGHT_MAX = 640,
    parameter integer AUTO_HEIGHT_JUMP = 64,
    parameter integer AUTO_X_GATE = 256,
    parameter integer AUTO_TIMEOUT_CYCLES = CLK_HZ/5,
    parameter integer AUTO_DUTY_PERCENT = 20
) (
    input wire clk,
    input wire arst_n,
    input wire [1:0] key_n,
    input wire auto_mode, auto_armed, auto_target_update, auto_target_valid,
    input wire [10:0] auto_target_cx,
    input wire [9:0] auto_target_height,
    output wire auto_cancel,
    output wire O_motor_ain1,
    output wire O_motor_ain2,
    output wire O_motor_pwma,
    output wire O_motor_bin1,
    output wire O_motor_bin2,
    output wire O_motor_pwmb,
    output wire O_motor_stby
);
    localparam integer PWM_PERIOD = CLK_HZ/PWM_HZ;
    localparam integer AW = AUTO_TIMEOUT_CYCLES>1 ? $clog2(AUTO_TIMEOUT_CYCLES+1) : 1;
    localparam integer AUTO_DUTY = (PWM_PERIOD*AUTO_DUTY_PERCENT)/100;
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_sync;
    wire rst_n = reset_sync[1];
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) reset_sync <= 2'b00;
        else reset_sync <= {reset_sync[0], 1'b1};
    end

    wire key1_press, key2_press;
    motor_key_filter #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_key1 (
        .clk(clk), .rst_n(rst_n), .key_n(key_n[0]), .press(key1_press)
    );
    motor_key_filter #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_key2 (
        .clk(clk), .rst_n(rst_n), .key_n(key_n[1]), .press(key2_press)
    );

    // D5 cancels both automatic axes and the car while F is armed.
    wire auto_selected = auto_mode && auto_armed;
    assign auto_cancel = auto_selected && key1_press;
    reg [1:0] command_phase;
    reg [1:0] speed_index;
    reg [31:0] duty_command;
    wire ready_for_keys;
    always @* begin
        case (speed_index)
            2'd1:    duty_command = (PWM_PERIOD * 30) / 100;
            2'd2:    duty_command = (PWM_PERIOD * 40) / 100;
            default: duty_command = (PWM_PERIOD * 20) / 100;
        endcase
    end
    // F always owns the motor outputs. Clear the old manual command so that
    // leaving F cannot resume motion without a new D5 press.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin command_phase <= 0; speed_index <= 0; end
        else if (auto_mode) begin command_phase <= 0; speed_index <= 0; end
        else if (ready_for_keys) begin
            if (key1_press && key2_press) command_phase <= {command_phase[1], 1'b0};
            else begin
                if (key1_press) command_phase <= command_phase + 1'b1;
                if (key2_press) begin
                    if (speed_index == 2) speed_index <= 0;
                    else speed_index <= speed_index + 1'b1;
                end
            end
        end
    end

    // The first fresh box after arming defines the desired apparent height.
    // This is a relative monocular distance proxy, not a metric distance.
    reg [9:0] height_ref, height_prev;
    reg ref_valid, auto_run, auto_reverse;
    reg [1:0] stable_frames;
    reg [AW-1:0] update_age;
    wire [10:0] x_error =
        auto_target_cx >= AUTO_IMAGE_W/2 ?
        auto_target_cx - AUTO_IMAGE_W/2 : AUTO_IMAGE_W/2 - auto_target_cx;
    wire geometry_ok =
        auto_target_cx < AUTO_IMAGE_W &&
        x_error <= AUTO_X_GATE &&
        auto_target_height >= AUTO_HEIGHT_MIN &&
        auto_target_height <= AUTO_HEIGHT_MAX;
    wire [10:0] height_jump =
        auto_target_height >= height_prev ?
        auto_target_height - height_prev : height_prev - auto_target_height;
    wire [9:0] start_band = (height_ref >> 3) < 10'd8 ? 10'd8 : (height_ref >> 3);
    wire [9:0] stop_band  = (height_ref >> 4) < 10'd4 ? 10'd4 : (height_ref >> 4);
    wire [10:0] height_now = {1'b0,auto_target_height};
    wire [10:0] low_start  = {1'b0,height_ref} - {1'b0,start_band};
    wire [10:0] high_start = {1'b0,height_ref} + {1'b0,start_band};
    wire [10:0] low_stop   = {1'b0,height_ref} - {1'b0,stop_band};
    wire [10:0] high_stop  = {1'b0,height_ref} + {1'b0,stop_band};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) update_age <= AUTO_TIMEOUT_CYCLES;
        else if (!auto_selected) update_age <= AUTO_TIMEOUT_CYCLES;
        else if (auto_target_update) update_age <= 0;
        else if (update_age < AUTO_TIMEOUT_CYCLES) update_age <= update_age + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            height_ref<=0; height_prev<=0; ref_valid<=0;
            auto_run<=0; auto_reverse<=0; stable_frames<=0;
        end else if (!auto_selected || auto_cancel || !auto_target_valid ||
                     update_age>=AUTO_TIMEOUT_CYCLES) begin
            height_ref<=0; height_prev<=0; ref_valid<=0;
            auto_run<=0; auto_reverse<=0; stable_frames<=0;
        end else if (auto_target_update) begin
            if (!geometry_ok) begin
                ref_valid<=0; stable_frames<=0; auto_run<=0;
            end else if (!ref_valid) begin
                height_ref<=auto_target_height;
                height_prev<=auto_target_height;
                ref_valid<=1; stable_frames<=1; auto_run<=0;
            end else if (height_jump > AUTO_HEIGHT_JUMP) begin
                height_prev<=auto_target_height;
                stable_frames<=0; auto_run<=0;
            end else begin
                height_prev<=auto_target_height;
                if (stable_frames<3) stable_frames<=stable_frames+1'b1;
                if (stable_frames>=2) begin
                    if (auto_run && !auto_reverse && height_now<low_stop) begin
                        auto_run<=1; auto_reverse<=0;
                    end else if (auto_run && auto_reverse && height_now>high_stop) begin
                        auto_run<=1; auto_reverse<=1;
                    end else if (height_now<low_start) begin
                        auto_run<=1; auto_reverse<=0;
                    end else if (height_now>high_start) begin
                        auto_run<=1; auto_reverse<=1;
                    end else auto_run<=0;
                end
            end
        end
    end

    wire auto_safe = auto_selected && auto_target_valid && geometry_ok &&
                     update_age<AUTO_TIMEOUT_CYCLES && !auto_cancel;
    wire run_cmd = auto_mode ? (auto_safe && auto_run) : command_phase[0];
    wire reverse_cmd = auto_mode ? auto_reverse : command_phase[1];
    wire [31:0] selected_duty = auto_mode ? AUTO_DUTY : duty_command;
    tb6612_dual_driver #(
        .PWM_PERIOD(PWM_PERIOD), .STARTUP_CYCLES(STARTUP_CYCLES),
        .COAST_CYCLES(COAST_CYCLES), .RAMP_PWM_PERIODS(RAMP_PWM_PERIODS),
        .A_INVERT(A_INVERT), .B_INVERT(B_INVERT)
    ) u_driver (
        .clk(clk), .rst_n(rst_n), .run_cmd(run_cmd),
        .reverse_cmd(reverse_cmd), .duty_cmd(selected_duty),
        .ain1(O_motor_ain1), .ain2(O_motor_ain2), .pwma(O_motor_pwma),
        .bin1(O_motor_bin1), .bin2(O_motor_bin2), .pwmb(O_motor_pwmb),
        .stby(O_motor_stby), .ready(ready_for_keys)
    );
endmodule
