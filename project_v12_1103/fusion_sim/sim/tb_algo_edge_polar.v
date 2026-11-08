`timescale 1ns/1ps

module tb_algo_edge_polar;
    localparam W = 24;
    localparam H = 6;
    localparam NPIX = 4*W*H;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [7:0] y_in = 0, dolp_in = 0, thr_in = 0;
    reg vin = 0, hs_in = 0, vs_in = 0;

    wire [23:0] rgb0, rgb_lum, rgb_max, rgb_red, rgb_inv, rgb_zero, rgb_wd0;
    wire [7:0] y0, ey0, ed0, y_lum, ey_lum, ed_lum, y_max, ey_max, ed_max;
    wire [7:0] y_red, ey_red, ed_red, y_inv, ey_inv, ed_inv, y_zero, ey_zero, ed_zero;
    wire [7:0] y_wd0, ey_wd0, ed_wd0;
    wire bin0, bin_lum, bin_max, bin_red, bin_inv, bin_zero, bin_wd0;
    wire de0, de_lum, de_max, de_red, de_inv, de_zero, de_wd0;
    wire hs0, hs_lum, hs_max, hs_red, hs_inv, hs_zero, hs_wd0;
    wire vs0, vs_lum, vs_max, vs_red, vs_inv, vs_zero, vs_wd0;

    algo_edge_polar #(.LB_W(W),.LB_DEPTH(32),.LB_AW(5)) u_default
      (clk,rst_n,y_in,dolp_in,vin,hs_in,vs_in,thr_in,rgb0,y0,ey0,ed0,bin0,de0,hs0,vs0);
    algo_edge_polar #(.EDGE_MODE(0),.LB_W(W),.LB_DEPTH(32),.LB_AW(5)) u_lum
      (clk,rst_n,y_in,dolp_in,vin,hs_in,vs_in,thr_in,rgb_lum,y_lum,ey_lum,ed_lum,bin_lum,de_lum,hs_lum,vs_lum);
    algo_edge_polar #(.FUSE_MODE(1),.LB_W(W),.LB_DEPTH(32),.LB_AW(5)) u_max
      (clk,rst_n,y_in,dolp_in,vin,hs_in,vs_in,thr_in,rgb_max,y_max,ey_max,ed_max,bin_max,de_max,hs_max,vs_max);
    algo_edge_polar #(.W_RGB(8'd255),.W_DOLP(8'd255),.LB_W(W),.LB_DEPTH(32),.LB_AW(5)) u_red
      (clk,rst_n,y_in,dolp_in,vin,hs_in,vs_in,thr_in,rgb_red,y_red,ey_red,ed_red,bin_red,de_red,hs_red,vs_red);
    algo_edge_polar #(.EDGE_INV(1),.LB_W(W),.LB_DEPTH(32),.LB_AW(5)) u_inv
      (clk,rst_n,y_in,dolp_in,vin,hs_in,vs_in,thr_in,rgb_inv,y_inv,ey_inv,ed_inv,bin_inv,de_inv,hs_inv,vs_inv);
    algo_edge_polar #(.BORDER(0),.LB_W(W),.LB_DEPTH(32),.LB_AW(5)) u_zero
      (clk,rst_n,y_in,dolp_in,vin,hs_in,vs_in,thr_in,rgb_zero,y_zero,ey_zero,ed_zero,bin_zero,de_zero,hs_zero,vs_zero);
    algo_edge_polar #(.W_DOLP(8'd0),.LB_W(W),.LB_DEPTH(32),.LB_AW(5)) u_wd0
      (clk,rst_n,y_in,dolp_in,vin,hs_in,vs_in,thr_in,rgb_wd0,y_wd0,ey_wd0,ed_wd0,bin_wd0,de_wd0,hs_wd0,vs_wd0);

    integer phase = 0;
    integer out_count = 0;
    integer rgb_only_edges = 0, dolp_only_edges = 0, saturated_samples = 0;
    reg qv0 = 0, qv1 = 0, qh0 = 0, qh1 = 0, qs0 = 0, qs1 = 0;
    reg [7:0] qthr0 = 0, qthr1 = 0;
    reg [7:0] qy0=0, qey0=0, qed0=0, qyl=0, qeyl=0, qedl=0;
    reg [7:0] qym=0, qeym=0, qedm=0, qyr=0, qeyr=0, qedr=0;
    reg [7:0] qyi=0, qeyi=0, qedi=0, qyz=0, qeyz=0, qedz=0;
    reg [7:0] qyw=0, qeyw=0, qedw=0;
    reg [7:0] qy0_d1=0, qey0_d1=0, qed0_d1=0, qyl_d1=0, qeyl_d1=0, qedl_d1=0;
    reg [7:0] qym_d1=0, qeym_d1=0, qedm_d1=0, qyr_d1=0, qeyr_d1=0, qedr_d1=0;
    reg [7:0] qyi_d1=0, qeyi_d1=0, qedi_d1=0, qyz_d1=0, qeyz_d1=0, qedz_d1=0;
    reg [7:0] qyw_d1=0, qeyw_d1=0, qedw_d1=0;
    reg [7:0] dense_y [0:NPIX-1], dense_ey [0:NPIX-1], dense_ed [0:NPIX-1];
    reg dense_bin [0:NPIX-1];

    function integer pix_y;
        input integer f, r, c;
        begin
            case (f)
              0: pix_y = (c < 8) ? 20 : 220;
              1: pix_y = 80;
              2: pix_y = (r*47 + c*73 + r*c*13 + 19) & 255;
              default: begin
                if (r < 3 && c < 3) begin
                    if ((r==0 && c>=1) || (r==1 && c==2)) pix_y=255;
                    else pix_y=0;
                end else pix_y = ((r<3) ^ (c<8)) ? 255 : 0;
              end
            endcase
        end
    endfunction

    function integer pix_d;
        input integer f, r, c;
        begin
            case (f)
              0: pix_d = 80;
              1: pix_d = (r < 3) ? 10 : 240;
              2: pix_d = (r*91 + c*23 + 77) & 255;
              default: pix_d = pix_y(f,r,c);
            endcase
        end
    endfunction

    function integer sample;
        input integer f, r, c, ch, border;
        integer rr, cc;
        begin
            rr=r; cc=c;
            if (rr<0 || cc<0) begin
                if (!border) sample=0;
                else begin
                    if (rr<0) rr=0;
                    if (cc<0) cc=0;
                    sample = ch ? pix_d(f,rr,cc) : pix_y(f,rr,cc);
                end
            end else sample = ch ? pix_d(f,rr,cc) : pix_y(f,rr,cc);
        end
    endfunction

    function integer sobel8;
        input integer f, r, c, ch, border;
        integer gx, gy, a;
        begin
            gx = sample(f,r-2,c,ch,border) + 2*sample(f,r-1,c,ch,border) + sample(f,r,c,ch,border)
               - sample(f,r-2,c-2,ch,border) - 2*sample(f,r-1,c-2,ch,border) - sample(f,r,c-2,ch,border);
            gy = sample(f,r-2,c-2,ch,border) + 2*sample(f,r-2,c-1,ch,border) + sample(f,r-2,c,ch,border)
               - sample(f,r,c-2,ch,border) - 2*sample(f,r,c-1,ch,border) - sample(f,r,c,ch,border);
            if (gx<0) gx=-gx;
            if (gy<0) gy=-gy;
            a=(gx+gy)>>3;
            sobel8 = (a>255) ? 255 : a;
        end
    endfunction

    function integer weighted;
        input integer a,b,wr,wd;
        integer n;
        begin
            n=a*wr+b*wd;
            n=n>>8;
            weighted=(n>255) ? 255 : n;
        end
    endfunction

    task fail;
        input [8*180-1:0] message;
        begin $display("FAIL: %0s at time %0t",message,$time); $fatal(1); end
    endtask

    task tick;
        input v, h, s;
        input integer f, r, c;
        input [7:0] blank_thr;
        integer ey, ed, eyz, edz, fused, fusedz, fusedm, fusedr, fusedw;
        integer binexp, bininvexp;
        reg [7:0] cy, cd, ct;
        begin
            @(negedge clk);
            vin=v; hs_in=h; vs_in=s;
            if (v) begin
                cy=pix_y(f,r,c); cd=pix_d(f,r,c);
                ct=(f*37 + r*29 + c*17 + 11) & 255;
                y_in=cy; dolp_in=cd; thr_in=ct;
                ey=sobel8(f,r,c,0,1); ed=sobel8(f,r,c,1,1);
                eyz=sobel8(f,r,c,0,0); edz=sobel8(f,r,c,1,0);
                fused=weighted(ey,ed,192,64);
                fusedz=weighted(eyz,edz,192,64);
                fusedm=(ey>ed)?ey:ed;
                fusedr=weighted(ey,ed,255,255);
                fusedw=weighted(ey,ed,192,0);
                binexp=(fused>=ct); bininvexp=(fused<ct);
                if (f==0 && ed==0 && ey>0) rgb_only_edges=rgb_only_edges+1;
                if (f==1 && ey==0 && ed>0) dolp_only_edges=dolp_only_edges+1;
                if (f==3 && r==2 && c==2 && fusedr==255) saturated_samples=saturated_samples+1;
            end else begin
                cy=0; cd=0; ct=blank_thr; y_in=8'hA5; dolp_in=8'h5A; thr_in=blank_thr;
                ey=0; ed=0; eyz=0; edz=0; fused=0; fusedz=0; fusedm=0; fusedr=0; fusedw=0;
                binexp=0; bininvexp=0;
            end
            @(posedge clk); #1;
            if (de0 !== qv1 || de_lum !== qv1 || de_max !== qv1 || de_red !== qv1 || de_inv !== qv1 || de_zero !== qv1 || de_wd0 !== qv1) fail("valid delay");
            if (hs0 !== qh1 || hs_lum !== qh1 || hs_max !== qh1 || hs_red !== qh1 || hs_inv !== qh1 || hs_zero !== qh1 || hs_wd0 !== qh1) fail("HS pulse delay");
            if (vs0 !== qs1 || vs_lum !== qs1 || vs_max !== qs1 || vs_red !== qs1 || vs_inv !== qs1 || vs_zero !== qs1 || vs_wd0 !== qs1) fail("VS must remain a one-cycle pulse with matching delay");
            if (qv1) begin
                if (y0!==qy0_d1 || ey0!==qey0_d1 || ed0!==qed0_d1 || bin0!== (qy0_d1>=qthr1) || rgb0!==((qy0_d1>=qthr1)?24'hFFFFFF:24'h000000)) fail("default weighted output");
                if (y_lum!==qyl_d1 || ey_lum!==qeyl_d1 || ed_lum!==0 || bin_lum!==(qyl_d1>=qthr1)) fail("EDGE_MODE=0 direct brightness edge");
                if (y_max!==qym_d1 || ey_max!==qeym_d1 || ed_max!==qedm_d1 || bin_max!==(qym_d1>=qthr1)) fail("FUSE_MODE=max");
                if (y_red!==qyr_d1 || ey_red!==qeyr_d1 || ed_red!==qedr_d1 || bin_red!==(qyr_d1>=qthr1)) fail("17-bit RED weighted saturation");
                if (y_inv!==qyi_d1 || bin_inv!==(qyi_d1<qthr1)) fail("EDGE_INV");
                if (y_zero!==qyz_d1 || ey_zero!==qeyz_d1 || ed_zero!==qedz_d1 || bin_zero!==(qyz_d1>=qthr1)) begin
                    $display("zero-border phase=%0d out=%0d input=(%0d,%0d,%0d) actual y/ey/ed/bin=%0d/%0d/%0d/%0d expected=%0d/%0d/%0d thr=%0d",phase,out_count,f,r,c,y_zero,ey_zero,ed_zero,bin_zero,qyz_d1,qeyz_d1,qedz_d1,qthr1);
                    $display("zero pY=%0d,%0d,%0d/%0d,%0d,%0d/%0d,%0d,%0d row=%0d col=%0d",u_zero.q00[15:8],u_zero.q01[15:8],u_zero.q02[15:8],u_zero.q10[15:8],u_zero.q11[15:8],u_zero.q12[15:8],u_zero.q20[15:8],u_zero.q21[15:8],u_zero.q22[15:8],u_zero.u_lb.row_idx,u_zero.u_lb.xc);
                    fail("zero border");
                end
                if (y_wd0!==qyw_d1 || ey_wd0!==qeyw_d1 || ed_wd0!==qedw_d1 || bin_wd0!==(qyw_d1>=qthr1)) fail("W_DOLP=0 weighted equation");
                if (phase==0) begin
                    dense_y[out_count]=y0; dense_ey[out_count]=ey0; dense_ed[out_count]=ed0; dense_bin[out_count]=bin0;
                end else if (out_count>=NPIX || y0!==dense_y[out_count] || ey0!==dense_ey[out_count] || ed0!==dense_ed[out_count] || bin0!==dense_bin[out_count]) fail("sparse stream differs from dense stream");
                out_count=out_count+1;
            end
            qv1=qv0; qh1=qh0; qs1=qs0; qthr1=qthr0;
            qy0_d1=qy0; qey0_d1=qey0; qed0_d1=qed0;
            qyl_d1=qyl; qeyl_d1=qeyl; qedl_d1=qedl;
            qym_d1=qym; qeym_d1=qeym; qedm_d1=qedm;
            qyr_d1=qyr; qeyr_d1=qeyr; qedr_d1=qedr;
            qyi_d1=qyi; qeyi_d1=qeyi; qedi_d1=qedi;
            qyz_d1=qyz; qeyz_d1=qeyz; qedz_d1=qedz;
            qyw_d1=qyw; qeyw_d1=qeyw; qedw_d1=qedw;
            qy0=fused; qey0=ey; qed0=ed;
            qyl=ey; qeyl=ey; qedl=0;
            qym=fusedm; qeym=ey; qedm=ed;
            qyr=fusedr; qeyr=ey; qedr=ed;
            qyi=fused; qeyi=ey; qedi=ed;
            qyz=fusedz; qeyz=eyz; qedz=edz;
            qyw=fusedw; qeyw=ey; qedw=ed;
            qv0=v; qh0=h; qs0=s; qthr0=ct;
        end
    endtask

    task reset_dut;
        begin
            @(negedge clk); rst_n=0; vin=0; hs_in=0; vs_in=0; y_in=0; dolp_in=0; thr_in=0;
            qv0=0; qv1=0; qh0=0; qh1=0; qs0=0; qs1=0; qthr0=0; qthr1=0; out_count=0;
            repeat (3) @(posedge clk);
            @(negedge clk); rst_n=1;
        end
    endtask

    task run_phase;
        input integer gap_mode;
        integer f,r,c,gap,k;
        begin
            phase=gap_mode;
            reset_dut();
            for (f=0; f<4; f=f+1) begin
                tick(0,0,1,f,0,0,8'hC3); // VS frame pulse
                tick(0,0,0,f,0,0,8'h11); // required VS-to-HS blank cycle
                for (r=0; r<H; r=r+1) begin
                    tick(0,1,0,f,r,0,8'hE7); // HS leads first pixel by one cycle
                    for (c=0; c<W; c=c+1) begin
                        if (c>0) begin
                            if (gap_mode==1) gap=3;
                            else if (gap_mode==2 && c>=16) gap=(f*3+r*5+c*7)%8;
                            else gap=0;
                            for (k=0; k<gap; k=k+1) tick(0,0,0,f,r,c,((f*13+r*9+c*3+k)&255));
                        end
                        tick(1,0,0,f,r,c,0);
                    end
                    tick(0,0,0,f,r,W-1,8'h69);
                end
                repeat (3) tick(0,0,0,f,H-1,W-1,8'hD2);
            end
            repeat (4) tick(0,0,0,3,H-1,W-1,8'h27);
            if (out_count != NPIX) begin $display("phase %0d got %0d pixels, expected %0d",gap_mode,out_count,NPIX); $fatal(1); end
        end
    endtask

    initial begin
        run_phase(0);
        run_phase(1);
        run_phase(2);
        if (rgb_only_edges==0 || dolp_only_edges==0 || saturated_samples==0) fail("coverage for independent edges and RED saturation");
        $display("PASS: algo_edge_polar golden model, 3 stream schedules, frames/borders/fusion/threshold/VS");
        $finish;
    end
endmodule
