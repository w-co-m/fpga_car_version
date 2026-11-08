`timescale 1ns/1ps
module tb_osd_font;
    reg [7:0] ch;
    reg [3:0] row;
    wire [15:0] bits;
    integer i;
    reg [7:0] chars [0:35];
    reg [15:0] an_rows [0:15];
    reg [15:0] lu_rows [0:15];

    osd_char_lib dut(.I_char(ch), .I_row(row), .O_row_bits(bits));

    task check_char;
        input [7:0] c;
        integer yy, xx, t, b, l, r, seen;
        reg [15:0] first_row;
        begin
            ch = c;
            t = 16; b = -1; l = 16; r = -1; seen = 0;
            for (yy = 0; yy < 16; yy = yy + 1) begin
                row = yy[3:0]; #1;
                if (bits != 16'd0) begin
                    if (t == 16) t = yy;
                    b = yy;
                    seen = 1;
                end
                for (xx = 0; xx < 16; xx = xx + 1) begin
                    if (bits[15-xx]) begin
                        if (xx < l) l = xx;
                        if (xx > r) r = xx;
                    end
                end
            end
            if (!seen || t != 1 || b != 14)
                $fatal(1, "font height/baseline mismatch char=%c top=%0d bottom=%0d", c, t, b);
            if (l < 3 || r > 12)
                $fatal(1, "font sidebearing mismatch char=%c left=%0d right=%0d", c, l, r);
            row = 4'd1; #1; first_row = bits;
            row = 4'd2; #1;
            if (bits !== first_row)
                $fatal(1, "vertical 2x raster mismatch char=%c", c);
            row = 4'd3; #1; first_row = bits;
            row = 4'd4; #1;
            if (bits !== first_row)
                $fatal(1, "vertical 2x raster mismatch char=%c", c);
            row = 4'd5; #1; first_row = bits;
            row = 4'd6; #1;
            if (bits !== first_row)
                $fatal(1, "vertical 2x raster mismatch char=%c", c);
            row = 4'd7; #1; first_row = bits;
            row = 4'd8; #1;
            if (bits !== first_row)
                $fatal(1, "vertical 2x raster mismatch char=%c", c);
            row = 4'd9; #1; first_row = bits;
            row = 4'd10; #1;
            if (bits !== first_row)
                $fatal(1, "vertical 2x raster mismatch char=%c", c);
            row = 4'd11; #1; first_row = bits;
            row = 4'd12; #1;
            if (bits !== first_row)
                $fatal(1, "vertical 2x raster mismatch char=%c", c);
            row = 4'd13; #1; first_row = bits;
            row = 4'd14; #1;
            if (bits !== first_row)
                $fatal(1, "vertical 2x raster mismatch char=%c", c);
        end
    endtask

    initial begin
        ch=0; row=0;
        for (i=0; i<26; i=i+1) chars[i] = 8'h41 + i;
        for (i=0; i<10; i=i+1) chars[26+i] = 8'h30 + i;
        for (i=0; i<36; i=i+1) check_char(chars[i]);

        // A ?????bit15 ?????????X=3..12 ???????
        ch="A"; row=1; #1;
        if (bits !== 16'h07e0) $fatal(1, "golden A mismatch row1=%h", bits);
        ch="R"; row=1; #1;
        if (bits !== 16'h1fe0) $fatal(1, "golden R mismatch row1=%h", bits);
        ch="0"; row=1; #1;
        if (bits !== 16'h07e0) $fatal(1, "golden 0 mismatch row1=%h", bits);

        ch="/"; row=7; #1; if (bits === 0) $fatal(1, "slash missing");
        ch="="; row=5; #1; if (bits === 0) $fatal(1, "equals missing");
        ch=8'h20; row=7; #1; if (bits !== 0) $fatal(1, "space must be blank");
        ch=8'h3f; row=7; #1; if (bits !== 0) $fatal(1, "unknown must be blank");

        an_rows[0]=16'h0200; an_rows[1]=16'h7ff0; an_rows[2]=16'h4410; an_rows[3]=16'h0400;
        an_rows[4]=16'h7ff0; an_rows[5]=16'h0840; an_rows[6]=16'h1040; an_rows[7]=16'h1c80;
        an_rows[8]=16'h0300; an_rows[9]=16'h0cc0; an_rows[10]=16'h7020; an_rows[11]=0;
        an_rows[12]=0; an_rows[13]=0; an_rows[14]=0; an_rows[15]=0;
        lu_rows[0]=16'h79e0; lu_rows[1]=16'h4a20; lu_rows[2]=16'h4d40; lu_rows[3]=16'h7880;
        lu_rows[4]=16'h1140; lu_rows[5]=16'h1630; lu_rows[6]=16'h5be0; lu_rows[7]=16'h5220;
        lu_rows[8]=16'h5220; lu_rows[9]=16'h5be0; lu_rows[10]=16'h6220; lu_rows[11]=0;
        lu_rows[12]=0; lu_rows[13]=0; lu_rows[14]=0; lu_rows[15]=0;
        ch=8'h80;
        for (i=0; i<16; i=i+1) begin
            row=i; #1; if (bits !== an_rows[i]) $fatal(1, "Chinese AN mask changed at row=%0d", i);
        end
        ch=8'h81;
        for (i=0; i<16; i=i+1) begin
            row=i; #1; if (bits !== lu_rows[i]) $fatal(1, "Chinese LU mask changed at row=%0d", i);
        end
        $display("PASS: all 36 alphanumeric glyph metrics and punctuation");
        $finish;
    end
endmodule
