`timescale 1ns/1ps
module tb_video_algorithm_display;
    reg clk=0, rst_n=0, k0=1, k1=1;
    reg [23:0] rgb=24'h204080;
    reg de=0, hs=0, vs=0;
    wire [23:0] out;
    wire od, oh, ov;
    wire [3:0] mode;
    integer errors=0, i;
    always #5 clk=~clk;
    video_algorithm_display #(.ALGO_COUNT(4), .CLK_HZ(1000), .DEBOUNCE_CYCLES(3),
                              .IMG_WIDTH(8)) dut (
        .clk(clk), .rst_n(rst_n), .threshold_edit(1'b0), .bin_threshold_active(), .edge_threshold_active(), .threshold_edit_active(), .key0_n(k0), .key1_n(k1),
        .rgb_in(rgb), .de_in(de), .hs_in(hs), .vs_in(vs),
        .rgb_out(out), .de_out(od), .hs_out(oh), .vs_out(ov),
        .mode_active(mode)
    );
    task tick;
        begin @(negedge clk); end
    endtask
    task press_next;
        begin k1=0; repeat(15) tick; k1=1; repeat(15) tick; end
    endtask
    task commit;
        begin de=0; repeat(8) tick; vs=1; repeat(8) tick; vs=0; repeat(8) tick; end
    endtask
    task expect_mode;
        input [3:0] expected;
        begin if(mode !== expected) begin errors=errors+1; $display("FAIL mode got=%d expected=%d",mode,expected); end end
    endtask
    initial begin
        repeat(4) tick; rst_n=1; repeat(20) tick;
        expect_mode(0);
        // Request during active video must not affect this frame.
        de=1; press_next; expect_mode(0);
        commit; expect_mode(1);
        de=1; repeat(8) tick;
        if(out !== 24'h3e3e3e || !od) begin errors=errors+1; $display("FAIL gray: %h de=%b",out,od); end
        press_next; expect_mode(1); commit; expect_mode(2);
        de=1; repeat(8) tick;
        if(out !== 24'h000000 || !od) begin errors=errors+1; $display("FAIL binary: %h",out); end
        de=0; press_next; commit; expect_mode(3);
        // Complete lines let the Sobel buffer establish a uniform frame.
        for(i=0;i<4;i=i+1) begin
            de=1; repeat(8) tick;
            if(out !== 24'h000000) begin errors=errors+1; $display("FAIL flat Sobel: %h",out); end
            de=0; repeat(8) tick;
        end
        press_next; commit; expect_mode(0);
        de=1; repeat(8) tick;
        if(out !== rgb) begin errors=errors+1; $display("FAIL raw: %h",out); end
        de=0; k0=0; repeat(15) tick; k0=1; repeat(15) tick;
        commit; expect_mode(3);
        rst_n=0; repeat(4) tick; expect_mode(0);
        $display("INTEGRATION RESULT errors=%0d",errors);
        if(errors) $fatal(1,"integration failed");
        $finish;
    end
    initial begin #100000; $fatal(1,"integration timeout"); end
endmodule
