`timescale 1ns/1ps
// Regression for the real video_out -> hdmi_mixer pixel path.
module tb_video_out_mixer;
    localparam integer IMG_W = 16;
    localparam integer IMG_H = 2;
    localparam integer HDMI_W = 20;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg vs = 1'b0, hs = 1'b0, de = 1'b0, user = 1'b0, last = 1'b0;
    reg ddr_rd_valid = 1'b0;
    reg [127:0] ddr_rd_data = 128'd0;
    wire rd_en, ddr_busy, ddr_rd_en;
    wire [24:0] ddr_addr;
    wire [23:0] video_rd_data, hdmi_data;
    wire hdmi_de, hdmi_hs, hdmi_vs;

    integer errors = 0;
    integer request_count = 0;
    integer frame_base = 0;
    integer frame_de_count = 0;
    integer out_x = 0, out_y = 0;
    reg exp_de_1 = 1'b0, exp_de_2 = 1'b0;
    reg exp_hs_1 = 1'b0, exp_hs_2 = 1'b0;
    reg exp_vs_1 = 1'b0, exp_vs_2 = 1'b0;
    integer expected_pixel;
    integer row, col, word_idx, pixel_idx;
    reg [767:0] packed_pixels;

    always #5 clk = ~clk;

    video_out u_video_out (
        .I_rst_n(rst_n),
        .I_ddr_clk(clk), .O_video_out_rd_busy(ddr_busy),
        .I_video_in_wr_busy(1'b0), .I_video_out_rp(2'd0),
        .O_ddr_user_rd_en(ddr_rd_en), .O_ddr_user_addr(ddr_addr),
        .I_ddr_user_ready(1'b0), .I_ddr_user_rd_valid(ddr_rd_valid),
        .I_ddr_user_rd_data(ddr_rd_data),
        .I_dsi_clk(clk), .I_video_vsync(vs), .I_video_rd_en(rd_en),
        .O_vdieo_data(video_rd_data)
    );

    hdmi_mixer #(.H_OFFSET(0), .V_OFFSET(0), .IMG_WIDTH(IMG_W),
                 .IMG_HEIGHT(IMG_H), .DEBUG_MODE(0)) u_hdmi_mixer (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_video_vsync(vs), .I_video_hsync(hs), .I_video_de(de),
        .I_video_user(user), .I_video_last(last), .I_debug_status(4'd0),
        .O_video_rd_en(rd_en), .I_video_rd_data(video_rd_data),
        .O_hdmi_vsync(hdmi_vs), .O_hdmi_hsync(hdmi_hs),
        .O_hdmi_de(hdmi_de), .O_hdmi_data(hdmi_data)
    );

    // 对照 HDMI 输出的每个 DE 像素坐标，主动区按逐像素期望值比较，
    // 图像窗口外的 DE 像素必须为黑色；同步信号检查相同固定流水延迟。
    always @(posedge clk) begin
        #1;
        if (hdmi_de !== exp_de_2 || hdmi_hs !== exp_hs_2 || hdmi_vs !== exp_vs_2) begin
            errors = errors + 1;
            $display("SYNC mismatch t=%0t DE/HS/VS=%b%b%b expected=%b%b%b",
                     $time, hdmi_de, hdmi_hs, hdmi_vs, exp_de_2, exp_hs_2, exp_vs_2);
        end
        exp_de_2 = exp_de_1; exp_de_1 = de;
        exp_hs_2 = exp_hs_1; exp_hs_1 = hs;
        exp_vs_2 = exp_vs_1; exp_vs_1 = vs;

        if (user) begin
            out_x = 0;
            out_y = 0;
            frame_de_count = 0;
        end
        if (hdmi_de) begin
            frame_de_count = frame_de_count + 1;
            if ((out_x < IMG_W) && (out_y < IMG_H))
                expected_pixel = frame_base + out_y*IMG_W + out_x + 1;
            else
                expected_pixel = 0;
            if (hdmi_data !== expected_pixel[23:0]) begin
                errors = errors + 1;
                $display("PIXEL mismatch frame_base=%0d x=%0d y=%0d actual=%06h expected=%06h",
                         frame_base, out_x, out_y, hdmi_data, expected_pixel[23:0]);
            end
            if (out_x == HDMI_W-1) begin
                out_x = 0;
                out_y = out_y + 1;
            end else begin
                out_x = out_x + 1;
            end
        end
    end

    always @(posedge clk)
        if (rd_en) request_count = request_count + 1;

    task enqueue_frame;
        input integer base;
        integer i, w;
        begin
            for (i=0; i<32; i=i+1)
                packed_pixels[767-i*24 -: 24] = base + i + 1;
            for (w=0; w<6; w=w+1) begin
                @(negedge clk);
                ddr_rd_valid = 1'b1;
                ddr_rd_data = packed_pixels[767-w*128 -: 128];
            end
            @(negedge clk);
            ddr_rd_valid = 1'b0;
            ddr_rd_data = 128'd0;
            repeat (4) @(negedge clk);
        end
    endtask

    task run_frame;
        input integer base;
        integer y, x;
        begin
            frame_base = base;
            // 高有效 VS 触发实际 video_out FIFO 复位，留足清零周期后填入本帧数据。
            vs = 1'b1; de = 1'b0; hs = 1'b0; user = 1'b0; last = 1'b0;
            repeat (20) @(negedge clk);
            vs = 1'b0;
            repeat (3) @(negedge clk);
            enqueue_frame(base);
            // 帧标记在DE开始前到达，使窗口行计数在首像素前复位。
            user = 1'b1;
            @(negedge clk);
            user = 1'b0;

            for (y=0; y<IMG_H; y=y+1) begin
                for (x=0; x<HDMI_W; x=x+1) begin
                    @(negedge clk);
                    de = 1'b1;
                    hs = 1'b0;
                    user = 1'b0;
                    last = (x==HDMI_W-1);
                    #1;
                    if (rd_en !== ((x < IMG_W) && (y < IMG_H))) begin
                        errors = errors + 1;
                        $display("READ_EN mismatch input x=%0d y=%0d actual=%b",x,y,rd_en);
                    end
                end
                @(negedge clk);
                de = 1'b0; user = 1'b0; last = 1'b0; hs = 1'b1;
                #1;
                if (rd_en !== 1'b0) begin
                    errors = errors + 1;
                    $display("READ_EN asserted during line blanking");
                end
                @(negedge clk); hs = 1'b0;
                repeat (4) @(negedge clk);
            end
            de = 1'b0; user = 1'b0; last = 1'b0; hs = 1'b0;
            repeat (8) @(negedge clk); // drain all HDMI pipeline stages
            if (frame_de_count != IMG_H*HDMI_W) begin
                errors = errors + 1;
                $display("DE count mismatch base=%0d actual=%0d expected=%0d",
                         base, frame_de_count, IMG_H*HDMI_W);
            end
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        run_frame(0);
        run_frame(100);
        if (request_count != 2*IMG_W*IMG_H) begin
            errors = errors + 1;
            $display("read request count actual=%0d expected=%0d",
                     request_count, 2*IMG_W*IMG_H);
        end
        if (errors != 0)
            $fatal(1,"FAIL tb_video_out_mixer errors=%0d", errors);
        $display("PASS tb_video_out_mixer: 2 frames, all active pixels, borders, blanking and sync");
        $finish;
    end
endmodule
