`timescale 1ns/1ps

// Minimal screen-gray pink foam reproduction through the production display path.
module tb_algo10_pink_rect;
    // Frozen legacy rule-5 single-frame contract; production rule-6 has its own regressions.
    defparam display.u_bank.COLOR_DET_RULE=5;

    localparam W = 32, H = 24;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [23:0] rgb_in = 0;
    reg de_in = 0, hs_in = 0, vs_in = 0;
    reg threshold_edit = 0;
    reg [3:0] render_mode = 13;
    reg inner_marker_in = 0, normal_check_en = 0;
    wire [23:0] rgb_out;
    wire de_out, hs_out, vs_out;
    wire [3:0] mode_active, mode_pending;
    wire edit_active;
    integer x, y;
    reg mask_check_en = 0;
    integer mask_checks = 0;
    integer normal_checks = 0;
    reg mask_exp [0:4], de_exp [0:4], hs_exp [0:4], vs_exp [0:4];
    reg normal_inner_exp [0:4];
    integer q;

    video_algorithm_display #(.IMG_WIDTH(W), .IMG_HEIGHT(H), .DEBOUNCE_CYCLES(3),
        .EXTERNAL_RENDER_MODE(1), .ALGO_COUNT(16)) display (
        .clk(clk), .rst_n(rst_n), .key0_n(1'b1), .key1_n(1'b1),
        .threshold_edit(threshold_edit), .rgb_in(rgb_in), .de_in(de_in), .hs_in(hs_in),
        .vs_in(vs_in), .rgb_out(rgb_out), .de_out(de_out), .hs_out(hs_out),
        .vs_out(vs_out), .mode_active(mode_active), .mode_pending_out(mode_pending),
        .render_mode_in(render_mode), .polar_capture_pulse(), .polar_restart_pulse(),
        .bin_threshold_active(), .edge_threshold_active(), .bright_gain_active(),
        .contrast_gain_active(), .threshold_edit_active(edit_active),
        .frame_valid_in(1'b1), .bank_run(1'b1)
    );

    // Check the detector mask and shared 5-cycle pixel/sync path while SW1 is
    // selected. The golden mask uses this bench's literal uniform target scene.
    always @(posedge clk) begin
        if (!rst_n) begin
            for (q = 0; q < 5; q = q + 1) begin
                mask_exp[q] <= 0; de_exp[q] <= 0; hs_exp[q] <= 0; vs_exp[q] <= 0;
                normal_inner_exp[q] <= 0;
            end
        end else begin
            mask_exp[0] <= de_in && (rgb_in == 24'h998c8d);
            normal_inner_exp[0] <= de_in && inner_marker_in;
            de_exp[0] <= de_in; hs_exp[0] <= hs_in; vs_exp[0] <= vs_in;
            for (q = 1; q < 5; q = q + 1) begin
                mask_exp[q] <= mask_exp[q-1]; de_exp[q] <= de_exp[q-1];
                hs_exp[q] <= hs_exp[q-1]; vs_exp[q] <= vs_exp[q-1];
                normal_inner_exp[q] <= normal_inner_exp[q-1];
            end
            #1;
`ifdef PINK_RECT_DEBUG_TEST
            if (mask_check_en && render_mode == 13 && display.u_bank.color_debug_active) begin
                if (de_out !== de_exp[4] || hs_out !== hs_exp[4] || vs_out !== vs_exp[4])
                    $fatal(1, "mask mode RGB/sync five-cycle alignment mismatch");
                if (rgb_out !== (mask_exp[4] ? 24'h00ff00 : 24'h000000))
                    $fatal(1, "mask RGB mismatch got=%h expected=%h hit=%0d", rgb_out,
                           mask_exp[4] ? 24'h00ff00 : 24'h000000, mask_exp[4]);
                if (de_exp[4]) mask_checks = mask_checks + 1;
            end
            if (normal_check_en && render_mode == 13 && !display.u_bank.color_debug_active && normal_inner_exp[4]) begin
                if (rgb_out !== 24'h998c8d)
                    $fatal(1, "normal mode failed to restore interior source RGB: %h", rgb_out);
                normal_checks = normal_checks + 1;
            end
`endif
        end
    end

    task blank;
        input integer count;
        integer k;
        begin
            for (k = 0; k < count; k = k + 1) begin
                @(negedge clk); rgb_in = 0; de_in = 0; hs_in = 0; vs_in = 0; inner_marker_in = 0;
            end
        end
    endtask

    task scene_frame;
        input [23:0] marker;
        input integer shape; // 0 horizontal, 1 vertical, 2 rotated textured, 3 thin, 4 sparse
        integer xx, yy, dx, dy;
        begin
            @(negedge clk); rgb_in = 0; de_in = 0; hs_in = 0; vs_in = 1;
            @(negedge clk); vs_in = 0;
            for (yy = 0; yy < H; yy = yy + 1) begin
                for (xx = 0; xx < W; xx = xx + 1) begin
                    @(negedge clk);
                    de_in = 1; hs_in = (xx == 0); rgb_in = 0;
                    inner_marker_in = 0;
                    dx = xx - 16; dy = yy - 12;
                    case (shape)
                        0: if (xx >= 8 && xx <= 23 && yy >= 8 && yy <= 15) rgb_in = marker;
                        1: if (xx >= 12 && xx <= 19 && yy >= 4 && yy <= 19) rgb_in = marker;
                        2: if ((dx+dy >= -11) && (dx+dy <= 11) &&
                               (dy-dx >= -5) && (dy-dx <= 5) && ((xx+yy)%4 != 0)) rgb_in = marker;
                        3: if (xx >= 15 && xx <= 16 && yy >= 4 && yy <= 19) rgb_in = marker;
                        4: if ((xx == 8 || xx == 16 || xx == 23) &&
                               (yy == 8 || yy == 12 || yy == 15)) rgb_in = marker;
                    endcase
                end
                @(negedge clk); rgb_in = 0; de_in = 0; hs_in = 0; inner_marker_in = 0;
            end
            blank(8);
        end
    endtask

    task valid_case;
        input [23:0] marker;
        input integer shape;
        input integer xmin, xmax, ymin, ymax;
        input [8*32-1:0] label;
        begin
            scene_frame(marker, shape);
            scene_frame(marker, shape);
            if (!display.u_bank.color_bbox_valid ||
                display.u_bank.color_bbox_x_min !== xmin || display.u_bank.color_bbox_x_max !== xmax ||
                display.u_bank.color_bbox_y_min !== ymin || display.u_bank.color_bbox_y_max !== ymax ||
                !display.u_bank.u_color_detect.shape_ok) begin
                $display("FAIL: %0s bbox/shape invalid got valid=%0d [%0d,%0d]-[%0d,%0d] shape_ok=%0d",
                         label, display.u_bank.color_bbox_valid, display.u_bank.color_bbox_x_min,
                         display.u_bank.color_bbox_y_min, display.u_bank.color_bbox_x_max,
                         display.u_bank.color_bbox_y_max, display.u_bank.u_color_detect.shape_ok);
                $fatal(1, "PINK_RECT_CASE %0s", label);
            end
        end
    endtask

    task rejected_color;
        input [23:0] marker;
        input [8*32-1:0] label;
        begin
            scene_frame(marker, 0);
            scene_frame(marker, 0);
            if (display.u_bank.color_bbox_valid) $fatal(1, "false positive %0s", label);
        end
    endtask

    task selector_frame;
        input change_to;
        integer xx, yy;
        begin
            @(negedge clk); rgb_in = 0; de_in = 0; hs_in = 0; vs_in = 1;
            @(negedge clk); vs_in = 0;
            for (yy = 0; yy < H; yy = yy + 1) begin
                for (xx = 0; xx < W; xx = xx + 1) begin
                    @(negedge clk);
                    de_in = 1; hs_in = (xx == 0); rgb_in = 0;
                    if (xx >= 8 && xx <= 23 && yy >= 8 && yy <= 15) rgb_in = 24'h998c8d;
                    inner_marker_in = (xx == 10 && yy == 10);
                    if (yy == 5 && xx == 0) threshold_edit = change_to;
                end
                @(negedge clk); rgb_in = 0; de_in = 0; hs_in = 0; inner_marker_in = 0;
            end
            blank(8);
        end
    endtask

    initial begin
        blank(4); rst_n = 1;
        valid_case(24'h998c8d, 0, 8, 23, 8, 15, "screen pink horizontal");
        valid_case(24'h918081, 0, 8, 23, 8, 15, "screen pink sample 2");
        valid_case(24'h9f9395, 0, 8, 23, 8, 15, "screen pink sample 3");
        valid_case(24'h4c4646, 0, 8, 23, 8, 15, "half brightness pink");
        valid_case(24'h781e14, 0, 8, 23, 8, 15, "red marker regression");
        valid_case(24'h998f8f, 0, 8, 23, 8, 15, "ratio above boundary");
        valid_case(24'h999090, 0, 8, 23, 8, 15, "ratio equality: 16*153=17*144");
        rejected_color(24'h999190, "G just beyond relative-red ratio");
        rejected_color(24'h999091, "B just beyond relative-red ratio");
        valid_case(24'h2e2828, 0, 8, 23, 8, 15, "chroma equals six");
        rejected_color(24'h2d2828, "chroma five with relative-red ratio pass");
        valid_case(24'h644637, 0, 8, 23, 8, 15, "hue spread boundary equality");
        rejected_color(24'h644636, "hue spread just outside boundary");
        valid_case(24'h998c8d, 1, 12, 19, 4, 19, "screen pink vertical");
        valid_case(24'h998c8d, 2, 8, 24, 4, 20, "45-degree textured pink");
        rejected_color(24'hdcb48c, "warm white");
        rejected_color(24'hf0aa1e, "orange");
        rejected_color(24'hdc28d2, "magenta");
        rejected_color(24'he0e0e0, "gray");
        rejected_color(24'h14e014, "green");
        rejected_color(24'h170000, "below red floor");
        scene_frame(24'h998c8d, 3); scene_frame(24'h998c8d, 3);
        if (display.u_bank.color_bbox_valid) $fatal(1, "thin foam bar bypassed aspect filter");
        scene_frame(24'h998c8d, 4); scene_frame(24'h998c8d, 4);
        if (display.u_bank.color_bbox_valid) $fatal(1, "sparse foam hits bypassed MIN_PIX/fill filter");

`ifdef PINK_RECT_DEBUG_TEST
        // SW1 changes during a frame, but the diagnostic view commits only at VS.
        selector_frame(1'b1);
        if (!edit_active || display.u_bank.color_debug_active)
            $fatal(1, "SW1 debug selection changed mid-frame instead of at VS");
        mask_check_en = 1;
        selector_frame(1'b1);
        if (!display.u_bank.color_debug_active || mask_checks < 100)
            $fatal(1, "mask debug view did not commit at VS or emit enough pixels");
        selector_frame(1'b0);
        if (edit_active || !display.u_bank.color_debug_active)
            $fatal(1, "SW1 debug exit changed mid-frame instead of at VS");
        normal_check_en = 1;
        selector_frame(1'b0);
        if (display.u_bank.color_debug_active || !display.u_bank.color_bbox_valid || normal_checks == 0)
            $fatal(1, "normal color box did not resume at next VS");
        normal_check_en = 0;
`endif
        mask_check_en = 0;

        render_mode = 4'd15;
        scene_frame(24'h998c8d, 0); scene_frame(24'h998c8d, 0);
        scene_frame(24'h998c8d, 0);
        if (!display.u_bank.u_track.trk_valid || display.u_bank.u_track.trk_x_min !== 5'd8 ||
            display.u_bank.u_track.trk_x_max !== 5'd23 || display.u_bank.u_track.trk_y_min !== 5'd8 ||
            display.u_bank.u_track.trk_y_max !== 5'd15)
            $fatal(1, "mode15 tracker did not consume the pink bbox");
        render_mode = 4'd13;
        $display("PASS tb_algo10_pink_rect");
        $finish;
    end
endmodule
