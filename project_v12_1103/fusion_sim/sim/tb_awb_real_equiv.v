`timescale 1ns/1ps
module tb_awb_real_equiv;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, tvalid=0, tuser=0, fixed_gain=0;
    reg [95:0] tdata=0;
    wire [95:0] new_data, ref_data;
    wire new_valid, ref_valid, new_last, ref_last, new_user, ref_user;
    wire [19:0] ref_gain_r = |baseline.dout_R[0][47:20] ? 20'hfffff : baseline.dout_R[0][19:0];
    wire [19:0] ref_gain_b = |baseline.dout_B[0][47:20] ? 20'hfffff : baseline.dout_B[0][19:0];
    integer cycle=0, errors=0, compared=0, overlap_count=0, output_count=0;
    integer fixed_on_count=0, fixed_off_count=0, frame_count=0, reset_count=0, outstanding=0;
    reg [7:0] red,green,blue;

    awb #(.IMG_WIDTH(16),.IMG_HEIGHT(4),.ENABLE_POLAR_FIXED_GAIN(1)) optimized(
        .I_clk(clk),.I_rst_n(rst_n),.I_tlast(1'b0),.I_tuser(tuser),.I_tdata(tdata),.I_tvalid(tvalid),
        .I_polar_fixed_gain(fixed_gain),.I_tready(),.O_tlast(new_last),.O_tuser(new_user),.O_tdata(new_data),.O_tvalid(new_valid),.O_tready(1'b1));
    awb_reference #(.IMG_WIDTH(16),.IMG_HEIGHT(4),.ENABLE_POLAR_FIXED_GAIN(1)) baseline(
        .I_clk(clk),.I_rst_n(rst_n),.I_tlast(1'b0),.I_tuser(tuser),.I_tdata(tdata),.I_tvalid(tvalid),
        .I_polar_fixed_gain(fixed_gain),.I_tready(),.O_tlast(ref_last),.O_tuser(ref_user),.O_tdata(ref_data),.O_tvalid(ref_valid),.O_tready(1'b1));

    always @(posedge clk) begin
        if(!rst_n) outstanding=0;
        else begin
            if(optimized.I_tvalid_r1) outstanding=outstanding+1;
            if(optimized.gain_valid_r && outstanding>0) outstanding=outstanding-1;
            if(tuser && optimized.gain_valid_r && baseline.done[0]) overlap_count=overlap_count+1;
            if(optimized.gain_valid_r !== baseline.done[0] || optimized.gain_valid_b !== optimized.gain_valid_r) begin
                $display("FAIL valid cycle=%0d new=%b/%b ref=%b",cycle,optimized.gain_valid_r,optimized.gain_valid_b,baseline.done[0]);
                errors=errors+1;
            end
            if(optimized.gain_valid_r && !baseline.done[0]) begin
                $display("FAIL old divider not done when gain valid cycle=%0d",cycle);
                errors=errors+1;
            end
            if(optimized.gain_valid_r &&
               (optimized.gain_r20 !== ref_gain_r || optimized.gain_b20 !== ref_gain_b)) begin
                $display("FAIL gain cycle=%0d new=%h/%h ref=%h/%h",cycle,optimized.gain_r20,optimized.gain_b20,ref_gain_r,ref_gain_b);
                errors=errors+1;
            end
        end
    end

    always @(posedge clk) begin
        #1;
        if(rst_n && (optimized.in_r_r1 !== baseline.in_r_r1 || optimized.in_b_r1 !== baseline.in_b_r1)) begin
            $display("FAIL stored gain cycle=%0d new=%h/%h ref=%h/%h",cycle,optimized.in_r_r1,optimized.in_b_r1,baseline.in_r_r1,baseline.in_b_r1);
            errors=errors+1;
        end
    end

    always @(negedge clk) if(rst_n) begin
        compared=compared+1;
        if(new_valid) output_count=output_count+1;
        if(new_user) frame_count=frame_count+1;
        if(fixed_gain) fixed_on_count=fixed_on_count+1;
        else fixed_off_count=fixed_off_count+1;
        if({new_valid,new_last,new_user,new_data} !== {ref_valid,ref_last,ref_user,ref_data}) begin
            $display("FAIL cycle=%0d new valid/last/user=%b%b%b data=%h ref=%b%b%b data=%h",cycle,
                     new_valid,new_last,new_user,new_data,ref_valid,ref_last,ref_user,ref_data);
            errors=errors+1;
        end
    end

    initial begin
        repeat(60) @(negedge clk); rst_n=1;
        for(cycle=0;cycle<180;cycle=cycle+1) begin
            @(negedge clk);
            tuser=(cycle==0 || cycle==76 || cycle==125);
            tvalid=((cycle%9)!=3 && (cycle%13)!=8);
            if(cycle==24 || cycle==72) tvalid=1;
            fixed_gain=(cycle>=55 && cycle<90) || (cycle>=140 && cycle<160);
            red=8'd35+(cycle*17)%170;
            green=8'd50+(cycle*11)%180;
            blue=8'd25+(cycle*23)%190;
            tdata={red,green,blue, red+8'd13,green+8'd21,blue+8'd7,
                   red+8'd31,green+8'd9,blue+8'd43, red+8'd5,green+8'd37,blue+8'd19};
        end
        // Reset with valid requests still in flight; both dividers must flush equally.
        @(negedge clk);
        if(outstanding==0) errors=errors+1;
        rst_n=0;tvalid=0;tuser=0;fixed_gain=0;reset_count=reset_count+1;
        repeat(3) @(negedge clk); rst_n=1;
        for(cycle=180;cycle<400;cycle=cycle+1) begin
            @(negedge clk);
            tuser=(cycle==190 || cycle==260 || cycle==330);
            tvalid=((cycle%7)!=2 && (cycle%11)!=6);
            if(cycle==190 || cycle==208) tvalid=1;
            fixed_gain=(cycle>=215 && cycle<235) || (cycle>=340 && cycle<370);
            red=8'd45+(cycle*19)%160;
            green=8'd40+(cycle*7)%190;
            blue=8'd30+(cycle*29)%180;
            tdata={red,green,blue, red+8'd11,green+8'd17,blue+8'd23,
                   red+8'd29,green+8'd5,blue+8'd37, red+8'd3,green+8'd41,blue+8'd13};
        end
        @(negedge clk); tvalid=0;tuser=1;fixed_gain=1;
        @(negedge clk); tuser=0;
        repeat(12) @(negedge clk);
        fixed_gain=0;
        @(negedge clk); tuser=1;
        @(negedge clk); tuser=0;
        // Keep both dividers idle for more than 100 clocks, including frame
        // starts while idle and a fixed-gain exit, under strict full-cycle checks.
        repeat(120) @(negedge clk);
        if(compared<400 || output_count<100 || frame_count<5 || reset_count!=1 || outstanding!=0 ||
           overlap_count==0 || fixed_on_count==0 || fixed_off_count==0) errors=errors+1;
        $display("tb_awb_real_equiv %s errors=%0d compared=%0d outputs=%0d frames=%0d fixed_on=%0d fixed_off=%0d fixed_overlap=%0d resets=%0d outstanding=%0d divider_delta=49",errors==0?"PASS":"FAIL",errors,compared,output_count,frame_count,fixed_on_count,fixed_off_count,overlap_count,reset_count,outstanding);
        $finish;
    end
endmodule

module signal_delay #(parameter IMG_HEIGHT=4,IMG_WIDTH=16,DATA_WIDTH=96,DELAY_CYCLE=50)(
    input wire I_clk,I_rst_n,I_tuser,I_valid,input wire[DATA_WIDTH-1:0]I_data,
    output wire O_valid,output wire[DATA_WIDTH-1:0]O_data,output wire O_tuser);
    reg [DATA_WIDTH-1:0] d[0:DELAY_CYCLE-1];
    reg [DELAY_CYCLE-1:0] v,u;
    integer i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            v<=0;u<=0;
            for(i=0;i<DELAY_CYCLE;i=i+1)d[i]<=0;
        end else begin
            v<={v[DELAY_CYCLE-2:0],I_valid};
            u<={u[DELAY_CYCLE-2:0],I_tuser};
            d[0]<=I_data;
            for(i=1;i<DELAY_CYCLE;i=i+1)d[i]<=d[i-1];
        end
    end
    assign O_valid=v[DELAY_CYCLE-1];
    assign O_tuser=u[DELAY_CYCLE-1];
    assign O_data=d[DELAY_CYCLE-1];
endmodule
