

// 顶层作用：连接摄像头采集、ISP、DDR 帧缓存、算法切换和 HDMI 输出。
// 不同链路使用不同的时钟域，跨域传输应沿用现有 FIFO/同步结构，不直接接裸数据。
module design_top_wrapper (
    input wire        I_sys_clk,
    input wire        I_rst_n,
      
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      
    // 两键低有效：位0接B9（实板Key2）（上一种、逻辑key0_n）；位1接C7（实板Key3）（下一种、逻辑key1_n）。
    input wire [1:0]  I_button,
    // SW1/B4：0切换算法；1在BIN/SOBEL调阈值，在DOLP/AOP/FUSION/PEDGE中B9重启、C7采集。
    input wire        I_threshold_edit,

    // KEY1(D5), KEY2(A9); existing KEY3/4 remain I_button[0/1].
    input wire [1:0] I_motor_key_n,
    output wire O_motor_ain1,
    output wire O_motor_ain2,
    output wire O_motor_pwma,
    output wire O_motor_bin1,
    output wire O_motor_bin2,
    output wire O_motor_pwmb,
    output wire O_motor_stby,
    output wire O_servo_pan_pwm,
    output wire O_servo_tilt_pwm,

    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,

    inout wire        IO_rx_clk_pad_n, 
    inout wire        IO_rx_clk_pad_p, 
    inout wire[3:0]   IO_rx_data_pad_n,
    inout wire[3:0]   IO_rx_data_pad_p,

    output wire[12:0] ddr_addr,
    output wire[ 1:0] ddr_ba,
    output wire[ 0:0] ddr_cke,
    output wire[ 0:0] ddr_odt,
    output wire[ 0:0] ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire[ 0:0] ddr_ck_p,
    output wire[ 0:0] ddr_ck_n,
    inout wire[1:0]   ddr_dm,
    inout wire[15:0]  ddr_dq,
    inout wire[1:0]   ddr_dqs_p,
    inout wire[1:0]   ddr_dqs_n   
);


    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;
		
	wire        	S_pll_lock;
    wire        	S_rst_n; // 异步复位源，仅送同步器和多时钟模块
    wire S_sys_rst_n, S_cam_rst_n, S_csi_rst_n, S_ddr_rst_n;
    wire S_ddr_controller_rst_n,S_ddr_clients_rst_n,S_data_rst_n;
    wire S_backend_reset_required,S_mc_reset_required;
    wire[1:0]S_ddr_recovery_state;
    wire[3:0]S_vo_pixel_mode;
    wire S_vo_pixel_valid;
    reg[15:0]S_ddr_heartbeat_count;
    reg S_ddr_heartbeat;
    (* async_reg="true" *) reg[1:0]S_recovery_pixel_1,S_recovery_pixel_2;
    reg[2:0]S_frame_valid_mixer;
	(* keep = "true" *) wire        S_cam_i2c_error;
	
	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req; 
	
	wire        	S_csi_rx_clk;  
    wire        	S_hs_rx_valid;  
    wire[15:0]  	S_hs_rx_data;   
	wire[1:0]   	S_lane_error;
	
	wire        	S_csi_frame_start;       
	wire        	S_csi_frame_end;         
	wire        	S_csi_valid;             
	wire[31:0]  	S_csi_data;  
	(* keep = "true" *) wire [15:0] S_csi_data_length;
		
	wire        	S_raw10_frame_start; 
	wire        	S_raw10_frame_end;   
	wire        	S_raw10_valid;       
	wire [39:0] 	S_raw10_data;

	wire 			S_axis_tlast;  
	wire 			S_axis_tuser;  
	wire [39:0]		S_axis_tdata;  
	wire 			S_axis_tvalid; 
	
	wire [39:0]		S_raw_tdata ;
	wire			S_raw_tlast ;
	wire 			S_raw_tvalid;
	wire 			S_raw_tuser ;
	
	wire			S_ISP_O_tready;
	wire [127:0]	S_ISP_O_tdata ;
	wire 			S_ISP_O_tlast ;
	wire 			S_ISP_O_tuser ;
	wire 			S_ISP_O_tvalid; 
	

    wire        S_ddr_clk;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hdmi_rst_n;
    wire        S_video_out_rst_n;


    wire        S_vi_128b_frame_start;
    wire        S_vi_128b_valid;      
    wire[127:0] S_vi_128b_data;    
    
    wire        S_video_out_rd_busy;
    wire        S_video_in_wr_busy; 
    wire[1:0]   S_video_out_rp;     

    wire        S_ddr_user_wr_en;       
    wire        S_ddr_user_rd_en;       
    wire[24:0]  S_ddr_user_addr;        
    wire[127:0] S_ddr_user_wr_data;     
    wire        S_ddr_user_ready;       
    wire        S_ddr_user_rd_valid;    
    wire[127:0] S_ddr_user_rd_data;     

    wire        S_vi_ddr_wr_en;   
    wire[24:0]  S_vi_ddr_wr_addr; 
    wire[127:0] S_vi_ddr_wr_data;
    wire        S_vi_ddr_wr_ready;

    wire        S_vo_ddr_rd_en;   
    wire[24:0]  S_vo_ddr_rd_addr; 
    wire        S_vo_ddr_rd_ready;

    // 四角度/三结果均位于DDR独立页；后台只按短块接管同一个MC队列。
    wire S_polar_pause, S_polar_owner, S_live_ready, S_vo_return_valid, S_mc_queue_idle;
    wire S_camera_frame_ddr, S_camera_good_frame_ddr, S_vo_pending, S_vo_result_active, S_vo_underflow;
    wire [3:0] S_live_page_valid, S_mode_pending, S_render_mode, S_vo_frame_mode;
    wire [3:0] S_source_mode;
    wire [3:0] S_display_page_mask;
    wire [24:0] S_source_base;
    wire S_source_is_result, S_source_valid, S_capture_pulse, S_restart_pulse, S_polar_fixed_wb;
    wire [8:0] S_vo_fill;
    wire [9:0] S_vo_credit;
    wire [1:0] S_polar_angle;
    wire S_polar_capture_busy, S_polar_compute_busy, S_polar_ready, S_polar_error;
    wire        S_init_calib_complete; 
    wire[24:0]  S_mc_app_addr;          
    wire[2:0]   S_mc_app_cmd;           
    wire        S_mc_app_en;            
    wire[127:0] S_mc_app_wdf_data;      
    wire        S_mc_app_wdf_end;       
    wire[15:0]  S_mc_app_wdf_mask;      
    wire        S_mc_app_wdf_wren;      
    wire[127:0] S_mc_app_rd_data;       
    wire        S_mc_app_rd_data_end;   
    wire        S_mc_app_rd_data_valid; 
    wire        S_mc_app_rdy;           
    wire        S_mc_app_wdf_rdy;       

    wire        S_hdmi_vsync;
    wire        S_hdmi_hsync;
    wire        S_hdmi_de;
    wire        S_hdmi_user;
    wire        S_hdmi_last;
    wire        S_video_out_vsync;
    wire        S_hdmi_window_rd_en;
    wire        S_hdmi_out_vsync;
    wire        S_hdmi_out_hsync;
    wire        S_hdmi_out_de;
    wire[23:0]  S_hdmi_out_data;

    wire[23:0]  S_video_rd_data;
    // 保留最小MIPI诊断；移除没有消费者的采样遥测。
    reg         S_dbg_hs_seen;
    wire[3:0]   S_hdmi_debug_status;
    wire        S_lane_error_any;
    wire        S_csi_packet_start;
    reg         S_csi_length_active_d;
    reg [10:0]  S_mipi_line_count;
    reg         S_mipi_length_error;
    reg         S_mipi_lane_error;
    reg         S_mipi_frame_seen;
    reg         S_mipi_frame_done;
    reg         S_mipi_last_length_error;
    reg         S_mipi_last_line_error;
    reg         S_mipi_last_lane_error;
    wire[3:0]   S_mipi_diag_status_async;
    reg [3:0]   S_mipi_diag_status_sync1;
    reg [3:0]   S_mipi_diag_status_sync2;


    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    // PLL自身仍由SW0复位；其lock不能反过来复位PLL，否则无法启动。
    assign S_rst_n = I_rst_n & S_pll_lock;
    assign S_data_rst_n = S_rst_n & S_ddr_clients_rst_n;
    assign S_ISP_O_tready = 1'b1; // Camera/ISP cannot be throttled; VI discards incomplete frames.
    ddr_recovery_supervisor u_ddr_recovery(
        .clk(I_sys_clk),.por_n(I_rst_n),.base_ready(S_pll_lock),
        .calibrated(S_init_calib_complete),.ddr_fault(S_backend_reset_required | S_mc_reset_required),
        .ddr_heartbeat(S_ddr_heartbeat),.controller_reset_n(S_ddr_controller_rst_n),
        .clients_reset_n(S_ddr_clients_rst_n),.status(S_ddr_recovery_state));
    always @(posedge S_ddr_clk or negedge S_data_rst_n)
        if(!S_data_rst_n)begin S_ddr_heartbeat_count<=0;S_ddr_heartbeat<=0;end
        else begin
            S_ddr_heartbeat_count<=S_ddr_heartbeat_count+1'b1;
            if(&S_ddr_heartbeat_count)S_ddr_heartbeat<=~S_ddr_heartbeat;
        end
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
        if(!S_hdmi_rst_n)begin S_recovery_pixel_1<=1;S_recovery_pixel_2<=1;S_frame_valid_mixer<=0;end
        else begin
            S_recovery_pixel_1<=S_ddr_recovery_state;S_recovery_pixel_2<=S_recovery_pixel_1;
            S_frame_valid_mixer<={S_frame_valid_mixer[1:0],S_vo_pixel_valid && S_ddr_clients_rst_n};
        end
    reset_sync u_reset_sys(.clk(I_sys_clk),.async_rst_n(S_rst_n),.rst_n(S_sys_rst_n));
    reset_sync u_reset_cam(.clk(S_24m_clk),.async_rst_n(S_rst_n),.rst_n(S_cam_rst_n));
    reset_sync u_reset_csi(.clk(S_csi_rx_clk),.async_rst_n(S_rst_n),.rst_n(S_csi_rst_n));
    reset_sync u_reset_ddr(.clk(S_ddr_clk),.async_rst_n(S_data_rst_n),.rst_n(S_ddr_rst_n));
    reset_sync u_reset_pixel(.clk(S_hdmi_pixel_clk),.async_rst_n(S_rst_n),.rst_n(S_hdmi_rst_n));

    wire S_target_update,S_target_mode_e,S_target_valid;
    wire [10:0] S_target_cx;
    wire [9:0] S_target_cy,S_target_height;
    wire S_auto_armed,S_auto_live,S_auto_cancel,S_camera_alive;
    // Independent motor control; stop on external reset or PLL unlock.
    // Set A_INVERT/B_INVERT after checking the physical wheel orientation.
    motor_control_top #(
        .CLK_HZ(100000000), .PWM_HZ(10000),
        .A_INVERT(1), .B_INVERT(1)
    ) u_motor_ctrl (
        .clk(S_100m_clk), .arst_n(I_rst_n & S_pll_lock),
        .key_n({1'b1, I_motor_key_n[0]}),
        .auto_mode(S_target_mode_e), .auto_armed(S_auto_armed),
        .auto_target_update(S_target_update),
        .auto_target_valid(S_target_valid && S_camera_alive),
        .auto_target_cx(S_target_cx), .auto_target_height(S_target_height),
        .auto_cancel(S_auto_cancel),
        .O_motor_ain1(O_motor_ain1), .O_motor_ain2(O_motor_ain2),
        .O_motor_pwma(O_motor_pwma),
        .O_motor_bin1(O_motor_bin1), .O_motor_bin2(O_motor_bin2),
        .O_motor_pwmb(O_motor_pwmb), .O_motor_stby(O_motor_stby)
    );
    // Registered frame telemetry, pixel clock -> 100 MHz control clock.
    wire S_trk_update,S_trk_valid;
    wire [4:0] S_trk_lost;
    wire [10:0] S_trk_x0,S_trk_x1;
    wire [9:0] S_trk_y0,S_trk_y1;
    wire [11:0] S_trk_xsum={1'b0,S_trk_x0}+{1'b0,S_trk_x1};
    wire [10:0] S_trk_ysum={1'b0,S_trk_y0}+{1'b0,S_trk_y1};
    wire [10:0] S_trk_height =
        (S_trk_valid && S_trk_y1 >= S_trk_y0) ?
        ({1'b0,S_trk_y1} - {1'b0,S_trk_y0} + 11'd1) : 11'd0;
    track_target_cdc u_track_cdc(
        .arst_n(I_rst_n & S_pll_lock),.src_clk(S_hdmi_pixel_clk),.dst_clk(S_100m_clk),
        .src_send(S_trk_update),.src_mode_e(S_render_mode==4'hF),
        .src_valid(S_trk_valid && S_trk_lost==0 && S_frame_valid_mixer[2] && S_ddr_clients_rst_n && S_trk_height!=0 && S_trk_height<=720),
        .src_cx(S_trk_xsum[11:1]),.src_cy(S_trk_ysum[10:1]),.src_height(S_trk_height[9:0]),
        .dst_update(S_target_update),.dst_mode_e(S_target_mode_e),.dst_valid(S_target_valid),
        .dst_cx(S_target_cx),.dst_cy(S_target_cy),.dst_height(S_target_height));
    // F is TRACK in the unified 16-mode map. KEY2(A9) arms/disarms auto in F.
    // Outside F the original six-step manual test is retained.
    // PAN_TEST_ONLY=0 restores the original tilt+pan six-step test.
    // Vendor speed map: +/-66 -> 1732/1268 us; neutral remains 1500 us.
    gimbal_control_top #(
        .CLK_HZ(100000000), .FRAME_US(20000),
        .PAN_STOP_US(1500), .PAN_POS_US(1732), .PAN_NEG_US(1268),
        .PAN_DIR_INVERT(1), .PAN_JOG_MS(300),
        .PAN_TEST_ONLY(0), .PAN_USE_VENDOR_MAP(1), .PAN_SPEED(66),
        .TILT_HOME_DEG(90), .TILT_MIN_DEG(80), .TILT_MAX_DEG(100),
        .TILT_DIR_INVERT(0), .TILT_STEP_US(5)
    ) u_gimbal_ctrl (
        .clk(S_100m_clk), .arst_n(I_rst_n & S_pll_lock),
        .key2_n(I_motor_key_n[1]), .auto_cancel(S_auto_cancel),
        .target_update(S_target_update),.target_mode_e(S_target_mode_e),.target_valid(S_target_valid && S_camera_alive),
        .target_cx(S_target_cx),.target_cy(S_target_cy),.auto_armed(S_auto_armed),.auto_live(S_auto_live),
        .O_servo_pan_pwm(O_servo_pan_pwm),
        .O_servo_tilt_pwm(O_servo_tilt_pwm)
    );



    // A frozen DDR frame must not keep steering after the camera stops producing good frames.
    camera_activity_watchdog #(.CLK_HZ(100000000),.TIMEOUT_MS(200)) u_camera_watchdog(
        .arst_n(S_rst_n),.camera_clk(S_ddr_clk),.camera_good_frame(S_camera_good_frame_ddr),
        .ctrl_clk(S_100m_clk),.camera_alive(S_camera_alive));

    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n) begin
        if(!S_csi_rst_n)
            S_dbg_hs_seen <= 1'b0;
        else if(S_hs_rx_valid)
            S_dbg_hs_seen <= 1'b1;
    end

    assign S_lane_error_any = |S_lane_error;

    // A RAW10 line contains 1280 * 10 / 8 = 1600 bytes.  The CSI parser
    // reports the number of 16-bit lane words, therefore the expected value
    // is 1600 / 2 = 800 = 16'h0320.  Count one long packet whenever that
    // decoded length changes from zero to non-zero.
    assign S_csi_packet_start = (S_csi_data_length != 16'd0) &&
                                !S_csi_length_active_d;

    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n) begin
        if(!S_csi_rst_n) begin
            S_csi_length_active_d      <= 1'b0;
            S_mipi_line_count          <= 11'd0;
            S_mipi_length_error        <= 1'b0;
            S_mipi_lane_error          <= 1'b0;
            S_mipi_frame_seen          <= 1'b0;
            S_mipi_frame_done          <= 1'b0;
            S_mipi_last_length_error   <= 1'b0;
            S_mipi_last_line_error     <= 1'b0;
            S_mipi_last_lane_error     <= 1'b0;
        end
        else begin
            S_csi_length_active_d <= (S_csi_data_length != 16'd0);

            if(S_csi_frame_start) begin
                S_mipi_line_count   <= 11'd0;
                S_mipi_length_error <= 1'b0;
                S_mipi_lane_error   <= 1'b0;
                S_mipi_frame_seen   <= 1'b1;
            end
            else begin
                if(S_csi_packet_start) begin
                    S_mipi_line_count <= S_mipi_line_count + 11'd1;
                    if(S_csi_data_length != 16'h0320)
                        S_mipi_length_error <= 1'b1;
                end

                if(S_lane_error_any)
                    S_mipi_lane_error <= 1'b1;
            end

            // Publish only a completed frame, so the HDMI-domain diagnostic
            // sees a stable result rather than counters changing every line.
            if(S_csi_frame_end) begin
                S_mipi_frame_done        <= 1'b1;
                S_mipi_last_length_error <= S_mipi_length_error;
                S_mipi_last_line_error   <= (S_mipi_line_count != 11'd720);
                S_mipi_last_lane_error   <= S_mipi_lane_error |
                                            S_lane_error_any;
            end
        end
    end

    // Diagnostic result codes consumed by hdmi_mixer DEBUG_MODE=4:
    // 0=config incomplete, 1=no HS traffic, 2=no completed CSI frame,
    // 3=lane error, 4=wrong RAW10 line length, 5=wrong lines/frame,
    // 6=the observed MIPI frame structure is correct, 7=I2C error.
    // I2C error has the highest priority because O_cfg_done only indicates
    // that the write sequencer reached its end; it does not prove that every
    // sensor register write was acknowledged successfully.
    assign S_mipi_diag_status_async =
        S_cam_i2c_error              ? 4'd7 :
        !S_cam_cfg_done              ? 4'd0 :
        !S_dbg_hs_seen               ? 4'd1 :
        !(S_mipi_frame_seen &&
          S_mipi_frame_done)         ? 4'd2 :
        S_mipi_last_lane_error       ? 4'd3 :
        S_mipi_last_length_error     ? 4'd4 :
        S_mipi_last_line_error       ? 4'd5 : 4'd6;

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_mipi_diag_status_sync1 <= 4'd0;
            S_mipi_diag_status_sync2 <= 4'd0;
        end
        else begin
            S_mipi_diag_status_sync1 <= S_mipi_diag_status_async;
            S_mipi_diag_status_sync2 <= S_mipi_diag_status_sync1;
        end
    end

    assign S_hdmi_debug_status = S_mipi_diag_status_sync2;
	
	// 按同板已出图例程保持PWDNB为高电平；复位由配置核完成软复位。
	assign O_cam_rst = 1'b1;
    assign O_cam_24m 	= S_24m_clk;
	
	
	
	
    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( ~I_rst_n          ),
        
        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),

        .clk4_out    ( S_hdmi_pixel_clk  ),
        .clk5_out    ( S_hdmi_serial_clk ),

        .lock        ( S_pll_lock        )

    );


	

  
  ae_set u_ae_set (
      .I_clk(S_24m_clk),
      .I_rst(~S_cam_rst_n),
      .I_btn(4'b1111),
      .I_cam_cfg_done(S_cam_cfg_done),
      .I_ae_cfg_done(S_ae_cfg_done),
      .O_ae_req(S_ae_req),
      .O_ae(S_ae),
      .O_ag(S_ag)
  );
  
    uicfgcs500_720p #(
      .CLK_DIV(24000000 / 100000 - 1) // 与同板已出图例程一致
  ) u_uicfgcs500_720p (
      .I_clk(S_24m_clk),  //系统时钟输入
      .I_rst_n(S_cam_rst_n), // 配置时钟域内两拍同步释放
      .I_ae_req(S_ae_req),
      .I_ae(S_ae),
      .I_ag(S_ag),
      .O_cam_scl(O_cam_scl),  //I2C总线，SCL时钟
      .IO_cam_sda(IO_cam_sda),  //I2C总线，SDA数据
      .O_cfg_done(S_cam_cfg_done),  //摄像头寄存器初始化完成
      .O_ae_cfg_done(S_ae_cfg_done),  //AE配置完成
      .O_iic_error(S_cam_i2c_error)
  );
	
    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "0dB"   ),// 与同板已出图例程一致
        .HS_VGA_GAIN           ( "8dB" ),//"-3dB","-1.5dB","0dB","1.5dB","3dB","4.5dB","6dB","7.5dB"
        .LANE_NUM              ( 2       ),
        .BYTE_NUM              ( 1       )
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),
        .I_rst                 (~S_sys_rst_n),

        .I_clk_lane_in_delay   ( 6'd0             ),
        .I_data_lane0_in_delay ( 6'd0             ),
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 4'b0000          ),
     
        .O_hs_rx_clk           ( S_csi_rx_clk     ),
        .O_hs_rx_valid         ( S_hs_rx_valid    ),
        .O_hs_rx_data          ( S_hs_rx_data     ),
      
        .O_lp_rx_lane0_p       (  ),
        .O_lp_rx_lane0_n       (  ),
      
        .I_lp_tx_en            ( 1'b0             ),
        .I_lp_tx_lane0_p       ( 1'b1             ),
        .I_lp_tx_lane0_n       ( 1'b1             ),
      
        .O_lane_match_error    (                  ),
        .O_lane_error          ( S_lane_error     ),
      
        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )
    );
	
	
 //  cwc cwc_inst
 //(
 //    .probe0(S_hs_rx_valid),
 //    .probe1(S_hs_rx_data),
 //    .probe2(S_lane_error),
 //    .clk(S_csi_rx_clk)
 //);

 //csi 解码为RAW数据
csi_unpacket_2lane u_csi_unpacket(
.I_clk                 ( S_csi_rx_clk       ),
.I_rst_n               (S_csi_rst_n),
.I_hs_valid            ( S_hs_rx_valid     ),
.I_hs_data             ( S_hs_rx_data      ),

.O_csi_frame_start     ( S_csi_frame_start ),
.O_csi_frame_end       ( S_csi_frame_end   ),
.O_csi_valid           ( S_csi_valid       ),
.O_csi_data            ( S_csi_data        ),
.O_data_length         ( S_csi_data_length )
);


//解码为RAW8
raw10_unpacket_2lane u_raw10_unpacket (
.I_clk  (S_csi_rx_clk),
.I_rst_n(S_csi_rst_n),

.I_csi_frame_start(S_csi_frame_start),
.I_csi_frame_end  (S_csi_frame_end),
.I_csi_valid      (S_csi_valid),
.I_csi_data       (S_csi_data),

.O_raw10_frame_start(S_raw10_frame_start),
.O_raw10_frame_end  (S_raw10_frame_end),
.O_raw10_valid      (S_raw10_valid),
.O_raw10_data       (S_raw10_data)
  );


//将数据转为stream流
uial2axis #(
.IMG_WIDTH(1280),
.IMG_HEIGHT(720),
.INPUT_DATA_WIDTH(40)
) 
u_uial2axis (
.I_native_clk(S_csi_rx_clk),
.I_rst_n     (S_csi_rst_n),
.I_data      (S_raw10_data       ),
.I_data_valid(S_raw10_valid      ),
.I_data_start(S_raw10_frame_start),
.I_data_end  (S_raw10_frame_end  ),
.axis_tvalid (S_axis_tvalid),
.axis_tdata  (S_axis_tdata ),
.axis_tuser  (S_axis_tuser ),
.axis_tlast  (S_axis_tlast )
);
	

// SC520CS原厂HD模式已经直接输出1280x720 RAW10，无需FPGA窗口裁剪。
assign S_raw_tdata  = S_axis_tdata;
assign S_raw_tlast  = S_axis_tlast;
assign S_raw_tvalid = S_axis_tvalid;
assign S_raw_tuser  = S_axis_tuser;


//cwc1 cwc1_Inst
//  (
//      .probe0(S_axis_tuser),
//      .probe1(S_axis_tvalid),
//      .probe2(S_axis_tlast),
//      .probe3(S_axis_tdata),
//      .probe4(S_ISP_O_tuser),
//      .probe5(S_ISP_O_tvalid),
//      .probe6(S_ISP_O_tlast),
//      .probe7(S_ISP_O_tdata),
//      .probe8 (S_raw_tdata ),
//      .probe9 (S_raw_tlast ),
//      .probe10(S_raw_tvalid),
//      .probe11(S_raw_tuser ),
//      .clk(S_csi_rx_clk)
//  );


// ISP偏振采集使用固定白平衡增益，四张角度图采用同一颜色响应。
isp_top #(.ENABLE_POLAR_FIXED_GAIN(1)) u_isp_top (
.axi4s_video_aclk(S_csi_rx_clk),
.I_polar_fixed_gain(S_polar_fixed_wb),
.I_rst_n         (S_csi_rst_n),
.I_tlast         (S_raw_tlast	),
.I_tuser         (S_raw_tuser	),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (S_raw_tvalid	),
.I_tdest         (),
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        ()
  );


    video_in #(.REQUIRE_COMPLETE_FRAME(1),.ENABLE_DISPLAY_PAGE_GUARD(1)) u_video_in(
        .I_rst_n              (  S_data_rst_n        ),

        .I_camera_clk         ( S_csi_rx_clk          ),
        .I_camera_frame_start ( S_ISP_O_tuser  ),
        .I_camera_valid       ( S_ISP_O_tvalid ),
        .I_camera_data        ( S_ISP_O_tdata  ),
        .I_mipi_rx_error      ( S_mipi_last_length_error | S_mipi_last_line_error | S_mipi_last_lane_error ),

        .I_ddr_clk            ( S_ddr_clk             ),
		.I_display_pause      ( S_polar_pause         ),
        .I_video_out_rd_busy  ( S_video_out_rd_busy | S_polar_owner ),
        .O_frame_start_ddr    ( S_camera_frame_ddr    ),
        .O_good_frame_ddr     ( S_camera_good_frame_ddr ),
        .I_display_page_mask  ( S_display_page_mask   ),
        .O_page_valid         ( S_live_page_valid     ),
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),
        .I_ddr_user_ready     ( S_live_ready          )
    );



    polar_video_backend #(.REQUIRE_GOOD_SETTLE(1),.ENABLE_POLAR_EDGE(1),.IMG_WIDTH(1280),.CHECK_FRAME_LAYOUT(1)) u_polar_backend(
        .pixel_clk(S_hdmi_pixel_clk),.camera_clk(S_csi_rx_clk),.ddr_clk(S_ddr_clk),.rst_n(S_data_rst_n),
        .requested_mode(S_mode_pending),.capture_pulse(S_capture_pulse),.restart_pulse(S_restart_pulse),
        .camera_frame_start(S_camera_frame_ddr),.camera_good_frame(S_camera_good_frame_ddr),.live_page(S_video_out_rp),.page_valid(S_live_page_valid),
        .displayed_mode(S_vo_frame_mode),.displayed_result(S_vo_result_active),
        .vo_busy(S_video_out_rd_busy),.vo_frame_pending(S_vo_pending),.vo_fill(S_vo_fill),.vo_credit(S_vo_credit),
        .vo_rd_en(S_vo_ddr_rd_en),.vo_addr(S_vo_ddr_rd_addr),
        .vi_busy(S_video_in_wr_busy),.vi_wr_en(S_vi_ddr_wr_en),.vi_addr(S_vi_ddr_wr_addr),.vi_data(S_vi_ddr_wr_data),
        .calibrated(S_init_calib_complete),.queue_idle(S_mc_queue_idle),.user_ready(S_ddr_user_ready),
        .user_rd_valid(S_ddr_user_rd_valid),.user_rd_data(S_ddr_user_rd_data),
        .display_pause(S_polar_pause),.background_owner(S_polar_owner),.live_ready(S_live_ready),
        .vo_return_valid(S_vo_return_valid),.user_wr_en(S_ddr_user_wr_en),.user_rd_en(S_ddr_user_rd_en),
        .user_addr(S_ddr_user_addr),.user_wr_data(S_ddr_user_wr_data),
        .source_base(S_source_base),.source_mode(S_source_mode),.source_is_result(S_source_is_result),
        .source_valid(S_source_valid),
        .render_mode(),.polar_angle(S_polar_angle),.polar_capture_busy(S_polar_capture_busy),
        .polar_compute_busy(S_polar_compute_busy),.polar_ready(S_polar_ready),.polar_error(S_polar_error),
        .fixed_white_balance(S_polar_fixed_wb),.reset_required(S_backend_reset_required));
    assign S_render_mode=S_vo_pixel_mode;

    // VO内部按DDR/像素域分别同步释放，外部送统一异步断言源。
    assign S_video_out_rst_n = S_data_rst_n;

    video_out #(.USE_EXTERNAL_SOURCE(1),.ENABLE_UNDERFLOW_GUARD(1),
        .ENABLE_DISPLAY_PAGE_GUARD(1),.ENABLE_FRAME_TRANSACTION(1)) u_video_out(
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),
 
        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .I_video_in_wr_busy  ( S_video_in_wr_busy | S_polar_owner ),
        .I_source_base(S_source_base),.I_source_mode(S_source_mode),.I_source_is_result(S_source_is_result),
        .I_source_valid(S_source_valid),.O_display_page_mask(S_display_page_mask),
        .O_frame_mode(S_vo_frame_mode),.O_result_source_active(S_vo_result_active),
        .O_pixel_mode(S_vo_pixel_mode),.O_pixel_frame_valid(S_vo_pixel_valid),.O_pixel_result_active(),
        .O_fifo_fill(S_vo_fill),.O_read_credit(S_vo_credit),.O_frame_pending(S_vo_pending),.O_underflow(S_vo_underflow),
        .I_video_out_rp      ( S_video_out_rp       ),
 
        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),
        .I_ddr_user_ready    ( S_live_ready         ),
        .I_ddr_user_rd_valid ( S_vo_return_valid    ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data   ),

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_window_rd_en  ),
        .O_vdieo_data        ( S_video_rd_data      )
    );



    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 (S_ddr_rst_n),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_queue_idle            ( S_mc_queue_idle         ),
        .reset_required          ( S_mc_reset_required      ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),
            
        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask       ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );



    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        .I_sys_clk              ( I_sys_clk              ),
        .I_sys_rst_n            (S_ddr_controller_rst_n),

        .O_ddr_clk              ( S_ddr_clk              ),
        .O_init_calib_complete  ( S_init_calib_complete  ),
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );



    uivtc #(
        .H_ActiveSize ( 1280 ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( 720  ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        // Normal camera display.  Set to 4 only when the MIPI diagnostic
        // full-screen status page is needed.
        .DEBUG_MODE ( 0    )
    )u_hdmi_mixer(
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_hdmi_vsync       ),
        .I_video_hsync   ( S_hdmi_hsync       ),
        .I_video_de      ( S_hdmi_de          ),
        .I_video_user    ( S_hdmi_user        ),
        .I_video_last    ( S_hdmi_last        ),
        .I_debug_status  ( S_hdmi_debug_status),
        .O_video_rd_en   ( S_hdmi_window_rd_en),
        .I_video_rd_data ( S_video_rd_data    ),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    // 算法接入点：DDR 读取画面已由 mixer 对齐，之后统一在像素域处理。
    // S_algo_rgb 与 DE/HS/VS 是算法处理后的输出；正式显示编号使用DDR确认后的S_render_mode。
    // 0–8实时算法在像素域运行；9–11已经在DDR域计算，像素域只做5级直通对齐。
    // 外部render_mode由video_out实际锁存的帧源返回，避免标签和DDR画面跨帧错配。
    // Algorithms run after the DDR/mixer alignment, in the HDMI pixel domain.
    wire [23:0] S_algo_rgb;
    wire S_algo_de, S_algo_hs, S_algo_vs;
    wire [7:0] S_bin_threshold, S_edge_threshold;
    wire [7:0] S_motion_threshold;
    wire [7:0] S_bright_gain, S_contrast_gain;
    wire S_threshold_edit;
        video_algorithm_display #(
        .CLK_HZ(75000000),
        .ALGO_COUNT(16),

        .IMG_WIDTH(1280),
        .IMG_HEIGHT(720),

        .ENABLE_POLAR_CONTROL(1),
        .EXTERNAL_RENDER_MODE(1),
        .ENABLE_FRAME_GUARD(1),

        // ============================================================
        // 各模式上电默认参数
        // ============================================================

        // MODE 2 - BINARY
        .BIN_THRESHOLD(28),

        // MODE 3 - SOBEL
        .EDGE_THRESHOLD(3),

        // MODE 4 - BRIGHT
        // Q4.4：16 = 1.0倍
        .BRIGHT_GAIN(16),

        // MODE 5 - CONTRAST
        // Q4.4：16 = 1.0倍
        .CONTRAST_GAIN(16),

        // MODE E - MOTION
        .MOTION_THRESHOLD(8),

        // 每次按键调整1
        .THRESHOLD_STEP(1),
        .GAIN_STEP(1),

        // ============================================================
        // 各模式允许的运行时调节范围
        // ============================================================

        // BINARY：视频实测明显有效区间
        .BIN_THRESHOLD_MIN(22),
        .BIN_THRESHOLD_MAX(34),

        // SOBEL
        .EDGE_THRESHOLD_MIN(2),
        .EDGE_THRESHOLD_MAX(5),

        // BRIGHT：0.5x ～ 1.75x
        .BRIGHT_GAIN_MIN(8),
        .BRIGHT_GAIN_MAX(28),

        // CONTRAST：0.875x ～ 1.5x
        .CONTRAST_GAIN_MIN(14),
        .CONTRAST_GAIN_MAX(24),

        // MOTION：视频尚未完成阈值扫描，暂不缩窄
        .MOTION_THRESHOLD_MIN(1),
        .MOTION_THRESHOLD_MAX(255)

    ) u_algorithm_display (
        .clk(S_hdmi_pixel_clk), .rst_n(S_hdmi_rst_n & I_rst_n),
        .key0_n(I_button[0]), .key1_n(I_button[1]), .threshold_edit(I_threshold_edit),
        .render_mode_in(S_render_mode), .mode_pending_out(S_mode_pending),
        .frame_valid_in(S_frame_valid_mixer[2]),.bank_run(S_ddr_clients_rst_n),
        .polar_capture_pulse(S_capture_pulse),.polar_restart_pulse(S_restart_pulse),
        .bin_threshold_active(S_bin_threshold), .edge_threshold_active(S_edge_threshold),
        .bright_gain_active(S_bright_gain), .contrast_gain_active(S_contrast_gain),
        .motion_threshold_active(S_motion_threshold),
        .threshold_edit_active(S_threshold_edit),
        .rgb_in(S_hdmi_out_data), .de_in(S_hdmi_out_de),
        .hs_in(S_hdmi_out_hsync), .vs_in(S_hdmi_out_vsync),
        .trk_update(S_trk_update),.trk_valid(S_trk_valid),.trk_lost_cnt(S_trk_lost),
        .trk_x_min(S_trk_x0),.trk_x_max(S_trk_x1),.trk_y_min(S_trk_y0),.trk_y_max(S_trk_y1),
        .rgb_out(S_algo_rgb), .de_out(S_algo_de),
        .hs_out(S_algo_hs), .vs_out(S_algo_vs), .mode_active()
    );
    // HDMI 接收叠加后的 S_osd 数据。不要误接回 S_hdmi_out_data，否则画面会绕过算法。
    // OSD 放在全部算法之后，安路标识与文字不会被灰度/二值化/Sobel 再处理。
    // OSD 额外增加 2 级，RGB 和 DE/HS/VS 一起延迟。
    wire [23:0] S_osd_rgb;
    wire S_osd_de, S_osd_hs, S_osd_vs;
    video_status_osd #(.ENABLE_POLAR_STATUS(1),.ENABLE_DDR_STATUS(1),.ENABLE_PREVIEW_GAMMA(1),
        .ENABLE_MOTION_THRESHOLD(1),.DECIMAL_COUNTER(1),.GIMBAL_STATUS_ENABLE(1)) u_status_osd (
        .clk(S_hdmi_pixel_clk), .rst_n(S_hdmi_rst_n & I_rst_n),
        .rgb_in(S_algo_rgb), .de_in(S_algo_de), .hs_in(S_algo_hs), .vs_in(S_algo_vs),
        .mode_active(S_render_mode), .bin_threshold_active(S_bin_threshold),
        .ddr_state(S_recovery_pixel_2),.gimbal_armed(S_auto_armed),.gimbal_live(S_auto_live),
        .bright_gain_active(S_bright_gain), .contrast_gain_active(S_contrast_gain),
        .polar_angle(S_polar_angle),.polar_capture_busy(S_polar_capture_busy),
        .polar_compute_busy(S_polar_compute_busy),.polar_ready(S_polar_ready),.polar_error(S_polar_error),
        .edge_threshold_active(S_edge_threshold), .threshold_edit_active(S_threshold_edit),
        .motion_threshold_active(S_motion_threshold),
        .rgb_out(S_osd_rgb),
        .de_out(S_osd_de), .hs_out(S_osd_hs), .vs_out(S_osd_vs)
    );
    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_key_in           ( 1'b0              ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( S_osd_vs          ),
        .I_video_in_de      ( S_osd_de          ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( S_osd_rgb         ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );

    
endmodule

