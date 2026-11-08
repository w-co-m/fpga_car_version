`timescale 1ns/1ps
module polar_cache_case #(parameter integer ENABLE_EDGE=0) (output reg finished=0);
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0,op_compute=0;
    reg [24:0] source_addr=0,dest_addr=0,block_offset=0;
    wire busy,done,error,request,rd_en,wr_en,owner_release;
    reg grant=0,ddr_ready=0,rd_valid=0;
    wire [24:0] addr;
    wire [127:0] wr_data;
    reg [127:0] rd_data=0;
    reg allow_grant=0;
        wire busy_d,error_d,request_d,rd_en_d,wr_en_d,owner_release_d,done_d;
    wire [24:0] addr_d; wire [127:0] wr_data_d;
    wire reset_required_d;
    polar_block_engine_ref #(.ENABLE_EDGE(ENABLE_EDGE),.IMG_WIDTH(32)) ref_inst(.*);
    polar_block_engine #(.ENABLE_EDGE(ENABLE_EDGE),.IMG_WIDTH(32)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.op_compute(op_compute),
        .source_addr(source_addr),.dest_addr(dest_addr),.block_offset(block_offset),
        .busy(busy_d),.done(done_d),.error(error_d),.request(request_d),.grant(grant),
        .owner_release(owner_release_d),.ddr_ready(ddr_ready),.rd_en(rd_en_d),.wr_en(wr_en_d),
        .addr(addr_d),.wr_data(wr_data_d),.rd_valid(rd_valid),.rd_data(rd_data),
        .abort_req(1'b0),.abort_ack(),.reset_required(reset_required_d));
    integer compared_cycles=0, reset_cycles=0, simultaneous_read_return=0, command_active_samples=0, write_data_samples=0;
    always @(posedge clk) begin
        compared_cycles=compared_cycles+1;
        if(!rst_n) reset_cycles=reset_cycles+1;
        // The frozen controller intentionally keeps retrying past the new hard
        // failure boundary. Normal transactions remain cycle-exact until then.
        if (!reset_required_d && {busy,done,error,request,owner_release,rd_en,wr_en} !==
            {busy_d,done_d,error_d,request_d,owner_release_d,rd_en_d,wr_en_d})
            $fatal(1,"cycle mismatch edge=%0d cycle=%0d",ENABLE_EDGE,cycle);
        if (!reset_required_d && (rd_en||wr_en) && addr!==addr_d) $fatal(1,"address mismatch edge=%0d cycle=%0d",ENABLE_EDGE,cycle);
        if (!reset_required_d && wr_en && wr_data!==wr_data_d) $fatal(1,"write data mismatch edge=%0d cycle=%0d",ENABLE_EDGE,cycle);
        if (rst_n) begin
            if (rd_en||wr_en) command_active_samples=command_active_samples+1;
            if (wr_en) write_data_samples=write_data_samples+1;
            if (dut.state==4 && (dut.fusion_de || (ENABLE_EDGE&&dut.edge_de)))
                $fatal(1,"output capture overlapped input feed edge=%0d",ENABLE_EDGE);
            if (dut.state==6 && (dut.fused_count!=16 || (ENABLE_EDGE&&dut.edge_count!=16)))
                $fatal(1,"result capture incomplete at build edge=%0d fused=%0d edge_count=%0d",ENABLE_EDGE,dut.fused_count,dut.edge_count);
            if (rd_valid&&rd_en) simultaneous_read_return=simultaneous_read_return+1;
        end
    end

    localparam [24:0] B0=25'd23000000,B45=25'd24400000,
        B90=25'd25800000,B135=25'd27200000,BDP=25'd28600000,
        BAP=25'd30000000,BF=25'd31400000;

    // Ordered DDR response model with variable return and delayed physical writes.
    reg [24:0] mem_addr[0:127];
    reg [127:0] mem_data[0:127];
    integer mem_count=0;
    reg [24:0] rq_addr[0:65535];
    integer rq_due[0:65535];
    integer rq_wr=0,rq_rd=0;
    reg [24:0] wq_addr[0:255];
    reg [127:0] wq_data[0:255];
    integer wq_due[0:255];
    integer wq_wr=0,wq_rd=0;
    integer cycle=0,seed=19273,grant_revoke=0,committed_writes=0;
    integer last_mismatch_once=0, permanent_mismatch=0, delay_writes=1, hold_returns=0;
    integer accepted_reads=0,accepted_writes=0,stale_reads=0;
    integer mi,qi,rv,delay_val;
    function integer find_slot(input [24:0] a);
        integer s;
        begin find_slot=-1; for(s=0;s<128;s=s+1)if(s<mem_count&&mem_addr[s]==a)find_slot=s; end
    endfunction
    function [127:0] mem_get(input [24:0] a);
        integer s;
        begin s=find_slot(a); if(s<0)mem_get=128'd0;else mem_get=mem_data[s]; end
    endfunction
    task mem_put(input [24:0] a,input [127:0] d);
        integer s;
        begin s=find_slot(a);if(s<0)begin s=mem_count;mem_count=mem_count+1;mem_addr[s]=a;end mem_data[s]=d;end
    endtask
    always @(posedge clk) begin
        cycle=cycle+1;
        if(rd_en)begin
            if(!grant||!ddr_ready)$fatal(1,"read command without grant/ready");
            if(rq_wr>=65535)$fatal(1,"read queue overflow");
            rq_addr[rq_wr]=addr;
            delay_val=2+($random(seed)&7);
            if(rq_wr==0)rq_due[rq_wr]=cycle;
            else rq_due[rq_wr]=rq_due[rq_wr-1]+(delay_val&3);
            rq_wr=rq_wr+1;accepted_reads=accepted_reads+1;
        end
        if(wr_en)begin
            if(!grant||!ddr_ready)$fatal(1,"write command without grant/ready");
            if(wq_wr>=255)$fatal(1,"write queue overflow");
            wq_addr[wq_wr]=addr;wq_data[wq_wr]=wr_data;wq_due[wq_wr]=cycle+(delay_writes?40:1);
            wq_wr=wq_wr+1;accepted_writes=accepted_writes+1;
        end
    end
    always @(negedge clk) begin
        if(!rst_n)begin rq_wr=0;rq_rd=0;wq_wr=0;wq_rd=0;rd_valid=0;rd_data=0;grant=0;grant_revoke=0;end
        rv=$random(seed);ddr_ready=((rv&3)!=0);
        if(permanent_mismatch)begin ddr_ready=1; if(owner_release)begin grant_revoke=1; grant=1; end else if(grant_revoke>0)begin grant_revoke=grant_revoke-1; grant=0; end else if(request)grant=1; end
        else if(owner_release)grant_revoke=3;
        else if(grant_revoke>0)begin
            grant_revoke=grant_revoke-1;
            if(grant_revoke==0)grant=0;
        end else if(allow_grant&&request)grant=1;

        // Physical writes land well after command acceptance.
        while(wq_rd<wq_wr&&wq_due[wq_rd]<=cycle)begin
            mem_put(wq_addr[wq_rd],wq_data[wq_rd]);
            wq_rd=wq_rd+1;committed_writes=committed_writes+1;
        end
        if(!hold_returns&&rq_rd<rq_wr&&rq_due[rq_rd]<=cycle)begin
            rd_valid=1;rd_data=mem_get(rq_addr[rq_rd]);
            if(permanent_mismatch && (dut.state==8 || dut.state==9) && dut.verify_returned==dut.write_total-1) rd_data=~rd_data;
            else if(last_mismatch_once && (dut.state==8 || dut.state==9) && dut.verify_returned==dut.write_total-1) begin rd_data=~rd_data;last_mismatch_once=0;end
            // Count readback responses that observe a queued, uncommitted write.
            for(qi=0;qi<wq_wr;qi=qi+1)
                if(qi>=wq_rd&&wq_addr[qi]==rq_addr[rq_rd])stale_reads=stale_reads+1;
            rq_rd=rq_rd+1;
        end else begin rd_valid=0;rd_data=0;end
    end

    function [23:0] mkpix(input integer angle,input integer pix);
        integer r,g,b;
        begin r=40+pix*3+angle*7;g=20+pix*2+angle*15;b=10+pix*5+angle*11;mkpix={r[7:0],g[7:0],b[7:0]};end
    endfunction
    function [23:0] palette_ref(input [7:0] a);
        integer segment,offset,fade;
        begin
            segment=a/43;offset=a-segment*43;fade=offset*6;
            case(segment)
                0:palette_ref={8'd255,fade[7:0],8'd0};
                1:palette_ref={8'd255-fade[7:0],8'd255,8'd0};
                2:palette_ref={8'd0,8'd255,fade[7:0]};
                3:palette_ref={8'd0,8'd255-fade[7:0],8'd255};
                4:palette_ref={fade[7:0],8'd0,8'd255};
                default:palette_ref={8'd255,8'd0,8'd255-fade[7:0]};
            endcase
        end
    endfunction
    reg [383:0] source_pixels[0:3];
    integer a,p,w;
    reg [7:0] gi0,gi45,gi90,gi135;
    reg [23:0] gc0,gc45,gc90,gc135;
    reg gde=0,gactive=0;
    wire [23:0] gprgb,grgb;
    wire [7:0] gpy,gpdp,gpap,gy,gdp,gap;
    wire gpde,gph,gpv,gfbin,gfde,gfh,gfv;
    reg [7:0] gi0r=0,gi45r=0,gi90r=0,gi135r=0,gthr=8'h40;
    reg [23:0] gc0r=0,gc45r=0,gc90r=0,gc135r=0;
    reg [383:0] gdolp=0,gaop=0,gfusion=0;
    integer graw_count=0,gfusion_count=0;
    algo_polar_fusion golden(
        .clk(clk),.rst_n(rst_n),.i0(gi0r),.i45(gi45r),.i90(gi90r),.i135(gi135r),
        .rgb0(gc0r),.rgb45(gc45r),.rgb90(gc90r),.rgb135(gc135r),
        .de_in(gde),.hs_in(1'b0),.vs_in(1'b0),.thr_in(gthr),
        .polar_rgb_out(gprgb),.polar_y_out(gpy),.polar_dolp_out(gpdp),.polar_aop_out(gpap),
        .polar_de_out(gpde),.polar_hs_out(gph),.polar_vs_out(gpv),
        .rgb_out(grgb),.y_out(gy),.dolp_out(gdp),.aop_out(gap),.bin_out(gfbin),
        .de_out(gfde),.hs_out(gfh),.vs_out(gfv));
    always @(posedge clk)if(gactive)begin
        if(gpde&&graw_count<16)graw_count=graw_count+1;
        if(gfde&&gfusion_count<16)begin
            gdolp={gdolp[359:0],{3{gdp}}};gaop={gaop[359:0],palette_ref(gap)};
            gfusion={gfusion[359:0],grgb};gfusion_count=gfusion_count+1;
        end
    end

    task start_job(input integer comp,input [24:0] src,input [24:0] dst,input [24:0] off);
        begin @(negedge clk);op_compute=comp;source_addr=src;dest_addr=dst;block_offset=off;start=1;
              @(negedge clk);start=0;end
    endtask
    task wait_done;
        integer timeout;
        begin timeout=0;while(!done&&timeout<30000)begin @(posedge clk);#1;timeout=timeout+1;end
              if(!done)$fatal(1,"timeout waiting for block engine, state=%0d error=%b",dut.state,error);
              if(error)$fatal(1,"unexpected sticky error");
              if(wq_rd!=wq_wr)$fatal(1,"done before delayed physical writes committed");
              @(posedge clk);#1;end
    endtask
    task reset_at_state(input integer comp,input integer target_state);
        integer t;
        begin
            hold_returns=(target_state==2);delay_writes=(target_state==15);
            allow_grant=1;
            start_job(comp,25'd1000,25'd8000+target_state*16,25'd2000);
            t=0;while(dut.state!=target_state&&t<10000)begin @(negedge clk);t=t+1;end
            if(dut.state!=target_state)$fatal(1,"reset target state timeout edge=%0d state=%0d target=%0d",ENABLE_EDGE,dut.state,target_state);
            if(target_state==2 && rq_rd>=rq_wr)$fatal(1,"reset stale-response case had no queued response edge=%0d",ENABLE_EDGE);
            @(negedge clk);rst_n=0;start=0;rd_valid=0;grant=0;
            repeat(2)@(negedge clk);
            rst_n=1;hold_returns=0;allow_grant=1;
            repeat(2)begin @(posedge clk);#1;if(rd_valid||busy||request||done||error)$fatal(1,"reset did not clear state/stale response edge=%0d",ENABLE_EDGE);end
        end
    endtask
    task compare_mem(input [24:0] a,input [127:0] expected);
        begin if(mem_get(a)!==expected)$fatal(1,"memory mismatch at %0d got %h expected %h",a,mem_get(a),expected);end
    endtask

    integer timeout;
    reg [127:0] copy0,copy1,copy2;
    reg [127:0] expword[0:8];
    initial begin
        repeat(5)@(posedge clk);@(negedge clk);rst_n=1;
        // Pack each 16-pixel RGB888 block MSB first across 128-bit words.
        copy0=128'h0123456789abcdef0011223344556677;
        copy1=128'h89abcdef0123456789abcdeffedcba98;
        copy2=128'h55aa55aa55aa55aa1234567890abcdef;
        mem_put(25'd1000,copy0);mem_put(25'd1008,copy1);mem_put(25'd1016,copy2);
        mem_put(25'd4000,~copy0);mem_put(25'd4008,~copy1);mem_put(25'd4016,~copy2);
        for(a=0;a<4;a=a+1)begin
            source_pixels[a]=0;
            for(p=0;p<16;p=p+1)source_pixels[a][383-p*24 -:24]=mkpix(a,p);
            case(a)
                0:for(w=0;w<3;w=w+1)begin mem_put(B0+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B0+25'd2000+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B0+25'd2016+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B0+25'd3000+w*8,source_pixels[a][383-w*128 -:128]);end
                1:for(w=0;w<3;w=w+1)begin mem_put(B45+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B45+25'd2000+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B45+25'd2016+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B45+25'd3000+w*8,source_pixels[a][383-w*128 -:128]);end
                2:for(w=0;w<3;w=w+1)begin mem_put(B90+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B90+25'd2000+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B90+25'd2016+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B90+25'd3000+w*8,source_pixels[a][383-w*128 -:128]);end
                3:for(w=0;w<3;w=w+1)begin mem_put(B135+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B135+25'd2000+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B135+25'd2016+w*8,source_pixels[a][383-w*128 -:128]);mem_put(B135+25'd3000+w*8,source_pixels[a][383-w*128 -:128]);end
            endcase
        end

        // A request cannot issue a command until grant is enabled.
        allow_grant=0;start_job(0,25'd1000,25'd3000,0);
        repeat(8)begin @(posedge clk);#1;if(rd_en||wr_en)$fatal(1,"issued a DDR command without grant");end
        @(negedge clk);allow_grant=1;
        wait_done();
        compare_mem(25'd3000,copy0);compare_mem(25'd3008,copy1);compare_mem(25'd3016,copy2);
        if(stale_reads==0)$fatal(1,"test did not exercise readback before physical writes landed");
        start_job(0,25'd4000,25'd5000,0);wait_done();
        compare_mem(25'd5000,~copy0);compare_mem(25'd5008,~copy1);compare_mem(25'd5016,~copy2);
        $display("PASS copy: two 3-word blocks matched after delayed physical writes and %0d stale verification observations",stale_reads);

        // Capture a separate real-core golden result for memory checks.
        gactive=1;graw_count=0;gfusion_count=0;gdolp=0;gaop=0;gfusion=0;
        for(p=0;p<16;p=p+1)begin
            @(negedge clk);gc0r=mkpix(0,p);gc45r=mkpix(1,p);gc90r=mkpix(2,p);gc135r=mkpix(3,p);
            gi0r=gc0r[15:8];gi45r=gc45r[15:8];gi90r=gc90r[15:8];gi135r=gc135r[15:8];gde=1;
        end
        @(negedge clk);gde=0;
        timeout=0;while((graw_count<16||gfusion_count<16)&&timeout<200)begin @(posedge clk);#1;timeout=timeout+1;end
        if(graw_count!=16||gfusion_count!=16)$fatal(1,"golden pipeline count raw=%0d fused=%0d",graw_count,gfusion_count);
        gactive=0;
        for(w=0;w<3;w=w+1)begin
            expword[w]=gdolp[383-w*128 -:128];expword[w+3]=gaop[383-w*128 -:128];
            expword[w+6]=gfusion[383-w*128 -:128];
        end
        start_job(1,0,0,25'd0);
        wait_done();
        for(w=0;w<3;w=w+1)begin
            compare_mem(BDP+w*8,expword[w]);
            compare_mem(BAP+w*8,expword[w+3]);
            compare_mem(BF+w*8,expword[w+6]);
        end
        start_job(1,0,0,25'd2000);
        wait_done();
        for(w=0;w<3;w=w+1)begin
            compare_mem(BDP+25'd2000+w*8,expword[w]);
            compare_mem(BAP+25'd2000+w*8,expword[w+3]);
            compare_mem(BF+25'd2000+w*8,expword[w+6]);
        end
        start_job(1,0,0,25'd3000);wait_done();
        for(w=0;w<3;w=w+1)begin
            compare_mem(BDP+25'd3000+w*8,expword[w]);
            compare_mem(BAP+25'd3000+w*8,expword[w+3]);
            compare_mem(BF+25'd3000+w*8,expword[w+6]);
        end
        $display("PASS compute: two 16-pixel blocks -> DoLP/AoP/FUSION; all 18 words match golden algorithm chain");
        if(accepted_reads<80||accepted_writes<24)$fatal(1,"DDR command coverage too small r=%0d w=%0d",accepted_reads,accepted_writes);
        if(simultaneous_read_return==0)$fatal(1,"no same-cycle read request/return observed edge=%0d",ENABLE_EDGE);
        delay_writes=0;
        reset_at_state(0,1);reset_at_state(0,2);reset_at_state(0,3);
        reset_at_state(1,4);reset_at_state(1,5);
        reset_at_state(0,7);reset_at_state(0,8);reset_at_state(0,9);
        reset_at_state(0,15);reset_at_state(0,10);
        $display("PASS reset states: 1,2,3,4,5,7,8,9,15,10 plus stale-response flush edge=%0d",ENABLE_EDGE);
        last_mismatch_once=1;
        start_job(0,25'd1000,25'd6000,0);wait_done();
        if(last_mismatch_once!==0) $fatal(1,"directed last-word mismatch was not injected");
        $display("PASS last-word mismatch: single retry recovered (edge=%0d)",ENABLE_EDGE);
        permanent_mismatch=1;
        start_job(0,25'd1000,25'd7000,0);
        timeout=0;while(!error&&timeout<400000)begin @(posedge clk);#1;timeout=timeout+1;end
        if(!error_d || !reset_required_d || dut.verify_attempts!==13'd4096) $fatal(1,"verify terminal/error missing edge=%0d cycles=%0d attempts=%h error=%b",ENABLE_EDGE,timeout,dut.verify_attempts,error_d);
        permanent_mismatch=0;
        repeat(20)begin @(posedge clk);#1;if(rd_en_d || wr_en_d || done_d || !busy_d || !reset_required_d)$fatal(1,"terminal escaped quarantine");end
        $display("PASS terminal: 4096 mismatch passes then quarantine edge=%0d cycles=%0d",ENABLE_EDGE,timeout);
        if(reset_cycles<20 || compared_cycles<25000 || command_active_samples<10000 || write_data_samples<30)
            $fatal(1,"equivalence coverage below threshold edge=%0d reset=%0d cycles=%0d commands=%0d writes=%0d",ENABLE_EDGE,reset_cycles,compared_cycles,command_active_samples,write_data_samples);
        $display("PASS polar_cache_case edge=%0d cycles=%0d reset_cycles=%0d active_commands=%0d write_data=%0d simultaneous_rd=%0d stale=%0d reset_states=10",ENABLE_EDGE,compared_cycles,reset_cycles,command_active_samples,write_data_samples,simultaneous_read_return,stale_reads);
        finished=1;
    end
endmodule

module tb_polar_cache_equiv;
    wire finished0,finished1;
    polar_cache_case #(0) case_no_edge(finished0);
    polar_cache_case #(1) case_edge(finished1);
    initial begin
        wait(finished0&&finished1);
        $display("PASS tb_polar_cache_equiv edge0+edge1 cycle-by-cycle equivalence");
        $finish;
    end
    initial begin #30000000;$fatal(1,"global test timeout");end
endmodule











