`timescale 1ns/1ps
module tb_motion_threshold_controls;
    reg clk=0, rst_n=0;
    reg key0_n=1, key1_n=1, threshold_edit=0, frame_commit=0;
    reg [3:0] edit_mode=14;
    always #5 clk=~clk;

    wire [3:0] mode_pending, mode_active;
    wire threshold_edit_active;
    wire [7:0] motion_threshold_active;
    key_mode_ctrl #(.DEBOUNCE_CYCLES(2), .EXTERNAL_EDIT_MODE(1), .ENABLE_THRESHOLD_CONTROL(1),
        .ENABLE_MOTION_THRESHOLD_CONTROL(1)) dut (
        .clk(clk), .rst_n(rst_n), .key0_n(key0_n), .key1_n(key1_n),
        .frame_commit(frame_commit), .mode_pending(mode_pending), .mode_active(mode_active),
        .threshold_edit(threshold_edit), .edit_mode_in(edit_mode),
        .threshold_edit_active(threshold_edit_active), .motion_threshold_active(motion_threshold_active),
        .bin_threshold_active(), .edge_threshold_active(), .bright_gain_active(), .contrast_gain_active(),
        .polar_capture_pulse(), .polar_restart_pulse());

    key_mode_ctrl #(.DEBOUNCE_CYCLES(2)) legacy (
        .clk(clk), .rst_n(rst_n), .key0_n(1'b1), .key1_n(1'b1), .frame_commit(1'b0),
        .mode_pending(), .mode_active(), .threshold_edit(1'b0), .edit_mode_in(4'd0),
        .threshold_edit_active(), .motion_threshold_active(), .bin_threshold_active(),
        .edge_threshold_active(), .bright_gain_active(), .contrast_gain_active(),
        .polar_capture_pulse(), .polar_restart_pulse());

    video_status_osd #(.ENABLE_MOTION_THRESHOLD(1)) osd (
        .clk(clk),.rst_n(rst_n),.rgb_in(24'd0),.de_in(1'b0),.hs_in(1'b0),.vs_in(1'b0),
        .mode_active(4'd14),.bin_threshold_active(8'd128),.edge_threshold_active(8'd32),
        .bright_gain_active(8'd24),.contrast_gain_active(8'd24),.threshold_edit_active(1'b1),
        .polar_angle(2'd0),.polar_capture_busy(1'b0),.polar_compute_busy(1'b0),.polar_ready(1'b0),
        .polar_error(1'b0),.ddr_state(2'd0),.motion_threshold_active(8'd8),
        .rgb_out(),.de_out(),.hs_out(),.vs_out());
    video_status_osd legacy_osd (
        .clk(clk),.rst_n(rst_n),.rgb_in(24'd0),.de_in(1'b0),.hs_in(1'b0),.vs_in(1'b0),
        .mode_active(4'd14),.bin_threshold_active(8'd128),.edge_threshold_active(8'd32),
        .bright_gain_active(8'd24),.contrast_gain_active(8'd24),.threshold_edit_active(1'b1),
        .polar_angle(2'd0),.polar_capture_busy(1'b0),.polar_compute_busy(1'b0),.polar_ready(1'b0),
        .polar_error(1'b0),.ddr_state(2'd0),.motion_threshold_active(8'd8),
        .rgb_out(),.de_out(),.hs_out(),.vs_out());

    integer i;
    task press_key0;
        begin
            key0_n=0; repeat(14) @(posedge clk);
            key0_n=1; repeat(14) @(posedge clk);
        end
    endtask
    task press_key1;
        begin
            key1_n=0; repeat(14) @(posedge clk);
            key1_n=1; repeat(14) @(posedge clk);
        end
    endtask
    task check_text;
        input [5:0] idx;
        input [7:0] expected;
        begin
            if (osd.text_char(2'd3,idx,4'd14,32'd0,8'd128,8'd8,1'b1,2'd0,
                              1'b0,1'b0,1'b0,1'b0,2'd0) !== expected)
                $fatal(1,"enabled OSD char %0d expected %c",idx,expected);
        end
    endtask

    initial begin
        repeat(3) @(posedge clk); rst_n=1;
        repeat(5) @(posedge clk);
        if (motion_threshold_active !== 8'd8) $fatal(1,"reset threshold must be 8");
        threshold_edit=1; repeat(8) @(posedge clk);
        if (!threshold_edit_active) $fatal(1,"SW1 did not debounce");
        // Key2 decrements pending and commits only on frame_commit.
        press_key0();
        if (dut.motion_threshold_pending !== 8'd7) $fatal(1,"decrement step failed");
        if (motion_threshold_active !== 8'd8) $fatal(1,"threshold changed before frame commit");
        frame_commit=1; @(posedge clk); frame_commit=0; @(posedge clk);
        if (motion_threshold_active !== 8'd7) $fatal(1,"frame commit did not publish pending threshold");
        edit_mode=3; press_key1();
        if (dut.edge_threshold_pending !== 8'd33) $fatal(1,"mode 3 edge parameter did not remain independent");
        if (dut.motion_threshold_pending !== 8'd7) $fatal(1,"threshold changed outside mode 14");
        edit_mode=14;
        // Return to mode 14 and verify the stored setting survived the mode change.
        for (i=0;i<6;i=i+1) press_key1();
        if (dut.motion_threshold_pending !== 8'd13) $fatal(1,"unexpected threshold after mode round trip");
        // Use key2 until lower clamp, then check additional decrement is ignored.
        for (i=0;i<12;i=i+1) press_key0();
        if (dut.motion_threshold_pending !== 8'd1) $fatal(1,"lower clamp failed");
        press_key0();
        if (dut.motion_threshold_pending !== 8'd1) $fatal(1,"lower clamp underflow");
        for (i=0;i<254;i=i+1) press_key1();
        if (dut.motion_threshold_pending !== 8'd255) $fatal(1,"upper endpoint failed");
        press_key1();
        if (dut.motion_threshold_pending !== 8'd255) $fatal(1,"upper clamp overflow");

        // A simultaneous two-key press must not alter the selected parameter.
        key0_n=0; key1_n=0; repeat(20) @(posedge clk); key0_n=1; key1_n=1; repeat(16) @(posedge clk);
        if (dut.motion_threshold_pending !== 8'd255) $fatal(1,"two-key press was not suppressed");

        check_text(0,"M"); check_text(1,"O"); check_text(2,"T"); check_text(3," ");
        check_text(4,"T"); check_text(5,"H"); check_text(6,"R"); check_text(7,":");
        check_text(8,"0"); check_text(9,"0"); check_text(10,"8");
        check_text(14,"K"); check_text(15,"E"); check_text(16,"Y"); check_text(17,":");
        check_text(18,"T"); check_text(19,"H"); check_text(20,"R");
        if (osd.text_char(2'd3,18,4'd14,32'd0,8'd128,8'd8,1'b0,2'd0,
            1'b0,1'b0,1'b0,1'b0,2'd0) !== "M" ||
            osd.text_char(2'd3,21,4'd14,32'd0,8'd128,8'd8,1'b0,2'd0,
            1'b0,1'b0,1'b0,1'b0,2'd0) !== "E") $fatal(1,"mode 14 OSD did not show KEY:MODE with SW1 off");
        if (legacy_osd.text_char(2'd3,0,4'd14,32'd0,8'd128,8'd32,1'b1,2'd0,
            1'b0,1'b0,1'b0,1'b0,2'd0) !== 8'h20) $fatal(1,"disabled OSD mode 14 semantics changed");
        if (legacy.motion_threshold_active !== 8'd8) $fatal(1,"disabled controller default changed");
        $display("PASS tb_motion_threshold_controls");
        $finish;
    end
endmodule
