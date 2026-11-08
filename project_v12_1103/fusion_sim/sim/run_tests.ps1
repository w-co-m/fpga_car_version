param(
    [string]$ModelSimBin = 'D:\modelsim\win64',
    [string]$SimTempRoot = [IO.Path]::GetTempPath(),
    [switch]$StageOnly
)
$ErrorActionPreference = 'Stop'
# ModelSim 10.6d cannot reliably open its SQLite libraries in Chinese paths.
$simTemp = $SimTempRoot
$env:TEMP = $simTemp
$env:TMP = $simTemp
$testRoot = Join-Path $simTemp ('suanfa_verify_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$testRoot\rtl" | Out-Null
Copy-Item -Path "$PSScriptRoot\..\..\user_source\algorithms\*.v" -Destination "$testRoot\rtl"
Copy-Item -Path "$PSScriptRoot\..\..\user_source\osd\*.v" -Destination "$testRoot\rtl"
Copy-Item -Path "$PSScriptRoot\*.v" -Destination $testRoot
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'reference/algo7_delivery/algo7_delivery_math_ref.vh') -Destination $testRoot
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'reference/slice_opt/awb_gain_divider_slice_ref.vh') -Destination $testRoot
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../user_source/ddr_page_map.vh') -Destination $testRoot
# The three integration regressions use the real legacy RTL/FIFO models.
# DDR core and camera slave are interface models scoped to their own test library.
$legacy = @{
 'tb_csi_abort_recovery' = @('user/hdl_source/isp/csi_unpacket_2lane.v')
 'tb_ddr_frame_safety' = @('user/hdl_source/video_in.v','user/hdl_source/video_out.v','user/hdl_source/mc_to_user_interface.v','user/ip_source/w128_d512_fifo/w128_d512_fifo.v','user/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v','user/ip_source/w155_d512_fifo/w155_d512_fifo.v','user/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v')
 'tb_video_out_mixer' = @('user/hdl_source/video_out.v','user/hdl_source/hdmi_mixer.v','user/ip_source/w128_d512_fifo/w128_d512_fifo.v','user/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v')
 'tb_ddr_backpressure' = @('user/hdl_source/mc_to_user_interface.v','user/hdl_source/ph1p35_ddr/ph1p35_324_ddr_wrapper.v','user/ip_source/w155_d512_fifo/w155_d512_fifo.v','user/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v','sim/ddr2_test_stub.v')
 'tb_camera_retry' = @('sim/reference/legacy_camera/uics520_cfg/uicfgcs520.v','sim/reference/legacy_camera/uics520_cfg/uics520reg_720p60.v','sim/reference/legacy_camera/uics520_cfg/uics520regAE.v','sim/reference/legacy_camera/uics520_cfg/SC520GainTbl.v')
}
$legacy['tb_display_page_guard'] = $legacy['tb_ddr_frame_safety']
$legacy['tb_ddr_capacity'] = $legacy['tb_ddr_frame_safety']
$legacy['tb_polar_videoio'] = $legacy['tb_ddr_frame_safety']
$legacy['tb_polar_videoio_async'] = $legacy['tb_ddr_frame_safety']
$legacy['tb_polar_awb'] = @('user/hdl_source/awb.v')
$legacy['tb_awb_slice_equiv'] = @('user/hdl_source/awb_gain_divider.v')
$legacy['tb_reset_domains'] = @('user/hdl_source/video_in.v','user/hdl_source/video_out.v','user/hdl_source/lane_lvds_10_1.v','user/ip_source/w128_d512_fifo/w128_d512_fifo.v','user/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v')
$legacy['tb_hdmi_vtc_stream'] = $legacy['tb_video_out_mixer'] + @('user/hdl_source/vtc/uivtc.v','user/hdl_source/mc_to_user_interface.v','user/ip_source/w155_d512_fifo/w155_d512_fifo.v','user/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v')
$legacy['tb_hdmi_offset'] = @('user/hdl_source/hdmi_mixer.v')
$ispContent = @('user/hdl_source/isp/demosaic_4x_2_0/raw_matrix_3x3_buffer.v','user/hdl_source/isp/demosaic_4x_2_0/mipi_to_raw_converter.v','user/hdl_source/isp/demosaic_4x_2_0/zhenghe.v','user/hdl_source/isp/demosaic_4x_2_0/line_buffer_demosaic.v','user/hdl_source/isp/demosaic_4x_2_0/demosaic.v','user/hdl_source/isp/demosaic_4x_2_0/bilinear_interpolation.v','sim/tb_isp_content.v')
$legacy['tb_isp_constant'] = $ispContent
$legacy['tb_isp_ramp'] = $ispContent
$legacy['tb_isp_small'] = $ispContent
$ispPack = $ispContent[0..5] + @('user/hdl_source/isp/isp_top.v','user/hdl_source/awb.v','user/hdl_source/signal_delay.v','user/hdl_source/data_96bit_to_128bit.v','user/hdl_source/isp/data128_96/data128_96.v','sim/tb_isp_pack.v')
$legacy['tb_isp_pack_constant'] = $ispPack
$legacy['tb_isp_pack_ramp'] = $ispPack


$legacy['tb_camera_init'] = @('user/hdl_source/uics500_cfg/uicfgcs500_720p.v','user/hdl_source/uics500_cfg/uics500reg_720p60.v','user/hdl_source/uics500_cfg/SC500GainTbl.v','user/hdl_source/uics500_cfg/uics500regAE.v')
$legacy['tb_camera_init'] += @('user/hdl_source/uiisp_beta/ae_set.v')
$legacy['tb_camera_profile'] = $legacy['tb_camera_init']
$legacy['tb_shared_ddr_complete'] = @('user/hdl_source/video_in.v','user/hdl_source/video_out.v','user/ip_source/w128_d512_fifo/w128_d512_fifo.v','user/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v')
$legacy['tb_shared_ddr_legacy'] = $legacy['tb_shared_ddr_complete']

# Review peripheral regressions keep the real ISP and FIFO models.
$legacy['tb_frame_transaction'] = $legacy['tb_video_out_mixer']
$legacy['tb_ddr_recovery_system'] = $legacy['tb_video_out_mixer'] + @('user/hdl_source/mc_to_user_interface.v','user/ip_source/w155_d512_fifo/w155_d512_fifo.v','user/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v')
$legacy['tb_hdmi_frame_transaction'] = $legacy['tb_hdmi_vtc_stream'] + @('sim/tb_hdmi_vtc_stream.v')
$legacy['tb_osd_direct_equiv'] = @('tools/review_peripheral_20261018/osd_video_status_osd_reference.v')
$legacy['tb_isp_capture_phase'] = $ispPack[0..5] + @('user/hdl_source/isp/isp_top.v','user/hdl_source/awb.v','user/hdl_source/signal_delay.v','user/hdl_source/data_96bit_to_128bit.v','user/hdl_source/isp/data128_96/data128_96.v','user/hdl_source/video_in.v','user/ip_source/w128_d512_fifo/w128_d512_fifo.v','user/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v')
$reviewIO = @('user/hdl_source/video_in.v','user/hdl_source/mc_to_user_interface.v','user/hdl_source/hdmi_tx.v','user/ip_source/w128_d512_fifo/w128_d512_fifo.v','user/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v','user/ip_source/w155_d512_fifo/w155_d512_fifo.v','user/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v')
$legacy['tb_review_io_guard'] = $reviewIO
$legacy['tb_mc_watchdog'] = $reviewIO
$legacy['tb_hdmi_reset'] = $reviewIO

foreach ($name in $legacy.Keys) {
    $folder = Join-Path $testRoot $name
    New-Item -ItemType Directory -Path $folder | Out-Null
    foreach ($relative in $legacy[$name]) {
        Copy-Item -LiteralPath (Join-Path "$PSScriptRoot/.." ($relative.Replace('user/','../user_source/'))) -Destination $folder
    }
}

# FRAME HEX changed to CNT; adapt only the copied reference used by the full
# pixel-equivalence bench. The checked-in frozen reference stays byte-identical.
$osdReferenceCopy = Join-Path (Join-Path $testRoot 'tb_osd_direct_equiv') 'osd_video_status_osd_reference.v'
$osdReferenceText = [IO.File]::ReadAllText($osdReferenceCopy).Replace("`r`n", "`n")
$oldLabel = @'
                2'd1: begin
                    case (index)
                        0:text_char="F"; 1:text_char="R"; 2:text_char="A";
                        3:text_char="M"; 4:text_char="E"; 5:text_char=" ";
                        6:text_char="H"; 7:text_char="E"; 8:text_char="X";
                        9:text_char=":"; 10:text_char=" ";
                        default: if ((index >= 11) && (index <= 18)) begin
                            nibble = (frame_value >> ((18-index)*4)) & 4'hf;
                            if (nibble < 10) text_char = 8'h30 + nibble;
                            else            text_char = 8'h41 + nibble - 10;
                        end
                    endcase
                end
'@
$newLabel = @'
                2'd1: begin
                    case (index)
                        0:text_char="C"; 1:text_char="N"; 2:text_char="T";
                        3:text_char=":"; 4:text_char=" ";
                        default: if ((index >= 5) && (index <= 12)) begin
                            nibble = (frame_value >> ((12-index)*4)) & 4'hf;
                            if (nibble < 10) text_char = 8'h30 + nibble;
                            else            text_char = 8'h41 + nibble - 10;
                        end
                    endcase
                end
'@
$oldLabel = $oldLabel.Replace("`r`n", "`n")
$newLabel = $newLabel.Replace("`r`n", "`n")
if (!$osdReferenceText.Contains($oldLabel)) { throw 'Copied OSD reference has no expected FRAME HEX label block.' }
[IO.File]::WriteAllText($osdReferenceCopy, $osdReferenceText.Replace($oldLabel, $newLabel), [Text.UTF8Encoding]::new($false))

if ($StageOnly) { Write-Output "PASS all regression dependencies staged: $testRoot"; return }
Push-Location $testRoot
try {
$rtl = @(Get-ChildItem -LiteralPath 'rtl' -Filter *.v | ForEach-Object FullName)
$mainBenches = @('tb_key_mode_ctrl','tb_algo_bank','tb_video_algorithm_display','tb_level_controls','tb_level_gain_osd','tb_video_status_osd','tb_algo_histeq','tb_nine_modes','tb_algo_level_rgb888','tb_algo_morph','tb_threshold_ctrl','tb_dynamic_thresholds','tb_threshold_display','tb_video_out_mixer','tb_ddr_backpressure','tb_camera_retry','tb_algo_polar_core','tb_polar_guard','tb_csi_abort_recovery','tb_osd_dash','tb_ddr_frame_safety','tb_ddr_capacity','tb_algo_fusion','tb_algo_polar_fusion','tb_polar_ui','tb_polar_block_engine','tb_polar_capture','tb_polar_arbiter','tb_polar_cdc','tb_polar_backend','tb_polar_videoio','tb_polar_videoio_async','tb_polar_awb','tb_awb_slice_equiv','tb_polar_retry_recovery','tb_display_page_guard','tb_good_frame_settle','tb_algo_edge_polar','tb_polar_edge_block','tb_algo9_system','tb_polar_osd_angles','tb_key_terminal_overlap','tb_polar_retry_service','tb_algo_color_detect','tb_algo_color_detect_720p','tb_algo10_system','tb_algo10_external_mode','tb_algo10_features','tb_algo10_shape_720p','tb_reset_sync','tb_reset_domains','tb_hdmi_vtc_stream','tb_hdmi_offset','tb_isp_constant','tb_isp_ramp','tb_isp_small','tb_isp_pack_constant','tb_isp_pack_ramp','tb_camera_init','tb_camera_profile','tb_shared_ddr_complete','tb_shared_ddr_legacy','tb_algo_motion_720','tb_algo_motion_small','tb_algo_track','tb_track_color_order','tb_algo1112_system','tb_algo1112_external_mode','tb_algo12_mode15','tb_osd_font','tb_algo_motion_spatial720','tb_ddr_page_map')
$mainBenches += 'tb_algo10_lighting'
$mainBenches += 'tb_algo10_pink_rect'
$mainBenches += 'tb_preview_gamma'
$mainBenches += 'tb_red_regions'
$mainBenches += 'tb_red_regions_limits'
$mainBenches += 'tb_red_regions_720p'
$mainBenches += 'tb_motion_low_contrast'
$mainBenches += 'tb_motion_low_contrast_edges'
$mainBenches += 'tb_motion_low_contrast_720p'
$mainBenches += 'tb_motion_threshold_controls'
$mainBenches += 'tb_motion_threshold_alignment'
$reviewBenches = @('tb_ddr_recovery','tb_ddr_read_timeout','tb_frame_transaction','tb_frame_guard_alignment','tb_ddr_recovery_system','tb_hdmi_frame_transaction','tb_logo_direct','tb_osd_direct_equiv','tb_polar_abort','tb_polar_terminal','tb_review_io_guard','tb_mc_watchdog','tb_hdmi_reset','tb_isp_capture_phase')
foreach ($name in ($mainBenches + $reviewBenches)) {
    $work = "verify_$name"
    if (!(Test-Path -LiteralPath $work)) { & "$ModelSimBin\vlib.exe" $work }
    $extra = @()
    if ($legacy.ContainsKey($name)) { $extra = @(Get-ChildItem -LiteralPath $name -Filter *.v | ForEach-Object FullName) }
    $testSource = "$name.v"
    if ($name -in @('tb_mc_watchdog','tb_hdmi_reset')) { $testSource = 'tb_review_io_guard.v' }
    if ($name -eq 'tb_camera_profile') { $testSource = 'tb_camera_init.v' }
    if ($name -eq 'tb_polar_videoio_async') { $testSource = 'tb_polar_videoio.v' }
    if ($name -in @('tb_shared_ddr_complete','tb_shared_ddr_legacy')) { $testSource = 'tb_shared_ddr.v' }
    $defines = @()
    if ($name -eq 'tb_good_frame_settle') { $defines = @('+define+GOOD_SETTLE_AVAILABLE') }
    if ($name -eq 'tb_algo9_system') { $defines = @('+define+ALGO9_AVAILABLE') }
    if ($name -eq 'tb_algo10_pink_rect') { $defines = @('+define+PINK_RECT_DEBUG_TEST') }
    if ($name -eq 'tb_preview_gamma') { $defines = @('+define+PREVIEW_GAMMA_AVAILABLE') }
    $compile = & "$ModelSimBin\vlog.exe" -work $work '+incdir+.' "+incdir+$testRoot/rtl" "+incdir+$testRoot/$name" @defines @rtl @extra $testSource 2>&1
    $compile | Set-Content -LiteralPath "$PSScriptRoot\$name.compile.log" -Encoding utf8
    $compile | Write-Output
    if ($LASTEXITCODE -ne 0) { throw "Compile failed: $name" }
    $output = & "$ModelSimBin\vsim.exe" -c -onfinish exit -lib $work $name -do 'run -all; quit -f' 2>&1
    $output | Set-Content -LiteralPath "$PSScriptRoot\$name.log" -Encoding utf8
    $output | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($output -match '\*\* (Error|Fatal)|FAIL|errors=[1-9]') -or !(($output -join "`n") -match 'PASS|errors=0')) { throw "Simulation failed: $name" }
}
} finally { Pop-Location }

# Dedicated resource-optimization checks use frozen references and real gain
# arithmetic rather than the unity-gain stubs in the packing regressions.
& (Join-Path $PSScriptRoot '../tools/run_awb_resource_tests.ps1') -ModelSimBin $ModelSimBin
& (Join-Path $PSScriptRoot '../tools/run_osd_resource_tests.ps1') -ModelSimBin $ModelSimBin
& (Join-Path $PSScriptRoot '../tools/run_polar_cache_tests.ps1') -ModelSimBin $ModelSimBin
& (Join-Path $PSScriptRoot '../tools/run_shared_ddr_720p.ps1') -ModelSimBin $ModelSimBin
& (Join-Path $PSScriptRoot '../tools/run_algo7_color_tests.ps1') -ModelSimBin $ModelSimBin
Write-Output ("PASS FULL_REGRESSION main=" + ($mainBenches.Count + $reviewBenches.Count) + " special=5")


