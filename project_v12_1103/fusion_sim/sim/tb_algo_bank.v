`timescale 1ns/1ps

module tb_algo_bank;
    localparam IMG_WIDTH = 4;
    localparam LB_DEPTH = 8;
    localparam LB_AW = 3;
    localparam OUTPUT_LATENCY = 5;
    localparam MAX_SAMPLES = 512;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg [23:0] rgb_in = 24'd0;
    reg [3:0] mode = 4'd0;
    reg de_in = 1'b0, hs_in = 1'b0, vs_in = 1'b0;
    wire [23:0] rgb_out;
    wire de_out, hs_out, vs_out;

    algo_bank #(
        .IMG_WIDTH(IMG_WIDTH), .LB_DEPTH(LB_DEPTH), .LB_AW(LB_AW),
        .BIN_THRESHOLD(8'd128), .EDGE_THRESHOLD(8'd32),
        .OUTPUT_LATENCY(OUTPUT_LATENCY), .VS_ACTIVE_LOW(0)
    ) dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .bin_threshold_in(8'd128), .edge_threshold_in(8'd32), .mode(mode),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_out), .de_out(de_out), .hs_out(hs_out), .vs_out(vs_out)
    );

    reg [23:0] exp_rgb [0:MAX_SAMPLES-1];
    reg exp_de [0:MAX_SAMPLES-1];
    reg exp_hs [0:MAX_SAMPLES-1];
    reg exp_vs [0:MAX_SAMPLES-1];
    integer sample_count = 0;
    integer checks = 0;

    reg [7:0] frame [0:1][0:IMG_WIDTH-1][0:IMG_WIDTH-1];
    integer active_frame = 0;
    integer frame_row = 0;
    integer frame_col = 0;

    function [7:0] gray_of;
        input [23:0] rgb;
        reg [15:0] total;
        begin
            total = 16'd77 * rgb[23:16] + 16'd150 * rgb[15:8] +
                    16'd29 * rgb[7:0] + 16'd128;
            gray_of = total[15:8];
        end
    endfunction

    function [7:0] frame_pixel;
        input integer f, y, x;
        integer cy, cx;
        begin
            cy = (y < 0) ? 0 : ((y >= IMG_WIDTH) ? IMG_WIDTH-1 : y);
            cx = (x < 0) ? 0 : ((x >= IMG_WIDTH) ? IMG_WIDTH-1 : x);
            frame_pixel = frame[f][cy][cx];
        end
    endfunction

    function [23:0] sobel_ref;
        input integer f, y, x;
        integer a,b,c,d,e,g,h,i,j,k,gx,gy,mag,edge8;
        begin
            a=frame_pixel(f,y-2,x-2); b=frame_pixel(f,y-2,x-1); c=frame_pixel(f,y-2,x);
            d=frame_pixel(f,y-1,x-2); e=frame_pixel(f,y-1,x-1); g=frame_pixel(f,y-1,x);
            h=frame_pixel(f,y,x-2);   i=frame_pixel(f,y,x-1);   j=frame_pixel(f,y,x);
            gx = (c + 2*g + j) - (a + 2*d + h);
            gy = (a + 2*b + c) - (h + 2*i + j);
            mag = ((gx < 0) ? -gx : gx) + ((gy < 0) ? -gy : gy);
            edge8 = mag >> 3;
            sobel_ref = (edge8 >= 32) ? 24'hFFFFFF : 24'h000000;
        end
    endfunction

    task tick_sample;
        input [23:0] pixel;
        input [3:0] selected_mode;
        input valid;
        input hsync;
        input vsync;
        input [23:0] expected;
        begin
            @(negedge clk);
            rgb_in = pixel;
            mode = selected_mode;
            de_in = valid;
            hs_in = hsync;
            vs_in = vsync;
            exp_rgb[sample_count] = expected;
            exp_de[sample_count] = valid;
            exp_hs[sample_count] = hsync;
            exp_vs[sample_count] = vsync;
            @(posedge clk); #1;
            if (rst_n && sample_count >= OUTPUT_LATENCY-1) begin
                if (exp_de[sample_count-(OUTPUT_LATENCY-1)] && rgb_out !== exp_rgb[sample_count-(OUTPUT_LATENCY-1)]) begin
                    $display("RGB mismatch sample=%0d mode=%0d got=%06h expected=%06h", sample_count, mode, rgb_out, exp_rgb[sample_count-(OUTPUT_LATENCY-1)]);
                    $fatal(1);
                end
                if ({de_out,hs_out,vs_out} !== {exp_de[sample_count-(OUTPUT_LATENCY-1)],exp_hs[sample_count-(OUTPUT_LATENCY-1)],exp_vs[sample_count-(OUTPUT_LATENCY-1)]}) begin
                    $display("SYNC mismatch sample=%0d got=%b%b%b", sample_count, de_out, hs_out, vs_out);
                    $fatal(1);
                end
                checks = checks + 1;
            end
            sample_count = sample_count + 1;
        end
    endtask

    task blank_cycles;
        input integer count;
        input [3:0] selected_mode;
        integer t;
        begin
            for (t=0; t<count; t=t+1)
                tick_sample(24'h000000, selected_mode, 1'b0, 1'b0, 1'b1, 24'h000000);
        end
    endtask

    task run_frame;
        input integer f;
        input [3:0] selected_mode;
        input integer pattern;
        integer y,x;
        reg [7:0] v, rv, gv, bv;
        reg [23:0] rgb_pixel, expected;
        begin
            active_frame = f;
            // Active-high VS marks vertical blank. It is kept high before each frame
            // so the line buffer must discard prior-frame row history at the next DE.
            blank_cycles(3, selected_mode);
            for (y=0; y<IMG_WIDTH; y=y+1) begin
                for (x=0; x<IMG_WIDTH; x=x+1) begin
                    if (pattern == 0) begin rv=((x==1)?8'hFF:8'h10+y*8); gv=rv; bv=rv; end
                    else if (pattern == 1) begin rv=((x==2)?8'hF0:8'h20+y*7+x); gv=rv; bv=rv; end
                    else if (y==0 && x==0) begin rv=8'hFF;gv=0;bv=0; end
                    else if (y==0 && x==1) begin rv=0;gv=8'hFF;bv=0; end
                    else if (y==0 && x==2) begin rv=0;gv=0;bv=8'hFF; end
                    else if (y==0 && x==3) begin rv=8'hFF;gv=8'hFF;bv=8'hFF; end
                    else if (y==1 && x==0) begin rv=0;gv=0;bv=0; end
                    else begin rv=y*13+x*29; gv=y*7+x*43; bv=y*31+x*11; end
                    rgb_pixel = {rv,gv,bv};
                    v = gray_of(rgb_pixel);
                    frame[f][y][x] = v;
                    case (selected_mode)
                        4'd0: expected = rgb_pixel;
                        4'd1: expected = {v, v, v};
                        4'd2: expected = (v >= 8'd128) ? 24'hFFFFFF : 24'h000000;
                        4'd3: expected = sobel_ref(f,y,x);
                        default: expected = 24'h000000;
                    endcase
                    tick_sample(rgb_pixel, selected_mode, 1'b1, (x==0), 1'b0, expected);
                end
                tick_sample(24'h0, selected_mode, 1'b0, 1'b0, 1'b0, 24'h0);
            end
            blank_cycles(OUTPUT_LATENCY+2, selected_mode);
        end
    endtask

    integer m;
    initial begin
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;
        // Distinct RGB channels and adjacent colors exercise the weighted gray reference.
        run_frame(0, 4'd0, 2);
        run_frame(0, 4'd1, 2);
        run_frame(0, 4'd2, 2);
        run_frame(0, 4'd3, 2);
        // A second, different Sobel frame catches stale rows at frame top/left.
        run_frame(1, 4'd3, 1);
        if (checks < 100) $fatal(1, "too few output checks: %0d", checks);
        $display("PASS tb_algo_bank: %0d output/sync checks", checks);
        $finish;
    end
endmodule


