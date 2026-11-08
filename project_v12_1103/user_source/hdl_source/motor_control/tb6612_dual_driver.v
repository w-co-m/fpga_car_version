`timescale 1ns/1ps
// Open-loop, equal duty on channels A/B. Stop means STBY=0 (coast).
// PWM and ramp use clock enables; no fabric-generated clock is used.
module tb6612_dual_driver #(
    parameter integer PWM_PERIOD = 10000,
    parameter integer STARTUP_CYCLES = 50000000,
    parameter integer COAST_CYCLES = 30000000,
    parameter integer RAMP_PWM_PERIODS = 100,
    parameter integer A_INVERT = 0,
    parameter integer B_INVERT = 0
) (
    input wire clk,
    input wire rst_n,
    input wire run_cmd,
    input wire reverse_cmd,
    input wire [31:0] duty_cmd,
    output wire ain1,
    output wire ain2,
    output wire pwma,
    output wire bin1,
    output wire bin2,
    output wire pwmb,
    output wire stby,
    output wire ready
);
    localparam [1:0] BOOT=2'd0, IDLE=2'd1, COAST=2'd2, RUN=2'd3;
    localparam integer PW = (PWM_PERIOD > 1) ? $clog2(PWM_PERIOD+1) : 1;
    localparam integer MW = (STARTUP_CYCLES > COAST_CYCLES) ? STARTUP_CYCLES : COAST_CYCLES;
    localparam integer TW = (MW > 1) ? $clog2(MW+1) : 1;
    localparam integer RW = (RAMP_PWM_PERIODS > 1) ? $clog2(RAMP_PWM_PERIODS) : 1;
    localparam integer DUTY_STEP = (PWM_PERIOD >= 20) ? PWM_PERIOD/20 : 1;
    reg [1:0] state;
    reg [TW-1:0] wait_count;
    reg active_reverse;
    reg [PW-1:0] pwm_count;
    reg [PW-1:0] duty_current;
    reg [RW-1:0] ramp_count;
    reg pwm_q;
    wire [31:0] duty_limited = (duty_cmd > PWM_PERIOD) ? PWM_PERIOD : duty_cmd;
    wire drive = rst_n && (state == RUN) && run_cmd && (reverse_cmd == active_reverse);
    wire dir_a = active_reverse ^ (A_INVERT != 0);
    wire dir_b = active_reverse ^ (B_INVERT != 0);

    assign stby = drive;
    assign ready = rst_n && (state != BOOT);
    assign ain1 = drive && !dir_a;
    assign ain2 = drive && dir_a;
    assign bin1 = drive && !dir_b;
    assign bin2 = drive && dir_b;
    assign pwma = drive && pwm_q;
    assign pwmb = drive && pwm_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= BOOT;
            wait_count <= STARTUP_CYCLES;
            active_reverse <= 1'b0;
            pwm_count <= 0;
            duty_current <= 0;
            ramp_count <= 0;
            pwm_q <= 1'b0;
        end else begin
            case (state)
                BOOT: begin
                    if (wait_count <= 1) begin state <= IDLE; wait_count <= 0; end
                    else wait_count <= wait_count - 1'b1;
                end
                IDLE: begin
                    pwm_q <= 1'b0;
                    pwm_count <= 0;
                    duty_current <= 0;
                    ramp_count <= 0;
                    if (run_cmd) begin
                        state <= COAST;
                        wait_count <= COAST_CYCLES;
                    end
                end
                COAST: begin
                    pwm_q <= 1'b0;
                    pwm_count <= 0;
                    duty_current <= 0;
                    ramp_count <= 0;
                    if (!run_cmd) begin state <= IDLE; wait_count <= 0; end
                    else if (wait_count <= 1) begin
                        active_reverse <= reverse_cmd;
                        state <= RUN;
                        wait_count <= 0;
                    end else wait_count <= wait_count - 1'b1;
                end
                RUN: begin
                    if (!run_cmd || (reverse_cmd != active_reverse)) begin
                        pwm_q <= 1'b0;
                        pwm_count <= 0;
                        duty_current <= 0;
                        ramp_count <= 0;
                        if (!run_cmd) state <= IDLE;
                        else begin state <= COAST; wait_count <= COAST_CYCLES; end
                    end else begin
                        pwm_q <= (pwm_count < duty_current);
                        if (pwm_count == PWM_PERIOD-1) begin
                            pwm_count <= 0;
                            if (ramp_count == RAMP_PWM_PERIODS-1) begin
                                ramp_count <= 0;
                                // Update duty only at a PWM period boundary.
                                if (duty_current < duty_limited) begin
                                    if (duty_limited - duty_current <= DUTY_STEP)
                                        duty_current <= duty_limited;
                                    else duty_current <= duty_current + DUTY_STEP;
                                end else if (duty_current > duty_limited) begin
                                    if (duty_current - duty_limited <= DUTY_STEP)
                                        duty_current <= duty_limited;
                                    else duty_current <= duty_current - DUTY_STEP;
                                end
                            end else ramp_count <= ramp_count + 1'b1;
                        end else pwm_count <= pwm_count + 1'b1;
                    end
                end
                default: begin
                    state <= BOOT;
                    wait_count <= STARTUP_CYCLES;
                    pwm_q <= 1'b0;
                    pwm_count <= 0;
                    duty_current <= 0;
                    ramp_count <= 0;
                end
            endcase
        end
    end
endmodule
