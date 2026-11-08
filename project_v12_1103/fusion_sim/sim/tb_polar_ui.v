`timescale 1ns/1ps
module tb_polar_ui;
    reg clk=0, rst_n=0, key0_n=1, key1_n=1, frame_commit=0, threshold_edit=0;
    wire [3:0] mode_pending, mode_active;
    wire [7:0] bin_threshold, edge_threshold;
    wire threshold_edit_active, capture_pulse, restart_pulse;
    reg [3:0] osd_mode=0;
    reg [1:0] osd_angle=0;
    integer capture_count=0, restart_count=0, i;
    reg [7:0] ch;

    always #5 clk=~clk;
    always @(posedge clk) begin
        if (capture_pulse) capture_count=capture_count+1;
        if (restart_pulse) restart_count=restart_count+1;
    end

    key_mode_ctrl #(.ALGO_COUNT(12), .CLK_HZ(1000), .DEBOUNCE_CYCLES(3),
                    .ENABLE_THRESHOLD_CONTROL(1), .ENABLE_POLAR_CONTROL(1)) keys (
        .clk(clk), .rst_n(rst_n), .key0_n(key0_n), .key1_n(key1_n),
        .frame_commit(frame_commit), .threshold_edit(threshold_edit),
        .mode_pending(mode_pending), .mode_active(mode_active),
        .threshold_edit_active(threshold_edit_active),
        .bin_threshold_active(bin_threshold), .edge_threshold_active(edge_threshold),
        .polar_capture_pulse(capture_pulse), .polar_restart_pulse(restart_pulse)
    );

    video_status_osd #(.ENABLE_POLAR_STATUS(1)) osd (
        .clk(clk), .rst_n(rst_n), .rgb_in(24'h123456), .de_in(1'b0),
        .hs_in(1'b0), .vs_in(1'b0), .mode_active(osd_mode),
        .bin_threshold_active(bin_threshold), .edge_threshold_active(edge_threshold),
        .threshold_edit_active(threshold_edit_active), .polar_angle(osd_angle),
        .polar_capture_busy(1'b0), .polar_compute_busy(1'b0),
        .polar_ready(1'b1), .polar_error(1'b0),
        .rgb_out(), .de_out(), .hs_out(), .vs_out()
    );

    task tick;
        input integer n;
        integer j;
        begin for(j=0;j<n;j=j+1) begin @(posedge clk); #1; end end
    endtask
    task press_next;
        begin @(negedge clk); key1_n=0; tick(12); @(negedge clk); key1_n=1; tick(10); end
    endtask
    task press_previous;
        begin @(negedge clk); key0_n=0; tick(12); @(negedge clk); key0_n=1; tick(10); end
    endtask

    initial begin
        tick(3); rst_n=1; tick(8);
        if(mode_pending!==0 || mode_active!==0) $fatal(1,"reset mode");

        // SW1=0 cycles through the legacy nine and the three polar modes.
        for(i=1;i<=12;i=i+1) begin
            press_next();
            if(mode_pending !== (i%12)) $fatal(1,"12-mode cycle step %0d got %0d",i,mode_pending);
        end
        @(negedge clk); frame_commit=1; tick(1); @(negedge clk); frame_commit=0;
        if(mode_active!==0) $fatal(1,"mode commit wrap");
        for(i=0;i<9;i=i+1) press_next();
        if(mode_pending!==9) $fatal(1,"enter DOLP");
        @(negedge clk); frame_commit=1; tick(1); @(negedge clk); frame_commit=0;
        if(mode_active!==9) $fatal(1,"DOLP commit");

        // In polar modes SW1=1 maps KEY3 to one capture pulse and KEY2 to restart.
        @(negedge clk); threshold_edit=1; tick(10);
        press_next();
        if(capture_count!=1 || restart_count!=0 || mode_pending!=9)
            $fatal(1,"DOLP capture arbitration count=%0d/%0d mode=%0d",capture_count,restart_count,mode_pending);
        press_previous();
        if(restart_count!=1 || capture_count!=1) $fatal(1,"DOLP restart pulse");

        @(negedge clk); threshold_edit=0; tick(10);
        press_next(); press_next();
        if(mode_pending!==11) $fatal(1,"select FUSION mode");
        @(negedge clk); frame_commit=1; tick(1); @(negedge clk); frame_commit=0;
        @(negedge clk); threshold_edit=1; tick(10);
        press_next(); press_previous();
        if(capture_count!=2 || restart_count!=2 || mode_active!==11)
            $fatal(1,"FUSION commands/mode");

        // Double-key protection is retained in command mode.
        @(negedge clk); key0_n=0; key1_n=0; tick(15);
        @(negedge clk); key0_n=1; key1_n=1; tick(10);
        if(capture_count!=2 || restart_count!=2) $fatal(1,"two-key command was not suppressed");

        // OSD's real character selection names all new modes and formats all angles/statuses.
        if(osd.mode_char(4'd9,0)!="D" || osd.mode_char(4'd9,3)!="P" ||
           osd.mode_char(4'd10,2)!="P" || osd.mode_char(4'd11,5)!="N")
            $fatal(1,"polar mode labels");
        if(osd.text_char(2'd2,6'd6,4'd9,0,0,0,0,0,0,0,1,0,2'd0)!="0" ||
           osd.text_char(2'd2,6'd7,4'd9,0,0,0,0,1,0,0,1,0,2'd0)!="4" ||
           osd.text_char(2'd2,6'd8,4'd9,0,0,0,0,1,0,0,1,0,2'd0)!="5" ||
           osd.text_char(2'd2,6'd7,4'd9,0,0,0,0,2,0,0,1,0,2'd0)!="9" ||
           osd.text_char(2'd2,6'd8,4'd9,0,0,0,0,2,0,0,1,0,2'd0)!="0" ||
           osd.text_char(2'd2,6'd6,4'd9,0,0,0,0,3,0,0,1,0,2'd0)!="1" ||
           osd.text_char(2'd2,6'd7,4'd9,0,0,0,0,3,0,0,1,0,2'd0)!="3" ||
           osd.text_char(2'd2,6'd8,4'd9,0,0,0,0,3,0,0,1,0,2'd0)!="5" ||
           osd.text_char(2'd2,6'd10,4'd9,0,0,0,0,1,0,0,1,0,2'd0)!="S")
            $fatal(1,"angle and SW1 text");
        if(osd.text_char(2'd3,6'd1,4'd9,0,0,0,0,0,1,0,0,0,2'd0)!="A" ||
           osd.text_char(2'd3,6'd1,4'd9,0,0,0,0,0,0,1,0,0,2'd0)!="O" ||
           osd.text_char(2'd3,6'd0,4'd9,0,0,0,0,0,0,0,1,0,2'd0)!="R" ||
           osd.text_char(2'd3,6'd2,4'd9,0,0,0,0,0,0,0,1,1,2'd0)!="T" ||
           osd.text_char(2'd3,6'd8,4'd9,0,0,0,0,0,0,0,1,0,2'd0)!="N" ||
           osd.text_char(2'd3,6'd17,4'd9,0,0,0,0,0,0,0,1,0,2'd0)!="T")
            $fatal(1,"capture/compute/ready status text");
        if(osd.text_char(2'd3,6'd0,4'd9,0,0,0,0,0,0,0,1,1,2'd0)!="R")
            $fatal(1,"retry error priority");

        // Drive a polar status glyph through the OSD's two registered stages.
        @(negedge clk); osd_mode=4'd9; osd_angle=2'd0;
        osd.pixel_x=12'd203; osd.pixel_y=12'd67;
        // This directed probe assigns private scan state instead of driving DE.
        // Keep the new relative cell counters consistent with x=TEXT_X+3.
        osd.text_cell_index=6'd0; osd.text_pixel_in_cell=5'd3;
        @(posedge clk); #1;
        if(osd.s1_char_code!="A" || osd.s1_char_row!=3 || osd.s1_char_col!=3)
            $fatal(1,"OSD did not select ANGLE glyph");
        @(posedge clk); #1;
        if(osd.rgb_out!==24'h00e6ff) $fatal(1,"OSD did not render ANGLE glyph pixel: %h",osd.rgb_out);

        $display("PASS tb_polar_ui: 12 modes, SW1 command pulses/arbitration, polar OSD labels/status/glyph");
        $finish;
    end
endmodule
