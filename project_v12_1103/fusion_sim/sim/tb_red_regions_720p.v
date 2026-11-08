`timescale 1ns/1ps

// Real 1280x720 integration test for run-based region selection and tracking.
module tb_red_regions_720p;
    localparam IMG_W = 1280, IMG_H = 720;
    localparam [23:0] BG = 24'h000000, SENTINEL = 24'h123456;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [23:0] rgb_in = BG;
    reg [3:0] mode = 13;
    reg de_in = 0, hs_in = 0, vs_in = 0;
    wire [23:0] rgb_out;
    wire de_out, hs_out, vs_out;
    reg [23:0] rgb_pipe [0:4];
    reg de_pipe [0:4], hs_pipe [0:4], vs_pipe [0:4];
    integer p, sync_checks = 0, rgb_checks = 0;
    reg watch_box = 0;
    reg [10:0] expected_x0, expected_x1;
    reg [9:0] expected_y0, expected_y1;
    integer frame_number = 0;
    integer x, y;

    // Use all production defaults, including IMG_WIDTH=1280 and IMG_HEIGHT=720.
    algo_bank dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .mode(mode),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .bin_threshold_in(8'd128), .edge_threshold_in(8'd32),
        .bright_gain_in(8'd24), .contrast_gain_in(8'd24),
        .rgb_out(rgb_out), .de_out(de_out), .hs_out(hs_out), .vs_out(vs_out),
        .color_debug_in(1'b0)
    );

    // Mode 13 and 15 both expose a five-clock RGB/sync path. The one sentinel
    // pixel is outside every detection/tracking box and must pass through intact.
    always @(posedge clk) begin
        if (!rst_n) begin
            for (p = 0; p < 5; p = p + 1) begin
                rgb_pipe[p] <= 0; de_pipe[p] <= 0; hs_pipe[p] <= 0; vs_pipe[p] <= 0;
            end
        end else begin
            rgb_pipe[0] <= rgb_in; de_pipe[0] <= de_in;
            hs_pipe[0] <= hs_in; vs_pipe[0] <= vs_in;
            for (p = 1; p < 5; p = p + 1) begin
                rgb_pipe[p] <= rgb_pipe[p-1]; de_pipe[p] <= de_pipe[p-1];
                hs_pipe[p] <= hs_pipe[p-1]; vs_pipe[p] <= vs_pipe[p-1];
            end
            #1;
            if (mode == 13 || mode == 15) begin
                if (de_out !== de_pipe[4] || hs_out !== hs_pipe[4] || vs_out !== vs_pipe[4])
                    $fatal(1, "five-clock RGB/sync mismatch frame=%0d mode=%0d", frame_number, mode);
                sync_checks = sync_checks + 1;
                if (de_pipe[4] && rgb_pipe[4] === SENTINEL) begin
                    if (rgb_out !== SENTINEL)
                        $fatal(1, "non-box RGB was modified frame=%0d mode=%0d got=%h", frame_number, mode, rgb_out);
                    rgb_checks = rgb_checks + 1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && watch_box && de_in) begin
            if (!dut.color_bbox_valid || dut.color_bbox_x_min !== expected_x0 ||
                dut.color_bbox_x_max !== expected_x1 || dut.color_bbox_y_min !== expected_y0 ||
                dut.color_bbox_y_max !== expected_y1)
                $fatal(1, "published bbox changed during DE at x=%0d y=%0d", x, y);
        end
    end

    task idle;
        input integer count;
        integer k;
        begin
            for (k = 0; k < count; k = k + 1) begin
                @(negedge clk); rgb_in = BG; de_in = 0; hs_in = 0; vs_in = 0;
            end
        end
    endtask

    function is_target_pixel;
        input integer xx, yy, scene;
        begin
            case (scene)
                1: is_target_pixel =
                    ((xx >= 1100 && xx <= 1279 && yy >= 610 && yy <= 719) ||
                     (xx >= 100 && xx <= 149 && yy >= 100 && yy <= 119));
                2: is_target_pixel = (xx >= 600 && xx <= 799 && yy >= 300 && yy <= 399);
                default: is_target_pixel = 0;
            endcase
        end
    endfunction

    task send_frame;
        input integer scene;
        integer xx, yy, blank_i;
        begin
            @(negedge clk); rgb_in = BG; de_in = 0; hs_in = 0; vs_in = 1;
            @(negedge clk); vs_in = 0;
            for (yy = 0; yy < IMG_H; yy = yy + 1) begin
                y = yy;
                for (xx = 0; xx < IMG_W; xx = xx + 1) begin
                    x = xx;
                    @(negedge clk);
                    de_in = 1; hs_in = (xx == 0); rgb_in = BG;
                    if (xx == 0 && yy == 0) rgb_in = SENTINEL;
                    if (is_target_pixel(xx, yy, scene)) rgb_in = 24'h998c8d;
                end
                for (blank_i = 0; blank_i < 32; blank_i = blank_i + 1) begin
                    @(negedge clk); rgb_in = BG; de_in = 0; hs_in = 1;
                end
            end
            idle(8);
            frame_number = frame_number + 1;
            $display("frame %0d sent scene=%0d mode=%0d", frame_number, scene, mode);
        end
    endtask

    task expect_region;
        input [10:0] x0, x1;
        input [9:0] y0, y1;
        input integer hits;
        input [8*36-1:0] label;
        begin
            if (!dut.color_bbox_valid || dut.color_bbox_x_min !== x0 || dut.color_bbox_x_max !== x1 ||
                dut.color_bbox_y_min !== y0 || dut.color_bbox_y_max !== y1) begin
                $display("FAIL %0s bbox valid=%0d [%0d,%0d]-[%0d,%0d] expected [%0d,%0d]-[%0d,%0d]",
                    label,dut.color_bbox_valid,dut.color_bbox_x_min,dut.color_bbox_y_min,
                    dut.color_bbox_x_max,dut.color_bbox_y_max,x0,y0,x1,y1);
                $fatal(1,"region bbox mismatch");
            end
            if (hits >= 0 && dut.u_color_detect.hit_cnt !== hits) begin
                $display("FAIL %0s hits=%0d expected=%0d",label,dut.u_color_detect.hit_cnt,hits);
                $fatal(1,"region hit count mismatch");
            end
        end
    endtask

    initial begin
        for (p = 0; p < 5; p = p + 1) begin
            rgb_pipe[p] = 0; de_pipe[p] = 0; hs_pipe[p] = 0; vs_pipe[p] = 0;
        end
        idle(8); rst_n = 1;

        // Two disconnected objects: the larger component includes the final
        // bottom-right active pixel; exact hits prove that pixel was counted.
        send_frame(1); send_frame(1); send_frame(1);
        expect_region(11'd1100,11'd1279,10'd610,10'd719,19800,"largest red component");

        // The target disappears in the current frame. The last published frame
        // box must stay fixed from first through final DE.
        expected_x0=11'd1100; expected_x1=11'd1279;
        expected_y0=10'd610; expected_y1=10'd719; watch_box=1;
        send_frame(0);
        watch_box=0;
        expect_region(11'd1100,11'd1279,10'd610,10'd719,19800,"frame-stable retained component");

        // Two published misses hold the box; the third clears it.
        send_frame(0);
        if (!dut.color_bbox_valid) $fatal(1,"region was not held through the short loss");
        send_frame(0);
        if (!dut.color_bbox_valid) $fatal(1,"region hold expired before two missed frames");
        send_frame(0);
        if (dut.color_bbox_valid) $fatal(1,"region did not expire after the configured hold");

        // A new distant object is selected after expiry; mode 15 must consume
        // its newly published coordinates through the unchanged five-clock path.
        mode=15;
        send_frame(2); send_frame(2); send_frame(2);
        expect_region(11'd600,11'd799,10'd300,10'd399,20000,"reacquired moved component");
        send_frame(2);
        if (!dut.u_track.trk_valid || dut.u_track.trk_x_min !== 11'd600 ||
            dut.u_track.trk_x_max !== 11'd799 || dut.u_track.trk_y_min !== 10'd300 ||
            dut.u_track.trk_y_max !== 10'd399)
            $fatal(1,"mode15 tracker did not consume the new region bbox");

        if (sync_checks < 1000 || rgb_checks < 4)
            $fatal(1,"insufficient output path checks sync=%0d rgb=%0d",sync_checks,rgb_checks);
        $display("PASS tb_red_regions_720p sync_checks=%0d sentinel_rgb_checks=%0d",sync_checks,rgb_checks);
        $finish;
    end

    initial begin
        #200000000; $fatal(1,"timeout waiting for 720p region sequence");
    end
endmodule
