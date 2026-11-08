`timescale 1ns/1ps
module tb_csi_abort_recovery;
reg clk=0; always #5 clk=~clk;
reg rst=0, hv=0; reg [15:0] hd=0;
wire ov; wire [31:0] od; wire fs,fe,hs; wire [15:0] len;
integer count=0, errors=0, i, bad_data=0;
csi_unpacket_2lane dut(.I_clk(clk),.I_rst_n(rst),.I_hs_valid(hv),.I_hs_data(hd),.O_csi_frame_start(fs),.O_csi_frame_end(fe),.O_csi_valid(ov),.O_csi_data(od),.O_csi_hs(hs),.O_data_length(len));
always @(posedge clk) begin #1; if (ov) begin count=count+1; if (od !== 32'h13572468) bad_data=bad_data+1; end end
task send; input [15:0] d; begin @(negedge clk); hv=1; hd=d; end endtask
task idle; input integer n; integer j; begin for(j=0;j<n;j=j+1) begin @(negedge clk); hv=0; hd=0; end end endtask
task packet; integer k; begin
    send(16'h2b40); send(16'h0600);
    for(k=0;k<800;k=k+1) if ((k%2)==0) send(16'h1357); else send(16'h2468);
    send(16'hffff); idle(12);
end endtask
initial begin
    idle(8); rst=1; idle(8);
    packet();
    $display("CHECK clean_words=%0d clean_data_errors=%0d",count,bad_data);
    if(count != 400) begin $display("FAIL clean packet expected 400 words"); errors=errors+1; end
    if(bad_data != 0) begin $display("FAIL clean packet data pair mismatch count=%0d",bad_data); errors=errors+1; end

    count=0; bad_data=0;
    send(16'h2b40); send(16'h0600);
    for(i=0;i<201;i=i+1) if ((i%2)==0) send(16'h1357); else send(16'h2468);
    idle(4);
    $display("CHECK abort_complete_words=%0d abort_data_errors=%0d",count,bad_data);
    if(count != 100) begin $display("FAIL odd abort must emit only 100 complete 32-bit words"); errors=errors+1; end
    if(bad_data != 0) begin $display("FAIL odd abort emitted an invalid half-word combination"); errors=errors+1; end
    count=0; bad_data=0; idle(64);
    $display("CHECK abort_idle_words=%0d",count);
    if(count != 0) begin $display("FAIL aborted packet continued output during idle"); errors=errors+1; end

    count=0; bad_data=0; packet();
    $display("CHECK recovery_words=%0d recovery_data_errors=%0d",count,bad_data);
    if(count != 400) begin $display("FAIL complete packet after abort expected 400 words"); errors=errors+1; end
    if(bad_data != 0) begin $display("FAIL recovered packet did not restart at the correct half-word phase"); errors=errors+1; end

    if(errors != 0) $fatal(1,"CSI abort recovery failed: %0d checks",errors);
    $display("PASS tb_csi_abort_recovery");
    $finish;
end
endmodule
