`timescale 1ns/1ps
module tb_polar_guard;
    `include "algo7_delivery_math_ref.vh"
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,de=0;
    reg [7:0] i0=0,i45=0,i90=0,i135=0;
    wire valid,high_valid;
    wire [7:0] angle,high_angle;
    algo_polar_core #(.AOP_MAG_MIN(33)) dut(.clk(clk),.rst_n(rst_n),
        .i0(i0),.i45(i45),.i90(i90),.i135(i135),.rgb0(24'd0),.rgb45(24'd0),.rgb90(24'd0),.rgb135(24'd0),.de_in(de),.hs_in(1'b0),.vs_in(1'b0),
        .aop_out(angle),.dolp_out(),.rgb_unpol_out(),.y_unpol_out(),.de_out(valid),.hs_out(),.vs_out());
    algo_polar_core #(.AOP_MAG_MIN(361)) high_guard(.clk(clk),.rst_n(rst_n),
        .i0(i0),.i45(i45),.i90(i90),.i135(i135),.rgb0(24'd0),.rgb45(24'd0),.rgb90(24'd0),.rgb135(24'd0),.de_in(de),.hs_in(1'b0),.vs_in(1'b0),
        .aop_out(high_angle),.dolp_out(),.rgb_unpol_out(),.y_unpol_out(),.de_out(high_valid),.hs_out(),.vs_out());
    integer expected[0:8191],expected_high[0:8191];
    integer sent=0,received=0,x,y;
    task sample(input integer a,b,c,d);
        integer ref_pair,ref_high;
        begin
            @(negedge clk);i0=a;i45=b;i90=c;i135=d;de=1;
            ref_pair=algo7_delivery_ref(a[7:0],b[7:0],c[7:0],d[7:0],16,33);
            ref_high=algo7_delivery_ref(a[7:0],b[7:0],c[7:0],d[7:0],16,361);
            expected[sent]=ref_pair[7:0];expected_high[sent]=ref_high[7:0];
            sent=sent+1;
        end
    endtask
    always @(posedge clk) begin
        #1;
        if(rst_n && valid)begin
            if(angle!==expected[received][7:0])$fatal(1,"AoP exact index=%0d got=%0d expected=%0d",received,angle,expected[received]);
            if(high_valid!==1 || high_angle!==expected_high[received][7:0])$fatal(1,"AoP 361 exact index=%0d got=%0d expected=%0d",received,high_angle,expected_high[received]);
            received=received+1;
        end
    end
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        sample(16,36,48,28); // historical exact norm boundary; delivery guard is approximate.
        sample(0,0,33,0);
        sample(39,0,33,0);   // S1=6, S2=0: delivery Q4 magnitude threshold boundary.
        sample(39,4,33,0);   // weak approximate magnitude, distinct from exact sqrt gate.
        for(x=-40;x<=40;x=x+1)begin
            for(y=-40;y<=40;y=y+1) sample(x>0?x:0,y>0?y:0,x<0?-x:0,y<0?-y:0);
            @(negedge clk);de=0;
        end
        sample(255,255,0,0);sample(0,0,255,255);
        sample(255,0,0,255);sample(0,255,255,0);
        @(negedge clk);de=0;
        repeat(30)@(negedge clk);
        if(received!=sent)$fatal(1,"lost outputs received=%0d sent=%0d",received,sent);
        $display("PASS tb_polar_guard: %0d vectors, threshold 33 boundary/signs/gaps and threshold 361",received);
        $finish;
    end
endmodule
