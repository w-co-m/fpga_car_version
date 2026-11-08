`timescale 1ns/1ps
module tb_polar_osd_angles;
    reg clk=0, rst_n=0;
    reg [3:0] mode=9;
    reg [1:0] angle=0;
    wire [23:0] rgb_out;
    wire de_out, hs_out, vs_out;
    integer m, i;
    reg [7:0] ch;
    reg [7:0] expected_labels [0:3][0:7];
    reg [7:0] angle_digits [0:3][0:2];

    always #5 clk=~clk;

    video_status_osd #(.ENABLE_POLAR_STATUS(1)) dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(24'h123456), .de_in(1'b0),
        .hs_in(1'b0), .vs_in(1'b0), .mode_active(mode),
        .bin_threshold_active(8'd128), .edge_threshold_active(8'd32),
        .threshold_edit_active(1'b1), .polar_angle(angle),
        .polar_capture_busy(1'b0), .polar_compute_busy(1'b0),
        .polar_ready(1'b1), .polar_error(1'b0),
        .rgb_out(rgb_out), .de_out(de_out), .hs_out(hs_out), .vs_out(vs_out)
    );

    initial begin
        expected_labels[0][0]="D"; expected_labels[0][1]="O"; expected_labels[0][2]="L"; expected_labels[0][3]="P";
        expected_labels[1][0]="A"; expected_labels[1][1]="O"; expected_labels[1][2]="P";
        expected_labels[2][0]="F"; expected_labels[2][1]="U"; expected_labels[2][2]="S"; expected_labels[2][3]="I"; expected_labels[2][4]="O"; expected_labels[2][5]="N";
        expected_labels[3][0]="P"; expected_labels[3][1]="E"; expected_labels[3][2]="D"; expected_labels[3][3]="G"; expected_labels[3][4]="E";
        for (i=0; i<4; i=i+1) begin
            if (i==0) begin expected_labels[i][4]=" "; expected_labels[i][5]=" "; expected_labels[i][6]=" "; expected_labels[i][7]=" "; end
            if (i==1) begin expected_labels[i][3]=" "; expected_labels[i][4]=" "; expected_labels[i][5]=" "; expected_labels[i][6]=" "; expected_labels[i][7]=" "; end
            if (i==2) begin expected_labels[i][6]=" "; expected_labels[i][7]=" "; end
            if (i==3) begin expected_labels[i][5]=" "; expected_labels[i][6]=" "; expected_labels[i][7]=" "; end
        end
        angle_digits[0][0]="0"; angle_digits[0][1]="0"; angle_digits[0][2]="0";
        angle_digits[1][0]="0"; angle_digits[1][1]="4"; angle_digits[1][2]="5";
        angle_digits[2][0]="0"; angle_digits[2][1]="9"; angle_digits[2][2]="0";
        angle_digits[3][0]="1"; angle_digits[3][1]="3"; angle_digits[3][2]="5";
        repeat(3) @(posedge clk);
        rst_n=1;

        for (m=0; m<4; m=m+1) begin
            mode=9+m;
            for (i=0; i<8; i=i+1) begin
                ch=dut.mode_char(mode, i);
                if (ch !== expected_labels[m][i])
                    $fatal(1,"mode %0d label index %0d got %0c expected %0c",mode,i,ch,expected_labels[m][i]);
                ch=dut.text_char(2'd0,6'd6+i,mode,0,0,0,0,0,0,0,0,0,2'd0);
                if (ch !== expected_labels[m][i])
                    $fatal(1,"MODE line %0d label index %0d got %0c expected %0c",mode,i,ch,expected_labels[m][i]);
            end
        end

        for (i=0; i<4; i=i+1) begin
            angle=i;
            if (dut.text_char(2'd2,6'd6,4'd9,0,0,0,0,angle,0,0,1,0,2'd0) !== angle_digits[i][0] ||
                dut.text_char(2'd2,6'd7,4'd9,0,0,0,0,angle,0,0,1,0,2'd0) !== angle_digits[i][1] ||
                dut.text_char(2'd2,6'd8,4'd9,0,0,0,0,angle,0,0,1,0,2'd0) !== angle_digits[i][2])
                $fatal(1,"angle %0d must render %0c%0c%0c",i,angle_digits[i][0],angle_digits[i][1],angle_digits[i][2]);
        end
        $display("PASS tb_polar_osd_angles: mode labels 9..12 and ANGLE 000/045/090/135");
        $finish;
    end
endmodule
