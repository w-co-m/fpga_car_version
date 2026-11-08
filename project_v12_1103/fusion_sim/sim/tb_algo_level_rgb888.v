`timescale 1ns/1ps
module tb_algo_level_rgb888;
    reg clk = 0, rst_n = 1;
    reg [23:0] rgb_in = 0;
    reg de_in = 0, hs_in = 0, vs_in = 0;
    reg [7:0] thr_in = 0;
    wire [23:0] bright_rgb, bright_rgb_mode1, contrast_rgb, contrast_rgb_mode1;
    wire [7:0] bright_y, bright_y_mode1, contrast_y, contrast_y_mode1;
    wire bright_bin, bright_bin_mode1, contrast_bin, contrast_bin_mode1;
    wire bright_de, bright_hs, bright_vs, bright_de_mode1, bright_hs_mode1, bright_vs_mode1;
    wire contrast_de, contrast_hs, contrast_vs, contrast_de_mode1, contrast_hs_mode1, contrast_vs_mode1;
    reg [35:0] e_b0, e_b1, e_c0, e_c1;
    reg [35:0] q_b0 = 0, q_b_mode1 = 0, q_c0 = 0, q_c_mode1 = 0;
    reg [35:0] q_b0_d = 0, q_b_mode1_d = 0, q_c0_d = 0, q_c_mode1_d = 0;
    reg valid0 = 0, valid1 = 0;
    integer checks = 0;
    integer i;

    always #5 clk = ~clk;

    algo_bright u_bright (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .thr_in(thr_in), .rgb_out(bright_rgb), .y_out(bright_y), .bin_out(bright_bin),
        .de_out(bright_de), .hs_out(bright_hs), .vs_out(bright_vs)
    );
    algo_bright #(.RGB_MODE(1)) u_bright_mode1 (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .thr_in(thr_in), .rgb_out(bright_rgb_mode1), .y_out(bright_y_mode1), .bin_out(bright_bin_mode1),
        .de_out(bright_de_mode1), .hs_out(bright_hs_mode1), .vs_out(bright_vs_mode1)
    );
    algo_contrast u_contrast (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .thr_in(thr_in), .rgb_out(contrast_rgb), .y_out(contrast_y), .bin_out(contrast_bin),
        .de_out(contrast_de), .hs_out(contrast_hs), .vs_out(contrast_vs)
    );
    algo_contrast #(.RGB_MODE(1)) u_contrast_mode1 (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .thr_in(thr_in), .rgb_out(contrast_rgb_mode1), .y_out(contrast_y_mode1), .bin_out(contrast_bin_mode1),
        .de_out(contrast_de_mode1), .hs_out(contrast_hs_mode1), .vs_out(contrast_vs_mode1)
    );

    function [7:0] gray_ref;
        input [23:0] pixel;
        integer sum;
        begin
            sum = pixel[23:16] * 77 + pixel[15:8] * 150 + pixel[7:0] * 29 + 128;
            gray_ref = sum >> 8;
        end
    endfunction

    // {saturated, value}; gain is Q4.4 and center is zero or 128.
    function [8:0] map_ref;
        input [7:0] value, gain;
        input integer center;
        integer mapped, distance;
        begin
            if (value >= center) begin
                distance = value - center;
                mapped = ((distance * gain) >> 4) + center;
            end else begin
                distance = center - value;
                mapped = center - ((distance * gain) >> 4);
            end
            if (mapped < 0 || (value < center && distance * gain / 16 >= center)) map_ref = {1'b1, 8'd0};
            else if (mapped > 255) map_ref = {1'b1, 8'hff};
            else map_ref = {1'b0, mapped[7:0]};
        end
    endfunction

    function [8:0] add_delta_ref;
        input [7:0] channel, old_y, new_y;
        integer value;
        begin
            value = channel + new_y - old_y;
            if (value < 0) add_delta_ref = {1'b1, 8'd0};
            else if (value > 255) add_delta_ref = {1'b1, 8'hff};
            else add_delta_ref = {1'b0, value[7:0]};
        end
    endfunction

    task expected;
        input [23:0] pixel;
        input [7:0] gain;
        input de, hs, vs;
        output [35:0] bright0, bright1, contrast0, contrast1;
        reg [7:0] y, yb, yc;
        reg [8:0] by, cy, r, g, b, r1, g1, b1;
        reg [23:0] rgb_b0, rgb_b1, rgb_c0, rgb_c1;
        reg sat_b0, sat_b1, sat_c0, sat_c1;
        begin
            y = gray_ref(pixel);
            by = map_ref(y, gain, 0);
            cy = map_ref(y, gain, 128);
            yb = by[7:0];
            yc = cy[7:0];
            r = add_delta_ref(pixel[23:16], y, yb);
            g = add_delta_ref(pixel[15:8], y, yb);
            b = add_delta_ref(pixel[7:0], y, yb);
            rgb_b0 = {r[7:0], g[7:0], b[7:0]};
            sat_b0 = by[8] | r[8] | g[8] | b[8];
            r1 = map_ref(pixel[23:16], gain, 0);
            g1 = map_ref(pixel[15:8], gain, 0);
            b1 = map_ref(pixel[7:0], gain, 0);
            rgb_b1 = {r1[7:0], g1[7:0], b1[7:0]};
            sat_b1 = by[8] | r1[8] | g1[8] | b1[8];
            r = add_delta_ref(pixel[23:16], y, yc);
            g = add_delta_ref(pixel[15:8], y, yc);
            b = add_delta_ref(pixel[7:0], y, yc);
            rgb_c0 = {r[7:0], g[7:0], b[7:0]};
            sat_c0 = cy[8] | r[8] | g[8] | b[8];
            r1 = map_ref(pixel[23:16], gain, 128);
            g1 = map_ref(pixel[15:8], gain, 128);
            b1 = map_ref(pixel[7:0], gain, 128);
            rgb_c1 = {r1[7:0], g1[7:0], b1[7:0]};
            sat_c1 = cy[8] | r1[8] | g1[8] | b1[8];
            bright0 = {sat_b0, yb, rgb_b0, de, hs, vs};
            bright1 = {sat_b1, yb, rgb_b1, de, hs, vs};
            contrast0 = {sat_c0, yc, rgb_c0, de, hs, vs};
            contrast1 = {sat_c1, yc, rgb_c1, de, hs, vs};
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (rst_n && valid1) begin
            if ({bright_bin, bright_y, bright_rgb, bright_de, bright_hs, bright_vs} !== q_b0_d)
                $fatal(1, "bright RGB_MODE=0 mismatch expected=%h actual=%h", q_b0_d,
                       {bright_bin, bright_y, bright_rgb, bright_de, bright_hs, bright_vs});
            if ({bright_bin_mode1, bright_y_mode1, bright_rgb_mode1, bright_de_mode1, bright_hs_mode1, bright_vs_mode1} !== q_b_mode1_d)
                $fatal(1, "bright RGB_MODE=1 mismatch expected=%h actual=%h", q_b_mode1_d,
                       {bright_bin_mode1, bright_y_mode1, bright_rgb_mode1, bright_de_mode1, bright_hs_mode1, bright_vs_mode1});
            if ({contrast_bin, contrast_y, contrast_rgb, contrast_de, contrast_hs, contrast_vs} !== q_c0_d)
                $fatal(1, "contrast RGB_MODE=0 mismatch expected=%h actual=%h", q_c0_d,
                       {contrast_bin, contrast_y, contrast_rgb, contrast_de, contrast_hs, contrast_vs});
            if ({contrast_bin_mode1, contrast_y_mode1, contrast_rgb_mode1, contrast_de_mode1, contrast_hs_mode1, contrast_vs_mode1} !== q_c_mode1_d)
                $fatal(1, "contrast RGB_MODE=1 mismatch expected=%h actual=%h", q_c_mode1_d,
                       {contrast_bin_mode1, contrast_y_mode1, contrast_rgb_mode1, contrast_de_mode1, contrast_hs_mode1, contrast_vs_mode1});
            checks = checks + 1;
        end
        if (!rst_n) begin
            q_b0 = 0; q_b_mode1 = 0; q_c0 = 0; q_c_mode1 = 0;
            q_b0_d = 0; q_b_mode1_d = 0; q_c0_d = 0; q_c_mode1_d = 0; valid0 = 0; valid1 = 0;
        end else begin
            q_b0_d = q_b0; q_b_mode1_d = q_b_mode1; q_c0_d = q_c0; q_c_mode1_d = q_c_mode1;
            q_b0 = e_b0; q_b_mode1 = e_b1; q_c0 = e_c0; q_c_mode1 = e_c1;
            valid1 = valid0;
            expected(rgb_in, thr_in, de_in, hs_in, vs_in, e_b0, e_b1, e_c0, e_c1);
            q_b0 = e_b0; q_b_mode1 = e_b1; q_c0 = e_c0; q_c_mode1 = e_c1; valid0 = 1;
        end
    end

    initial begin
        #1 rst_n = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        // Include unity, >1, fractional and zero gains, mixed RGB values, and dynamic gain changes.
        for (i = 0; i < 40; i = i + 1) begin
            @(negedge clk);
            case (i % 4)
                0: thr_in = 8'd16;
                1: thr_in = 8'd32;
                2: thr_in = 8'd24;
                3: thr_in = 8'd0;
            endcase
            case (i % 10)
                0: rgb_in = 24'h000000;
                1: rgb_in = 24'hffffff;
                2: rgb_in = 24'h4080c0;
                3: rgb_in = 24'h7f80ff;
                4: rgb_in = 24'h01e07f;
                5: rgb_in = 24'h2080df;
                6: rgb_in = 24'hff0001;
                7: rgb_in = 24'h10f080;
                8: rgb_in = 24'h809040;
                9: rgb_in = 24'h010203;
            endcase
            de_in = i[0]; hs_in = i[1]; vs_in = i[2];
        end
        @(negedge clk);
        de_in = 0; hs_in = 0; vs_in = 0; rgb_in = 0; thr_in = 0;
        repeat (4) @(negedge clk);
        if (checks != 43) $fatal(1, "expected 40 test pixels plus 3 pipeline drain pixels, got %0d", checks);
        $display("tb_algo_level_rgb888 PASS: %0d checked pixels (40 test + 3 drain), RGB_MODE 0/1", checks);
        $finish;
    end
endmodule
