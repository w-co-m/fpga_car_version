`timescale 1ns/1ps
module tb_osd_direct_equiv;
    reg clk = 1'b0, rst_n = 1'b0;
    reg [23:0] rgb_in = 24'd0;
    reg de_in = 1'b0, hs_in = 1'b0, vs_in = 1'b0;
    reg [3:0] mode_active = 4'd0;
    reg [7:0] bin_threshold_active = 8'd0, edge_threshold_active = 8'd0;
    reg [7:0] bright_gain_active = 8'd0, contrast_gain_active = 8'd0;
    reg threshold_edit_active = 1'b0;
    reg [1:0] polar_angle = 2'd0, ddr_state = 2'd0;
    reg polar_capture_busy = 1'b0, polar_compute_busy = 1'b0;
    reg polar_ready = 1'b0, polar_error = 1'b0;
    wire [23:0] rgb_new, rgb_ref, rgb_ddr;
    wire de_new, hs_new, vs_new, de_ref, hs_ref, vs_ref;
    wire de_ddr, hs_ddr, vs_ddr;
    integer cycle_count = 0, frame_no, y, x, mode_no, gain_no, value_no;
    integer values [0:5];
    integer ddr_no, char_no;
    reg [7:0] expected_wait [0:8];
    reg [7:0] expected_error [0:8];

    always #5 clk = ~clk;

    video_status_osd dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .mode_active(mode_active), .bin_threshold_active(bin_threshold_active),
        .edge_threshold_active(edge_threshold_active), .bright_gain_active(bright_gain_active),
        .contrast_gain_active(contrast_gain_active), .threshold_edit_active(threshold_edit_active),
        .polar_angle(polar_angle), .polar_capture_busy(polar_capture_busy), .ddr_state(2'd0),
        .polar_compute_busy(polar_compute_busy), .polar_ready(polar_ready), .polar_error(polar_error),
        .rgb_out(rgb_new), .de_out(de_new), .hs_out(hs_new), .vs_out(vs_new)
    );
    video_status_osd_reference reference (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .mode_active(mode_active), .bin_threshold_active(bin_threshold_active),
        .edge_threshold_active(edge_threshold_active), .bright_gain_active(bright_gain_active),
        .contrast_gain_active(contrast_gain_active), .threshold_edit_active(threshold_edit_active),
        .polar_angle(polar_angle), .polar_capture_busy(polar_capture_busy),
        .polar_compute_busy(polar_compute_busy), .polar_ready(polar_ready), .polar_error(polar_error),
        .rgb_out(rgb_ref), .de_out(de_ref), .hs_out(hs_ref), .vs_out(vs_ref)
    );
    video_status_osd #(.ENABLE_DDR_STATUS(1)) ddr_dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .mode_active(mode_active), .bin_threshold_active(bin_threshold_active),
        .edge_threshold_active(edge_threshold_active), .bright_gain_active(bright_gain_active),
        .contrast_gain_active(contrast_gain_active), .threshold_edit_active(threshold_edit_active),
        .polar_angle(polar_angle), .polar_capture_busy(polar_capture_busy),
        .polar_compute_busy(polar_compute_busy), .polar_ready(polar_ready), .polar_error(polar_error),
        .ddr_state(ddr_state), .rgb_out(rgb_ddr), .de_out(de_ddr), .hs_out(hs_ddr), .vs_out(vs_ddr)
    );

    task step;
        input active, hs_value, vs_value;
        input integer row_value, col_value;
        begin
            @(negedge clk);
            de_in = active;
            hs_in = hs_value;
            vs_in = vs_value;
            rgb_in = {row_value[7:0], col_value[7:0], cycle_count[7:0]};
            polar_angle = cycle_count[1:0];
            polar_capture_busy = cycle_count[2];
            polar_compute_busy = cycle_count[3];
            polar_ready = cycle_count[4];
            polar_error = cycle_count[5];
            #1;
            if (active && row_value == 20 && col_value == 200 && ddr_state != 0 && ddr_dut.char_code !== "M")
                $fatal(1, "DDR state changed MODE row mode=%0d state=%0d char=%h", mode_active, ddr_state, ddr_dut.char_code);
            if (active && row_value == 86 && col_value >= 200 && col_value < 362 &&
                ((col_value - 200) % 18) == 0) begin
                char_no = (col_value - 200) / 18;
                if (ddr_state == 1) begin
                    if (char_no <= 8 && ddr_dut.char_code !== expected_wait[char_no])
                        $fatal(1, "DDR WAIT char=%0d got=%h expected=%h state=%0d", char_no, ddr_dut.char_code, expected_wait[char_no], ddr_state);
                end else if (ddr_state == 2 || ddr_state == 3) begin
                    if (char_no <= 8 && ddr_dut.char_code !== expected_error[char_no])
                        $fatal(1, "DDR ERROR char=%0d got=%h expected=%h", char_no, ddr_dut.char_code, expected_error[char_no]);
                end
            end
            @(posedge clk); #1;
            if ({rgb_new,de_new,hs_new,vs_new} !== {rgb_ref,de_ref,hs_ref,vs_ref})
                $fatal(1, "normal OSD mismatch cycle=%0d row=%0d col=%0d mode=%0d new=%h/%b%b%b ref=%h/%b%b%b",
                       cycle_count,row_value,col_value,mode_active,rgb_new,de_new,hs_new,vs_new,rgb_ref,de_ref,hs_ref,vs_ref);
            if ({de_ddr,hs_ddr,vs_ddr} !== {de_new,hs_new,vs_new})
                $fatal(1, "DDR changed output sync cycle=%0d row=%0d col=%0d",cycle_count,row_value,col_value);
            if (active && row_value == 87 && col_value == 205 && ddr_state != 0 && rgb_ddr !== 24'h00e6ff)
                $fatal(1, "DDR status glyph was not rendered state=%0d rgb=%h", ddr_state, rgb_ddr);
            cycle_count = cycle_count + 1;
        end
    endtask

    task scan_frame;
        input [3:0] mode_value;
        input [7:0] bin_value, edge_value, bright_value, contrast_value;
        input edit_value;
        input [1:0] ddr_value;
        begin
            mode_active = mode_value;
            bin_threshold_active = bin_value;
            edge_threshold_active = edge_value;
            bright_gain_active = bright_value;
            contrast_gain_active = contrast_value;
            threshold_edit_active = edit_value;
            ddr_state = ddr_value;
            step(1'b0,1'b0,1'b1,0,0);
            step(1'b0,1'b0,1'b0,0,0);
            for (y=0; y<180; y=y+1) begin
                for (x=0; x<740; x=x+1)
                    step(1'b1,(x<40),1'b0,y,x);
                step(1'b0,1'b0,1'b0,y,740);
            end
        end
    endtask

    initial begin
        values[0]=0; values[1]=9; values[2]=10; values[3]=99; values[4]=100; values[5]=255;
        expected_wait[0]="D"; expected_wait[1]="D"; expected_wait[2]="R";
        expected_wait[3]=8'h20; expected_wait[4]="W"; expected_wait[5]="A";
        expected_wait[6]="I"; expected_wait[7]="T"; expected_wait[8]=8'h20;
        expected_error[0]="D"; expected_error[1]="D"; expected_error[2]="R";
        expected_error[3]=8'h20; expected_error[4]="E"; expected_error[5]="R";
        expected_error[6]="R"; expected_error[7]="O"; expected_error[8]="R";
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n=1'b1;

        // Full logo and text raster for every mode, including 14-pixel glyph and cell boundaries.
        for (mode_no=0; mode_no<16; mode_no=mode_no+1)
            scan_frame(mode_no[3:0],8'd123,8'd234,8'd45,8'd201,1'b1,2'd0);

        // Exercise gain and threshold display boundaries in both GAIN modes.
        for (gain_no=0; gain_no<2; gain_no=gain_no+1)
            for (value_no=0; value_no<6; value_no=value_no+1)
                if (gain_no==0)
                    scan_frame(4'd4,8'd0,8'd0,values[value_no][7:0],8'd77,1'b0,2'd0);
                else
                    scan_frame(4'd5,8'd0,8'd0,8'd88,values[value_no][7:0],1'b1,2'd0);

        // DDR states remain visible independently of the OSD reset and leave sync unchanged.
        for (ddr_no=1; ddr_no<=3; ddr_no=ddr_no+1)
            scan_frame(4'd15,8'd0,8'd0,8'd24,8'd24,1'b0,ddr_no[1:0]);
        $display("PASS tb_osd_direct_equiv: cycles=%0d modes=0..15 gain_boundaries=0,9,10,99,100,255 DDR state 1=WAIT states 2/3=ERROR",cycle_count);
        $finish;
    end
endmodule
