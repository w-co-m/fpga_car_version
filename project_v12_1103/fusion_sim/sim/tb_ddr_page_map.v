`timescale 1ns/1ps
`include "ddr_page_map.vh"
module tb_ddr_page_map;
    reg [25:0] first_addr[0:11], end_addr[0:11];
    integer i,j,checks=0;
    initial begin
        first_addr[0]=`DDR_MAP_LIVE0_BASE; first_addr[1]=`DDR_MAP_LIVE1_BASE;
        first_addr[2]=`DDR_MAP_LIVE2_BASE; first_addr[3]=`DDR_MAP_LIVE3_BASE;
        first_addr[4]=`DDR_MAP_ANGLE0_BASE; first_addr[5]=`DDR_MAP_ANGLE45_BASE;
        first_addr[6]=`DDR_MAP_ANGLE90_BASE; first_addr[7]=`DDR_MAP_ANGLE135_BASE;
        first_addr[8]=`DDR_MAP_DOLP_BASE; first_addr[9]=`DDR_MAP_AOP_BASE;
        first_addr[10]=`DDR_MAP_FUSION_BASE; first_addr[11]=`DDR_MAP_EDGE_BASE;
        if (`DDR_MAP_FRAME_WORDS!=1280*720*24/128 ||
            `DDR_MAP_FRAME_SPAN!=`DDR_MAP_FRAME_WORDS*8)
            $fatal(1,"720p frame packing/address span mismatch");
        for(i=0;i<12;i=i+1)begin
            end_addr[i]=first_addr[i]+`DDR_MAP_FRAME_SPAN;
            if((first_addr[i]&26'd7)!=0 || end_addr[i]>26'd33554432)
                $fatal(1,"unaligned/out-of-range DDR page %0d",i);
            checks=checks+1;
            for(j=0;j<i;j=j+1)begin
                if(first_addr[i]<end_addr[j] && first_addr[j]<end_addr[i])
                    $fatal(1,"overlapping DDR pages %0d %0d",i,j);
                checks=checks+1;
            end
        end
        $display("PASS tb_ddr_page_map: 12 aligned pages, 66 pairwise overlap checks, 16-bit address units, checks=%0d",checks);
        $finish;
    end
endmodule
