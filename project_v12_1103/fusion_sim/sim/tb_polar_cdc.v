`timescale 1ns/1ps
module tb_polar_cdc;
    reg a=0,b=0;always #7 a=~a;always #11 b=~b;
    reg rst_n=0;reg[7:0] value=0;wire[7:0]out;reg pulse=0;wire event_out;
    integer errors=0,events=0,k;
    polar_status_cdc #(.WIDTH(8)) dut(.src_clk(a),.src_rst_n(rst_n),.src_data(value),.dst_clk(b),.dst_rst_n(rst_n),.dst_data(out));
    polar_pulse_cdc cmd(.src_clk(a),.src_rst_n(rst_n),.src_pulse(pulse),.dst_clk(b),.dst_rst_n(rst_n),.dst_pulse(event_out));
    always @(posedge b)if(event_out)events=events+1;
    initial begin
        #80;rst_n=1;
        for(k=1;k<=20;k=k+1)begin @(negedge a);value=k;repeat(15)@(negedge b);if(out!=k)errors=errors+1;end
        // 快速变化允许合并中间状态，但必须送达最后的完整总线。
        for(k=1;k<30;k=k+1)begin @(negedge a);value=k*7;end
        repeat(20)@(negedge b);if(out!=8'd203)errors=errors+1;
        repeat(4)begin @(negedge a);pulse=1;@(negedge a);pulse=0;repeat(12)@(negedge b);end
        if(events!=4)errors=errors+1;
        $display("tb_polar_cdc %s errors=%0d events=%0d",errors==0?"PASS":"FAIL",errors,events);$finish;
    end
endmodule
