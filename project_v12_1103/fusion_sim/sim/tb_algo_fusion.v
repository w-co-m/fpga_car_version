`timescale 1ns/1ps
module tb_algo_fusion;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg [23:0] rgb=0;
    reg [7:0] yy=0,dolp=0,aop=0,thr=0;
    reg vin=0,hs=0,vs=0;

    wire [23:0] rgb0,rgbh,rgbk0,rgb1,rgb1sat,rgb2;
    wire [7:0] y0,yh,yk0,y1,y1sat,y2,dp0,ap0;
    wire bin0,de0,hs0,vs0,deh,hsh,vsh;
    algo_fusion #(.FUSION_MODE(0),.K_DEF(64)) d0(
        .clk(clk),.rst_n(rst_n),.rgb_unpol_in(rgb),.y_unpol_in(yy),.dolp_in(dolp),.aop_in(aop),
        .vin(vin),.hs_in(hs),.vs_in(vs),.thr_in(thr),.rgb_out(rgb0),.y_out(y0),
        .dolp_out(dp0),.aop_out(ap0),.bin_out(bin0),.de_out(de0),.hs_out(hs0),.vs_out(vs0));
    algo_fusion #(.FUSION_MODE(0),.K_DEF(0)) dk0(
        .clk(clk),.rst_n(rst_n),.rgb_unpol_in(rgb),.y_unpol_in(yy),.dolp_in(dolp),.aop_in(aop),
        .vin(vin),.hs_in(hs),.vs_in(vs),.thr_in(thr),.rgb_out(rgbk0),.y_out(yk0),
        .dolp_out(),.aop_out(),.bin_out(),.de_out(),.hs_out(),.vs_out());
    algo_fusion #(.FUSION_MODE(0),.K_DEF(64),.AOP_HUE(1)) dh(
        .clk(clk),.rst_n(rst_n),.rgb_unpol_in(rgb),.y_unpol_in(yy),.dolp_in(dolp),.aop_in(aop),
        .vin(vin),.hs_in(hs),.vs_in(vs),.thr_in(thr),.rgb_out(rgbh),.y_out(yh),
        .dolp_out(),.aop_out(),.bin_out(),.de_out(deh),.hs_out(hsh),.vs_out(vsh));
    algo_fusion #(.FUSION_MODE(1)) d1(
        .clk(clk),.rst_n(rst_n),.rgb_unpol_in(rgb),.y_unpol_in(yy),.dolp_in(dolp),.aop_in(aop),
        .vin(vin),.hs_in(hs),.vs_in(vs),.thr_in(thr),.rgb_out(rgb1),.y_out(y1),
        .dolp_out(),.aop_out(),.bin_out(),.de_out(),.hs_out(),.vs_out());
    algo_fusion #(.FUSION_MODE(1),.W_RGB(255),.W_DOLP(255),.W_AOP(255)) d1sat(
        .clk(clk),.rst_n(rst_n),.rgb_unpol_in(rgb),.y_unpol_in(yy),.dolp_in(dolp),.aop_in(aop),
        .vin(vin),.hs_in(hs),.vs_in(vs),.thr_in(thr),.rgb_out(rgb1sat),.y_out(y1sat),
        .dolp_out(),.aop_out(),.bin_out(),.de_out(),.hs_out(),.vs_out());
    algo_fusion #(.FUSION_MODE(2)) d2(
        .clk(clk),.rst_n(rst_n),.rgb_unpol_in(rgb),.y_unpol_in(yy),.dolp_in(dolp),.aop_in(aop),
        .vin(vin),.hs_in(hs),.vs_in(vs),.thr_in(thr),.rgb_out(rgb2),.y_out(y2),
        .dolp_out(),.aop_out(),.bin_out(),.de_out(),.hs_out(),.vs_out());

    function integer clamp8(input integer x);
        begin if(x<0) clamp8=0; else if(x>255) clamp8=255; else clamp8=x; end
    endfunction
    function integer mode0(input integer y,d,k,inc);
        integer gain,v;
        begin
            if(k==0) k=64;
            gain=inc ? 256+(k*d)/128 : 256-(k*d)/128;
            v=(y*gain)/256;
            mode0=clamp8(v);
        end
    endfunction
    function integer mode0k0(input integer y,d,k,inc);
        integer gain,v;
        begin
            gain=inc ? 256+(k*d)/128 : 256-(k*d)/128;
            v=(y*gain)/256;
            mode0k0=clamp8(v);
        end
    endfunction
    function integer mode1(input integer y,d,a,wr,wd,wa);
        integer v;
        begin v=(wr*y+wd*d+wa*a)/256; mode1=clamp8(v); end
    endfunction
    function [23:0] keep_delta(input [23:0] c,input integer y,fy);
        integer delta;
        reg [7:0] r,g,b;
        begin
            delta=fy-y;
            r=clamp8(c[23:16]+delta); g=clamp8(c[15:8]+delta); b=clamp8(c[7:0]+delta);
            keep_delta={r,g,b};
        end
    endfunction
    function [23:0] wheel(input [7:0] a);
        integer q,t,r,g,b;
        begin
            q=a>>6; t=(a&63)<<2;
            case(q)
              0: begin r=255;g=t;b=0;end
              1: begin r=255-t;g=255;b=0;end
              2: begin r=0;g=255;b=t;end
              default: begin r=t;g=0;b=255;end
            endcase
            wheel={r[7:0],g[7:0],b[7:0]};
        end
    endfunction
    function [23:0] hue_rgb(input [7:0] a,input integer y);
        reg [23:0] h;
        reg [7:0] r,g,b;
        begin
            h=wheel(a); r=(h[23:16]*y)>>8; g=(h[15:8]*y)>>8; b=(h[7:0]*y)>>8;
            hue_rgb={r,g,b};
        end
    endfunction

    integer cyc=0,checks=0,errors=0,check_idx;
    integer stimulus_count=0,anchor_count=0,continuous_count=0,blank_count=0,tail_count=0;
    integer stim_i;
    integer q_y0[0:511],q_yh[0:511],q_yk0[0:511],q_y1[0:511],q_y1sat[0:511],q_y2[0:511];
    reg [23:0] q_rgb0[0:511],q_rgbh[0:511];
    reg [7:0] q_dp[0:511],q_ap[0:511];
    reg q_bin[0:511],q_de[0:511],q_hs[0:511],q_vs[0:511];
    always @(posedge clk) begin
        if(rst_n) begin
            q_y0[cyc]=mode0(yy,dolp,(thr[6:0]),thr[7]);
            q_yk0[cyc]=mode0k0(yy,dolp,(thr[6:0]),thr[7]);
            q_y1[cyc]=mode1(yy,dolp,aop,128,96,32);
            q_y1sat[cyc]=mode1(yy,dolp,aop,255,255,255);
            q_y2[cyc]=(yy>dolp)?yy:dolp;
            q_yh[cyc]=q_y0[cyc];
            q_rgb0[cyc]=keep_delta(rgb,yy,q_y0[cyc]);
            q_rgbh[cyc]=hue_rgb(aop,q_yh[cyc]);
            q_dp[cyc]=dolp; q_ap[cyc]=aop; q_bin[cyc]=(dolp>=128);
            q_de[cyc]=vin; q_hs[cyc]=hs; q_vs[cyc]=vs;
        end else begin
            q_y0[cyc]=0; q_yh[cyc]=0; q_yk0[cyc]=0; q_y1[cyc]=0; q_y1sat[cyc]=0; q_y2[cyc]=0;
            q_rgb0[cyc]=0; q_rgbh[cyc]=0; q_dp[cyc]=0; q_ap[cyc]=0; q_bin[cyc]=0;
            q_de[cyc]=0; q_hs[cyc]=0; q_vs[cyc]=0;
        end
        #1;
        if(cyc>0) begin
            check_idx=cyc-1; checks=checks+1;
            if(!rst_n) begin
                if(rgb0!==0 || y0!==0 || de0!==0 || hs0!==0 || vs0!==0) begin
                    errors=errors+1; $display("FAIL reset cycle outputs not clear");
                end
            end else begin
            if(y0!==q_y0[check_idx] || yh!==q_yh[check_idx] || yk0!==q_yk0[check_idx] || y1!==q_y1[check_idx] || y1sat!==q_y1sat[check_idx] || y2!==q_y2[check_idx]) begin
                errors=errors+1; $display("FAIL cycle=%0d Y outputs got %0d/%0d/%0d/%0d/%0d/%0d",cyc,y0,yh,yk0,y1,y1sat,y2);
            end
            if(rgb0!==q_rgb0[check_idx] || rgbh!==q_rgbh[check_idx]) begin
                errors=errors+1; $display("FAIL cycle=%0d RGB got %06h/%06h expected %06h/%06h",cyc,rgb0,rgbh,q_rgb0[check_idx],q_rgbh[check_idx]);
            end
            if(dp0!==q_dp[check_idx] || ap0!==q_ap[check_idx] || bin0!==q_bin[check_idx]) begin
                errors=errors+1; $display("FAIL cycle=%0d pass-through/mask",cyc);
            end
            if({de0,hs0,vs0}!=={q_de[check_idx],q_hs[check_idx],q_vs[check_idx]} || {deh,hsh,vsh}!=={q_de[check_idx],q_hs[check_idx],q_vs[check_idx]}) begin
                errors=errors+1; $display("FAIL cycle=%0d sync got %b expected %b",cyc,{de0,hs0,vs0},{q_de[check_idx],q_hs[check_idx],q_vs[check_idx]});
            end
            end
        end
        cyc=cyc+1;
    end

    task send(input [23:0] c,input [7:0] y,d,a,k,input incv,input v,h,vsx);
        begin
            @(negedge clk); rgb=c;yy=y;dolp=d;aop=a;thr={incv,k[6:0]};vin=v;hs=h;vs=vsx;
            stimulus_count=stimulus_count+1;
        end
    endtask
    task hand_send(input [23:0] c,input [7:0] y,d,a,k,input incv,input v,h,vsx,
                   input [7:0] e0,ek0,e1,e1sat,e2,input [23:0] ehue);
        begin
            send(c,y,d,a,k,incv,v,h,vsx);
            @(posedge clk); @(posedge clk); #1;
            if(y0!==e0 || yk0!==ek0 || y1!==e1 || y1sat!==e1sat || y2!==e2 || rgbh!==ehue) begin
                errors=errors+1;
                $display("FAIL hand anchor y=%0d dolp=%0d K=%0d inc=%0d",y,d,k,incv);
            end
            anchor_count=anchor_count+1;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        // Explicit boundaries: zero and maximum DoLP, K fallback/127, both polarities,
        // default K_DEF=0, weighted saturation, and hue output.
        hand_send(24'hC89664,100,0,0,64,0,1,0,1,100,100,50,99,100,24'h630000);
        hand_send(24'hC89664,100,255,64,64,0,1,1,1,50,50,153,255,255,24'h313100);
        hand_send(24'hFF8040,100,255,128,127,0,1,0,1,1,1,161,255,255,24'h000000);
        hand_send(24'h40C0FF,100,255,192,64,1,1,1,1,149,149,169,255,255,24'h000094);
        hand_send(24'hFFFFFF,250,255,0,64,1,1,0,1,255,255,220,255,255,24'hFE0000);
        hand_send(24'h808080,120,200,90,0,0,1,0,1,73,120,146,255,200,24'h2B4800);
        send(24'h204060,80,255,200,127,0,1,0,1);
        // Continuous pixels with per-pixel threshold/sync changes, then blank gaps.
        for(stim_i=0;stim_i<40;stim_i=stim_i+1) begin
            send({stim_i[7:0],(255-stim_i),stim_i[7:0]^8'h5A},30+(stim_i*7),stim_i*19,stim_i*37,(stim_i*11),stim_i[0],1,(stim_i%3)==0,(stim_i%11)==0);
            continuous_count=continuous_count+1;
        end
        for(stim_i=0;stim_i<8;stim_i=stim_i+1) begin
            send(24'h123456,200,255,255,stim_i,stim_i[0],0,(stim_i%2),0);
            blank_count=blank_count+1;
        end
        send(24'h80A0C0,140,255,128,127,0,1,1,1);
        // Assert reset between transactions and prove the asynchronous outputs clear.
        @(negedge clk); rst_n=0; vin=1; hs=1; vs=1;
        #1;
        if(rgb0!==0 || y0!==0 || de0!==0 || hs0!==0 || vs0!==0) begin errors=errors+1; $display("FAIL asynchronous reset clear"); end
        repeat(2) @(negedge clk);
        rst_n=1;
        send(24'hAA5500,90,255,17,0,1,1,1,0);
        for(stim_i=0;stim_i<4;stim_i=stim_i+1) begin
            send(24'h010203,255,stim_i*85,stim_i*63,0,0,(stim_i==0),0,(stim_i==0));
            tail_count=tail_count+1;
        end
        repeat(4) @(negedge clk);
        $display("[tb_algo_fusion] stimuli=%0d anchors=%0d continuous=%0d blank=%0d tail=%0d checks=%0d",stimulus_count,anchor_count,continuous_count,blank_count,tail_count,checks);
        if(errors==0 && stimulus_count==61 && anchor_count==6 && continuous_count==40 && blank_count==8 && tail_count==4 && checks==76)
            $display("[tb_algo_fusion] PASS checks=%0d errors=0",checks);
        else begin errors=errors+1; $display("[tb_algo_fusion] FAIL counts/checks/errors=%0d/%0d/%0d",stimulus_count,checks,errors); end
        $finish;
    end
endmodule
