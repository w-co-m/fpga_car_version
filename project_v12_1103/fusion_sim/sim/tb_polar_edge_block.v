`timescale 1ns/1ps
module tb_polar_edge_block;
    wire abort_req=1'b0;
    wire abort_ack,reset_required;
    localparam [24:0] B0=25'd23000000,B45=25'd24400000,
        B90=25'd25800000,B135=25'd27200000,EDGE=25'd4000000;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0,op_compute=0;
    reg [24:0] source_addr=0,dest_addr=0,block_offset=0;
    wire busy,done,error,request,owner_release,rd_en,wr_en;
    reg grant=0,ddr_ready=0,rd_valid=0;
    wire [24:0] addr; wire [127:0] wr_data; reg [127:0] rd_data=0;
    polar_block_engine #(.ENABLE_EDGE(1),.IMG_WIDTH(32),.EDGE_BASE(EDGE),
        .EDGE_THRESHOLD(8'd24)) dut(.*);

    reg [24:0] ma[0:1023],ra[0:4095],wa[0:1023];
    reg [127:0] md[0:1023],wd[0:1023];
    integer rd_due[0:4095],wr_due[0:1023];
    integer mc=0,rw=0,rr=0,ww=0,wr=0,cycle=0,seed=31271;
    integer n,s,rv,ready_delay,hs_seen=0,vs_seen=0,edge_write_count=0,stale_count=0,retry_total=0,total_white=0,qi;
    integer input_mode=0,last_hs_cycle=-1,last_vs_cycle=-1,compute_write_count=0;
    reg [383:0] pixels;
    function integer find_slot(input [24:0] a);
        integer j; begin find_slot=-1;for(j=0;j<mc;j=j+1)if(ma[j]==a)find_slot=j;end
    endfunction
    function [127:0] mem_get(input [24:0] a);
        integer j;begin j=find_slot(a);if(j<0)mem_get=0;else mem_get=md[j];end
    endfunction
    task mem_put(input [24:0] a,input [127:0] d);
        integer j;begin j=find_slot(a);if(j<0)begin j=mc;mc=mc+1;ma[j]=a;end md[j]=d;end
    endtask
    function [23:0] mkpix(input integer pixel,input integer angle);
        integer row,col,delta,g;
        begin
            row=pixel/32;col=pixel%32;
            delta=((row==1)&&(col>=15)&&(col<=18))?240:0;
            if(input_mode==0)begin
                case(angle)
                    1:g=128+delta/2;
                    3:g=128-delta/2;
                    default:g=128;
                endcase
            end else if(input_mode==1)g=delta?224:128;
            else g=128;
            mkpix={g[7:0],g[7:0],g[7:0]};
        end
    endfunction
    function integer model_value(input integer mode,input integer channel,input integer row,input integer col);
        integer region;
        begin
            region=(row==1)&&(col>=15)&&(col<=18);
            if(channel==0)begin
                if(mode==1&&region)model_value=224;else model_value=128;
            end else if(mode==0&&region)model_value=240;
            else model_value=0;
        end
    endfunction
    function integer model_sobel8(input integer mode,input integer row,input integer col,input integer channel);
        integer r0,r1,r2,c0,c1,c2,p00,p01,p02,p10,p11,p12,p20,p21,p22,gx,gy,mag;
        begin
            r0=(row>=2)?row-2:0;r1=(row>=1)?row-1:0;r2=row;
            c0=(col>=2)?col-2:0;c1=(col>=1)?col-1:0;c2=col;
            p00=model_value(mode,channel,r0,c0);p01=model_value(mode,channel,r0,c1);p02=model_value(mode,channel,r0,c2);
            p10=model_value(mode,channel,r1,c0);p11=model_value(mode,channel,r1,c1);p12=model_value(mode,channel,r1,c2);
            p20=model_value(mode,channel,r2,c0);p21=model_value(mode,channel,r2,c1);p22=model_value(mode,channel,r2,c2);
            gx=(p02+2*p12+p22)-(p00+2*p10+p20);
            gy=(p00+2*p01+p02)-(p20+2*p21+p22);
            mag=((gx<0)?-gx:gx)+((gy<0)?-gy:gy);
            model_sobel8=mag>>3;
        end
    endfunction
    function integer model_bin(input integer mode,input integer row,input integer col);
        integer score;
        begin
            score=(192*model_sobel8(mode,row,col,0)+64*model_sobel8(mode,row,col,1))>>8;
            if(score>255)score=255;
            model_bin=(score>=24);
        end
    endfunction

    always @(posedge clk) begin
        cycle=cycle+1;
        if(rst_n)begin
            if(dut.polar_hs)begin hs_seen=hs_seen+1;last_hs_cycle=cycle;end
            if(dut.polar_vs)begin vs_seen=vs_seen+1;last_vs_cycle=cycle;end
        end
        if(rd_en)begin
            if(!grant||!ddr_ready)$fatal(1,"read without grant/ready");
            ra[rw]=addr;rd_due[rw]=cycle+2+($random(seed)&7);rw=rw+1;
        end
        if(wr_en)begin
            if(!grant||!ddr_ready)$fatal(1,"write without grant/ready");
            wa[ww]=addr;wd[ww]=wr_data;wr_due[ww]=cycle+55;ww=ww+1;
            if(dut.compute_latched)compute_write_count=compute_write_count+1;
            if(addr>=EDGE&&addr<EDGE+25'd1408)edge_write_count=edge_write_count+1;
        end
        if(wr<ww&&wr_due[wr]<=cycle)begin
            mem_put(wa[wr],wd[wr]);wr=wr+1;
        end
    end
    always @(negedge clk) begin
        rv=$random(seed);ddr_ready=((rv&3)!=0);
        if(owner_release)grant=0;else if(request)grant=1;
        if(rr<rw&&rd_due[rr]<=cycle)begin
            rd_valid=1;rd_data=mem_get(ra[rr]);
            for(qi=wr;qi<ww;qi=qi+1)if(wa[qi]==ra[rr])stale_count=stale_count+1;
            rr=rr+1;
        end else begin rd_valid=0;rd_data=0;end
    end
    always @(posedge clk) if(wr_en)begin
        if(dut.write_index>=9&&dut.write_index<12&&
           addr!==EDGE+block_offset+(dut.write_index-9)*8)
            $fatal(1,"edge result address/order mismatch idx=%0d addr=%0d",dut.write_index,addr);
    end

    task start_job(input integer comp,input [24:0] src,input [24:0] dst,input [24:0] off);
        begin @(negedge clk);op_compute=comp;source_addr=src;dest_addr=dst;block_offset=off;start=1;
              @(negedge clk);start=0;end
    endtask
    task wait_done;
        integer timeout;
        begin timeout=0;while(!done&&timeout<12000)begin @(posedge clk);#1;timeout=timeout+1;end
              if(!done)$fatal(1,"timeout state=%0d raw/fused/edge=%0d/%0d/%0d",dut.state,dut.raw_count,dut.fused_count,dut.edge_count);
              if(error)$fatal(1,"engine error");
              while(wr<ww)@(negedge clk);
              @(posedge clk);#1;end
    endtask
    task check_edge_block(input [24:0] off);
        integer k,p,row0,col0,expected; reg [127:0] d; reg [383:0] frame_block;
        begin
            frame_block=0;
            for(k=0;k<3;k=k+1)begin
                d=mem_get(EDGE+off+k*8);
                frame_block[383-k*128 -:128]=d;
                for(s=0;s<16;s=s+1)begin
                    if(d[127-s*8 -:8]!==8'h00&&d[127-s*8 -:8]!==8'hff)
                        $fatal(1,"edge RGB is not black/white at off=%0d",off);
                    if(d[127-s*8 -:8]==8'hff)total_white=total_white+1;
                end
            end
            row0=(off/24)/2;col0=((off/24)%2)*16;
            for(p=0;p<16;p=p+1)begin
                expected=model_bin(input_mode,row0,col0+p);
                if(frame_block[383-p*24 -:24]!== (expected?24'hffffff:24'h000000))
                    $fatal(1,"independent Sobel model mismatch mode=%0d row=%0d col=%0d got=%h expected=%0d",input_mode,row0,col0+p,frame_block[383-p*24 -:24],expected);
            end
            retry_total=retry_total+dut.verify_attempts;
        end
    endtask

    task load_frame(input integer mode);
        integer rr0,bb0,aa0,pp0,ww0; reg [383:0] pbuf;
        begin
            input_mode=mode;
            for(rr0=0;rr0<3;rr0=rr0+1)for(bb0=0;bb0<2;bb0=bb0+1)
                for(aa0=0;aa0<4;aa0=aa0+1)begin
                    pbuf=0;
                    for(pp0=0;pp0<16;pp0=pp0+1)
                        pbuf[383-pp0*24 -:24]=mkpix(rr0*32+bb0*16+pp0,aa0);
                    case(aa0)
                        0:for(ww0=0;ww0<3;ww0=ww0+1)mem_put(B0+rr0*48+bb0*24+ww0*8,pbuf[383-ww0*128 -:128]);
                        1:for(ww0=0;ww0<3;ww0=ww0+1)mem_put(B45+rr0*48+bb0*24+ww0*8,pbuf[383-ww0*128 -:128]);
                        2:for(ww0=0;ww0<3;ww0=ww0+1)mem_put(B90+rr0*48+bb0*24+ww0*8,pbuf[383-ww0*128 -:128]);
                        3:for(ww0=0;ww0<3;ww0=ww0+1)mem_put(B135+rr0*48+bb0*24+ww0*8,pbuf[383-ww0*128 -:128]);
                    endcase
                end
        end
    endtask

    integer row,col,angle,word_idx,block_idx,base_hs,base_vs,timeout,frame_mode,white_before;
    initial begin
        repeat(5)@(posedge clk);@(negedge clk);rst_n=1;
        if(ww!=0)$fatal(1,"bad initial write state");
        for(word_idx=0;word_idx<3;word_idx=word_idx+1)mem_put(25'd100+word_idx*8,128'h0123456789abcdef0011223344556677^word_idx);
        base_hs=hs_seen;base_vs=vs_seen;
        start_job(0,25'd100,25'd200,0);wait_done();
        if(dut.column_block!=0||hs_seen!=base_hs||vs_seen!=base_vs)
            $fatal(1,"copy operation changed the edge window/frame markers");
        for(frame_mode=0;frame_mode<2;frame_mode=frame_mode+1)begin
            load_frame(frame_mode);white_before=total_white;
            for(block_idx=0;block_idx<6;block_idx=block_idx+1)begin
                base_hs=hs_seen;base_vs=vs_seen;
                start_job(1,0,0,block_idx*24);wait_done();
                check_edge_block(block_idx*24);
                if(block_idx==0&&(vs_seen-base_vs!=1||hs_seen-base_hs!=1))
                    $fatal(1,"first block needs VS, blank, HS tags got %0d/%0d",vs_seen-base_vs,hs_seen-base_hs);
                if((block_idx==2||block_idx==4)&&(hs_seen-base_hs!=1||vs_seen-base_vs!=0))
                    $fatal(1,"line start needs HS only at block %0d",block_idx);
                if((block_idx==1||block_idx==3||block_idx==5)&&(hs_seen-base_hs!=0||vs_seen-base_vs!=0))
                    $fatal(1,"in-line block must not inject sync at block %0d",block_idx);
                if(block_idx==0&&last_hs_cycle-last_vs_cycle<2)
                    $fatal(1,"VS and HS need an empty clock between them");
            end
            if(total_white==white_before)$fatal(1,"edge frame mode %0d produced no edge pixels",frame_mode);
        end
        if(edge_write_count!=36)$fatal(1,"expected 36 edge-page writes, got %0d",edge_write_count);
        if(compute_write_count!=144)$fatal(1,"expected all 12 result writes per compute block, got %0d",compute_write_count);
        if(stale_count==0||retry_total==0)
            $fatal(1,"delayed physical writes did not exercise readback retry");
        if(dut.column_block!=0)$fatal(1,"3-line column counter did not wrap to zero");
        // A uniform frame must not inherit the preceding frame's edge window.
        load_frame(2);white_before=total_white;base_hs=hs_seen;base_vs=vs_seen;
        start_job(1,0,0,0);wait_done();check_edge_block(0);
        if(vs_seen-base_vs!=1||hs_seen-base_hs!=1)
            $fatal(1,"offset zero did not reset frame/line edge window");
        if(total_white!=white_before)$fatal(1,"new frame leaked edge pixels from previous window");
        $display("PASS polar edge blocks: 12-word write/readback, retries, 3x3 seam, frame/line tags");
        $finish;
    end
    initial begin #5000000;$fatal(1,"global test timeout");end
endmodule
