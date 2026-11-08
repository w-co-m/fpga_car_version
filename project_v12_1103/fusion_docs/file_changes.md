# 相对原 v8 的逐文件变更

路径相对 project_v8_1022。SHA256 见 source_manifest.json；未列出的 181 个源目录文件保持字节不变。40/19/30 的统计含头文件、ADC 和说明/元数据；其中 RTL 为新增 38、修改 18、移除 26。旧版已替换文件随部署备份，未因名称相近随意删除依赖。

## 新增（40）

|文件|原因/改动|
|---|---|
|`user_source/algorithms/algo_bank.v`|16 路统一选择、统一 5 拍输出；共享检测/跟踪，导出遥测，F 仅消费 fresh 测量。|
|`user_source/algorithms/algo_binary.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_bright.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_color_detect.v`|共享唯一颜色检测器，导出 bbox_fresh，保留 D 模式抗闪烁显示。|
|`user_source/algorithms/algo_contrast.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_edge_polar.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_fusion.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_gray.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_histeq.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_level.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_morph.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_motion.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_passthrough.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_polar_core.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_polar_fusion.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_sobel.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/algo_track.v`|移植队友平滑/漏检跟踪器，新增与更新状态同拍的 update_out。|
|`user_source/algorithms/ddr_recovery_supervisor.v`|队友复位、DDR 恢复或帧事务 CDC 必需模块，与仲裁及页保护整体移植。|
|`user_source/algorithms/frame_mailbox_cdc.v`|队友复位、DDR 恢复或帧事务 CDC 必需模块，与仲裁及页保护整体移植。|
|`user_source/algorithms/key_mode_ctrl.v`|单个按键状态机：前后模式、阈值/增益、偏振采集和重启；16 模式循环。|
|`user_source/algorithms/line_buffer_3x3.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/line_buffer_3x3_sparse.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/algorithms/polar_block_engine.v`|队友四角度采集/计算/仲裁/状态后台的必要依赖；整体移植，不能只拷贝像素算法。|
|`user_source/algorithms/polar_capture_ctrl.v`|队友四角度采集/计算/仲裁/状态后台的必要依赖；整体移植，不能只拷贝像素算法。|
|`user_source/algorithms/polar_ddr_arbiter.v`|队友四角度采集/计算/仲裁/状态后台的必要依赖；整体移植，不能只拷贝像素算法。|
|`user_source/algorithms/polar_status_cdc.v`|队友四角度采集/计算/仲裁/状态后台的必要依赖；整体移植，不能只拷贝像素算法。|
|`user_source/algorithms/polar_video_backend.v`|队友四角度采集/计算/仲裁/状态后台的必要依赖；整体移植，不能只拷贝像素算法。|
|`user_source/algorithms/red_region_selector.v`|移植逐行连通区域与单目标关联；新增 measurement_valid，溢出和保留框不作为新测量。|
|`user_source/algorithms/reset_sync.v`|队友复位、DDR 恢复或帧事务 CDC 必需模块，与仲裁及页保护整体移植。|
|`user_source/algorithms/video_algorithm_display.v`|统一按键及帧边界控制、真实 DDR 模式与帧有效性保护，导出跟踪遥测。|
|`user_source/algorithms/video_delay.v`|移植队友统一算法/行缓存/延迟模块，替代旧 video_app 同功能分支；不叠加第二套算法库。|
|`user_source/ddr_page_map.vh`|唯一 DDR 页表，算法和 video_in/out 使用相对源文件路径引用，支持干净重建。|
|`user_source/hdl_source/awb_gain_divider.v`|移植队友低资源白平衡除法实现；保留原 IP 文件供参考回归，主路径不重复例化。|
|`user_source/hdl_source/image_correction.v`|队友未注册、未例化的历史采集参考，不接入 720p 主链，不算本版功能；可单独归档，保留文件不会占硬件资源。|
|`user_source/hdl_source/isp/demosaic_4x_2_0/blk_mem_gen_demosaic/.m_params_blk_mem_gen_demosaic.txt`|随包 IP 生成参数元数据，非 RTL；保留以供 IP 配置追溯，不单独消耗资源。|
|`user_source/hdl_source/servo_control/camera_activity_watchdog.v`|新增 DDR 有效摄像头帧→100 MHz 活动检测；200 ms 无新有效帧禁止旧画面继续驱动云台。|
|`user_source/osd/anlogic_logo_rom.v`|队友统一 OSD 字库或 Logo ROM 依赖；实际综合保留被实例使用的实现，测试仍使用参考 ROM。|
|`user_source/osd/anlogic_logo_sync_rom_direct.v`|队友统一 OSD 字库或 Logo ROM 依赖；实际综合保留被实例使用的实现，测试仍使用参考 ROM。|
|`user_source/osd/osd_char_lib.v`|队友统一 OSD 字库或 Logo ROM 依赖；实际综合保留被实例使用的实现，测试仍使用参考 ROM。|
|`user_source/osd/video_status_osd.v`|唯一 OSD：保留 Logo，顶层选择六位十进制帧号，增加两级同步的自动云台状态块。|

## 修改（19）

|文件|原因/改动|
|---|---|
|`user_source/constraints_source/pin.adc`|保留全部原引脚位置，加入 I_threshold_edit→B4；算法键和执行器键分属独立功能。|
|`user_source/hdl_source/awb.v`|移植固定白平衡/低资源运算，配合偏振采集，保留相应回归。|
|`user_source/hdl_source/data_96bit_to_128bit.v`|采用队友帧边界一致的打包控制。|
|`user_source/hdl_source/design_top_wrapper.v`|统一队友图像/DDR 后台与 v8 执行器；F 门控自动跟随，连接坐标 CDC、有效性、摄像头看门狗及 OSD。|
|`user_source/hdl_source/hdmi_mixer.v`|采用队友有效像素窗口/同步对齐，保持 720p mixer 架构；唯一 OSD 在后级。|
|`user_source/hdl_source/hdmi_tx.v`|采用队友 HDMI 帧接口及复位处理，与像素有效性路径配套。|
|`user_source/hdl_source/isp/csi_unpacket_2lane.v`|采用队友 CSI 异常/包长度和帧中止恢复处理。|
|`user_source/hdl_source/isp/demosaic_4x_2_0/raw_matrix_3x3_buffer.v`|移植队友完整帧/行相位配套处理。|
|`user_source/hdl_source/isp/demosaic_4x_2_0/zhenghe.v`|移植队友 demosaic 行列/帧相位配套处理。|
|`user_source/hdl_source/isp/isp_top.v`|移植与帧丢弃、白平衡及 ISP 打包一致的接口。|
|`user_source/hdl_source/lane_lvds_10_1.v`|采用队友跨域复位/释放处理。|
|`user_source/hdl_source/mc_to_user_interface.v`|移植 DDR 请求队列、忙闲、读返回及复位请求协议，匹配偏振仲裁后端。|
|`user_source/hdl_source/ph1p35_ddr/ph1p35_324_ddr_wrapper.v`|移植 DDR 控制器复位与客户端接口；仅保留一个 DDR IP 实例。|
|`user_source/hdl_source/uics500_cfg/uicfgcs500_720p.v`|保留 SC500，移植队友 720p 传感器配置/曝光配套控制。|
|`user_source/hdl_source/uics500_cfg/uics500reg_720p60.v`|仅注释不同，116 项寄存器值未改变，保留 SC500CS 720p60。|
|`user_source/hdl_source/uiisp_beta/ae_set.v`|仅注释不同，曝光 1990、增益 80 与基线相同。|
|`user_source/hdl_source/video_in.v`|移植完整帧长度/丢帧、页有效性与读写页保护，并输出摄像头有效帧事件；包含路径改为单一页表。|
|`user_source/hdl_source/video_out.v`|移植帧 ticket/ack、真实显示模式、源页锁定、欠流保护及像素帧有效性；包含路径改为单一页表。|
|`user_source/ip_source/PLL/PLL.v`|仅随包头部构建时间戳不同；PLL 逻辑、端口和频率参数未改变。|

## 删除（30）

|文件|原因/改动|
|---|---|
|`user_source/hdl_source/video_app/algo_pipeline.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/basic/algo_binary.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/basic/algo_gray.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/basic/algo_passthrough.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/basic/algo_sobel.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/common/line_buffer_3x3.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/common/video_delay.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/control/key_debounce.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/control/mode_ctrl.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/enhance/README.md`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/enhance/algo_bright.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/enhance/algo_contrast.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/enhance/algo_histeq.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/enhance/algo_level.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/enhance/algo_morph.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/osd/README.md`|旧独立 OSD/Logo/计数器并入统一 video_status_osd；旧字模/ROM 不再重复注册。|
|`user_source/hdl_source/video_app/osd/anlogic_logo_counter.v`|旧独立 OSD/Logo/计数器并入统一 video_status_osd；旧字模/ROM 不再重复注册。|
|`user_source/hdl_source/video_app/osd/anlogic_logo_rom_indexed.v`|旧独立 OSD/Logo/计数器并入统一 video_status_osd；旧字模/ROM 不再重复注册。|
|`user_source/hdl_source/video_app/osd/osd_char_lib.v`|旧独立 OSD/Logo/计数器并入统一 video_status_osd；旧字模/ROM 不再重复注册。|
|`user_source/hdl_source/video_app/osd/video_osd_labels.v`|旧独立 OSD/Logo/计数器并入统一 video_status_osd；旧字模/ROM 不再重复注册。|
|`user_source/hdl_source/video_app/perception/README.md`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/perception/algo_color_detect.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/perception/algo_motion.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/perception/algo_track.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|
|`user_source/hdl_source/video_app/polarization/README.md`|原 v8 普通相机偏振 DEMO 链路被真实四角度 DDR 后台替代；原文件在备份保留。|
|`user_source/hdl_source/video_app/polarization/algo_edge_polar.v`|原 v8 普通相机偏振 DEMO 链路被真实四角度 DDR 后台替代；原文件在备份保留。|
|`user_source/hdl_source/video_app/polarization/algo_fusion.v`|原 v8 普通相机偏振 DEMO 链路被真实四角度 DDR 后台替代；原文件在备份保留。|
|`user_source/hdl_source/video_app/polarization/algo_polar.v`|原 v8 普通相机偏振 DEMO 链路被真实四角度 DDR 后台替代；原文件在备份保留。|
|`user_source/hdl_source/video_app/polarization/polar_demo_source.v`|原 v8 普通相机偏振 DEMO 链路被真实四角度 DDR 后台替代；原文件在备份保留。|
|`user_source/hdl_source/video_app/video_app_top.v`|原 video_app 活动链路由 algorithms/ 的统一实现替代，避免模块重名与重复实例；旧版在备份保留。|

## 工程、约束与交付文件

|文件|处理|
|---|---|
|`td_project/camera_to_dsi_display.al`|注册统一图像子系统和 v8 执行器共 96 个项目条目；移除旧 video_app 注册；型号、顶层、原目录入口保留。|
|`td_project/camera_to_dsi_display.sdc`|队友帧事务/DDR 跨域约束与原执行器异步按键约束合并；100 MHz 与 75 MHz 同源路径继续计时。|
|`td_project/camera_to_dsi_display_Runs/{syn_1,phy_1}/camera_to_dsi_display.prj`|重新生成相对路径的同一源列表，删除旧链路条目。|
|`td_project/camera_to_dsi_display_Runs/{syn_1,phy_1}/{settings.cfg,camera_to_dsi_display.tcl}`|保留标准 fresh 综合/物理流程及压缩 bitgen 配置，使用本版源文件，原运行目录整体备份。|
|`fusion_sim/`|可重跑的最终测试、独立参考、路径已改为工程内相对位置的启动脚本；不把历史 work 库当输入。|
|`fusion_docs/`|模式、按键、文件清单、差异补丁、输入哈希、引脚审计、资源时序、仿真及构建日志。|
|`README_v8_双工程融合说明.md`|当前入口说明。原跟踪说明改为历史版本指引，完整旧说明随备份保留。|

## 已确认无需叠加的逻辑

- 一套 algo_bank、一套 key_mode_ctrl、一套 OSD、一套 motor_control_top、一套 gimbal_control_top 和一套 servo_pwm_dual。
- D/F 复用唯一颜色检测与连通区域选择；F 不再消费 D 的保留有效框。
- 旧 v8 偏振 DEMO、31 拍对齐链及独立 Logo/帧计数器不与队友实现并行综合。
- 摄像头非活动分辨率源码及 IP 保留为工程材料，未注册内容不会额外消耗硬件。
- 队友 tools 中 YOLO、历史 build/user 镜像、archive 不进入综合。不同增强/形态学语义已在主说明明确，不能以同名为由删功能。
