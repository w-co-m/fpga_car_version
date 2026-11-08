`timescale 1ns/1ps
module tb_level_controls;
    reg clk=0, rst_n=0, key0_n=1, key1_n=1, threshold_edit=0;
    reg [23:0] rgb_in=24'h606060;
    reg de_in=0, hs_in=0, vs_in=0;
    reg [3:0] render_mode_in=0;
    wire [23:0] rgb_out;
    wire de_out, hs_out, vs_out;
    wire [3:0] mode_active, mode_pending_out;
    wire [7:0] bin_threshold_active, edge_threshold_active;
    wire [7:0] bright_gain_active, contrast_gain_active;
    wire threshold_edit_active;
    reg [4:0] de_ref=0, hs_ref=0, vs_ref=0;
    integer i, checks=0;

    always #5 clk=~clk;
    video_algorithm_display #(
        .ALGO_COUNT(16), .CLK_HZ(1000), .DEBOUNCE_CYCLES(3),
        .IMG_WIDTH(8), .IMG_HEIGHT(8), .EXTERNAL_RENDER_MODE(1),
        .BRIGHT_GAIN(24), .CONTRAST_GAIN(24), .GAIN_STEP(1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .key0_n(key0_n), .key1_n(key1_n),
        .threshold_edit(threshold_edit), .rgb_in(rgb_in), .de_in(de_in),
        .hs_in(hs_in), .vs_in(vs_in), .rgb_out(rgb_out), .de_out(de_out),
        .hs_out(hs_out), .vs_out(vs_out), .mode_active(mode_active),
        .mode_pending_out(mode_pending_out), .render_mode_in(render_mode_in),
        .bin_threshold_active(bin_threshold_active),
        .edge_threshold_active(edge_threshold_active),
        .bright_gain_active(bright_gain_active),
        .contrast_gain_active(contrast_gain_active),
        .threshold_edit_active(threshold_edit_active)
    );

    // Brightness/contrast branches retain the common five-clock RGB/sync path.
    always @(posedge clk) begin
        if (!rst_n) begin de_ref=0; hs_ref=0; vs_ref=0; end
        else begin
            de_ref={de_ref[3:0],de_in};
            hs_ref={hs_ref[3:0],hs_in};
            vs_ref={vs_ref[3:0],vs_in};
        end
        #1;
        if (rst_n && (render_mode_in==4 || render_mode_in==5)) begin
            if ({de_out,hs_out,vs_out} !== {de_ref[4],hs_ref[4],vs_ref[4]})
                $fatal(1,"five-cycle sync mismatch mode=%0d got=%b%b%b expected=%b%b%b",
                       render_mode_in,de_out,hs_out,vs_out,de_ref[4],hs_ref[4],vs_ref[4]);
            checks=checks+1;
        end
    end

    task tick; input integer n; integer j; begin for(j=0;j<n;j=j+1) @(negedge clk); end endtask
    task frame_commit;
        begin
            de_in=0; vs_in=0; tick(2); vs_in=1; tick(1); vs_in=0; tick(2);
        end
    endtask
    task release_keys; begin key0_n=1; key1_n=1; tick(18); end endtask
    task press_next;
        begin key1_n=0; tick(18); key1_n=1; tick(18); end
    endtask
    task menu_next;
        begin
            press_next;
            if (mode_pending_out !== ((mode_active==15)?0:mode_active+1'b1))
                $fatal(1,"mode pending failed to advance: %0d/%0d",mode_pending_out,mode_active);
            frame_commit;
        end
    endtask
    task press_edit_up;
        begin key1_n=0; tick(18); key1_n=1; tick(18); end
    endtask
    task press_edit_down;
        begin key0_n=0; tick(18); key0_n=1; tick(18); end
    endtask
    task check_gains;
        input [7:0] bright_expected, contrast_expected;
        input [255:0] label_text;
        begin
            if (bright_gain_active !== bright_expected || contrast_gain_active !== contrast_expected)
                $fatal(1,"%0s gains=%0d/%0d expected=%0d/%0d",label_text,
                       bright_gain_active,contrast_gain_active,bright_expected,contrast_expected);
        end
    endtask
    task sample_pixel;
        input [23:0] pixel;
        input [23:0] expected;
        input [255:0] label_text;
        begin
            rgb_in=pixel; de_in=1; tick(9);
            if (rgb_out !== expected || de_out !== 1'b1)
                $fatal(1,"%0s mode=%0d got=%h de=%b expected=%h",label_text,
                       render_mode_in,rgb_out,de_out,expected);
            de_in=0; tick(8);
        end
    endtask
    task edit_once;
        input up;
        input [7:0] bright_expected, contrast_expected;
        reg [7:0] old_bright, old_contrast;
        begin
            old_bright=bright_gain_active;
            old_contrast=contrast_gain_active;
            if (up) press_edit_up; else press_edit_down;
            // Gain requests remain pending until a frame commit.
            if (bright_gain_active !== old_bright || contrast_gain_active !== old_contrast)
                $fatal(1,"gain active changed before frame commit");
            frame_commit;
            check_gains(bright_expected,contrast_expected,"committed one-step adjustment");
        end
    endtask
    task same_cycle_gain_commit;
        input [7:0] bright_expected, contrast_expected;
        begin
            key1_n=0;
            wait(dut.u_mode.press_event === 1'b1);
            @(negedge clk); vs_in=1;
            @(posedge clk); #1;
            if (bright_gain_active!==bright_expected || contrast_gain_active!==contrast_expected)
                $fatal(1,"same-cycle gain event/frame commit got=%0d/%0d expected=%0d/%0d",
                       bright_gain_active,contrast_gain_active,bright_expected,contrast_expected);
            @(negedge clk); vs_in=0;
            key1_n=1; tick(18);
        end
    endtask

    initial begin
        repeat(4) tick(1); rst_n=1; tick(12);
        check_gains(24,24,"reset defaults");

        // Select mode 4 through the real debounced menu and frame commit.
        repeat(4) begin menu_next; end
        if (mode_active!==4) $fatal(1,"failed to select mode4");
        render_mode_in=4; tick(2);
        sample_pixel(24'h606060,24'h909090,"brightness default 96*24/16");
        sample_pixel(24'h645032,24'h8d795b,"brightness default colored pixel");

        // External DDR route can report requested mode 5 while mode 4 remains
        // the actual displayed/edit target. The key must affect brightness only.
        menu_next;
        if (mode_active!==5 || render_mode_in!==4) $fatal(1,"external delayed-render setup failed");
        threshold_edit=1; tick(12);
        if (!threshold_edit_active) $fatal(1,"SW1 edit confirmation missing");
        edit_once(1,25,24);
        sample_pixel(24'h606060,24'h969696,"mode4 gain25 while requested mode is5");
        sample_pixel(24'h645032,24'h927e60,"brightness gain25 colored pixel");

        // A rendered-mode change during key arbitration cancels the action.
        key1_n=0; tick(7); render_mode_in=5; tick(12);
        key1_n=1; tick(18); render_mode_in=4; frame_commit;
        check_gains(25,24,"render-mode change cancels in-flight edit");

        // A SW1 change during arbitration also cancels the key event.
        key1_n=0; tick(7); threshold_edit=0; tick(12);
        key1_n=1; tick(18); frame_commit;
        if (mode_pending_out!==5 || mode_active!==5)
            $fatal(1,"SW1 change converted an edit press into a menu action");
        check_gains(25,24,"SW1 change cancels in-flight edit");

        threshold_edit=1; tick(12); if (!threshold_edit_active) $fatal(1,"SW1 did not re-enter edit");
        // A held key is one event; simultaneous keys are suppressed.
        key1_n=0; tick(100); key1_n=1; tick(18); frame_commit;
        check_gains(26,24,"long press is one adjustment");
        same_cycle_gain_commit(27,24);
        sample_pixel(24'h645032,24'h9d896b,"same-cycle commit colored pixel");
        key0_n=0; key1_n=0; tick(40); release_keys; frame_commit;
        check_gains(27,24,"two-key press is suppressed");

        // Verify the full 0..255 range, both saturation boundaries, and reset
        // independently for brightness while mode 4 is the actual render mode.
        for(i=26;i>=0;i=i-1) begin
            press_edit_down; frame_commit;
            if (bright_gain_active !== i[7:0] || contrast_gain_active !== 24)
                $fatal(1,"brightness decrement range mismatch i=%0d got=%0d/%0d",i,bright_gain_active,contrast_gain_active);
        end
        press_edit_down; frame_commit;
        check_gains(0,24,"brightness lower clamp");
        sample_pixel(24'h606060,24'h000000,"brightness gain zero");
        for(i=1;i<=255;i=i+1) begin
            press_edit_up; frame_commit;
            if (bright_gain_active !== i[7:0] || contrast_gain_active !== 24)
                $fatal(1,"brightness increment range mismatch i=%0d got=%0d/%0d",i,bright_gain_active,contrast_gain_active);
        end
        press_edit_up; frame_commit;
        check_gains(255,24,"brightness upper clamp");
        sample_pixel(24'hc8c8c8,24'hffffff,"brightness upper saturation");

        // Change the actual display route to mode 5. The contrast branch keeps
        // its independent default and its 128 gray anchor while gain changes.
        render_mode_in=5; tick(2);
        sample_pixel(24'h606060,24'h505050,"contrast default gain24");
        sample_pixel(24'h645032,24'h4e3a1c,"contrast default colored pixel");
        edit_once(1,255,25);
        sample_pixel(24'h606060,24'h4e4e4e,"contrast gain25 around gray128");
        sample_pixel(24'h645032,24'h4b3719,"contrast gain25 colored pixel");
        sample_pixel(24'h808080,24'h808080,"contrast middle-gray anchor");
        for(i=24;i>=0;i=i-1) begin
            press_edit_down; frame_commit;
            if (contrast_gain_active !== i[7:0] || bright_gain_active !== 255)
                $fatal(1,"contrast decrement range mismatch i=%0d got=%0d/%0d",i,bright_gain_active,contrast_gain_active);
        end
        press_edit_down; frame_commit;
        check_gains(255,0,"contrast lower clamp");
        sample_pixel(24'h606060,24'h808080,"contrast gain zero maps to anchor");
        for(i=1;i<=255;i=i+1) begin
            press_edit_up; frame_commit;
            if (contrast_gain_active !== i[7:0] || bright_gain_active !== 255)
                $fatal(1,"contrast increment range mismatch i=%0d got=%0d/%0d",i,bright_gain_active,contrast_gain_active);
        end
        press_edit_up; frame_commit;
        check_gains(255,255,"contrast upper clamp");
        sample_pixel(24'h000000,24'h000000,"contrast lower saturation");
        sample_pixel(24'hffffff,24'hffffff,"contrast upper saturation");

        // Existing binary/Sobel threshold controls use one-count steps and
        // remain independent of both new level gains.
        threshold_edit=0; tick(12);
        key0_n=0; tick(18); key0_n=1; tick(18); frame_commit; // mode 5 -> 4
        key0_n=0; tick(18); key0_n=1; tick(18); frame_commit; // mode 4 -> 3
        if(mode_active!==3) $fatal(1,"failed to select mode3");
        render_mode_in=3; threshold_edit=1; tick(12);
        press_edit_up; frame_commit;
        if(edge_threshold_active!==33 || bin_threshold_active!==128)
            $fatal(1,"Sobel threshold control changed: %0d/%0d",bin_threshold_active,edge_threshold_active);
        check_gains(255,255,"mode3 does not alter gains");
        threshold_edit=0; tick(12); key0_n=0; tick(18); key0_n=1; tick(18); frame_commit;
        if(mode_active!==2) $fatal(1,"failed to select mode2");
        render_mode_in=2; threshold_edit=1; tick(12);
        press_edit_up; frame_commit;
        if(bin_threshold_active!==129 || edge_threshold_active!==33)
            $fatal(1,"binary threshold control changed: %0d/%0d",bin_threshold_active,edge_threshold_active);
        check_gains(255,255,"mode2 does not alter gains");

        // Asynchronous reset restores both controls to their configured defaults.
        rst_n=0; tick(3);
        check_gains(24,24,"reset restores gains");
        $display("PASS tb_level_controls: pixel math, independent gains, delayed external render, commit, cancellation, debounce, bounds, saturation, mode2/3, five-cycle sync checks=%0d",checks);
        $finish;
    end
    initial begin #10000000; $fatal(1,"tb_level_controls timeout"); end
endmodule
