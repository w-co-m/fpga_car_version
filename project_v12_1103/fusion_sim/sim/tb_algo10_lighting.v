`timescale 1ns/1ps

// Integration regression for dim red markers through the production algo_bank.
module tb_algo10_lighting;
    localparam W = 32;
    localparam H = 24;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg [23:0] rgb_in = 0;
    reg [3:0] mode = 13;
    reg de_in = 0, hs_in = 0, vs_in = 0;
    wire [23:0] rgb_out;
    wire de_out, hs_out, vs_out;
    integer errors = 0;
    integer frame_no = 0;
    integer p;
    reg [23:0] rgb_pipe [0:4];
    reg de_pipe [0:4], hs_pipe [0:4], vs_pipe [0:4];
    integer i;

    algo_bank #(.IMG_WIDTH(W), .IMG_HEIGHT(H), .LB_DEPTH(W), .LB_AW(5),
                .COLOR_MIN_PIX(16), .MOTION_MIN_PIX(1000),
                .COLOR_DET_RULE(4),.COLOR_RED_MIN(8'd64),.COLOR_RED_RATIO_Q4(5'd24),
                .COLOR_ASPECT_MIN_Q44(8'd12),.COLOR_ASPECT_MAX_Q44(8'd20),
                .COLOR_FILL_MIN_Q8(9'd180)) dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .mode(mode),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .bin_threshold_in(8'd128), .edge_threshold_in(8'd32),
        .bright_gain_in(8'd24), .contrast_gain_in(8'd24),.color_debug_in(1'b0),
        .rgb_out(rgb_out), .de_out(de_out), .hs_out(hs_out), .vs_out(vs_out)
    );

    // Verify the mode-13 RGB and sync stream shares the documented five-cycle delay.
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 5; i = i + 1) begin
                rgb_pipe[i] <= 0; de_pipe[i] <= 0;
                hs_pipe[i] <= 0; vs_pipe[i] <= 0;
            end
        end else if (mode == 13 || mode == 15) begin
            rgb_pipe[0] <= rgb_in; de_pipe[0] <= de_in;
            hs_pipe[0] <= hs_in; vs_pipe[0] <= vs_in;
            for (i = 1; i < 5; i = i + 1) begin
                rgb_pipe[i] <= rgb_pipe[i-1]; de_pipe[i] <= de_pipe[i-1];
                hs_pipe[i] <= hs_pipe[i-1]; vs_pipe[i] <= vs_pipe[i-1];
            end
            #1;
            if (de_out !== de_pipe[4] || hs_out !== hs_pipe[4] || vs_out !== vs_pipe[4]) begin
                $display("FAIL: mode13 sync is not aligned to five-cycle RGB path");
                errors = errors + 1;
            end
            // Mode 13 is a color box overlay; outside its green box the input
            // pixel must be preserved. Mode 15 is checked for sync ordering.
            if (mode == 13 && de_pipe[4] && rgb_out !== rgb_pipe[4] && rgb_out !== 24'h00ff00) begin
                $display("FAIL: unexpected mode13 RGB/sync alignment rgb=%h expected=%h", rgb_out, rgb_pipe[4]);
                errors = errors + 1;
            end
        end
    end

    task tick_idle;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk); de_in = 0; hs_in = 0; vs_in = 0; rgb_in = 0;
            end
        end
    endtask

    task send_frame;
        input [23:0] marker;
        input integer shape; // 0: 8x8 square; 1: filled radius-4 disk
        integer x, y, dx, dy;
        begin
            @(negedge clk); vs_in = 1; de_in = 0; hs_in = 0; rgb_in = 0;
            @(negedge clk); vs_in = 0;
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 1) begin
                    @(negedge clk);
                    de_in = 1;
                    hs_in = (x == 0);
                    rgb_in = 0;
                    if (x >= 4 && x <= 11 && y >= 4 && y <= 11) begin
                        dx = x - 7; dy = y - 7;
                        if (shape == 0 || (shape == 1 && dx*dx + dy*dy <= 16)) rgb_in = marker;
                        if (shape == 2 && x >= 7 && x <= 8) rgb_in = marker;
                        if (shape == 3 && ((x == 4 || x == 7 || x == 11) &&
                                           (y == 4 || y == 7 || y == 11))) rgb_in = marker;
                    end
                end
                @(negedge clk); de_in = 0; hs_in = 0; rgb_in = 0;
            end
            tick_idle(8);
            frame_no = frame_no + 1;
        end
    endtask

    task expect_bbox;
        input [8*40-1:0] label;
        begin
            if (!dut.color_bbox_valid) begin
                $display("FAIL: %0s expected a valid published bbox (frame %0d)", label, frame_no);
                errors = errors + 1;
            end else if (dut.color_bbox_x_min !== 5'd4 || dut.color_bbox_x_max !== 5'd11 ||
                         dut.color_bbox_y_min !== 5'd4 || dut.color_bbox_y_max !== 5'd11) begin
                $display("FAIL: %0s bbox was [%0d,%0d]-[%0d,%0d], expected [4,4]-[11,11]",
                         label, dut.color_bbox_x_min, dut.color_bbox_y_min,
                         dut.color_bbox_x_max, dut.color_bbox_y_max);
                errors = errors + 1;
            end
        end
    endtask

    task verify_marker;
        input [23:0] marker;
        input integer shape;
        input [8*40-1:0] label;
        begin
            // Frame statistics publish at the following VS edge. A repeated
            // frame makes the just-completed marker observable at this point.
            send_frame(marker, shape);
            send_frame(marker, shape);
            expect_bbox(label);
        end
    endtask

    task verify_rejected;
        input [23:0] marker;
        input [8*40-1:0] label;
        begin
            send_frame(marker, 0);
            send_frame(marker, 0);
            if (dut.color_bbox_valid) begin
                $display("FAIL: %0s unexpectedly published a bbox", label);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        for (p = 0; p < 5; p = p + 1) begin
            rgb_pipe[p] = 0; de_pipe[p] = 0; hs_pipe[p] = 0; vs_pipe[p] = 0;
        end
        tick_idle(4); rst_n = 1;
        verify_marker(24'hf0280a, 0, "bright square");
        verify_marker(24'hb42d1e, 0, "180/45/30 square");
        verify_marker(24'h781e14, 0, "120/30/20 square");
        verify_marker(24'h40100b, 0, "64/16/11 square");
        verify_marker(24'h400000, 0, "R=64 with G=B=0 floor positive");
        verify_marker(24'h783228, 0, "120/50/40 square");
        verify_marker(24'h643237, 0, "100/50/55 square");
        verify_marker(24'h603f3f, 0, "96/63/63 below ratio boundary");
        verify_marker(24'h604040, 0, "96/64/64 exact ratio boundary");
        verify_rejected(24'h60413f, "G=65 beyond ratio boundary");
        verify_rejected(24'h604041, "R=96 G=64 B=65 beyond B ratio boundary");
        verify_rejected(24'h60413f, "R=96 G=65 beyond G ratio boundary");
        verify_marker(24'hffaaaa, 0, "255 channel overflow boundary");
        verify_rejected(24'hffabaa, "255 R with G=171 outside ratio");
        verify_rejected(24'h3f0000, "R below 64 floor");
        verify_rejected(24'hdcb48c, "warm white");
        verify_rejected(24'he0e0e0, "neutral gray");
        verify_rejected(24'hf0aa1e, "orange");
        verify_rejected(24'hdc28d2, "magenta");
        verify_rejected(24'h1414e0, "blue");
        verify_rejected(24'h14e014, "green");
        send_frame(24'h781e14, 2);
        send_frame(24'h781e14, 2);
        if (dut.color_bbox_valid) begin
            $display("FAIL: thin bar passed square/circle shape filter");
            errors = errors + 1;
        end
        send_frame(24'h781e14, 3);
        send_frame(24'h781e14, 3);
        if (dut.color_bbox_valid) begin
            $display("FAIL: sparse points passed fill shape filter");
            errors = errors + 1;
        end
        mode = 15;
        send_frame(24'h781e14, 0);
        send_frame(24'h781e14, 0);
        send_frame(24'h781e14, 0);
        send_frame(24'h781e14, 0);
        if (!dut.u_track.trk_valid || dut.u_track.trk_x_min !== 5'd4 ||
            dut.u_track.trk_x_max !== 5'd11 || dut.u_track.trk_y_min !== 5'd4 ||
            dut.u_track.trk_y_max !== 5'd11) begin
            $display("FAIL: mode15 tracker did not consume the dark-red bbox [4,4]-[11,11]");
            errors = errors + 1;
        end
        mode = 13;
        send_frame(24'h781e14, 1);
        send_frame(24'h781e14, 1);
        if (dut.u_color_detect.shape_type !== 2'd2 || !dut.u_color_detect.shape_ok) begin
            $display("FAIL: dim circular marker did not retain circle shape classification");
            errors = errors + 1;
        end
        if (errors != 0) $fatal(1, "FAIL tb_algo10_lighting errors=%0d", errors);
        $display("PASS tb_algo10_lighting");
        $finish;
    end
endmodule
