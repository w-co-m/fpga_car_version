`timescale 1ns/1ps
// 仅验证AWB固定增益开关与像素有效对齐。除法/50拍RAM延迟为本TB接口模型。
module tb_polar_awb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,fixed_gain=1,valid=0,user=0;
    wire[95:0] fixed_data,legacy_data;wire fixed_valid,legacy_valid;
    integer errors=0,count=0,phase=0;
    awb #(.IMG_WIDTH(8),.IMG_HEIGHT(4),.ENABLE_POLAR_FIXED_GAIN(1)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_tlast(1'b0),.I_tuser(user),.I_tdata({4{24'h204060}}),.I_tvalid(valid),
        .I_polar_fixed_gain(fixed_gain),.I_tready(),.O_tlast(),.O_tuser(),.O_tdata(fixed_data),.O_tvalid(fixed_valid),.O_tready(1'b1));
    awb #(.IMG_WIDTH(8),.IMG_HEIGHT(4)) legacy(
        .I_clk(clk),.I_rst_n(rst_n),.I_tlast(1'b0),.I_tuser(user),.I_tdata({4{24'h204060}}),.I_tvalid(valid),
        .I_polar_fixed_gain(1'b1),.I_tready(),.O_tlast(),.O_tuser(),.O_tdata(legacy_data),.O_tvalid(legacy_valid),.O_tready(1'b1));
    always @(negedge clk)if(fixed_valid)begin
        count=count+1;
        if(fixed_data !== (phase==0 ? {4{24'h204060}} : {4{24'h4040c0}}) ||
           !legacy_valid || legacy_data !== {4{24'h4040c0}})begin
            $display("FAIL AWB phase=%d fixed=%h legacy=%h",phase,fixed_data,legacy_data);errors=errors+1;
        end
    end
    initial begin
        repeat(4)@(negedge clk);rst_n=1;user=1;@(negedge clk);user=0;
        valid=1;repeat(60)@(negedge clk);valid=0;repeat(70)@(negedge clk);
        phase=1;fixed_gain=0;valid=1;repeat(60)@(negedge clk);valid=0;repeat(70)@(negedge clk);
        if(count!=120)errors=errors+1;
        $display("tb_polar_awb %s errors=%0d pixels=%0d",errors==0?"PASS":"FAIL",errors,count*4);$finish;
    end
endmodule
module awb_gain_divider(input wire clk,rst_n,start,input wire[31:0]sum_g32,den32,output reg valid,output reg[19:0]gain20);
    always @(posedge clk)if(!rst_n)begin gain20<=0;valid<=0;end
    else begin valid<=start;if(start)gain20<=20'h20000;end
endmodule
module signal_delay #(parameter IMG_HEIGHT=4,IMG_WIDTH=8,DATA_WIDTH=96,DELAY_CYCLE=50)(
    input wire I_clk,I_rst_n,I_tuser,I_valid,input wire[DATA_WIDTH-1:0]I_data,
    output wire O_valid,output wire[DATA_WIDTH-1:0]O_data,output wire O_tuser);
    reg[DATA_WIDTH-1:0]d[0:DELAY_CYCLE-1];reg[DELAY_CYCLE-1:0]v,u;integer i;
    always @(posedge I_clk or negedge I_rst_n)if(!I_rst_n)begin
        v<=0;u<=0;for(i=0;i<DELAY_CYCLE;i=i+1)d[i]<=0;
    end else begin
        v<={v[DELAY_CYCLE-2:0],I_valid};u<={u[DELAY_CYCLE-2:0],I_tuser};d[0]<=I_data;
        for(i=1;i<DELAY_CYCLE;i=i+1)d[i]<=d[i-1];
    end
    assign O_valid=v[DELAY_CYCLE-1];assign O_tuser=u[DELAY_CYCLE-1];assign O_data=d[DELAY_CYCLE-1];
endmodule
