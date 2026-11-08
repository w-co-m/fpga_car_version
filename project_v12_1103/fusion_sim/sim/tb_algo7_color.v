`timescale 1ns/1ps
module tb_algo7_color;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    polar_block_engine dut(
        .clk(clk),.rst_n(rst_n),.start(1'b0),.op_compute(1'b0),
        .source_addr(25'd0),.dest_addr(25'd0),.block_offset(25'd0),
        .grant(1'b0),.ddr_ready(1'b0),.rd_valid(1'b0),.rd_data(128'd0),
        .busy(),.done(),.error(),.request(),.owner_release(),.rd_en(),.wr_en(),.addr(),.wr_data());
    function [23:0] palette_ref(input [7:0] a);
        integer segment,offset,fade;
        begin
            segment=a/43;offset=a-segment*43;fade=offset*6;
            case(segment)
                0:palette_ref={8'd255,fade[7:0],8'd0};
                1:palette_ref={8'd255-fade[7:0],8'd255,8'd0};
                2:palette_ref={8'd0,8'd255,fade[7:0]};
                3:palette_ref={8'd0,8'd255-fade[7:0],8'd255};
                4:palette_ref={fade[7:0],8'd0,8'd255};
                default:palette_ref={8'd255,8'd0,8'd255-fade[7:0]};
            endcase
        end
    endfunction
    integer i;
    reg [23:0] expected;
    initial begin
        repeat(2)@(posedge clk);rst_n=1;
        if(dut.aop_hue(8'd0)!==24'hff0000 || dut.aop_hue(8'd128)!==24'h00fffc ||
           dut.aop_hue(8'd255)!==24'hff000f)
            $fatal(1,"palette endpoint/center anchors are incorrect");
        for(i=0;i<256;i=i+1)begin
            expected=palette_ref(i[7:0]);
            if(dut.aop_hue(i[7:0])!==expected)
                $fatal(1,"palette mismatch code=%0d got=%h expected=%h",i,dut.aop_hue(i[7:0]),expected);
        end
        $display("PASS tb_algo7_color: all 256 AoP codes match independent palette reference");
        $finish;
    end
endmodule
