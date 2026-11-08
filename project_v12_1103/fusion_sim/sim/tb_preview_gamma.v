`timescale 1ns/1ps
module tb_preview_gamma;
    reg clk=0, rst_n=0;
    reg [23:0] rgb_in=24'h404040;
    reg de_in=0, hs_in=0, vs_in=0;
    reg [3:0] mode_active=0;
    wire [23:0] rgb_out, reference_rgb;
    wire de_out, hs_out, vs_out, ref_de, ref_hs, ref_vs;
    integer samples=0, sweep_count=0, previous_gray=-1;
    integer text_checks=0, logo_checks=0, background_checks=0;
    integer i,m,x,y,difference,ideal_integer;
    real ideal;
    reg [23:0] last_input,last_expected;
    reg last_de,last_hs,last_vs,last_check,last_sweep,last_overlay;
    reg [3:0] last_mode;
    always #5 clk=~clk;

`ifdef PREVIEW_GAMMA_AVAILABLE
    video_status_osd #(.ENABLE_PREVIEW_GAMMA(1)) dut (
`else
    video_status_osd dut (
`endif
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .mode_active(mode_active), .bin_threshold_active(8'd128), .edge_threshold_active(8'd32),
        .bright_gain_active(8'd128), .contrast_gain_active(8'd128), .threshold_edit_active(1'b0),
        .polar_angle(2'd0), .polar_capture_busy(1'b0), .polar_compute_busy(1'b0),
        .polar_ready(1'b0), .polar_error(1'b0), .ddr_state(2'd0),
        .rgb_out(rgb_out), .de_out(de_out), .hs_out(hs_out), .vs_out(vs_out)
    );

    video_status_osd reference_osd (
        .clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.de_in(de_in),.hs_in(hs_in),.vs_in(vs_in),
        .mode_active(mode_active),.bin_threshold_active(8'd128),.edge_threshold_active(8'd32),
        .bright_gain_active(8'd128),.contrast_gain_active(8'd128),.threshold_edit_active(1'b0),
        .polar_angle(2'd0),.polar_capture_busy(1'b0),.polar_compute_busy(1'b0),
        .polar_ready(1'b0),.polar_error(1'b0),.ddr_state(2'd0),
        .rgb_out(reference_rgb),.de_out(ref_de),.hs_out(ref_hs),.vs_out(ref_vs)
    );
    task sample;
        input [23:0] pixel;
        input valid,hsync,vsync;
        input [23:0] expected;
        input check_rgb,sweep,overlay;
        begin
            @(negedge clk);rgb_in=pixel;de_in=valid;hs_in=hsync;vs_in=vsync;
            @(posedge clk);#1;
            if(samples>0) begin
                if({de_out,hs_out,vs_out}!=={last_de,last_hs,last_vs} ||
                   {ref_de,ref_hs,ref_vs}!=={last_de,last_hs,last_vs})
                    $fatal(1,"OSD gamma changed two-stage sync latency");
                if(last_overlay && last_de) begin
                    if((^reference_rgb)===1'bx || (^rgb_out)===1'bx) $fatal(1,"Unknown overlay pixel");
                    if(reference_rgb!==last_input) begin
                        if(rgb_out!==reference_rgb) $fatal(1,"Gamma changed text/logo color");
                        if(reference_rgb==24'h00e6ff) text_checks=text_checks+1;
                        else logo_checks=logo_checks+1;
                    end else begin
                        if(rgb_out!==24'h020507) $fatal(1,"Overlay background not brightened");
                        background_checks=background_checks+1;
                    end
                end else begin
                    if(reference_rgb!==last_input) $fatal(1,"Default-off OSD changed base RGB");
                    if(last_check && rgb_out!==last_expected)
                        $fatal(1,"mode %0d preview gamma expected %h, got %h",last_mode,last_expected,rgb_out);
                end
                if(last_sweep) begin
                    if((^rgb_out)===1'bx || rgb_out[23:16]!==rgb_out[15:8] ||
                       rgb_out[15:8]!==rgb_out[7:0] ||
                       (previous_gray>=0 && rgb_out[7:0]<previous_gray))
                        $fatal(1,"Gamma is not defined, neutral or monotonic");
                    ideal=255.0*$pow($itor(last_input[7:0])/255.0,0.7);
                    ideal_integer=$rtoi(ideal+0.5);
                    difference=rgb_out[7:0]-ideal_integer;
                    if(difference<0) difference=-difference;
                    if(difference>6) $fatal(1,"Gamma curve exceeds six-code approximation tolerance");
                    previous_gray=rgb_out[7:0];sweep_count=sweep_count+1;
                end
            end
            last_input=pixel;last_expected=expected;
            last_de=valid;last_hs=hsync;last_vs=vsync;
            last_check=check_rgb;last_sweep=sweep;last_overlay=overlay;last_mode=mode_active;
            samples=samples+1;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        sample(24'h404040,1,1,0,24'h616161,1,0,0);
        sample(24'h000000,1,0,0,24'h000000,1,0,0);
        sample(24'h101010,1,0,0,24'h252525,1,0,0);
        sample(24'h202020,1,0,0,24'h3c3c3c,1,0,0);
        sample(24'h808080,1,0,0,24'h9d9d9d,1,0,0);
        sample(24'hc0c0c0,1,0,0,24'hd1d1d1,1,0,0);
        sample(24'hffffff,1,0,0,24'hffffff,1,0,0);
        for(i=0;i<256;i=i+1) sample({i[7:0],i[7:0],i[7:0]},1,0,0,0,0,1,0);
        sample(0,1,0,0,0,1,0,0);
        if(sweep_count!=256) $fatal(1,"Incomplete 256-code gamma sweep");
        for(m=0;m<16;m=m+1) begin
            mode_active=m;
            if(m==0 || m==13 || m==15) sample(24'h204080,1,m[0],0,24'h3c619d,1,0,0);
            else sample(24'h204080,1,m[0],0,24'h204080,1,0,0);
        end
        mode_active=13;
        sample(24'h000000,1,0,0,24'h000000,1,0,0);
        sample(24'h00ff00,1,0,0,24'h00ff00,1,0,0);
        sample(24'hffff00,1,0,0,24'hffff00,1,0,0);
        sample(24'hffffff,1,0,0,24'hffffff,1,0,0);
        sample(0,0,0,1,0,1,0,0);sample(0,0,0,0,0,1,0,0);
        for(y=0;y<184;y=y+1) begin
            for(x=0;x<760;x=x+1) sample(24'h010203,1,(x==0),0,0,0,0,1);
            sample(24'h010203,0,0,0,0,0,0,1);
        end
        sample(0,0,0,0,0,0,0,0);
        if(text_checks==0 || logo_checks==0 || background_checks==0)
            $fatal(1,"Text/logo/background comparison was not exercised");
        @(negedge clk);rst_n=0;@(posedge clk);#1;
        if({rgb_out,de_out,hs_out,vs_out}!==27'd0 ||
           {reference_rgb,ref_de,ref_hs,ref_vs}!==27'd0) $fatal(1,"Gamma OSD reset did not clear outputs");
        $display("PASS tb_preview_gamma sweep=%0d text=%0d logo=%0d background=%0d samples=%0d",
                 sweep_count,text_checks,logo_checks,background_checks,samples);
        $finish;
    end
endmodule
