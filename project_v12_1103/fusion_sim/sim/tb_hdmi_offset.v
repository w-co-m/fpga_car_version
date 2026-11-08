`timescale 1ns/1ps
module tb_hdmi_offset;
    reg clk=0,rst_n=0,de=0,user=0,last=0;
    reg [11:0] x=0,y=0;
    wire rd_en,hdmi_de;
    wire [23:0] hdmi_data;
    integer errors=0,reads=0;
    reg [2:0] active_pipe=0;
    reg [2:0] de_pipe=0;
    always #5 clk=~clk;

    hdmi_mixer #(.H_OFFSET(1),.V_OFFSET(1),.IMG_WIDTH(2),.IMG_HEIGHT(2)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(1'b0),.I_video_hsync(1'b0),
        .I_video_de(de),.I_video_user(user),.I_video_last(last),.I_debug_status(4'd0),
        .O_video_rd_en(rd_en),.I_video_rd_data(24'h123456),.O_hdmi_vsync(),
        .O_hdmi_hsync(),.O_hdmi_de(hdmi_de),.O_hdmi_data(hdmi_data));

    always @(posedge clk) begin
        active_pipe={active_pipe[1:0],(de && x>=1 && x<3 && y>=1 && y<3)};
        de_pipe={de_pipe[1:0],de};
        #1;
        if(rst_n) begin
            if(hdmi_de !== de_pipe[2]) begin errors=errors+1;$display("DE mismatch got=%b expected=%b",hdmi_de,de_pipe[2]);end
            if(hdmi_data !== (active_pipe[2] ? 24'h123456 : 24'h000000)) begin errors=errors+1;$display("BORDER/data mismatch active=%b got=%h",active_pipe[2],hdmi_data);end
        end
    end

    task pixel(input integer px,input integer py,input integer frame_start,input integer line_end);
        begin
            @(negedge clk);x=px;y=py;de=1;user=frame_start;last=line_end;
            #1;
            if(rd_en !== (px>=1 && px<3 && py>=1 && py<3)) begin errors=errors+1;$display("READ_EN mismatch x=%0d y=%0d got=%b",px,py,rd_en);end
            if(rd_en) reads=reads+1;
        end
    endtask

    integer row,col;
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        for(row=0;row<4;row=row+1) begin
            for(col=0;col<4;col=col+1) pixel(col,row,(row==0 && col==0),(col==3));
            @(negedge clk);de=0;user=0;last=0;x=0;y=row;
        end
        repeat(5) @(negedge clk);
        if(reads!=4) begin errors=errors+1;$display("read count=%0d expected=4",reads);end
        if(errors!=0)$fatal(1,"FAIL tb_hdmi_offset errors=%0d",errors);
        $display("PASS tb_hdmi_offset: nonzero H/V offsets, exact four clipped reads, black borders");$finish;
    end
endmodule
