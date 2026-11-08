`timescale 1ns/1ps
module tb_algo_polar_core;
    `include "algo7_delivery_math_ref.vh"
    localparam LATENCY = 25;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, de_in=0, hs_in=0, vs_in=0;
    reg [7:0] i0=0, i45=0, i90=0, i135=0;
    wire [7:0] dolp_out,aop_out;
    wire de_out,hs_out,vs_out;
    wire [7:0] zero_dolp,zero_aop;
    wire zero_de;
    algo_polar_core dut(.clk(clk),.rst_n(rst_n),.i0(i0),.i45(i45),.i90(i90),.i135(i135),
        .rgb0(24'd0),.rgb45(24'd0),.rgb90(24'd0),.rgb135(24'd0),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.dolp_out(dolp_out),.aop_out(aop_out),
        .rgb_unpol_out(),.y_unpol_out(),.de_out(de_out),.hs_out(hs_out),.vs_out(vs_out));
    algo_polar_core #(.DOLP_S0_MIN(0),.AOP_MAG_MIN(0)) no_guard(
        .clk(clk),.rst_n(rst_n),.i0(i0),.i45(i45),.i90(i90),.i135(i135),
        .rgb0(24'd0),.rgb45(24'd0),.rgb90(24'd0),.rgb135(24'd0),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.dolp_out(zero_dolp),.aop_out(zero_aop),
        .rgb_unpol_out(),.y_unpol_out(),.de_out(zero_de),.hs_out(),.vs_out());
    integer n=0,checks=0,k,angle,level,pol,random_seed=17429;
    integer check_anchor;
    integer ed[0:4095],ea[0:4095];
    reg [2:0] es[0:4095];
    real phi,p,b,s0f,s1f,s2f,magf,anglef;
    integer ideal_dolp,ideal_aop,float_error,max_float_dolp=0,max_float_aop=0;
    integer weak_aop_mismatch=0,effective_angle_count=0;
    function integer clamp8(input integer v);
        clamp8=(v<0)?0:((v>255)?255:v);
    endfunction
    task tick(input integer v0,v45,v90,v135,input d,h,v);
        integer ref_pair,rd,ra,delta;
        begin
            @(negedge clk);
            i0=v0; i45=v45; i90=v90; i135=v135;
            de_in=d; hs_in=h; vs_in=v;
            ref_pair=algo7_delivery_ref(v0[7:0],v45[7:0],v90[7:0],v135[7:0],16,8);
            rd=ref_pair[15:8]; ra=ref_pair[7:0];
            s0f=v0+v90;s1f=v0-v90;s2f=v45-v135;magf=$sqrt(s1f*s1f+s2f*s2f);
            ideal_dolp=(s0f<16 || s0f==0)?0:clamp8($rtoi(256.0*magf/s0f));
            anglef=0.5*$atan2(s2f,s1f);
            ideal_aop=(magf<8)?128:clamp8($rtoi((anglef+1.5707963267948966)*256.0/3.141592653589793+0.5));
            float_error=rd-ideal_dolp;if(float_error<0)float_error=-float_error;if(float_error>max_float_dolp)max_float_dolp=float_error;
            if(magf>=8.0) begin
                effective_angle_count=effective_angle_count+1;
                float_error=ra-ideal_aop;if(float_error>128)float_error=float_error-256;if(float_error< -128)float_error=float_error+256;
                if(float_error<0)float_error=-float_error;if(float_error>max_float_aop)max_float_aop=float_error;
            end else if(ra!=128) weak_aop_mismatch=weak_aop_mismatch+1;
            ed[n]=rd; ea[n]=ra; es[n]={d,h,v};
            @(posedge clk); #1;
            if(n>=LATENCY-1) begin
                k=n-(LATENCY-1);
                if({de_out,hs_out,vs_out}!==es[k])
                    $fatal(1,"sync index %0d got %b expected %b",k,{de_out,hs_out,vs_out},es[k]);
                if(es[k][2]) begin
                    if(dolp_out!==ed[k][7:0]) $fatal(1,"DoLP exact index %0d got %0d expected %0d",k,dolp_out,ed[k]);
                    if(aop_out!==ea[k][7:0]) $fatal(1,"AoP exact index %0d got %0d expected %0d",k,aop_out,ea[k]);
                    checks=checks+1;
                end
            end
            n=n+1;
        end
    endtask
    initial begin
        if(algo7_delivery_ref(8'd2,8'd11,8'd14,8'd5,16,8)!==16'hE9EE)
            $fatal(1,"frozen delivery anchor (2,11,14,5) must be 233/238");
        if(algo7_delivery_ref(8'd1,8'd10,8'd15,8'd6,16,8)!==16'hE6F3)
            $fatal(1,"frozen delivery anchor (1,10,15,6) must be 230/243");
        check_anchor=algo7_delivery_ref(8'd9,8'd5,8'd3,8'd1,16,8);
        if(check_anchor[7:0]!==8'd151)
            $fatal(1,"S1=6,S2=4 approximate AoP gate anchor must be 151 (got %h)",
                   algo7_delivery_ref(8'd9,8'd5,8'd3,8'd1,16,8));
        if(algo7_delivery_ref(8'd0,8'd0,8'd0,8'd0,16,8)!==16'h0080)
            $fatal(1,"zero vector anchor must be 0/128");
        repeat(3)@(negedge clk); rst_n=1;
        tick(100,100,100,100,1,1,0);
        tick(200,100,0,100,1,0,0);
        tick(100,200,100,0,1,0,0);
        tick(100,0,100,200,1,0,0);
        tick(0,100,200,100,1,0,0);
        tick(2,11,14,5,1,0,0); // frozen delivery anchor: 233/238
        tick(1,10,15,6,1,0,0); // frozen delivery anchor: 230/243
        tick(9,5,3,1,1,0,0);   // S1=6,S2=4: approximate magnitude gate => AoP 151
        tick(130,140,70,60,1,0,0);
        tick(7,7,7,7,1,0,0);
        tick(52,50,48,50,1,0,0);
        tick(255,255,0,0,1,0,0); // nonphysical, DoLP must saturate
        tick(0,0,0,0,1,0,0); // zero denominator
        for(level=16;level<=240;level=level+32)
            for(pol=0;pol<=4;pol=pol+1)
                for(angle=-90;angle<90;angle=angle+15)begin
                    phi=angle*3.141592653589793/180.0;p=pol/4.0;b=level/2.0;
                    tick(clamp8($rtoi(b*(1+p*$cos(2*phi))+0.5)),
                         clamp8($rtoi(b*(1+p*$sin(2*phi))+0.5)),
                         clamp8($rtoi(b*(1-p*$cos(2*phi))+0.5)),
                         clamp8($rtoi(b*(1-p*$sin(2*phi))+0.5)),1,angle==-90,0);
                    if(angle==0) tick(0,0,0,0,0,0,0);
                end
        repeat(1280)tick($random(random_seed)&255,$random(random_seed)&255,
                          $random(random_seed)&255,$random(random_seed)&255,1,0,0);
        repeat(LATENCY+2)tick(0,0,0,0,0,0,1);
        if(checks!=1773)$fatal(1,"missing outputs %0d expected 1773",checks);
        // Reset must remove all in-flight pixels, even during a dense stream.
        repeat(5)tick(200,100,0,100,1,0,0);
        @(negedge clk);rst_n=0;
        @(posedge clk);#1;
        if({de_out,hs_out,vs_out}!==0)$fatal(1,"reset did not clear timing");
        @(negedge clk);rst_n=1;de_in=0;hs_in=0;vs_in=0;
        repeat(LATENCY+2)begin
            @(posedge clk);#1;
            if(de_out!==0)$fatal(1,"reset leaked an old pixel");
        end
        @(negedge clk);i0=0;i45=0;i90=0;i135=0;de_in=1;
        repeat(LATENCY)begin @(posedge clk);#1;end
        if(zero_de!==1 || zero_dolp!==0 || zero_aop!==128)
            $fatal(1,"zero denominator must be safe with guard params=0: %0d/%0d",zero_dolp,zero_aop);
        $display("PASS tb_algo_polar_core: %0d vectors, delivery integer match; float max DoLP=%0d, effective-angle=%0d over %0d, weak AoP gate mismatches=%0d, 25 registers, reset",checks,max_float_dolp,max_float_aop,effective_angle_count,weak_aop_mismatch);
        $finish;
    end
endmodule
