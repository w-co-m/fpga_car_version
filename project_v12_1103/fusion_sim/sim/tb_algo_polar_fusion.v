`timescale 1ns/1ps
module tb_algo_polar_fusion;
`include "algo7_delivery_math_ref.vh"
reg clk=0;always #5 clk=~clk;
reg rst_n=0,de=0,hs=0,vs=0;
reg [7:0] i0=0,i45=0,i90=0,i135=0,thr=0;
reg [23:0] c0=0,c45=0,c90=0,c135=0;
wire [23:0] polar_rgb,rgb;
wire [7:0] polar_y,polar_dolp,polar_aop,y,dolp,aop;
wire pd,ph,pv,fd,fh,fv,bin;
algo_polar_fusion dut(.clk(clk),.rst_n(rst_n),.i0(i0),.i45(i45),.i90(i90),.i135(i135),
 .rgb0(c0),.rgb45(c45),.rgb90(c90),.rgb135(c135),.de_in(de),.hs_in(hs),.vs_in(vs),.thr_in(thr),
 .polar_rgb_out(polar_rgb),.polar_y_out(polar_y),.polar_dolp_out(polar_dolp),.polar_aop_out(polar_aop),
 .polar_de_out(pd),.polar_hs_out(ph),.polar_vs_out(pv),
 .rgb_out(rgb),.y_out(y),.dolp_out(dolp),.aop_out(aop),.bin_out(bin),.de_out(fd),.hs_out(fh),.vs_out(fv));
integer er[0:1023],ey[0:1023],ep[0:1023],ea[0:1023],fr[0:1023],fy[0:1023];
integer ek[0:1023],measured_dp[0:1023],measured_ap[0:1023];
reg [2:0] sync[0:1023];
integer n=0,pc=0,fc=0,j,seed=51897,k,gain,target,delta;
function integer sat(input integer x);begin sat=x<0?0:x>255?255:x;end endfunction
task sample(input integer a,b,c,d,input integer q0,q45,q90,q135,input integer param_k,input valid,h,v);
integer ar,ag,ab,refy,refp,refa,kk,ref_pair;
begin
 @(negedge clk);i0=a;i45=b;i90=c;i135=d;c0=q0;c45=q45;c90=q90;c135=q135;thr=param_k;de=valid;hs=h;vs=v;
 // Independent floating reference includes intermediate DoLP and non-axis AoP.
 ar=(((q0>>16)&255)+((q45>>16)&255)+((q90>>16)&255)+((q135>>16)&255))/4;
 ag=(((q0>>8)&255)+((q45>>8)&255)+((q90>>8)&255)+((q135>>8)&255))/4;
 ab=((q0&255)+(q45&255)+(q90&255)+(q135&255))/4;
 refy=(a+c)/2;
 ref_pair=algo7_delivery_ref(a[7:0],b[7:0],c[7:0],d[7:0],16,8);
 refp=ref_pair[15:8];refa=ref_pair[7:0];
 ek[n]=param_k;
 er[n]=(ar<<16)|(ag<<8)|ab;ey[n]=refy;ep[n]=refp;ea[n]=refa;sync[n]={valid,h,v};
 kk=param_k&127;if(kk==0)kk=64;
 gain=(param_k&128)?256+(kk*refp/128):256-(kk*refp/128);
 target=sat(refy*gain/256);delta=target-refy;
 fr[n]=(sat(ar+delta)<<16)|(sat(ag+delta)<<8)|sat(ab+delta);fy[n]=target;
 @(posedge clk);#1;
 if(n>=24)begin
  j=n-24;
  if({pd,ph,pv}!==sync[j])$fatal(1,"polar timing index %0d",j);
  if(sync[j][2])begin
   if(polar_rgb!==er[j] || polar_y!==ey[j] || polar_dolp!==ep[j][7:0] || polar_aop!==ea[j][7:0])
     $fatal(1,"polar RGB/intensity alignment index=%0d got=%h/%0d/%0d/%0d expected=%h/%0d/%0d/%0d",j,polar_rgb,polar_y,polar_dolp,polar_aop,er[j],ey[j],ep[j],ea[j]);
   // Fusion consumes the actual quantized DoLP value (core tolerance is1 LSB).
   // Compute the fusion expectation independently from that value and the input
   // RGB average, then require an exact result two stages later.
   measured_dp[j]=polar_dolp;measured_ap[j]=polar_aop;
   kk=ek[j]&127;if(kk==0)kk=64;
   gain=(ek[j]&128)?256+(kk*polar_dolp/128):256-(kk*polar_dolp/128);
   target=sat(ey[j]*gain/256);delta=target-ey[j];
   fr[j]=(sat((er[j]>>16)+delta)<<16)|(sat(((er[j]>>8)&255)+delta)<<8)|sat((er[j]&255)+delta);fy[j]=target;
   pc=pc+1;
  end
 end
 if(n>=26)begin
  j=n-26;
  if({fd,fh,fv}!==sync[j])$fatal(1,"fusion timing index %0d",j);
  if(sync[j][2])begin
   if(rgb!==fr[j] || y!==fy[j] || dolp!==measured_dp[j] || aop!==measured_ap[j] || bin!==(measured_dp[j]>=128))
     $fatal(1,"fusion pixel/threshold index=%0d rgb=%h expected=%h y=%0d expected=%0d",j,rgb,fr[j],y,fy[j]);
   fc=fc+1;
  end
 end
 n=n+1;
end endtask
initial begin
 repeat(3)@(negedge clk);rst_n=1;
 for(k=0;k<256;k=k+1)begin
  case(k%5)
   0: sample(100,100,100,100,$random(seed),$random(seed),$random(seed),$random(seed),k,1,k%17==0,k%23==0);
   1: sample(200,100,0,100,$random(seed),$random(seed),$random(seed),$random(seed),k,1,k%17==0,k%23==0);
   2: sample(220,110,0,110,$random(seed),$random(seed),$random(seed),$random(seed),k,1,k%17==0,k%23==0);
   3: sample(64,96,64,32,$random(seed),$random(seed),$random(seed),$random(seed),k,1,k%17==0,k%23==0);
   4: sample(96,80,32,48,$random(seed),$random(seed),$random(seed),$random(seed),k,1,k%17==0,k%23==0);
  endcase
  if(k%7==0)sample(0,0,0,0,0,0,0,0,0,0,0,1);
 end
 repeat(28)sample(0,0,0,0,0,0,0,0,0,0,1,0);
 if(pc!=256 || fc!=256)$fatal(1,"lost pixels polar=%0d fusion=%0d",pc,fc);
 // Reset after fewer than25 samples must cancel every pixel in flight.
 repeat(8)sample(100,100,100,100,0,0,0,0,0,1,0,0);
 @(negedge clk);rst_n=0;@(posedge clk);#1;
 if({pd,ph,pv,fd,fh,fv}!==0 || polar_rgb!==0 || rgb!==0)$fatal(1,"reset failed");
 @(negedge clk);rst_n=1;de=0;hs=0;vs=0;
 repeat(28)begin @(posedge clk);#1;if(pd || fd)$fatal(1,"reset leaked pixel");end
 $display("PASS tb_algo_polar_fusion: 256 RGB tuples, 25/27 registers, per-pixel threshold, gaps, sync and reset");$finish;
end
endmodule
