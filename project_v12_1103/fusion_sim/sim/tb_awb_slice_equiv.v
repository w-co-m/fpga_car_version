`timescale 1ns/1ps
`include "awb_gain_divider_slice_ref.vh"
module tb_awb_slice_equiv;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, start=0;
    reg [31:0] sum_g32=0, den32=0;
    wire current_valid, reference_valid;
    wire [19:0] current_gain, reference_gain;

    integer cycle=0, errors=0, issued=0, compared_valid=0, compared_invalid=0;
    integer masked_reset=0, random_count=0, i, target;
    reg expected_valid[0:12000];
    reg [19:0] expected_gain[0:12000];
    reg [63:0] numerator, quotient;
    reg [31:0] random_g, random_d;

    awb_gain_divider current_dut(.clk(clk),.rst_n(rst_n),.start(start),
        .sum_g32(sum_g32),.den32(den32),.valid(current_valid),.gain20(current_gain));
    awb_gain_divider_slice_ref reference_dut(.clk(clk),.rst_n(rst_n),.start(start),
        .sum_g32(sum_g32),.den32(den32),.valid(reference_valid),.gain20(reference_gain));

    // The independently computed unsigned 64-bit quotient is the data oracle.
    // Requests are sampled on every edge, including reset; reset only masks the
    // externally visible output registers, just as it does in the RTL.
    always @(posedge clk) begin
        cycle = cycle + 1;
        if(start) begin
            issued = issued + 1;
            numerator = {32'd0,sum_g32} << 16;
            if(den32 == 0) quotient = 64'hffffffffffffffff;
            else quotient = numerator / den32;
            if(quotient > 64'h00000000000fffff) quotient = 64'h00000000000fffff;
            target = cycle + 49;
            if(target <= 12000) begin
                expected_valid[target] = 1'b1;
                expected_gain[target] = quotient[19:0];
            end
        end
        #1;
        if(!rst_n) begin
            if(current_valid !== 1'b0 || reference_valid !== 1'b0) begin
                $display("FAIL valid during reset cycle=%0d current=%b reference=%b",cycle,current_valid,reference_valid);
                errors = errors + 1;
            end
            if(expected_valid[cycle]) begin
                masked_reset = masked_reset + 1;
                expected_valid[cycle] = 1'b0;
            end
        end else begin
            if(current_valid !== reference_valid) begin
                $display("FAIL valid mismatch cycle=%0d current=%b reference=%b",cycle,current_valid,reference_valid);
                errors = errors + 1;
            end
            if(cycle > 60 && current_valid !== expected_valid[cycle]) begin
                $display("FAIL oracle valid cycle=%0d current=%b expected=%b",cycle,current_valid,expected_valid[cycle]);
                errors = errors + 1;
            end
            if(expected_valid[cycle]) begin
                compared_valid = compared_valid + 1;
                if(current_gain !== expected_gain[cycle]) begin
                    $display("FAIL oracle data cycle=%0d got=%h expected=%h",cycle,current_gain,expected_gain[cycle]);
                    errors = errors + 1;
                end
                if(reference_gain !== expected_gain[cycle]) begin
                    $display("FAIL reference oracle cycle=%0d got=%h expected=%h",cycle,reference_gain,expected_gain[cycle]);
                    errors = errors + 1;
                end
                expected_valid[cycle] = 1'b0;
            end else if(cycle > 60) begin
                // gain_pre is intentionally unreset. Once startup has flushed,
                // invalid-cycle data must retain the exact old/new behavior.
                compared_invalid = compared_invalid + 1;
                if(current_gain !== reference_gain) begin
                    $display("FAIL invalid data mismatch cycle=%0d current=%h reference=%h",cycle,current_gain,reference_gain);
                    errors = errors + 1;
                end
            end
        end
    end

    task drive;
        input request;
        input [31:0] g;
        input [31:0] d;
        begin
            @(negedge clk);
            start=request;
            sum_g32=g;
            den32=d;
        end
    endtask

    task boundary_case;
        input [31:0] d;
        input [1:0] offset_code;
        reg [63:0] boundary;
        begin
            boundary = {32'd0,d} << 4;
            case(offset_code)
                0: drive(1,boundary[31:0]-1'b1,d);
                1: drive(1,boundary[31:0],d);
                default: drive(1,boundary[31:0]+1'b1,d);
            endcase
        end
    endtask

    initial begin
        for(i=0;i<=12000;i=i+1) begin
            expected_valid[i]=0;
            expected_gain[i]=0;
        end
        // Force an actual asynchronous reset edge at time zero to initialize
        // only the specified output registers; internal datapath stays unreset.
        #1 rst_n=1;
        #1 rst_n=0;
        repeat(3) @(negedge clk);
        rst_n=1;

        boundary_case(32'd1,0); boundary_case(32'd1,1); boundary_case(32'd1,2);
        boundary_case(32'd2,0); boundary_case(32'd2,1); boundary_case(32'd2,2);
        boundary_case(32'h00012345,0); boundary_case(32'h00012345,1); boundary_case(32'h00012345,2);
        boundary_case(32'h0fffffff,0); boundary_case(32'h0fffffff,1); boundary_case(32'h0fffffff,2);
        drive(1,32'd0,32'd0);                    // divide by zero and zero numerator
        drive(1,32'hffffffff,32'd0);             // divide by zero with maximum numerator
        drive(1,32'd0,32'hffffffff);             // zero numerator and high-bit denominator
        drive(1,32'hffffffff,32'hffffffff);       // both operands maximum/high bit
        drive(1,32'h80000000,32'h80000000);
        drive(1,32'hffffffff,32'h7fffffff);

        // Ten thousand consecutive requests with independent random 32-bit
        // operands, exercising one-request-per-clock throughput.
        for(i=0;i<10000;i=i+1) begin
            @(negedge clk);
            random_g=$random;
            random_d=$random;
            start=1;
            sum_g32=random_g;
            den32=random_d;
            random_count=random_count+1;
        end
        drive(0,0,0);
        // Bubble pattern, plus requests accepted while reset is asserted.
        for(i=0;i<100;i=i+1) begin
            if((i%4)==0) drive(0,$random,$random);
            else drive(1,$random,$random);
        end
        drive(1,32'd7,32'd3);
        @(negedge clk); start=1;sum_g32=32'hfedcba98;den32=32'h87654321;rst_n=0;
        repeat(2) begin @(negedge clk); start=1;sum_g32=$random;den32=$random; end
        @(negedge clk); start=0;rst_n=1;
        for(i=0;i<100;i=i+1) begin
            if((i%3)==0) drive(0,$random,$random);
            else drive(1,$random,$random);
        end
        repeat(120) drive(0,0,1);
        if(random_count!=10000 || compared_valid<10000 || compared_invalid<100 || masked_reset==0)
            errors=errors+1;
        $display("tb_awb_slice_equiv %s errors=%0d issued=%0d valid=%0d invalid=%0d random=%0d reset_masked=%0d latency=49",
            errors==0?"PASS":"FAIL",errors,issued,compared_valid,compared_invalid,random_count,masked_reset);
        $finish;
    end
endmodule
