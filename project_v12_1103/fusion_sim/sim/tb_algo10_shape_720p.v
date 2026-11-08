`timescale 1ns/1ps

module tb_algo10_shape_720p;
    localparam integer W=1280, H=720, HIT_W=20;
    reg clk=0, rst_n=0, enable_in=1;
    reg [23:0] rgb_in=0;
    reg de_in=0, hs_in=0, vs_in=0;
    reg [7:0] thr_in=0;
    always #5 clk=~clk;

    wire [23:0] rgb_out;
    wire [7:0] y_out;
    wire bin_out, de_out, hs_out, vs_out;
    wire [10:0] bbox_x_min,bbox_x_max;
    wire [9:0] bbox_y_min,bbox_y_max;
    wire bbox_valid,bbox_valid_raw,shape_ok;
    wire [HIT_W-1:0] hit_cnt;
    wire [1:0] shape_type;
    wire [7:0] fill_ratio_q8,aspect_ratio_q44;

    algo_color_detect #(
        .IMG_WIDTH(W),.IMG_HEIGHT(H),.DET_RULE(2),.S_DEF(8'd96),.MIN_PIX(16),
        .R_SAT_MIN(8'd192),.BOX_W(2),.BOX_FILL(0),.BOX_COLOR(24'h00ff00),
        .SHAPE_FILTER_EN(1),.TARGET_SHAPE(0),
        .ASPECT_MIN_Q44(5'd12),.ASPECT_MAX_Q44(5'd20),
        .FILL_MIN_Q8(9'd180),.FILL_MAX_Q8(9'd260),
        .SHAPE_TOL_Q8(8'd28),.SHAPE_FILL_EN(1)
    ) dut (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.thr_in(thr_in),
        .rgb_out(rgb_out),.y_out(y_out),.bin_out(bin_out),
        .de_out(de_out),.hs_out(hs_out),.vs_out(vs_out),
        .bbox_x_min(bbox_x_min),.bbox_x_max(bbox_x_max),
        .bbox_y_min(bbox_y_min),.bbox_y_max(bbox_y_max),
        .bbox_valid(bbox_valid),.hit_cnt(hit_cnt),.bbox_valid_raw(bbox_valid_raw),
        .shape_ok(shape_ok),.shape_type(shape_type),
        .fill_ratio_q8(fill_ratio_q8),.aspect_ratio_q44(aspect_ratio_q44)
    );

    reg [23:0] exp_rgb[0:2];
    reg exp_de[0:2],exp_hs[0:2],exp_vs[0:2],exp_bin[0:2];
    integer sample_no=0, errors=0, qi, x, y;
    reg model_box_valid=0;
    integer model_xmin=0,model_xmax=0,model_ymin=0,model_ymax=0;

    function is_red2;
        input [23:0] p;
        reg [7:0] r,g;
        begin
            r=p[23:16]; g=p[15:8];
            is_red2=(r>=8'd192) && (r>=g) && (r-g>=8'd96);
        end
    endfunction

    task drive;
        input [23:0] p;
        input d,h,v;
        input integer px,py;
        integer in_box,on_edge;
        reg [23:0] expect_pixel;
        begin
            expect_pixel=p;
            in_box=model_box_valid && d && px>=model_xmin && px<=model_xmax &&
                   py>=model_ymin && py<=model_ymax;
            on_edge=(px-model_xmin<2) || (model_xmax-px<2) ||
                    (py-model_ymin<2) || (model_ymax-py<2);
            if (in_box && on_edge) expect_pixel=24'h00ff00;

            @(negedge clk);
            rgb_in=p; de_in=d; hs_in=h; vs_in=v; thr_in=0;
            exp_rgb[sample_no%3]=expect_pixel;
            exp_de[sample_no%3]=d; exp_hs[sample_no%3]=h; exp_vs[sample_no%3]=v;
            exp_bin[sample_no%3]=is_red2(p);
            @(posedge clk); #1;
            if (sample_no>=2) begin
                qi=(sample_no-2)%3;
                if (rgb_out!==exp_rgb[qi] || de_out!==exp_de[qi] ||
                    hs_out!==exp_hs[qi] || vs_out!==exp_vs[qi] ||
                    bin_out!==exp_bin[qi] || y_out!==(exp_bin[qi]?8'hff:8'h00)) begin
                    if (errors<12)
                        $display("FAIL 720p stream n=%0d rgb=%06h/%06h sync=%b%b%b/%b%b%b bin=%b/%b",
                            sample_no-2,rgb_out,exp_rgb[qi],de_out,hs_out,vs_out,
                            exp_de[qi],exp_hs[qi],exp_vs[qi],bin_out,exp_bin[qi]);
                    errors=errors+1;
                end
            end
            sample_no=sample_no+1;
        end
    endtask

    task blank;
        input h,v;
        begin drive(24'h000000,0,h,v,-1,-1); end
    endtask

    task publish_previous;
        begin
            // High-active VS held for four clocks; it must publish/reset once.
            blank(0,1); blank(0,1); blank(0,1); blank(0,1);
            blank(0,0); blank(0,0);
        end
    endtask

    task check_stats;
        input raw,valid;
        input [1:0] typ,fillband,aspectband;
        input [10:0] exmin,exmax;
        input [9:0] eymin,eymax;
        input [HIT_W-1:0] hits;
        begin
            if (bbox_valid_raw!==raw || bbox_valid!==valid || shape_ok!==valid ||
                shape_type!==typ || fill_ratio_q8!==fillband || aspect_ratio_q44!==aspectband ||
                hit_cnt!==hits ||
                (raw && (bbox_x_min!==exmin || bbox_x_max!==exmax ||
                         bbox_y_min!==eymin || bbox_y_max!==eymax))) begin
                $display("FAIL 720p bbox raw/valid/type/fill/aspect/hits got %b/%b/%0d/%0d/%0d/%0d expected %b/%b/%0d/%0d/%0d/%0d",
                    bbox_valid_raw,bbox_valid,shape_type,fill_ratio_q8,aspect_ratio_q44,hit_cnt,
                    raw,valid,typ,fillband,aspectband,hits);
                $display("     bbox got (%0d,%0d)-(%0d,%0d), expected (%0d,%0d)-(%0d,%0d)",
                    bbox_x_min,bbox_y_min,bbox_x_max,bbox_y_max,exmin,eymin,exmax,eymax);
                errors=errors+1;
            end
            model_box_valid=valid;
            model_xmin=exmin; model_xmax=exmax; model_ymin=eymin; model_ymax=eymax;
        end
    endtask

    task raster;
        input integer scene;
        integer xx,yy;
        reg target;
        begin
            for (yy=0;yy<H;yy=yy+1) begin
                for (xx=0;xx<W;xx=xx+1) begin
                    case(scene)
                        0: target=(xx<900); // 900x720 = 648,000 hits; 1.25 aspect boundary
                        1: target=(xx>=1024 && yy>=512); // target beyond old X10/Y9 limits
                        default: target=1'b1; // all 1280x720 = 921,600 hits
                    endcase
                    drive(target?24'hff0000:24'h000000,1,0,0,xx,yy);
                end
                if (yy<H-1) begin
                    blank(1,0);
                    if ((yy%180)==0) begin blank(1,0); blank(1,0); end
                end
            end
        end
    endtask

    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        publish_previous();
        check_stats(0,0,0,0,0,0,0,0,0,0);

        raster(0);
        publish_previous();
        check_stats(1,1,1,1,1,11'd0,11'd899,10'd0,10'd719,20'd648000);

        raster(1);
        publish_previous();
        check_stats(1,1,1,1,1,11'd1024,11'd1279,10'd512,10'd719,20'd53248);

        raster(2);
        publish_previous();
        check_stats(1,0,1,1,2,11'd0,11'd1279,10'd0,10'd719,20'd921600);

        if (errors==0) $display("PASS tb_algo10_shape_720p area648000/right-bottom/aspect-boundary/full-area921600/stream");
        else $fatal(1,"FAIL tb_algo10_shape_720p errors=%0d",errors);
        $finish;
    end

    initial begin
        #400000000;
        $fatal(1,"FAIL tb_algo10_shape_720p timeout");
    end
endmodule
