# 双轴云台 FPGA 控制（N2 底座 / N3 俯仰）

底座 `O_servo_pan_pwm` 使用 **N2**；俯仰 `O_servo_tilt_pwm` 使用 **N3**，与原工程 `user_source/constraints_source/pin.adc` 一致。旧说明中的 N4 是笔误。

`design_top_wrapper.v` 中的 `gimbal_control_top` 参数块决定实际行为；只修改下层模块默认值可能被顶层覆盖。

默认参数：100 MHz 时钟，20 ms PWM 帧，底座停止 1500 μs，商家速度映射 `PAN_SPEED=66`，双向 1732/1268 μs，点动 300 ms。

默认 `PAN_TEST_ONLY=1`：上电后松开 K2（A9），等待约 1 秒；之后每次在空闲时按 K2，交替做两个方向的底座点动，自动回到停止脉宽。长按不重复，运动中再次按下则提前取消。俯仰保持名义 90° 命令，上电可能从原位置回中。

`PAN_TEST_ONLY=0` 可恢复原六步 K2 测试：俯仰 80°、100°、90°、底座第一方向、第二方向、空闲。K1 电机及 K3/K4 视频控制保持原连接。

`PAN_USE_VENDOR_MAP=1` 时由 `PAN_SPEED` 决定运动脉宽；设为 0 才直接使用 `PAN_POS_US/PAN_NEG_US`。`PAN_DIR_INVERT=1` 交换方向。`PAN_STOP_US` 用于实测停止点校准。底座 PWM 被限制在 1000～2000 μs，俯仰保持 500～2500 μs 限幅。

360° 底座为连续旋转速度控制，不能按时间保证转角。FPGA 仿真无法确认电源、输入电平、负载及舵机本体正常；应在舵机插头处确认周期、脉宽、电平和供电，并做空载/装载验收。

完整替换步骤、参数、接线与验收表见本次修改包根目录的 `README_INSTALL_CN.md`，验证范围见 `VALIDATION_CN.md`。这些说明无需加入综合。
