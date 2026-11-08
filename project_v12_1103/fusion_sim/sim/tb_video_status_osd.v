`timescale 1ns/1ps
module tb_video_status_osd;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [23:0] rgb_in = 24'h123456;
    reg de_in = 1'b0, hs_in = 1'b0, vs_in = 1'b0;
    reg [3:0] mode_active = 4'd0;
    wire [23:0] rgb_out;
    wire de_out, hs_out, vs_out;
    reg expected_de = 1'b0, expected_hs = 1'b0, expected_vs = 1'b0;
    integer x, y, digit_index, glyph_col, glyph_checks=0;
    reg [7:0] bin_threshold=128, edge_threshold=32;
    reg edit=0;
    reg [23:0] expected_digits, expected_pixel;
    reg [7:0] reference_char, reference_x;
    reg [3:0] reference_row;
    wire [15:0] reference_bits;
    reg raw_pixel_seen, gray_pixel_seen, frame_digit_seen, logo_seen, passthrough_seen;

    always #5 clk = ~clk;

    // 参考字库接预先指定的字符，与被测OSD的阈值格式化及坐标选择独立。
    osd_char_lib reference_font(.I_char(reference_char),.I_row(reference_row),.O_row_bits(reference_bits));
    video_status_osd dut (.bin_threshold_active(bin_threshold), .edge_threshold_active(edge_threshold), .threshold_edit_active(edit),
.clk(clk), .rst_n(rst_n), .rgb_in(rgb_in),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in), .mode_active(mode_active),
        .rgb_out(rgb_out), .de_out(de_out), .hs_out(hs_out), .vs_out(vs_out)
    );

    // 两级流水下，采样输入后输出对应前一次 tick 的输入。
    task tick;
        input de_value, hs_value, vs_value;
        input [23:0] rgb_value;
        begin
            @(negedge clk);
            de_in = de_value;
            hs_in = hs_value;
            vs_in = vs_value;
            rgb_in = rgb_value;
            @(posedge clk); #1;
            if (de_out !== expected_de || hs_out !== expected_hs || vs_out !== expected_vs)
                $fatal(1, "two-stage sync alignment mismatch");
            expected_de = de_value;
            expected_hs = hs_value;
            expected_vs = vs_value;
        end
    endtask

    task stream_frame;
        input [3:0] mode_value;
        input integer frame_no;
        begin
            mode_active = mode_value;
            tick(1'b0,1'b0,1'b1,24'h123456);
            tick(1'b0,1'b0,1'b1,24'h123456);
            for (y=0; y<105; y=y+1) begin
                for (x=0; x<560; x=x+1) begin
                    tick(1'b1,(x==0),1'b0,{x[7:0],y[7:0],8'h56});
                    // 第四行三位阈值字符及间隙，输出坐标比本拍输入x小一。
                    if((mode_value==2 || mode_value==3) && y>=86 && y<102 && x>=345 && x<399) begin
                        expected_digits=(mode_value==2)?"136":"040";
                        digit_index=(x-1-344)/18;
                        glyph_col=(x-1-344)%18;
                        reference_char=(expected_digits >> ((2-digit_index)*8)) & 8'hff;
                        reference_row=y-86;
                        #1;
                        reference_x=x-1;
                        expected_pixel={reference_x,y[7:0],8'h56};
                        if(glyph_col<16 && reference_bits[15-glyph_col]) expected_pixel=24'h00e6ff;
                        if(rgb_out!==expected_pixel)
                            $fatal(1,"rendered threshold glyph mismatch mode=%d x=%d y=%d got=%h expected=%h",mode_value,x-1,y,rgb_out,expected_pixel);
                        glyph_checks=glyph_checks+1;
                    end
                    // 输出属于前一个像素坐标，因此循环输入坐标比目标 x 大一。
                    if (frame_no==1 && x==191 && y==54) begin
                        if (rgb_out !== 24'hbe3656) $fatal(1,"non-OSD pixel not passed through with two-stage alignment");
                        passthrough_seen = 1'b1;
                    end
                    // 统一字模R首行左侧有墨点，G首行左侧留白；探针对应输出(311,21)。
                    if (x==312 && y==21) begin
                        if (mode_value==0) raw_pixel_seen = (rgb_out == 24'h00e6ff);
                        if (mode_value==1) gray_pixel_seen = (rgb_out == 24'h371556);
                    end
                    // 5494 地址是源 ROM 中有效 Logo 像素，对应相对坐标 (54,34)。
                    if (frame_no==1 && x==75 && y==54)
                        logo_seen = (rgb_out != 24'h4a3656) && (rgb_out != 24'h000000);
                    // CNT紧凑布局：数字位于字符5..12，末位1墨点移至(423,43)。
                    if (frame_no==1 && x==424 && y==43)
                        frame_digit_seen = (rgb_out == 24'h00e6ff);
                    // 原末位数字位置(531,43)应恢复底图，不能继续画旧计数。
                    if (frame_no==1 && x==532 && y==43 && rgb_out !== 24'h132b56)
                        $fatal(1,"old frame-count location still contains an OSD pixel: %h",rgb_out);
                end
                tick(1'b0,1'b0,1'b0,24'h123456);
            end
        end
    endtask

    initial begin
        raw_pixel_seen = 1'b0;
        gray_pixel_seen = 1'b0;
        frame_digit_seen = 1'b0;
        logo_seen = 1'b0;
        passthrough_seen = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        if (rgb_out !== 24'd0 || de_out !== 1'b0 || hs_out !== 1'b0 || vs_out !== 1'b0)
            $fatal(1,"reset outputs not cleared");
        expected_de = 1'b0; expected_hs = 1'b0; expected_vs = 1'b0;
        @(negedge clk); rst_n = 1'b1;

        stream_frame(4'd0,1);
        if (!raw_pixel_seen || !frame_digit_seen || !logo_seen || !passthrough_seen)
            $fatal(1,"first frame checks failed raw=%b frame=%b logo=%b pass=%b",
                   raw_pixel_seen,frame_digit_seen,logo_seen,passthrough_seen);
        stream_frame(4'd1,2);
        if (!gray_pixel_seen) $fatal(1,"mode text did not change to GRAY");
        bin_threshold=136;edge_threshold=40;edit=1;
        stream_frame(4'd2,3);
        stream_frame(4'd3,4);
        if(glyph_checks!=1728)$fatal(1,"threshold glyph check count=%0d",glyph_checks);

        @(negedge clk); rst_n = 1'b0;
        #1;
        if (dut.frame_count !== 32'd0 || rgb_out !== 24'd0 || de_out !== 1'b0)
            $fatal(1,"asynchronous reset did not clear state and outputs");
        $display("PASS tb_video_status_osd: logo, mode text, frame hex, passthrough, timing, reset, %0d rendered threshold glyph pixels",glyph_checks);
        $finish;
    end
endmodule
