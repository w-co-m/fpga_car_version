`timescale 1ns/1ps

// Full-size integration check for mode 14's default block-mean detector.
module tb_motion_low_contrast_720p;
    localparam integer IMG_W = 1280;
    localparam integer IMG_H = 720;
    localparam [23:0] BG = 24'h181818;
    localparam [23:0] TARGET = 24'h282828;
    localparam [23:0] SENTINEL = 24'h171818;
    localparam [23:0] MOTION_RED = 24'hff0000;
    localparam [23:0] STATUS_GREEN = 24'h00ff00;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [23:0] rgb_in = BG;
    reg de_in = 0, hs_in = 0, vs_in = 0;
    wire [23:0] rgb_out;
    wire de_out, hs_out, vs_out;

    reg [23:0] rgb_pipe [0:4];
    reg de_pipe [0:4], hs_pipe [0:4], vs_pipe [0:4];
    integer x_pipe [0:4], y_pipe [0:4];
    integer i;
    integer x = 0, y = 0;
    integer frame_no = 0;
    integer red_pixels = 0;
    integer sync_checks = 0;
    integer rgb_checks = 0;
    integer sentinel_checks = 0;

    algo_bank dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .mode(4'd14),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .bin_threshold_in(8'd128), .edge_threshold_in(8'd32),
        .bright_gain_in(8'd24), .contrast_gain_in(8'd24),
        .color_debug_in(1'b0), .motion_threshold_in(8'd0),
        .rgb_out(rgb_out), .de_out(de_out), .hs_out(hs_out), .vs_out(vs_out)
    );

    function expected_mask;
        input integer xx, yy;
        begin
            // Frame 3 displays the motion measured in frame 2. The secondary
            // 15-of-16 sample tile intentionally changes only non-first pixels;
            // its complete 16-pixel block is the expected block-mean mask.
            expected_mask = (frame_no == 3) &&
                (((xx >= 1104) && (xx <= 1279) && (yy >= 610) && (yy <= 719)) ||
                 ((xx >= 800) && (xx <= 815) && (yy >= 300) && (yy <= 399)));
        end
    endfunction

    function status_area;
        input integer xx, yy;
        begin
            // algo_motion's production green status block: x=1224..1271, y=8..39.
            status_area = (xx >= 1224) && (xx < 1272) && (yy >= 8) && (yy < 40);
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 5; i = i + 1) begin
                rgb_pipe[i] <= 0;
                de_pipe[i] <= 0;
                hs_pipe[i] <= 0;
                vs_pipe[i] <= 0;
                x_pipe[i] <= 0;
                y_pipe[i] <= 0;
            end
        end else begin
            rgb_pipe[0] <= rgb_in;
            de_pipe[0] <= de_in;
            hs_pipe[0] <= hs_in;
            vs_pipe[0] <= vs_in;
            x_pipe[0] <= x;
            y_pipe[0] <= y;
            for (i = 1; i < 5; i = i + 1) begin
                rgb_pipe[i] <= rgb_pipe[i-1];
                de_pipe[i] <= de_pipe[i-1];
                hs_pipe[i] <= hs_pipe[i-1];
                vs_pipe[i] <= vs_pipe[i-1];
                x_pipe[i] <= x_pipe[i-1];
                y_pipe[i] <= y_pipe[i-1];
            end
            #1;
            if ({de_out, hs_out, vs_out} !== {de_pipe[4], hs_pipe[4], vs_pipe[4]})
                $fatal(1, "mode14 five-clock sync mismatch frame=%0d", frame_no);
            sync_checks = sync_checks + 1;

            if (de_pipe[4]) begin
                if (expected_mask(x_pipe[4], y_pipe[4])) begin
                    if (rgb_out !== MOTION_RED)
                        $fatal(1, "missing red mask at (%0d,%0d) frame=%0d rgb=%h",
                            x_pipe[4], y_pipe[4], frame_no, rgb_out);
                    red_pixels = red_pixels + 1;
                end else begin
                    if (rgb_out === MOTION_RED)
                        $fatal(1, "unexpected red mask at (%0d,%0d) frame=%0d",
                            x_pipe[4], y_pipe[4], frame_no);
                    if (!status_area(x_pipe[4], y_pipe[4]) && rgb_out !== rgb_pipe[4])
                        $fatal(1, "unmarked RGB changed at (%0d,%0d): got=%h expected=%h",
                            x_pipe[4], y_pipe[4], rgb_out, rgb_pipe[4]);
                    if (rgb_pipe[4] === SENTINEL) begin
                        if (rgb_out !== SENTINEL)
                            $fatal(1, "sentinel RGB changed: got=%h", rgb_out);
                        sentinel_checks = sentinel_checks + 1;
                    end
                    rgb_checks = rgb_checks + 1;
                end
            end
        end
    end

    task idle;
        input integer count;
        integer k;
        begin
            for (k = 0; k < count; k = k + 1) begin
                @(negedge clk);
                rgb_in = BG; de_in = 0; hs_in = 0; vs_in = 0;
            end
        end
    endtask

    task send_frame;
        input integer scene;
        integer xx, yy, blank_i;
        begin
            frame_no = frame_no + 1;
            red_pixels = 0;
            @(negedge clk); rgb_in = BG; de_in = 0; hs_in = 0; vs_in = 1;
            @(negedge clk); vs_in = 0;
            for (yy = 0; yy < IMG_H; yy = yy + 1) begin
                for (xx = 0; xx < IMG_W; xx = xx + 1) begin
                    @(negedge clk);
                    x = xx;
                    y = yy;
                    de_in = 1;
                    hs_in = (xx == 0);
                    rgb_in = BG;
                    if (xx == 20 && yy == 400) rgb_in = SENTINEL;
                    if (scene == 1 &&
                        (((xx >= 1104) && (xx <= 1279) && (yy >= 610) && (yy <= 719)) ||
                         ((xx >= 801) && (xx <= 815) && (yy >= 300) && (yy <= 399))))
                        rgb_in = TARGET;
                end
                for (blank_i = 0; blank_i < 16; blank_i = blank_i + 1) begin
                    @(negedge clk); rgb_in = BG; de_in = 0; hs_in = 1;
                end
            end
            idle(8);
            $display("frame %0d scene=%0d red_mask_pixels=%0d", frame_no, scene, red_pixels);
        end
    endtask

    task expect_count;
        input integer expected;
        input integer detected;
        input [8*40-1:0] label;
        begin
            if (dut.u_motion.motion_pixel_cnt !== expected ||
                dut.u_motion.motion_detected !== detected[0]) begin
                $display("FAIL %0s count=%0d detected=%b expected=%0d/%0d",
                    label, dut.u_motion.motion_pixel_cnt, dut.u_motion.motion_detected,
                    expected, detected);
                $fatal(1, "motion frame count mismatch");
            end
        end
    endtask

    initial begin
        for (i = 0; i < 5; i = i + 1) begin
            rgb_pipe[i] = 0; de_pipe[i] = 0; hs_pipe[i] = 0; vs_pipe[i] = 0;
            x_pipe[i] = 0; y_pipe[i] = 0;
        end
        idle(8); rst_n = 1;

        // Frame 1 seeds the reference; frame 2 changes a dim gray object
        // (24 -> 40, delta 16), including the bottom-right final pixel.
        send_frame(0);
        send_frame(1);
        expect_count(0, 0, "reference warmup");
        if (red_pixels != 0) $fatal(1, "mask appeared before frame result publication");

        // Frame 3 displays frame 2's mask. The exact area includes 176*110
        // pixels at bottom-right and 16*100 pixels from the offset sample tile.
        send_frame(1);
        expect_count(20960, 1, "low-contrast movement");
        if (red_pixels != 20960)
            $fatal(1, "wrong delayed mask area: got=%0d expected=20960", red_pixels);

        // The image is now stationary. Frame 4's previous-frame decision is
        // zero, so both the published count and red mask must clear.
        send_frame(1);
        expect_count(0, 0, "stationary recovery");
        if (red_pixels != 0) $fatal(1, "stationary image retained red mask pixels=%0d", red_pixels);

        if (sync_checks < 1000000 || rgb_checks < 1000000 || sentinel_checks < 4)
            $fatal(1, "insufficient pipeline checks sync=%0d rgb=%0d sentinel=%0d",
                sync_checks, rgb_checks, sentinel_checks);
        $display("PASS tb_motion_low_contrast_720p sync_checks=%0d rgb_checks=%0d sentinel_checks=%0d",
            sync_checks, rgb_checks, sentinel_checks);
        $finish;
    end

    initial begin
        #200000000; $fatal(1, "timeout waiting for 720p low-contrast sequence");
    end
endmodule
