`timescale 1ns/1ps
module tb_awb_gain_divider;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, start=0;
    reg [31:0] sum_g32=0, den32=0;
    wire valid; wire [19:0] gain20;
    integer cycle=0, errors=0, checked=0, issued=0, masked_during_reset=0;
    reg expected_valid[0:2000]; reg [19:0] expected_gain[0:2000];
    integer i, target;
    reg [63:0] numerator, quotient;
    awb_gain_divider dut(.clk(clk),.rst_n(rst_n),.start(start),
        .sum_g32(sum_g32),.den32(den32),.valid(valid),.gain20(gain20));

    // One authoritative scoreboard clock: every posedge, including reset,
    // idle, and drain edges, advances the same cycle index.
    always @(posedge clk) begin
        cycle = cycle + 1;
        if(start) begin
            issued = issued + 1;
            numerator = {32'd0,sum_g32} << 16;
            if(den32 == 0) quotient = 64'hffffffffffffffff;
            else quotient = numerator / den32;
            if(quotient > 64'hfffff) quotient = 64'hfffff;
            target = cycle + 49;
            expected_valid[target] = 1'b1;
            expected_gain[target] = quotient[19:0];
        end
        #1;
        if(!rst_n) begin
            if(valid !== 1'b0) begin
                $display("FAIL valid during reset cycle=%0d got=%b",cycle,valid);
                errors = errors + 1;
            end
            if(expected_valid[cycle]) begin
                masked_during_reset = masked_during_reset + 1;
                expected_valid[cycle] = 1'b0;
            end
        end else begin
            if(valid !== expected_valid[cycle]) begin
                $display("FAIL valid cycle=%0d got=%b expected=%b",cycle,valid,expected_valid[cycle]);
                errors = errors + 1;
            end
            if(expected_valid[cycle]) begin
                checked = checked + 1;
                if(gain20 !== expected_gain[cycle]) begin
                    $display("FAIL gain cycle=%0d got=%h expected=%h",cycle,gain20,expected_gain[cycle]);
                    errors = errors + 1;
                end
                expected_valid[cycle] = 1'b0;
            end
        end
    end

    task drive;
        input request;
        input [31:0] g;
        input [31:0] d;
        begin
            @(negedge clk);
            start=request; sum_g32=g; den32=d;
        end
    endtask

    initial begin
        for(i=0;i<=2000;i=i+1) begin expected_valid[i]=0; expected_gain[i]=0; end
        repeat(55) @(negedge clk);
        rst_n=1;
        drive(1,32'd1,32'd1);                 // 1.0
        drive(1,32'd1,32'd2);                 // fractional
        drive(1,32'd3,32'd2);                 // integral quotient bits
        drive(1,32'h0000ffff,32'h00000001);
        drive(1,32'd15,32'd1);                // 0xf0000, not saturated
        drive(1,32'd16,32'd1);                // saturation threshold
        drive(1,32'd1048574,32'd65536);       // exact 0xffffe
        drive(1,32'd1048575,32'd65536);       // exact 0xfffff
        drive(1,32'd1048576,32'd65536);       // saturated 0xfffff
        drive(1,32'hffffffff,32'hffffffff);   // near-one fraction
        drive(1,32'hffffffff,32'd0);          // divide-by-zero behavior
        for(i=0;i<220;i=i+1) begin
            if((i%5)==0) drive(0,$random,$random);
            else drive(1,$random,$random);
        end

        // Assert reset with several accepted requests still in flight.
        drive(1,32'd7,32'd3);
        @(negedge clk); start=0; rst_n=0;
        repeat(2) @(negedge clk);
        rst_n=1;
        drive(1,32'd2,32'd3);
        repeat(55) drive(0,0,1);
        if(issued != checked + masked_during_reset || checked < 130 || masked_during_reset == 0)
            errors = errors + 1;
        $display("tb_awb_gain_divider %s errors=%0d issued=%0d completed=%0d masked_reset=%0d",
            errors==0?"PASS":"FAIL",errors,issued,checked,masked_during_reset);
        $finish;
    end
endmodule
