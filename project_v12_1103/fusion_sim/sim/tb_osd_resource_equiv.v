`timescale 1ns/1ps
module tb_osd_resource_equiv;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [23:0] rgb_in = 24'd0;
    reg de_in = 1'b0, hs_in = 1'b0, vs_in = 1'b0;
    reg [3:0] mode_active = 4'd0;
    reg [7:0] bin_threshold_active = 8'd0, edge_threshold_active = 8'd0;
    reg [7:0] bright_gain_active = 8'd24, contrast_gain_active = 8'd24;
    reg threshold_edit_active = 1'b0;
    reg [1:0] polar_angle = 2'd0;
    reg polar_capture_busy = 1'b0, polar_compute_busy = 1'b0;
    reg polar_ready = 1'b0, polar_error = 1'b0;
    wire [23:0] rgb_new, rgb_old;
    wire de_new, hs_new, vs_new, de_old, hs_old, vs_old;
    reg [15:0] mode_sample_mask = 16'd0, title_mode_mask = 16'd0;
    reg fixed_mode_enable = 1'b0;
    reg [3:0] fixed_mode = 4'd0;
    integer mode_title_pixels [0:15];
    integer compared_cycles = 0, text_window_pixels = 0;
    integer gap_pixels = 0, frame_index, y, x, b, m, boundary, scenario_count=0;
    integer control_tick = 0;
    reg [63:0] track_title = "TRACK   ";

    always #5 clk = ~clk;

    video_status_osd #(.ENABLE_POLAR_STATUS(1)) dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .mode_active(mode_active), .bin_threshold_active(bin_threshold_active),
        .edge_threshold_active(edge_threshold_active), .threshold_edit_active(threshold_edit_active),
        .bright_gain_active(bright_gain_active), .contrast_gain_active(contrast_gain_active),
        .polar_angle(polar_angle), .polar_capture_busy(polar_capture_busy),
        .polar_compute_busy(polar_compute_busy), .polar_ready(polar_ready), .polar_error(polar_error),
        .rgb_out(rgb_new), .de_out(de_new), .hs_out(hs_new), .vs_out(vs_new)
    );
    video_status_osd_ref #(.ENABLE_POLAR_STATUS(1)) reference (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .mode_active(mode_active), .bin_threshold_active(bin_threshold_active),
        .edge_threshold_active(edge_threshold_active), .threshold_edit_active(threshold_edit_active),
        .bright_gain_active(bright_gain_active), .contrast_gain_active(contrast_gain_active),
        .polar_angle(polar_angle), .polar_capture_busy(polar_capture_busy),
        .polar_compute_busy(polar_compute_busy), .polar_ready(polar_ready), .polar_error(polar_error),
        .rgb_out(rgb_old), .de_out(de_old), .hs_out(hs_old), .vs_out(vs_old)
    );

    task step;
        input de_value, hs_value, vs_value;
        input [23:0] rgb_value;
        input integer frame_value, row_value, col_value;
        begin
            @(negedge clk);
            de_in = de_value;
            hs_in = hs_value;
            vs_in = vs_value;
            rgb_in = rgb_value;
            if (fixed_mode_enable) mode_active = fixed_mode;
            else mode_active = (col_value / 80 + row_value / 45 + frame_value * 7) % 16;
            bin_threshold_active = (col_value * 3 + row_value + frame_value * 17) % 256;
            edge_threshold_active = (row_value * 5 + col_value / 3 + frame_value * 29) % 256;
            bright_gain_active = (col_value * 11 + row_value * 3 + frame_value * 31) % 256;
            contrast_gain_active = (row_value * 17 + col_value * 7 + frame_value * 43) % 256;
            threshold_edit_active = ((control_tick / 13) % 2);
            polar_angle = (control_tick / 7) % 4;
            polar_capture_busy = ((control_tick / 3) % 2);
            polar_compute_busy = ((control_tick / 5) % 2);
            polar_ready = ((control_tick / 11) % 2);
            polar_error = ((control_tick / 17) % 2);
            control_tick = control_tick + 1;
            @(posedge clk); #1;
            if ({rgb_new,de_new,hs_new,vs_new} !== {rgb_old,de_old,hs_old,vs_old})
                $fatal(1, "OSD mismatch cycle=%0d frame=%0d row=%0d col=%0d mode=%0d new=%h/%b%b%b old=%h/%b%b%b",
                       compared_cycles, frame_value, row_value, col_value, mode_active,
                       rgb_new,de_new,hs_new,vs_new,rgb_old,de_old,hs_old,vs_old);
            if (dut.pixel_x !== reference.pixel_x || dut.pixel_y !== reference.pixel_y)
                $fatal(1,"coordinate mismatch cycle=%0d dut=(%0d,%0d) ref=(%0d,%0d)",
                       compared_cycles,dut.pixel_x,dut.pixel_y,reference.pixel_x,reference.pixel_y);
            compared_cycles = compared_cycles + 1;
            if (de_value && row_value >= 20 && row_value < 102 && col_value >= 199 && col_value < 740)
                text_window_pixels = text_window_pixels + 1;
            if (de_value && row_value >= 20 && row_value < 102 && col_value >= 200 && col_value < 740 &&
                ((col_value-200)%18 == 16 || (col_value-200)%18 == 17)) gap_pixels = gap_pixels + 1;
            if (de_value) mode_sample_mask[mode_active] = 1'b1;
            if (scenario_count == 1 && de_value && row_value >= 20 && row_value < 36 &&
                col_value >= 308 && col_value < 452)
                mode_title_pixels[mode_active] = mode_title_pixels[mode_active] + 1;
        end
    endtask

    task check_xy;
        input integer expected_x, expected_y;
        begin
            if (dut.pixel_x !== expected_x[11:0] || dut.pixel_y !== expected_y[11:0] ||
                reference.pixel_x !== expected_x[11:0] || reference.pixel_y !== expected_y[11:0])
                $fatal(1,"expected coordinates (%0d,%0d), dut=(%0d,%0d) ref=(%0d,%0d)",
                       expected_x,expected_y,dut.pixel_x,dut.pixel_y,reference.pixel_x,reference.pixel_y);
        end
    endtask

    task begin_text_row;
        input integer scenario;
        begin
            step(1'b0,1'b0,1'b1,24'h111111,scenario,0,0);
            step(1'b0,1'b0,1'b1,24'h222222,scenario,0,1);
            step(1'b0,1'b0,1'b0,24'h333333,scenario,0,2);
            for (y=0; y<20; y=y+1) begin
                step(1'b1,1'b0,1'b0,24'h444444,scenario,y,0);
                step(1'b0,1'b0,1'b0,24'h555555,scenario,y,1);
            end
            check_xy(0,20);
        end
    endtask

    task scan_text_to_x;
        input integer target_x;
        input integer scenario;
        begin
            for (x=0; x<=target_x; x=x+1)
                step(1'b1,(x<40),1'b0,{x[7:0],8'h20,scenario[7:0]},scenario,20,x);
            check_xy(target_x+1,20);
        end
    endtask

    initial begin
        for (m=0; m<16; m=m+1) mode_title_pixels[m] = 0;
        for (m=0; m<8; m=m+1)
            if (dut.mode_char(4'd15,m[5:0]) !== track_title[(7-m)*8 +: 8])
                $fatal(1,"TRACK mode title mismatch char=%0d",m);
        repeat (3) @(posedge clk);
        #1;
        if ({rgb_new,de_new,hs_new,vs_new} !== 27'd0 || {rgb_old,de_old,hs_old,vs_old} !== 27'd0)
            $fatal(1, "reset outputs did not clear");
        @(negedge clk); rst_n = 1'b1;
        for (frame_index=0; frame_index<2; frame_index=frame_index+1) begin
            step(1'b0,1'b0,1'b1,24'hdeadbe,frame_index,0,0);
            step(1'b0,1'b0,1'b1,24'h123456,frame_index,0,1);
            step(1'b0,1'b0,1'b0,24'habcdef,frame_index,0,2);
            check_xy(0,0);
            for (y=0; y<720; y=y+1) begin
                check_xy(0,y);
                for (x=0; x<1280; x=x+1)
                    step(1'b1,(x<40),1'b0,{x[7:0],y[7:0],frame_index[7:0]},frame_index,y,x);
                check_xy(1280,y);
                for (b=0; b<370; b=b+1)
                    step(1'b0,(b<40),1'b0,{b[7:0],y[7:0],8'h5a},frame_index,y,1280+b);
                check_xy(0,y+1);
            end
        end
        if (text_window_pixels < 2*82*540) $fatal(1,"text region coverage too low: %0d",text_window_pixels);
        if (gap_pixels < 2*4*30*2) $fatal(1,"text spacing coverage too low: %0d",gap_pixels);

        // Scan the complete 8-character mode name for all 16 fixed modes.
        fixed_mode_enable = 1'b1;
        scenario_count = 1;
        for (m=0; m<16; m=m+1) begin
            fixed_mode = m[3:0];
            step(1'b0,1'b0,1'b1,24'hdeadbe,m,0,0);
            step(1'b0,1'b0,1'b1,24'h123456,m,0,1);
            step(1'b0,1'b0,1'b0,24'habcdef,m,0,2);
            check_xy(0,0);
            for (y=0; y<36; y=y+1) begin
                check_xy(0,y);
                for (x=0; x<452; x=x+1)
                    step(1'b1,(x<40),1'b0,{x[7:0],y[7:0],m[7:0]},m,y,x);
                check_xy(452,y);
                step(1'b0,1'b0,1'b0,24'h010203,m,y,452);
                check_xy(0,y+1);
            end
            if (mode_title_pixels[m] != 16*144)
                $fatal(1,"mode title coverage mode=%0d pixels=%0d expected=%0d",m,mode_title_pixels[m],16*144);
            title_mode_mask[m] = 1'b1;
        end

        // End short active lines immediately around the text left, cell, and right edges.
        scenario_count = 2;
        fixed_mode = 4'd3;
        for (m=0; m<5; m=m+1) begin
            case (m)
                0: boundary=201;
                1: boundary=217;
                2: boundary=218;
                3: boundary=739;
                default: boundary=740;
            endcase
            begin_text_row(m);
            for (x=0; x<=boundary; x=x+1)
                step(1'b1,(x<40),1'b0,{x[7:0],8'h20,m[7:0]},m,20,x);
            check_xy(boundary+1,20);
            step(1'b0,1'b0,1'b0,24'h666666,m,20,boundary+1);
            check_xy(0,21);
            for (x=0; x<=218; x=x+1)
                step(1'b1,(x<40),1'b0,{x[7:0],8'h21,m[7:0]},m,21,x);
            check_xy(219,21);
            step(1'b0,1'b0,1'b0,24'h777777,m,21,219);
            check_xy(0,22);
            step(1'b0,1'b0,1'b0,24'h888888,m,22,0);
        end

        // VS wins over DE, remains high for multiple clocks, and resets the active text coordinates.
        scenario_count = 3;
        begin_text_row(0);
        scan_text_to_x(330,0);
        repeat (4) step(1'b1,1'b1,1'b1,24'h303030,0,20,0);
        check_xy(0,0);
        repeat (8) step(1'b0,1'b0,1'b1,24'h404040,0,20,0);
        check_xy(0,0);
        step(1'b0,1'b0,1'b0,24'h505050,0,20,0);

        // After long VS, advance by real DE falling edges and reset during the text row.
        begin_text_row(1);
        scan_text_to_x(330,1);
        @(negedge clk); rst_n=1'b0;
        #1;
        if ({rgb_new,de_new,hs_new,vs_new} !== 27'd0 || {rgb_old,de_old,hs_old,vs_old} !== 27'd0)
            $fatal(1,"asynchronous reset outputs did not clear");
        check_xy(0,0);
        repeat (2) @(posedge clk);
        @(negedge clk); rst_n=1'b1;
        step(1'b0,1'b0,1'b1,24'h010203,0,0,0);
        step(1'b0,1'b0,1'b0,24'h040506,0,0,1);
        if (title_mode_mask !== 16'hffff) $fatal(1,"mode title mask incomplete: %h",title_mode_mask);
        $display("PASS tb_osd_resource_equiv: full_frames=2 active_pixels=%0d cycles=%0d sampled_mode_mask=%h fixed_title_mode_mask=%h title_pixels_per_mode=%0d text_window_pixels=%0d spacing_pixels=%0d boundary_lines=5 vs_de_overlap=4 long_vs=8 reset_mid_text=1",
                 2*1280*720, compared_cycles, mode_sample_mask, title_mode_mask, 16*144, text_window_pixels, gap_pixels);
        $finish;
    end
endmodule
