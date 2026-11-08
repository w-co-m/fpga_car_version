onerror {quit -code 1 -f}
if {![info exists r]} {error "Set r to the fusion workspace before running this script"}
set u $r/../user_source
if {[info exists validation_output]} {set d $validation_output} else {set d $r/validation_fusion}
file mkdir $d
cd $d
if {![file exists work]} {vlib work}
vmap work work
eval vlog -work work +incdir+$u/algorithms [glob $u/algorithms/*.v $u/osd/*.v $u/hdl_source/servo_control/*.v $u/hdl_source/motor_control/*.v]
vlog -sv -work work $r/sim/tb_fusion_tracking.sv $r/sim/tb_fusion_osd.sv $r/sim/tb_fresh_regions.sv $r/tracking_sim/tb_auto_gimbal.sv $r/tracking_sim/tb_target_cdc.sv $r/tracking_sim/tb_gimbal_pwm_integration.sv
foreach tb {tb_auto_gimbal tb_target_cdc tb_gimbal_pwm_integration tb_fusion_tracking tb_fusion_osd tb_fresh_regions} {
 vsim -c -onfinish stop -voptargs=+acc work.$tb
 run -all
 quit -sim
}
quit -code 0 -f
