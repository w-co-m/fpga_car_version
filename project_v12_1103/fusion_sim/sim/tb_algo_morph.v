`timescale 1ns/1ps

module tb_algo_morph;
    reg clk=0, rst_n=0;
    reg [23:0] rgb_in=0;
    reg de_in=0, hs_in=0, vs_in=0;
    reg [7:0] thr_in=0;
    always #5 clk=~clk;

    wire [23:0] rgb_g, rgb_b, rgb_c, rgb_f, rgb_d;
    wire [7:0] y_g, y_b, y_c, y_f, y_d;
    wire bin_g, bin_b, bin_c, bin_f, bin_d;
    wire de_g, de_b, de_c, de_f, de_d;
    wire hs_g, hs_b, hs_c, hs_f, hs_d;
    wire vs_g, vs_b, vs_c, vs_f, vs_d;

    algo_morph #(.LB_W(6),.LB_DEPTH(8),.LB_AW(3)) u_gray
      (clk,rst_n,rgb_in,de_in,hs_in,vs_in,thr_in,rgb_g,y_g,bin_g,de_g,hs_g,vs_g);
    algo_morph #(.BIN_INPUT(1),.LB_W(6),.LB_DEPTH(8),.LB_AW(3)) u_binary
      (clk,rst_n,rgb_in,de_in,hs_in,vs_in,thr_in,rgb_b,y_b,bin_b,de_b,hs_b,vs_b);
    algo_morph #(.SE_CROSS(1),.LB_W(6),.LB_DEPTH(8),.LB_AW(3)) u_cross
      (clk,rst_n,rgb_in,de_in,hs_in,vs_in,thr_in,rgb_c,y_c,bin_c,de_c,hs_c,vs_c);
    algo_morph #(.OP_FROM_THR(0),.MORPH_OP(0),.LB_W(6),.LB_DEPTH(8),.LB_AW(3)) u_fixed_erode
      (clk,rst_n,rgb_in,de_in,hs_in,vs_in,thr_in,rgb_f,y_f,bin_f,de_f,hs_f,vs_f);
    algo_morph #(.OP_FROM_THR(0),.MORPH_OP(1),.LB_W(6),.LB_DEPTH(8),.LB_AW(3)) u_fixed_dilate
      (clk,rst_n,rgb_in,de_in,hs_in,vs_in,thr_in,rgb_d,y_d,bin_d,de_d,hs_d,vs_d);

    localparam W=6, H=5, LATENCY=3, MAX_CYCLES=1024;
    integer exp_valid[0:MAX_CYCLES-1];
    integer exp_y_gray[0:MAX_CYCLES-1], exp_y_bin[0:MAX_CYCLES-1];
    integer exp_y_cross[0:MAX_CYCLES-1], exp_y_fixed[0:MAX_CYCLES-1], exp_y_dilate[0:MAX_CYCLES-1];
    integer exp_de[0:MAX_CYCLES-1], exp_hs[0:MAX_CYCLES-1], exp_vs[0:MAX_CYCLES-1];
    integer cycle=0, checks=0, i, errors=0;
    integer stim_frame=0, stim_row=0, stim_col=0;

    function [23:0] pixel_at;
        input integer frame,row,col;
        integer r,g,b;
        begin
            r=(frame*37+row*53+col*19)&255;
            g=(frame*73+row*29+col*61)&255;
            b=(frame*11+row*47+col*7)&255;
            pixel_at={r[7:0],g[7:0],b[7:0]};
        end
    endfunction
    function integer gray_at;
        input integer frame,row,col;
        reg [23:0] p;
        begin
            p=pixel_at(frame,row,col);
            gray_at=(p[23:16]*77+p[15:8]*150+p[7:0]*29+128)>>8;
        end
    endfunction
    function integer thr_at;
        input integer frame,row,col;
        begin thr_at=(frame*47+row*31+col*23)&255; end
    endfunction
    function integer morph_at;
        input integer frame,row,col,bin_mode,cross_mode,fixed_mode;
        integer dy,dx,ny,nx,value,acc,op,selected;
        begin
            op=(fixed_mode==1) ? 0 : (fixed_mode==2) ? 1 : (thr_at(frame,row,col)&1);
            acc=op ? 0 : 255;
            for (dy=0;dy<3;dy=dy+1) begin
                for (dx=0;dx<3;dx=dx+1) begin
                    selected=(!cross_mode) || (dy==1) || (dx==1);
                    if (selected) begin
                        ny=row+dy-2; nx=col+dx-2;
                        if(ny<0) ny=0; if(ny>=H) ny=H-1;
                        if(nx<0) nx=0; if(nx>=W) nx=W-1;
                        value=gray_at(frame,ny,nx);
                        if(bin_mode) value=(value >= ((thr_at(frame,ny,nx)>>1)<<1)) ? 255 : 0;
                        if(op) begin if(value>acc) acc=value; end
                        else begin if(value<acc) acc=value; end
                    end
                end
            end
            morph_at=acc;
        end
    endfunction

    task idle_cycles;
        input integer count;
        integer k;
        begin
            for(k=0;k<count;k=k+1) begin
                @(negedge clk); de_in=0; hs_in=(k&1); vs_in=0; thr_in=k;
            end
        end
    endtask
    task send_frame;
        input integer frame;
        integer row,col;
        begin
            @(negedge clk); de_in=0; hs_in=0; vs_in=1; thr_in=0;
            @(negedge clk); vs_in=0;
            for(row=0;row<H;row=row+1) begin
                for(col=0;col<W;col=col+1) begin
                @(negedge clk);
                    stim_frame=frame; stim_row=row; stim_col=col;
                    rgb_in=pixel_at(frame,row,col); de_in=1;
                    hs_in=(col==0); thr_in=thr_at(frame,row,col);
                end
                @(negedge clk); de_in=0; hs_in=0; thr_in=8'hd3;
                @(negedge clk); de_in=0; hs_in=0;
            end
            idle_cycles(5);
        end
    endtask

    initial begin
        for(i=0;i<MAX_CYCLES;i=i+1) begin
            exp_valid[i]=0; exp_y_gray[i]=0; exp_y_bin[i]=0;
            exp_y_cross[i]=0; exp_y_fixed[i]=0; exp_y_dilate[i]=0;
            exp_de[i]=0; exp_hs[i]=0; exp_vs[i]=0;
        end
        repeat(3) @(negedge clk);
        rst_n=1;
        send_frame(0);

        // Reset while idle between frames; line memories are intentionally not reset,
        // so the next active VS must re-establish frame/edge state.
        @(negedge clk); rst_n=0; de_in=0; hs_in=0; vs_in=0;
        repeat(3) @(negedge clk);
        rst_n=1;
        send_frame(1);
        idle_cycles(8);
        @(negedge clk); rst_n=0;
        repeat(3) @(negedge clk);
        if(errors==0) $display("PASS: %0d active pixels checked across gray, binary, cross, fixed erode/dilate, controls and reset",checks);
        else $display("FAIL: %0d mismatches across %0d active pixels",errors,checks);
        $finish;
    end

    always @(posedge clk) begin
        if(cycle+LATENCY>=MAX_CYCLES) begin
            $display("FAIL: scoreboard capacity exceeded"); $finish;
        end
        if(!rst_n) begin
            exp_valid[cycle]=0; exp_valid[cycle+1]=0;
            exp_valid[cycle+2]=0; exp_valid[cycle+3]=0;
        end else begin
            exp_valid[cycle+LATENCY]=1;
            exp_de[cycle+LATENCY]=de_in;
            exp_hs[cycle+LATENCY]=hs_in;
            exp_vs[cycle+LATENCY]=vs_in;
            exp_y_gray[cycle+LATENCY]=0;
            exp_y_bin[cycle+LATENCY]=0;
            exp_y_cross[cycle+LATENCY]=0;
            exp_y_fixed[cycle+LATENCY]=0;
            exp_y_dilate[cycle+LATENCY]=0;
            if(de_in) begin
                exp_y_gray[cycle+LATENCY]=morph_at(stim_frame,stim_row,stim_col,0,0,0);
                exp_y_bin[cycle+LATENCY]=morph_at(stim_frame,stim_row,stim_col,1,0,0);
                exp_y_cross[cycle+LATENCY]=morph_at(stim_frame,stim_row,stim_col,0,1,0);
                exp_y_fixed[cycle+LATENCY]=morph_at(stim_frame,stim_row,stim_col,0,0,1);
                exp_y_dilate[cycle+LATENCY]=morph_at(stim_frame,stim_row,stim_col,0,0,2);
            end
        end
        #1;
        if(!rst_n) begin
            if({rgb_g,y_g,bin_g,de_g,hs_g,vs_g,rgb_b,y_b,bin_b,de_b,hs_b,vs_b,
                rgb_c,y_c,bin_c,de_c,hs_c,vs_c,rgb_f,y_f,bin_f,de_f,hs_f,vs_f,
                rgb_d,y_d,bin_d,de_d,hs_d,vs_d} !== 0) begin
                $display("FAIL reset outputs cycle %0d",cycle); errors=errors+1;
            end
        end else if(exp_valid[cycle]) begin
            if(de_g !== (exp_de[cycle]!=0) || hs_g !== (exp_hs[cycle]!=0) || vs_g !== (exp_vs[cycle]!=0) ||
               de_b !== (exp_de[cycle]!=0) || hs_b !== (exp_hs[cycle]!=0) || vs_b !== (exp_vs[cycle]!=0) ||
               de_c !== (exp_de[cycle]!=0) || hs_c !== (exp_hs[cycle]!=0) || vs_c !== (exp_vs[cycle]!=0) ||
               de_f !== (exp_de[cycle]!=0) || hs_f !== (exp_hs[cycle]!=0) || vs_f !== (exp_vs[cycle]!=0) ||
               de_d !== (exp_de[cycle]!=0) || hs_d !== (exp_hs[cycle]!=0) || vs_d !== (exp_vs[cycle]!=0)) begin
                $display("FAIL sync cycle %0d exp=%b%b%b gray=%b%b%b",cycle,
                    (exp_de[cycle]!=0),(exp_hs[cycle]!=0),(exp_vs[cycle]!=0),de_g,hs_g,vs_g); errors=errors+1;
            end
            if(exp_de[cycle]) begin
                checks=checks+1;
                if(y_g!==exp_y_gray[cycle] || rgb_g!=={exp_y_gray[cycle][7:0],exp_y_gray[cycle][7:0],exp_y_gray[cycle][7:0]} || bin_g!==(exp_y_gray[cycle]!=0)) begin
                    $display("FAIL gray cycle %0d expected %0d got %0d",cycle,exp_y_gray[cycle],y_g); errors=errors+1;
                end
                if(y_b!==exp_y_bin[cycle] || rgb_b!=={exp_y_bin[cycle][7:0],exp_y_bin[cycle][7:0],exp_y_bin[cycle][7:0]} || bin_b!==(exp_y_bin[cycle]!=0)) begin
                    $display("FAIL binary cycle %0d expected %0d got %0d",cycle,exp_y_bin[cycle],y_b); errors=errors+1;
                end
                if(y_c!==exp_y_cross[cycle] || rgb_c!=={exp_y_cross[cycle][7:0],exp_y_cross[cycle][7:0],exp_y_cross[cycle][7:0]}) begin
                    $display("FAIL cross cycle %0d expected %0d got %0d",cycle,exp_y_cross[cycle],y_c); errors=errors+1;
                end
                if(y_f!==exp_y_fixed[cycle] || rgb_f!=={exp_y_fixed[cycle][7:0],exp_y_fixed[cycle][7:0],exp_y_fixed[cycle][7:0]}) begin
                    $display("FAIL fixed erode cycle %0d expected %0d got %0d",cycle,exp_y_fixed[cycle],y_f); errors=errors+1;
                end
                if(y_d!==exp_y_dilate[cycle] || rgb_d!=={exp_y_dilate[cycle][7:0],exp_y_dilate[cycle][7:0],exp_y_dilate[cycle][7:0]}) begin
                    $display("FAIL fixed dilate cycle %0d expected %0d got %0d",cycle,exp_y_dilate[cycle],y_d); errors=errors+1;
                end
            end
        end
        cycle=cycle+1;
    end

endmodule
