`timescale 1ns/1ps
// 验证算法10经过按键显示模块与OSD的真实像素链路、帧边界提交和极化模式隔离。
module tb_algo10_system;
    // Frozen legacy rule-5 single-frame contract; production rule-6 has its own regressions.
    defparam display.u_bank.COLOR_DET_RULE=5;

    localparam integer W=32, H=16, BANK_LATENCY=5, OSD_LATENCY=2, TOTAL_LATENCY=7;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg key0_n=1,key1_n=1,threshold_edit=0;
    reg [23:0] rgb_in=0;
    reg de_in=0,hs_in=0,vs_in=0;
    wire [23:0] bank_rgb;
    wire bank_de,bank_hs,bank_vs;
    wire [3:0] mode_active,mode_pending;
    wire cap_pulse,restart_pulse,edit_active;
    wire [7:0] bin_threshold,edge_threshold;
    wire [23:0] rgb_out;
    wire de_out,hs_out,vs_out;
    integer cap_count=0,restart_count=0;
    integer sample_count=0,checks=0,i,n;
    reg check_stream=0;
    reg [23:0] expected_rgb[0:32767];
    reg expected_de[0:32767],expected_hs[0:32767],expected_vs[0:32767];
    reg [7:0] expected_name[0:7];

    video_algorithm_display #(.CLK_HZ(1000),.DEBOUNCE_CYCLES(3),.ALGO_COUNT(14),
        .ENABLE_POLAR_CONTROL(1),.IMG_WIDTH(W),.IMG_HEIGHT(H)) display (
        .clk(clk),.rst_n(rst_n),.key0_n(key0_n),.key1_n(key1_n),.threshold_edit(threshold_edit),
        .rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),
        .rgb_out(bank_rgb),.de_out(bank_de),.hs_out(bank_hs),.vs_out(bank_vs),
        .mode_active(mode_active),.mode_pending_out(mode_pending),.render_mode_in(4'd0),
        .polar_capture_pulse(cap_pulse),.polar_restart_pulse(restart_pulse),
        .bin_threshold_active(bin_threshold),.edge_threshold_active(edge_threshold),
        .threshold_edit_active(edit_active));
    video_status_osd #(.ENABLE_POLAR_STATUS(1)) osd (
        .clk(clk),.rst_n(rst_n),.rgb_in(bank_rgb),.de_in(bank_de),.hs_in(bank_hs),.vs_in(bank_vs),
        .mode_active(mode_active),.bin_threshold_active(bin_threshold),.edge_threshold_active(edge_threshold),
        .threshold_edit_active(edit_active),.polar_angle(2'd0),.polar_capture_busy(1'b0),
        .polar_compute_busy(1'b0),.polar_ready(1'b0),.polar_error(1'b0),
        .rgb_out(rgb_out),.de_out(de_out),.hs_out(hs_out),.vs_out(vs_out));

    always @(posedge clk) begin
        if(cap_pulse) cap_count=cap_count+1;
        if(restart_pulse) restart_count=restart_count+1;
    end

    task tick; begin drive_sample(rgb_in,de_in,hs_in,vs_in,rgb_in); end endtask
    task drive_sample;
        input [23:0] pixel;
        input valid,hsync,vsync;
        input [23:0] expected;
        begin
            @(negedge clk);
            rgb_in=pixel;de_in=valid;hs_in=hsync;vs_in=vsync;
            expected_rgb[sample_count]=expected;
            expected_de[sample_count]=valid;expected_hs[sample_count]=hsync;expected_vs[sample_count]=vsync;
            @(posedge clk); #1;
            if(check_stream && sample_count>=TOTAL_LATENCY-1)begin
                i=sample_count-(TOTAL_LATENCY-1);
                if({de_out,hs_out,vs_out}!=={expected_de[i],expected_hs[i],expected_vs[i]})
                    $fatal(1,"OSD sync mismatch sample=%0d got=%b%b%b expected=%b%b%b",sample_count,de_out,hs_out,vs_out,expected_de[i],expected_hs[i],expected_vs[i]);
                if(expected_de[i] && rgb_out!==expected_rgb[i])
                    $fatal(1,"mode13 RGB/bbox mismatch sample=%0d got=%06h expected=%06h",sample_count,rgb_out,expected_rgb[i]);
                checks=checks+1;
            end
            sample_count=sample_count+1;
        end
    endtask

    task key_press;
        input previous;
        begin
            if(previous)key0_n=0;else key1_n=0;
            repeat(18)tick;
            key0_n=1;key1_n=1;
            repeat(18)tick;
        end
    endtask
    task commit_frame;
        begin
            drive_sample(24'd0,1'b0,1'b0,1'b1,24'd0);
            drive_sample(24'd0,1'b0,1'b0,1'b0,24'd0);
        end
    endtask
    task move_next;
        input [3:0] expected_mode;
        begin
            key_press(0);commit_frame;
            if(mode_active!==expected_mode || mode_pending!==expected_mode)
                $fatal(1,"next mode/commit expected=%0d active=%0d pending=%0d",expected_mode,mode_active,mode_pending);
        end
    endtask
    task move_previous;
        input [3:0] expected_mode;
        begin
            key_press(1);commit_frame;
            if(mode_active!==expected_mode || mode_pending!==expected_mode)
                $fatal(1,"previous mode/commit expected=%0d active=%0d pending=%0d",expected_mode,mode_active,mode_pending);
        end
    endtask

    function [23:0] source_pixel;
        input integer kind,xx,yy;
        begin
            source_pixel=24'h123456;
            if(kind==0 && xx>=5 && xx<=10 && yy>=5 && yy<=10) source_pixel=24'hf00000;
            if(kind==2 && xx>=15 && xx<=22 && yy>=3 && yy<=8) source_pixel=24'hf00000;
        end
    endfunction
    function is_box_edge;
        input integer xx,yy;
        begin
            is_box_edge=((xx==5 || xx==6 || xx==9 || xx==10) && yy>=5 && yy<=10) ||
                        ((yy==5 || yy==6 || yy==9 || yy==10) && xx>=5 && xx<=10);
        end
    endfunction
    task send_frame;
        input integer kind;
        input integer expect_box;
        integer xx,yy;
        reg [23:0] src,exp;
        begin
            // 单拍高有效VS标记帧首；小帧避开OSD的Logo与文字区域。
            drive_sample(24'd0,1'b0,1'b0,1'b1,24'd0);
            drive_sample(24'd0,1'b0,1'b0,1'b0,24'd0);
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    src=source_pixel(kind,xx,yy);exp=src;
                    if(expect_box && is_box_edge(xx,yy))exp=24'h00ff00;
                    drive_sample(src,1'b1,(xx==0),1'b0,exp);
                end
                drive_sample(24'd0,1'b0,1'b0,1'b0,24'd0);
            end
            repeat(TOTAL_LATENCY+2)drive_sample(24'd0,1'b0,1'b0,1'b0,24'd0);
        end
    endtask

    initial begin
        repeat(5)tick;rst_n=1;repeat(12)tick;
        // 14种模式的前后环回与每一帧边界提交。
        move_previous(13);move_next(0);
        for(n=1;n<=13;n=n+1)move_next(n[3:0]);
        expected_name[0]="C";expected_name[1]="O";expected_name[2]="L";expected_name[3]="O";
        expected_name[4]="R";expected_name[5]="B";expected_name[6]="O";expected_name[7]="X";
        for(n=0;n<8;n=n+1)if(osd.mode_char(4'd13,n)!==expected_name[n])
            $fatal(1,"OSD COLORBOX label truncated at character %0d",n);
        if(osd.mode_char(4'd13,8)!==8'h20)$fatal(1,"OSD COLORBOX label exceeds eight characters");

        // 模式13下SW1编辑态按键不得发偏振操作或改动图像阈值。
        threshold_edit=1;repeat(18)tick;key_press(0);repeat(8)tick;
        if(cap_count!=0 || restart_count!=0 || mode_pending!=13 || mode_active!=13 ||
           bin_threshold!=8'd128 || edge_threshold!=8'd32)
            $fatal(1,"mode13 SW1 generated a control/threshold operation");
        threshold_edit=0;repeat(18)tick;

        // 清空检查队列并验证：普通模式原图统计到的目标框在模式13下一帧出现。
        move_next(0);
        check_stream=1;sample_count=0;
        send_frame(0,0);
        key_press(1);
        send_frame(1,1);

        // 重新得到有效旧框，保持红色输入跨越普通模式直到9..12停用检测。
        send_frame(0,0);
        move_next(0);check_stream=0;send_frame(0,0);
        for(n=1;n<=8;n=n+1)begin
            move_next(n[3:0]);
            if(display.u_bank.u_color_detect.bbox_valid!==1'b1)
                $fatal(1,"ordinary mode %0d failed to retain shared raw-frame detection",n-1);
            send_frame(0,0);
        end
        move_next(9);
        if(display.u_bank.u_color_detect.bbox_valid!==1'b0)
            $fatal(1,"polar mode9 did not clear the previous detection box");
        check_stream=1;sample_count=0;send_frame(2,0);
        for(n=10;n<=13;n=n+1)move_next(n[3:0]);
        send_frame(1,0);

        // 检测重新启用后可重新统计，而不是长期保持清框状态。
        send_frame(0,0);
        send_frame(1,1);
        if(checks<1000)$fatal(1,"too few bank/display/OSD checks: %0d",checks);
        $display("PASS tb_algo10_system checks=%0d capture=%0d restart=%0d",checks,cap_count,restart_count);
        $finish;
    end
    initial begin #1000000;$fatal(1,"tb_algo10_system timeout");end
endmodule