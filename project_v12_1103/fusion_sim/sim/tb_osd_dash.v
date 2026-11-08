`timescale 1ns/1ps
module tb_osd_dash;
reg [7:0] ch=8'h2d;
reg [3:0] row=0;
wire [15:0] bits;
integer i,ink=0;
osd_char_lib dut(ch,row,bits);
initial begin
    for(i=0;i<16;i=i+1) begin row=i; #1; if(bits!==0) ink=ink+1; end
    $display("CHECK dash_glyph_rows_with_ink=%0d",ink);
    if(ink == 0) $fatal(1,"selected dash glyph has no visible pixels");
    $display("PASS tb_osd_dash");
    $finish;
end
endmodule
