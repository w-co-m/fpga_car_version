`timescale 1ns/1ps

module tb_algo10_features;
    localparam integer W=20, H=14, HIT_W=9;
    reg clk=0, rst_n=0, enable_in=1;
    reg [23:0] rgb_in=0;
    reg de_in=0, hs_in=0, vs_in=0, vs_low_in=1;
    reg [7:0] thr_in=0;
    always #5 clk=~clk;

    wire [23:0] rgb_main;
    wire [7:0] y_main;
    wire bin_main, de_main, hs_main, vs_main;
    wire [4:0] xmin, xmax;
    wire [3:0] ymin, ymax;
    wire bbox_valid, bbox_valid_raw, shape_ok;
    wire [HIT_W-1:0] hit_cnt;
    wire [1:0] shape_type;
    wire [7:0] fill_ratio_q8, aspect_ratio_q44;
    wire valid_circle, valid_unfiltered;
    wire strict_fill_valid;
    wire [7:0] strict_fill_band;
    wire low_valid, low_raw;
    wire [HIT_W-1:0] low_hits;
    wire [4:0] low_xmin,low_xmax;
    wire [3:0] low_ymin,low_ymax;
    wire bin_g, bin_b, bin_rule0, bin_abs;

    algo_color_detect #(
        .IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_COLOR(0),.DET_RULE(2),.S_DEF(8'd96),
        .MIN_PIX(16),.R_SAT_MIN(8'd192),.SHAPE_FILTER_EN(1),.TARGET_SHAPE(0),
        .ASPECT_MIN_Q44(5'd12),.ASPECT_MAX_Q44(5'd20),
        .FILL_MIN_Q8(9'd180),.FILL_MAX_Q8(9'd260),
        .SHAPE_TOL_Q8(8'd28),.SHAPE_FILL_EN(1)
    ) main_dut (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
        .rgb_out(rgb_main),.y_out(y_main),.bin_out(bin_main),
        .de_out(de_main),.hs_out(hs_main),.vs_out(vs_main),
        .bbox_x_min(xmin),.bbox_x_max(xmax),.bbox_y_min(ymin),.bbox_y_max(ymax),
        .bbox_valid(bbox_valid),.hit_cnt(hit_cnt),
        .bbox_valid_raw(bbox_valid_raw),.shape_ok(shape_ok),.shape_type(shape_type),
        .fill_ratio_q8(fill_ratio_q8),.aspect_ratio_q44(aspect_ratio_q44)
    );

    algo_color_detect #(
        .IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_COLOR(0),.DET_RULE(2),.S_DEF(8'd96),
        .MIN_PIX(16),.R_SAT_MIN(8'd192),.SHAPE_FILTER_EN(1),.TARGET_SHAPE(2),
        .ASPECT_MIN_Q44(5'd12),.ASPECT_MAX_Q44(5'd20),
        .FILL_MIN_Q8(9'd180),.FILL_MAX_Q8(9'd260),
        .SHAPE_TOL_Q8(8'd28),.SHAPE_FILL_EN(1)
    ) circle_target_dut (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
        .rgb_out(),.y_out(),.bin_out(),.de_out(),.hs_out(),.vs_out(),
        .bbox_x_min(),.bbox_x_max(),.bbox_y_min(),.bbox_y_max(),
        .bbox_valid(valid_circle),.hit_cnt(),.bbox_valid_raw(),.shape_ok(),
        .shape_type(),.fill_ratio_q8(),.aspect_ratio_q44()
    );

    algo_color_detect #(
        .IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_COLOR(0),.DET_RULE(2),.S_DEF(8'd96),
        .MIN_PIX(16),.R_SAT_MIN(8'd192),.SHAPE_FILTER_EN(1),.TARGET_SHAPE(0),
        .ASPECT_MIN_Q44(5'd12),.ASPECT_MAX_Q44(5'd20),
        .FILL_MIN_Q8(9'd180),.FILL_MAX_Q8(9'd260),
        .SHAPE_TOL_Q8(8'd28),.SHAPE_FILL_EN(1),.VS_ACTIVE_LOW(1)
    ) low_polarity_dut (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_low_in),.thr_in(thr_in),
        .rgb_out(),.y_out(),.bin_out(),.de_out(),.hs_out(),.vs_out(),
        .bbox_x_min(low_xmin),.bbox_x_max(low_xmax),.bbox_y_min(low_ymin),.bbox_y_max(low_ymax),
        .bbox_valid(low_valid),.hit_cnt(low_hits),.bbox_valid_raw(low_raw),.shape_ok(),
        .shape_type(),.fill_ratio_q8(),.aspect_ratio_q44()
    );

    // A stricter test-only ceiling makes the otherwise unreachable >260/256
    // fill band observable while keeping the production default instance intact.
    algo_color_detect #(
        .IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_COLOR(0),.DET_RULE(2),.S_DEF(8'd96),
        .MIN_PIX(16),.R_SAT_MIN(8'd192),.SHAPE_FILTER_EN(1),.TARGET_SHAPE(0),
        .ASPECT_MIN_Q44(5'd12),.ASPECT_MAX_Q44(5'd20),
        .FILL_MIN_Q8(9'd180),.FILL_MAX_Q8(9'd240),
        .SHAPE_TOL_Q8(8'd28),.SHAPE_FILL_EN(1)
    ) strict_fill_dut (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
        .rgb_out(),.y_out(),.bin_out(),.de_out(),.hs_out(),.vs_out(),
        .bbox_x_min(),.bbox_x_max(),.bbox_y_min(),.bbox_y_max(),.bbox_valid(strict_fill_valid),
        .hit_cnt(),.bbox_valid_raw(),.shape_ok(),.shape_type(),
        .fill_ratio_q8(strict_fill_band),.aspect_ratio_q44()
    );

    algo_color_detect #(
        .IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_COLOR(0),.DET_RULE(2),.S_DEF(8'd96),
        .MIN_PIX(16),.R_SAT_MIN(8'd192),.SHAPE_FILTER_EN(0)
    ) no_filter_dut (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
        .rgb_out(),.y_out(),.bin_out(),.de_out(),.hs_out(),.vs_out(),
        .bbox_x_min(),.bbox_x_max(),.bbox_y_min(),.bbox_y_max(),
        .bbox_valid(valid_unfiltered),.hit_cnt(),.bbox_valid_raw(),.shape_ok(),
        .shape_type(),.fill_ratio_q8(),.aspect_ratio_q44()
    );

    // Legacy rules are independent compatibility probes on the same samples.
    algo_color_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.DET_RULE(0),.S_DEF(8'd32),.MIN_PIX(1)) legacy_rule0 (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
        .rgb_out(),.y_out(),.bin_out(bin_rule0),.de_out(),.hs_out(),.vs_out(),
        .bbox_x_min(),.bbox_x_max(),.bbox_y_min(),.bbox_y_max(),.bbox_valid(),.hit_cnt(),
        .bbox_valid_raw(),.shape_ok(),.shape_type(),.fill_ratio_q8(),.aspect_ratio_q44()
    );
    algo_color_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.DET_RULE(1),.MIN_PIX(1)) legacy_abs (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
        .rgb_out(),.y_out(),.bin_out(bin_abs),.de_out(),.hs_out(),.vs_out(),
        .bbox_x_min(),.bbox_x_max(),.bbox_y_min(),.bbox_y_max(),.bbox_valid(),.hit_cnt(),
        .bbox_valid_raw(),.shape_ok(),.shape_type(),.fill_ratio_q8(),.aspect_ratio_q44()
    );
    algo_color_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_COLOR(1),.DET_RULE(2),.S_DEF(8'd96),.MIN_PIX(1),.R_SAT_MIN(8'd192)) rule2_green (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
        .rgb_out(),.y_out(),.bin_out(bin_g),.de_out(),.hs_out(),.vs_out(),
        .bbox_x_min(),.bbox_x_max(),.bbox_y_min(),.bbox_y_max(),.bbox_valid(),.hit_cnt(),
        .bbox_valid_raw(),.shape_ok(),.shape_type(),.fill_ratio_q8(),.aspect_ratio_q44()
    );
    algo_color_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TARGET_COLOR(2),.DET_RULE(2),.S_DEF(8'd96),.MIN_PIX(1),.R_SAT_MIN(8'd192)) rule2_blue (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
        .rgb_out(),.y_out(),.bin_out(bin_b),.de_out(),.hs_out(),.vs_out(),
        .bbox_x_min(),.bbox_x_max(),.bbox_y_min(),.bbox_y_max(),.bbox_valid(),.hit_cnt(),
        .bbox_valid_raw(),.shape_ok(),.shape_type(),.fill_ratio_q8(),.aspect_ratio_q44()
    );

    reg qde[0:8191], qhs[0:8191], qvs[0:8191];
    reg qmain[0:8191], qg[0:8191], qb[0:8191], q0[0:8191], qabs[0:8191];
    integer n=0, errors=0, k;

    function rule2_red;
        input [23:0] p;
        input [7:0] t;
        reg [7:0] r,g,b,th;
        begin
            r=p[23:16]; g=p[15:8]; b=p[7:0]; th=(t==0)?8'd96:t;
            rule2_red=(r>=8'd192) && (r>=g) && (r-g>=th);
        end
    endfunction
    function rule2_green_expected;
        input [23:0] p;
        input [7:0] t;
        reg [7:0] r,g,b,th;
        begin
            r=p[23:16]; g=p[15:8]; b=p[7:0]; th=(t==0)?8'd96:t;
            rule2_green_expected=(g>=8'd192) && (g>=r) && (g-r>=th);
        end
    endfunction
    function rule2_blue_expected;
        input [23:0] p;
        input [7:0] t;
        reg [7:0] r,g,b,th;
        begin
            r=p[23:16]; g=p[15:8]; b=p[7:0]; th=(t==0)?8'd96:t;
            rule2_blue_expected=(b>=8'd192) && (b>=r) && (b-r>=th);
        end
    endfunction
    function rule0_expected;
        input [23:0] p;
        input [7:0] t;
        reg [7:0] r,g,b,th;
        begin
            r=p[23:16]; g=p[15:8]; b=p[7:0]; th=(t==0)?8'd32:t;
            rule0_expected=(r>=g) && (r-g>=th) && (r>=b) && (r-b>=th);
        end
    endfunction
    function abs_expected;
        input [23:0] p;
        reg [7:0] r,g,b;
        begin
            r=p[23:16]; g=p[15:8]; b=p[7:0];
            abs_expected=(r>=128 && r<=255 && g<=64 && b<=128);
        end
    endfunction

    task drive;
        input [23:0] p;
        input d,h,v,en;
        input [7:0] t;
        begin
            @(negedge clk);
            rgb_in=p; de_in=d; hs_in=h; vs_in=v; vs_low_in=~v; enable_in=en; thr_in=t;
            qde[n]=d; qhs[n]=h; qvs[n]=v;
            qmain[n]=rule2_red(p,t); qg[n]=rule2_green_expected(p,t);
            qb[n]=rule2_blue_expected(p,t); q0[n]=rule0_expected(p,t); qabs[n]=abs_expected(p);
            @(posedge clk); #1;
            if (n>=2) begin
                k=n-2;
                if (bin_main !== qmain[k] || bin_g !== qg[k] || bin_b !== qb[k] ||
                    bin_rule0 !== q0[k] || bin_abs !== qabs[k]) begin
                    $display("FAIL pixel[%0d] masks got %b%b%b%b%b exp %b%b%b%b%b",
                        k,bin_main,bin_g,bin_b,bin_rule0,bin_abs,
                        qmain[k],qg[k],qb[k],q0[k],qabs[k]); errors=errors+1;
                end
                if (y_main !== (qmain[k]?8'hff:8'h00) || de_main !== qde[k] ||
                    hs_main !== qhs[k] || vs_main !== qvs[k]) begin
                    $display("FAIL 3-stage mask/sync alignment sample=%0d",k); errors=errors+1;
                end
            end
            n=n+1;
        end
    endtask

    task idle;
        input v,h,en;
        begin drive(24'h000000,0,h,v,en,0); end
    endtask

    task publish_previous;
        begin
            // One VS edge, followed by a multi-cycle active level and blank clocks.
            idle(1,0,enable_in); idle(1,0,enable_in); idle(1,0,enable_in);
            idle(0,0,enable_in); idle(0,0,enable_in);
        end
    endtask

    task row_blank;
        begin
            idle(0,1,enable_in); idle(0,1,enable_in);
        end
    endtask

    task draw_solid_rect;
        input integer x0,y0,rw,rh;
        integer x,y;
        begin
            for (y=0;y<H;y=y+1) begin
                for (x=0;x<W;x=x+1)
                    drive((x>=x0 && x<x0+rw && y>=y0 && y<y0+rh)?24'hFF0000:24'h000000,1,0,0,enable_in,0);
                if (y<H-1) row_blank();
            end
        end
    endtask

    task draw_circle37;
        integer x,y,w,x0;
        begin
            for (y=0;y<H;y=y+1) begin
                case (y-2)
                    0,6: w=3;
                    1,5: w=5;
                    default: w=7;
                endcase
                x0=7-(w/2);
                for (x=0;x<W;x=x+1)
                    drive((y>=2 && y<=8 && x>=x0 && x<x0+w)?24'hFF0000:24'h000000,1,0,0,enable_in,0);
                if (y<H-1) row_blank();
            end
        end
    endtask

    task draw_sparse16;
        integer x,y;
        reg hit;
        begin
            for (y=0;y<9;y=y+1) begin
                for (x=0;x<W;x=x+1) begin
                    hit=((y==1 || y==7) && (x==1 || x==7)) ||
                        ((y>=2 && y<=5) && (x>=2 && x<=4));
                    drive(hit?24'hFF0000:24'h000000,1,0,0,enable_in,0);
                end
                if (y<8) row_blank();
            end
        end
    endtask

    task draw_triangle21;
        integer x,y;
        begin
            for (y=0;y<6;y=y+1) begin
                for (x=0;x<W;x=x+1)
                    drive((x>=2 && x<3+y)?24'hFF0000:24'h000000,1,0,0,enable_in,0);
                if (y<5) row_blank();
            end
        end
    endtask

    task check_shape;
        input raw,valid;
        input [1:0] typ,fillband,aspectband;
        input [4:0] ex0,ex1;
        input [3:0] ey0,ey1;
        input [HIT_W-1:0] hits;
        input integer circle_expected,unfiltered_expected;
        begin
            if (bbox_valid_raw!==raw || bbox_valid!==valid || shape_ok!==valid ||
                shape_type!==typ || fill_ratio_q8!==fillband || aspect_ratio_q44!==aspectband ||
                hit_cnt!==hits || valid_circle!==circle_expected || valid_unfiltered!==unfiltered_expected ||
                low_valid!==valid || low_raw!==raw || low_hits!==hits ||
                (raw && (xmin!==ex0 || xmax!==ex1 || ymin!==ey0 || ymax!==ey1 ||
                         low_xmin!==ex0 || low_xmax!==ex1 || low_ymin!==ey0 || low_ymax!==ey1))) begin
                $display("FAIL shape raw/valid/type/fill/aspect/hits got %b/%b/%0d/%0d/%0d/%0d expected %b/%b/%0d/%0d/%0d/%0d",
                    bbox_valid_raw,bbox_valid,shape_type,fill_ratio_q8,aspect_ratio_q44,hit_cnt,
                    raw,valid,typ,fillband,aspectband,hits);
                $display("     bbox got (%0d,%0d)-(%0d,%0d), expected (%0d,%0d)-(%0d,%0d), targetCircle=%b noFilter=%b",
                    xmin,ymin,xmax,ymax,ex0,ey0,ex1,ey1,valid_circle,valid_unfiltered);
                if (low_raw!==raw || low_valid!==valid || low_hits!==hits ||
                    low_xmin!==xmin || low_xmax!==xmax || low_ymin!==ymin || low_ymax!==ymax)
                    $display("     active-low VS mismatch raw/valid/hits=%b/%b/%0d bbox=(%0d,%0d)-(%0d,%0d)",
                        low_raw,low_valid,low_hits,low_xmin,low_ymin,low_xmax,low_ymax);
                errors=errors+1;
            end
        end
    endtask

    task check_cleared;
        input [8*24-1:0] reason;
        begin
            if (bbox_valid!==0 || bbox_valid_raw!==0 || shape_ok!==0 || shape_type!==0 ||
                fill_ratio_q8!==0 || aspect_ratio_q44!==0 || hit_cnt!==0 ||
                xmin!==0 || xmax!==0 || ymin!==0 || ymax!==0 ||
                strict_fill_valid!==0 || strict_fill_band!==0) begin
                $display("FAIL %0s did not clear outputs: valid/raw/shape/type/bands/hits=%b/%b/%b/%0d/%0d/%0d/%0d bbox=(%0d,%0d)-(%0d,%0d)",
                    reason,bbox_valid,bbox_valid_raw,shape_ok,shape_type,
                    fill_ratio_q8,aspect_ratio_q44,hit_cnt,xmin,ymin,xmax,ymax);
                errors=errors+1;
            end
        end
    endtask

    task check_strict_fill;
        input [1:0] band;
        input valid;
        begin
            if (strict_fill_band!==band || strict_fill_valid!==valid) begin
                $display("FAIL strict-fill band/valid got %0d/%b expected %0d/%b",strict_fill_band,strict_fill_valid,band,valid);
                errors=errors+1;
            end
        end
    endtask

    integer x,y;
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;

        // Full RGB888 thresholds, warm-light rejection, and old rule compatibility.
        drive(24'hFFC882,0,0,0,1,0); // warm white: rule2 rejects, rule0 still accepts
        drive(24'hB40000,0,0,0,1,0); // saturated dark red: rejected by 192 floor
        drive(24'hFF9F00,0,0,0,1,96); // R-G = 96, inclusive threshold
        drive(24'hFFA000,0,0,0,1,96); // R-G = 95
        drive(24'hFF9E00,0,0,0,1,96); // R-G = 97
        drive(24'hBF0000,0,0,0,1,96); // R saturation = 191
        drive(24'hC00000,0,0,0,1,96); // R saturation = 192
        drive(24'h00F000,0,0,0,1,96); // green rule2 target
        drive(24'h0000F0,0,0,0,1,96); // blue rule2 target
        drive(24'h000000,0,0,0,1,0);
        drive(24'h000000,0,0,0,1,0);
        drive(24'h000000,0,0,0,1,0);

        // Reinitialize coordinates/statistics after non-DE mask vectors.
        rst_n=0; repeat(3) @(negedge clk); #1; check_cleared("reset"); rst_n=1; n=0;
        publish_previous();
        check_shape(0,0,0,0,0,0,0,0,0,0,0,0);

        // 6x5 solid rectangle; last pixel is followed immediately by VS.
        draw_solid_rect(2,2,6,5);
        publish_previous();
        check_shape(1,1,1,1,1,2,7,2,6,30,0,1);
        check_strict_fill(2,0);

        // Exact MIN_PIX count and bottom-right terminal hit followed immediately by VS.
        draw_solid_rect(16,10,4,4);
        publish_previous();
        check_shape(1,1,1,1,1,16,19,10,13,16,0,1);
        check_strict_fill(2,0);

        // Independent 37/49 circular raster: target type 2 passes only TARGET_SHAPE=2.
        draw_circle37();
        publish_previous();
        check_shape(1,1,2,1,1,4,10,2,8,37,1,1);
        check_strict_fill(1,1);

        // Raw rectangle survives with filtering disabled, but aspect band 2 rejects default filter.
        draw_solid_rect(1,3,16,2);
        publish_previous();
        check_shape(1,0,1,1,2,1,16,3,4,32,0,1);
        check_strict_fill(2,0);

        // Width/height below the lower aspect bound produces discrete band 0.
        draw_solid_rect(1,0,2,H);
        publish_previous();
        check_shape(1,0,1,1,0,1,2,0,13,28,0,1);
        check_strict_fill(2,0);

        // Sixteen sparse hits occupy a 7x7 box: raw survives, low-fill band 0 rejects.
        draw_sparse16();
        publish_previous();
        check_shape(1,0,0,0,1,1,7,1,7,16,0,1);
        check_strict_fill(0,0);

        // Triangle occupancy 21/36 classifies as type 3 but falls below fill band.
        draw_triangle21();
        publish_previous();
        check_shape(1,0,3,0,1,2,7,0,5,21,0,1);
        check_strict_fill(0,0);

        // MIN_PIX boundary, empty target disappearance, and deterministic disable clear.
        for (y=0;y<4;y=y+1) begin
            for (x=0;x<W;x=x+1)
                drive((x<4 && !(y==3 && x==3))?24'hFF0000:24'h000000,1,0,0,enable_in,0);
            if (y<3) row_blank();
        end
        publish_previous();
        if (bbox_valid_raw!==0 || bbox_valid!==0 || hit_cnt!==15) begin
            $display("FAIL MIN_PIX=16 raw/valid/hits got %b/%b/%0d",bbox_valid_raw,bbox_valid,hit_cnt); errors=errors+1;
        end
        draw_solid_rect(0,0,0,0);
        publish_previous();
        if (bbox_valid_raw!==0 || bbox_valid!==0 || hit_cnt!==0) begin
            $display("FAIL empty-frame clear raw/valid/hits got %b/%b/%0d",bbox_valid_raw,bbox_valid,hit_cnt); errors=errors+1;
        end

        // Disable from a valid frame, then re-enable and reset from another valid frame.
        draw_solid_rect(2,2,6,5);
        publish_previous();
        check_shape(1,1,1,1,1,2,7,2,6,30,0,1);
        check_strict_fill(2,0);
        drive(24'h000000,0,0,0,0,0);
        drive(24'h000000,0,0,0,0,0);
        drive(24'h000000,0,0,0,0,0);
        check_cleared("disable from valid");
        enable_in=1;
        draw_solid_rect(2,2,6,5);
        publish_previous();
        check_shape(1,1,1,1,1,2,7,2,6,30,0,1);
        check_strict_fill(2,0);
        rst_n=0; repeat(3) @(negedge clk); #1; check_cleared("reset from valid");

        if (errors==0) $display("PASS tb_algo10_features pixels=RGB888 thresholds+legacy rules; shapes=rect/circle/bar/sparse/triangle; frame-lag/VS/disable");
        else $fatal(1,"FAIL tb_algo10_features errors=%0d",errors);
        $finish;
    end
endmodule
