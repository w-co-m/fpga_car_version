`timescale 1ns/1ps
module tb_algo_motion_spatial720;
    parameter W=1280;
    parameter H=720;
    reg clk;
    reg rst_n;
    reg enable_in;
    reg [23:0] rgb_in;
    reg [7:0] y_in;
    reg de_in,hs_in,vs_in;
    reg [7:0] threshold_in;
    wire [23:0] rgb_out;
    wire [7:0] mask_out;
    wire bin_out,motion_detected;
    wire [19:0] motion_pixel_cnt;
    wire ref_ready,de_out,hs_out,vs_out;

    reg [23:0] exp_rgb_now,exp_rgb_prev;
    reg [7:0] exp_mask_now,exp_mask_prev;
    reg exp_bin_now,exp_bin_prev;
    reg exp_de_now,exp_de_prev,exp_hs_now,exp_hs_prev,exp_vs_now,exp_vs_prev;
    reg exp_prev_valid,scoreboard_enable;
    integer cycle_count,row,col,pattern,hs_width;
    integer target_count;
    reg [7:0] sample_value_now,pixel_value;
    reg expected_motion;

    always #5 clk=~clk;

    algo_motion #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.DS_LOG2(4),.MOTION_CNT(1),.STATUS_OSD(0)) dut (
        .clk(clk),.rst_n(rst_n),.enable_in(enable_in),.rgb_in(rgb_in),.y_in(y_in),
        .de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),.threshold_in(threshold_in),
        .rgb_out(rgb_out),.mask_out(mask_out),.bin_out(bin_out),
        .motion_detected(motion_detected),.motion_pixel_cnt(motion_pixel_cnt),.ref_ready(ref_ready),
        .de_out(de_out),.hs_out(hs_out),.vs_out(vs_out)
    );

    // 8-bit spatial pattern; adjacent rows and blocks use different samples.
    function [7:0] base_sample;
        input integer r;
        input integer b;
        integer v;
        begin
            v=40+((r*73+b*29+r*b*11+(r/8)*17+(b/4)*31)%160);
            base_sample=v[7:0];
        end
    endfunction

    function selected_block;
        input integer r;
        input integer b;
        begin
            selected_block=((r==0 && b==0) ||
                            (r==511 && b==63) || (r==511 && b==64) ||
                            (r==512 && b==0) ||
                            (r==719 && b==79));
        end
    endfunction

    // Output registers are compared with the previous input cycle, including blanking.
    always @(posedge clk) begin
        #1;
        if (!rst_n) begin
            exp_prev_valid=0;
        end else begin
            if (scoreboard_enable && exp_prev_valid) begin
                if (rgb_out !== exp_rgb_prev || mask_out !== exp_mask_prev ||
                    bin_out !== exp_bin_prev || de_out !== exp_de_prev ||
                    hs_out !== exp_hs_prev || vs_out !== exp_vs_prev) begin
                    $display("FAIL spatial pipeline at cycle %0d: RGB %h/%h mask %h/%h DEHS %b%b/%b%b VS %b/%b",
                        cycle_count,rgb_out,exp_rgb_prev,mask_out,exp_mask_prev,
                        de_out,hs_out,exp_de_prev,exp_hs_prev,vs_out,exp_vs_prev);
                    $finish;
                end
                cycle_count=cycle_count+1;
            end
            exp_rgb_prev=exp_rgb_now;
            exp_mask_prev=exp_mask_now;
            exp_bin_prev=exp_bin_now;
            exp_de_prev=exp_de_now;
            exp_hs_prev=exp_hs_now;
            exp_vs_prev=exp_vs_now;
            exp_prev_valid=1;
        end
    end

    task drive_cycle;
        input de_value;
        input hs_value;
        input vs_value;
        input [7:0] y_value;
        input [23:0] rgb_value;
        input mark_motion;
        begin
            @(negedge clk);
            de_in=de_value; hs_in=hs_value; vs_in=vs_value;
            y_in=y_value; rgb_in=rgb_value;
            exp_rgb_now=mark_motion ? 24'hFF0000 : rgb_value;
            exp_mask_now=(de_value && mark_motion) ? 8'hFF : 8'h00;
            exp_bin_now=de_value && mark_motion;
            exp_de_now=de_value; exp_hs_now=hs_value; exp_vs_now=vs_value;
            @(posedge clk); #2;
        end
    endtask

    task pulse_vs;
        input integer width;
        integer n;
        begin
            for(n=0;n<width;n=n+1) drive_cycle(0,0,1,0,0,0);
            drive_cycle(0,0,0,0,0,0);
        end
    endtask

    task pulse_hs;
        input integer width;
        integer n;
        begin
            for(n=0;n<width;n=n+1) drive_cycle(0,1,0,0,0,0);
            drive_cycle(0,0,0,0,0,0);
        end
    endtask

    task send_frame;
        input integer changed;
        integer r,c,b;
        reg [7:0] s,y;
        reg mark;
        begin
            for(r=0;r<H;r=r+1) begin
                for(c=0;c<W;c=c+1) begin
                    b=c/16;
                    s=base_sample(r,b);
                    mark=changed && selected_block(r,b);
                    if(mark) s=s+8'd32;
                    if((c%16)==0) y=s;
                    else y=(c%2) ? 8'hFF : 8'h00;
                    drive_cycle(1,0,0,y,{r[7:0],y,c[7:0]},mark);
                end
                hs_width=(r%3)+1;
                pulse_hs(hs_width);
                drive_cycle(0,0,0,0,0,0);
            end
        end
    endtask

    task check_result;
        input [19:0] expected_count;
        input expected_detected;
        begin
            if (!ref_ready || motion_pixel_cnt !== expected_count || motion_detected !== expected_detected) begin
                $display("FAIL spatial frame result ready=%b count=%0d detected=%b expected=%0d/%b/1",
                    ref_ready,motion_pixel_cnt,motion_detected,expected_count,expected_detected);
                $finish;
            end
        end
    endtask

    initial begin
        clk=0; rst_n=0; enable_in=1; rgb_in=0; y_in=0;
        de_in=0; hs_in=0; vs_in=0; threshold_in=0;
        exp_rgb_now=0; exp_rgb_prev=0; exp_mask_now=0; exp_mask_prev=0;
        exp_bin_now=0; exp_bin_prev=0; exp_de_now=0; exp_de_prev=0;
        exp_hs_now=0; exp_hs_prev=0; exp_vs_now=0; exp_vs_prev=0;
        exp_prev_valid=0; scoreboard_enable=0; cycle_count=0;
        target_count=5;

        repeat(3) @(posedge clk);
        @(negedge clk); rst_n=1; scoreboard_enable=1;

        pulse_vs(3);
        send_frame(0); pulse_vs(1);
        if (!ref_ready || motion_pixel_cnt !== 20'd0) begin
            $display("FAIL 720p varied reference frame did not warm up cleanly"); $finish;
        end

        send_frame(0); pulse_vs(1);
        check_result(20'd0,1'b0); // textured but identical: no false motion at any address

        send_frame(1); pulse_vs(3);
        check_result(target_count*16,1'b1);

        $display("PASS tb_algo_motion_spatial720 cycles=%0d motion_pixels=%0d",cycle_count,motion_pixel_cnt);
        $finish;
    end
endmodule
