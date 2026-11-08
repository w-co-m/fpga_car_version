`timescale 1ns/1ps
module tb_level_gain_osd;
    reg clk=0, rst_n=0;
    reg [23:0] rgb_in=24'h123456;
    reg de_in=0, hs_in=0, vs_in=0;
    reg [3:0] mode_active=4;
    reg [7:0] bin_value=128, edge_value=32, bright_gain=24, contrast_gain=24;
    reg edit_value=1;
    wire [23:0] rgb_out;
    wire de_out, hs_out, vs_out;
    reg expected_de=0, expected_hs=0, expected_vs=0;
    reg [7:0] ref_char=8'h20;
    reg [3:0] ref_row=0;
    wire [15:0] ref_bits;
    integer x,y,idx,col,checks=0;
    reg [7:0] output_x;
    reg [23:0] expected_pixel;

    always #5 clk=~clk;
    osd_char_lib ref_font(.I_char(ref_char),.I_row(ref_row),.O_row_bits(ref_bits));
    video_status_osd dut (
        .clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),
        .mode_active(mode_active),.bin_threshold_active(bin_value),.edge_threshold_active(edge_value),
        .bright_gain_active(bright_gain),.contrast_gain_active(contrast_gain),
        .threshold_edit_active(edit_value),.polar_angle(2'd0),.polar_capture_busy(1'b0),
        .polar_compute_busy(1'b0),.polar_ready(1'b0),.polar_error(1'b0),
        .rgb_out(rgb_out),.de_out(de_out),.hs_out(hs_out),.vs_out(vs_out)
    );

    function [7:0] expected_char;
        input [3:0] mode;
        input integer n;
        input integer value;
        input edit;
        begin
            expected_char=8'h20;
            case(n)
                0: expected_char=(mode==4)?"B":"C";
                1: expected_char=(mode==4)?"R":"O";
                2: expected_char=(mode==4)?"I":"N";
                4: expected_char="G"; 5: expected_char="A";
                6: expected_char="I"; 7: expected_char="N";
                8: expected_char=":";
                9: expected_char=8'h30+(value/100);
                10: expected_char=8'h30+((value/10)%10);
                11: expected_char=8'h30+(value%10);
                14: expected_char="K"; 15: expected_char="E";
                16: expected_char="Y"; 17: expected_char=":";
                18: expected_char=edit?"G":"M";
                19: expected_char=edit?"A":"O";
                20: expected_char=edit?"I":"D";
                21: expected_char=edit?"N":"E";
            endcase
        end
    endfunction

    task tick_pixel;
        input de_value,hs_value,vs_value;
        input [23:0] pixel_value;
        begin
            @(negedge clk);
            de_in=de_value; hs_in=hs_value; vs_in=vs_value; rgb_in=pixel_value;
            @(posedge clk); #1;
            if ({de_out,hs_out,vs_out} !== {expected_de,expected_hs,expected_vs})
                $fatal(1,"OSD sync mismatch");
            expected_de=de_value; expected_hs=hs_value; expected_vs=vs_value;
        end
    endtask

    task scan_gain_line;
        input [3:0] selected_mode;
        input [7:0] gain;
        input edit_on;
        integer gain_i;
        begin
            mode_active=selected_mode;
            edit_value=edit_on;
            if(selected_mode==4) bright_gain=gain;
            else contrast_gain=gain;
            gain_i=gain;
            // Start a new frame and scan through the fourth text row (y=86..101).
            tick_pixel(0,0,1,24'h123456);
            tick_pixel(0,0,1,24'h123456);
            tick_pixel(0,0,0,24'h123456);
            for(y=0;y<105;y=y+1) begin
                for(x=0;x<600;x=x+1) begin
                    tick_pixel(1,(x==0),0,{x[7:0],y[7:0],8'h56});
                    // The OSD output is the preceding input pixel (x-1).
                    if(y>=86 && y<102 && x>=201 && x<=596) begin
                        idx=(x-1-200)/18;
                        col=(x-1-200)%18;
                        ref_char=expected_char(selected_mode,idx,gain_i,edit_on);
                        ref_row=y-86;
                        output_x=x-1;
                        #1;
                        expected_pixel={output_x,y[7:0],8'h56};
                        if(col<16 && ref_bits[15-col]) expected_pixel=24'h00e6ff;
                        if(rgb_out!==expected_pixel)
                            $fatal(1,"gain OSD mismatch mode=%0d edit=%b gain=%0d index=%0d col=%0d got=%h expected=%h",
                                   selected_mode,edit_on,gain_i,idx,col,rgb_out,expected_pixel);
                        checks=checks+1;
                    end
                end
                tick_pixel(0,0,0,24'h123456);
            end
        end
    endtask

    initial begin
        repeat(3) @(posedge clk); #1;
        if({rgb_out,de_out,hs_out,vs_out}!==27'd0) $fatal(1,"reset outputs not clear");
        @(negedge clk); rst_n=1;
        scan_gain_line(4,24,1); // BRI GAIN:024  KEY:GAIN
        scan_gain_line(4,25,1); // pending-frame value is formatted as 025
        scan_gain_line(4,25,0); // SW1=0 changes only the KEY suffix to MODE
        scan_gain_line(5,24,1); // CON GAIN:024  KEY:GAIN
        scan_gain_line(5,255,1); // all three decimal digits and independent input
        if(checks!=5*16*396) $fatal(1,"gain OSD pixel count=%0d expected=%0d",checks,5*16*396);
        $display("PASS tb_level_gain_osd: BRI/CON strings, gain digits 024/025/255, KEY:GAIN/MODE, checked_pixels=%0d",checks);
        $finish;
    end
    initial begin #30000000; $fatal(1,"OSD gain test timeout"); end
endmodule
