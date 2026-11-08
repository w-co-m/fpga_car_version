`timescale 1ns/1ps
module tb_polar_retry_service;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, start=0, op_compute=0;
    reg [24:0] source_addr=25'd1000, dest_addr=25'd2000, block_offset=25'd64;
    wire busy, done, error, bg_request, owner_release, bg_rd_en, bg_wr_en;
    wire [24:0] bg_addr; wire [127:0] bg_data;
    wire bg_grant, live_ready, bg_ready, vo_return_valid, bg_return_valid;
    wire [127:0] return_data; wire wr_en, rd_en; wire [24:0] addr; wire [127:0] wr_data;
    reg calibrated=0, queue_idle=1, user_ready=1, rd_valid=0;
    reg [127:0] rd_data=0;
    reg [8:0] vo_fill=9'd400; reg [9:0] vo_credit=0;
    reg vi_busy=0, vi_wr_en=0; reg [24:0] vi_addr=25'd900; reg [127:0] vi_data=128'hdeadbeef;
    reg vo_busy=0, vo_rd_en=0, vo_frame_pending=0; reg [24:0] vo_addr=25'd800;
    reg force_bad=1;
    reg [127:0] memory [0:255];
    integer cycle=0, live_reads=0, vi_writes=0, frame_services=0;
    integer release_count=0, grant_count=0, copy_verify_reads=0, compute_verify_reads=0;
    integer copy_done=0, compute_done=0, last_copy_seen=0, last_compute_seen=0;
    integer i, slot, response_slot, word_idx;
    integer copy_word_reads[0:2], compute_word_reads[0:11];
    reg pending_return=0; reg [24:0] pending_addr=0;
    always @(posedge clk)begin
      if(!rst_n)vo_credit<=0;
      else case({live_ready && vo_rd_en,vo_return_valid})
        2'b10:vo_credit<=vo_credit+1'b1;
        2'b01:if(vo_credit!=0)vo_credit<=vo_credit-1'b1;
        default:;
      endcase
    end

    polar_block_engine #(.ENABLE_EDGE(1),.IMG_WIDTH(1280)) eng(
      .clk(clk),.rst_n(rst_n),.start(start),.op_compute(op_compute),
      .source_addr(source_addr),.dest_addr(dest_addr),.block_offset(block_offset),
      .busy(busy),.done(done),.error(error),.request(bg_request),.grant(bg_grant),
      .owner_release(owner_release),.ddr_ready(bg_ready),.rd_en(bg_rd_en),.wr_en(bg_wr_en),
      .addr(bg_addr),.wr_data(bg_data),.rd_valid(bg_return_valid),.rd_data(return_data));

    polar_ddr_arbiter #(.MIN_DISPLAY_FILL(320)) arb(
      .clk(clk),.rst_n(rst_n),.calibrated(calibrated),.queue_idle(queue_idle),
      .user_ready(user_ready),.rd_valid(rd_valid),.rd_data(rd_data),
      .vi_busy(vi_busy),.vi_wr_en(vi_wr_en),.vi_addr(vi_addr),.vi_data(vi_data),
      .vo_busy(vo_busy),.vo_rd_en(vo_rd_en),.vo_frame_pending(vo_frame_pending),
      .vo_fill(vo_fill),.vo_credit(vo_credit),.vo_addr(vo_addr),
      .bg_request(bg_request),.bg_release(owner_release),.bg_rd_en(bg_rd_en),
      .bg_wr_en(bg_wr_en),.bg_addr(bg_addr),.bg_data(bg_data),.bg_grant(bg_grant),
      .live_ready(live_ready),.bg_ready(bg_ready),.vo_return_valid(vo_return_valid),
      .bg_return_valid(bg_return_valid),.return_data(return_data),.wr_en(wr_en),
      .rd_en(rd_en),.addr(addr),.wr_data(wr_data));

    function integer mem_slot(input [24:0] a);
      begin
        if(a==25'd1000) mem_slot=0; else if(a==25'd1008) mem_slot=1; else if(a==25'd1016) mem_slot=2;
        else if(a==25'd2000) mem_slot=3; else if(a==25'd2008) mem_slot=4; else if(a==25'd2016) mem_slot=5;
        else if(a>=25'd23000000 && a<25'd23000024) mem_slot=18+(a-25'd23000000)/8;
        else if(a>=25'd24400000 && a<25'd24400024) mem_slot=21+(a-25'd24400000)/8;
        else if(a>=25'd25800000 && a<25'd25800024) mem_slot=24+(a-25'd25800000)/8;
        else if(a>=25'd27200000 && a<25'd27200024) mem_slot=27+(a-25'd27200000)/8;
        else if(a>=25'd28600000 && a<25'd28600024) mem_slot=6+(a-25'd28600000)/8;
        else if(a>=25'd30000000 && a<25'd30000024) mem_slot=9+(a-25'd30000000)/8;
        else if(a>=25'd31400000 && a<25'd31400024) mem_slot=12+(a-25'd31400000)/8;
        else if(a>=25'd4000000 && a<25'd4000024) mem_slot=15+(a-25'd4000000)/8;
        else mem_slot=-1;
      end
    endfunction

    // One-cycle DDR response model. Verification corruption only affects the final
    // word of each destination set, so retries exercise full-word coverage.
    always @(posedge clk) begin
      cycle=cycle+1;
      rd_valid<=pending_return;
      if(pending_return) begin
        response_slot=mem_slot(pending_addr);
                if(response_slot<0) rd_data<=128'd0;
        else if(force_bad && ((pending_addr==25'd2016) ||
                 (pending_addr==25'd4000016))) rd_data<=memory[response_slot]^128'd1;
        else rd_data<=memory[response_slot];
      end else rd_data<=0;
      pending_return<=rd_en;
      if(rd_en) begin
        pending_addr<=addr;
        if(addr>=25'd2000 && addr<=25'd2016) begin
          copy_verify_reads=copy_verify_reads+1;
          if(addr==25'd2016) last_copy_seen=last_copy_seen+1;
          copy_word_reads[(addr-25'd2000)/8]=copy_word_reads[(addr-25'd2000)/8]+1;
        end
        if((addr>=25'd28600000 && addr<25'd28600024) ||
           (addr>=25'd30000000 && addr<25'd30000024) ||
           (addr>=25'd31400000 && addr<25'd31400024) ||
           (addr>=25'd4000000 && addr<25'd4000024)) begin
          compute_verify_reads=compute_verify_reads+1;
          if(addr==25'd4000016) last_compute_seen=last_compute_seen+1;
          if(addr>=25'd28600000 && addr<25'd28600024) word_idx=(addr-25'd28600000)/8;
          else if(addr>=25'd30000000 && addr<25'd30000024) word_idx=3+(addr-25'd30000000)/8;
          else if(addr>=25'd31400000 && addr<25'd31400024) word_idx=6+(addr-25'd31400000)/8;
          else word_idx=9+(addr-25'd4000000)/8;
          compute_word_reads[word_idx]=compute_word_reads[word_idx]+1;
        end
      end
      if(wr_en) begin
        slot=mem_slot(addr);
        if(slot>=0) memory[slot]<=wr_data;
      end
      if(owner_release) release_count=release_count+1;
      if(bg_grant) grant_count=grant_count+1;
      if(live_ready && vo_rd_en) live_reads=live_reads+1;
      if(live_ready && vi_wr_en) vi_writes=vi_writes+1;
      if(live_ready && vo_frame_pending) frame_services=frame_services+1;
      if(done) begin
        if(op_compute) compute_done=compute_done+1; else copy_done=copy_done+1;
      end
    end

    // Background grants require real arbiter admission conditions. While released,
    // display fill recovers, frame work is announced, and VI writes get service.
    always @(negedge clk) begin
      if(!rst_n) begin
        calibrated=0; vo_fill=400; vo_rd_en=0; vi_busy=0; vi_wr_en=0; vo_frame_pending=0;
      end else begin
        calibrated=1;
        vo_rd_en=(cycle%4==0);
        vi_busy=(cycle%31==0);
        vi_wr_en=vi_busy;
        vo_frame_pending=(cycle%97==0);
        if(!bg_grant && vo_fill<511) vo_fill=vo_fill+1'b1;
        else if(bg_grant && vo_fill>0) vo_fill=vo_fill-1'b1;
      end
    end

    task start_job(input integer comp);
      begin
        @(negedge clk); op_compute=comp; start=1;
        @(negedge clk); start=0;
      end
    endtask
    task wait_for_retry_boundary;
      integer t;
      begin
        t=0; while(eng.verify_attempts<4095 && t<3000000) begin @(posedge clk); #1; t=t+1; end
        if(eng.verify_attempts!=4095 || error) $fatal(1,"timeout/early error before final allowed pass busy=%b request=%b grant=%b comp_reads=%0d final=%0d done=%0d",busy,bg_request,bg_grant,compute_verify_reads,last_compute_seen,compute_done);
      end
    endtask
    task wait_for_done(input integer comp);
      integer t;
      begin
        t=0; while(!done && t<3000000) begin @(posedge clk); #1; t=t+1; end
        if(!done) $fatal(1,"timeout waiting for recovery completion error=%b grant=%b",error,bg_grant);
        if(error) $fatal(1,"recovery completed with sticky error");
        @(posedge clk); #1;
        if(comp && compute_done!=1) $fatal(1,"compute completion count=%0d",compute_done);
        if(!comp && copy_done!=1) $fatal(1,"copy completion count=%0d",copy_done);
        @(negedge clk);
      end
    endtask

    initial begin
      for(i=0;i<256;i=i+1) memory[i]=0;
      for(i=0;i<3;i=i+1) copy_word_reads[i]=0;
      for(i=0;i<12;i=i+1) compute_word_reads[i]=0;
      memory[0]=128'h11112222333344445555666677778888;
      memory[1]=128'h9999aaaabbbbccccddddeeeeffff0000;
      memory[2]=128'h0123456789abcdeffedcba9876543210;
      for(i=18;i<21;i=i+1) memory[i]=128'h2030405060708090a0b0c0d0e0f00112;
      for(i=21;i<24;i=i+1) memory[i]=128'h30405060708090a0b0c0d0e0f0011223;
      for(i=24;i<27;i=i+1) memory[i]=128'h405060708090a0b0c0d0e0f001122334;
      for(i=27;i<30;i=i+1) memory[i]=128'h5060708090a0b0c0d0e0f00112233445;
      repeat(5) @(negedge clk); rst_n=1; calibrated=1;
      start_job(0);
      wait_for_retry_boundary();
      if(eng.verify_attempts!=4095 || error) $fatal(1,"copy final pass boundary wrong attempts=%0d",eng.verify_attempts);
      if(!busy || done) $fatal(1,"copy engine completed or went idle during retry saturation");
      for(i=0;i<3;i=i+1) if(copy_word_reads[i]<4095) $fatal(1,"copy word %0d verification count=%0d",i,copy_word_reads[i]);
      if(last_copy_seen<4095 || copy_verify_reads<4095*3)
        $fatal(1,"copy verification did not cover all three words reads=%0d last=%0d",copy_verify_reads,last_copy_seen);
      if(live_reads==0 || vi_writes==0 || frame_services==0)
        $fatal(1,"arbiter service coverage missing live=%0d vi=%0d frames=%0d",live_reads,vi_writes,frame_services);
      if(release_count<4095 || grant_count<=release_count)
        $fatal(1,"background ownership was not repeatedly released grants=%0d releases=%0d",grant_count,release_count);
      $display("COPY SATURATED attempts=%0d verify_reads=%0d grants=%0d releases=%0d live=%0d vi=%0d frames=%0d",
               eng.verify_attempts,copy_verify_reads,grant_count,release_count,live_reads,vi_writes,frame_services);
      @(negedge clk); force_bad=0; wait_for_done(0);
      if(error) $fatal(1,"copy recovery failed to clear retry error");

      // Run algorithm-9 with all four angle inputs and all twelve output words.
      // Distinct four-angle source words exercise the normal compute and edge path.
      @(negedge clk); force_bad=1; source_addr=0; dest_addr=0; block_offset=25'd0;
      start_job(1);
      wait_for_retry_boundary();
      if(eng.verify_attempts!=4095 || error) $fatal(1,"compute final pass boundary wrong");
      if(!busy || done) $fatal(1,"compute engine completed or went idle during retry saturation");
      for(i=0;i<12;i=i+1) if(compute_word_reads[i]<4095) $fatal(1,"compute word %0d verification count=%0d",i,compute_word_reads[i]);
      if(last_compute_seen<4095 || compute_verify_reads<4095*12)
        $fatal(1,"compute verification did not cover twelve words reads=%0d last=%0d",compute_verify_reads,last_compute_seen);
      $display("COMPUTE SATURATED attempts=%0d verify_reads=%0d final_word_reads=%0d",eng.verify_attempts,compute_verify_reads,last_compute_seen);
      @(negedge clk); force_bad=0; wait_for_done(1);
      if(error) $fatal(1,"compute recovery failed to clear retry error");
      if(copy_done!=1 || compute_done!=1) $fatal(1,"done counts copy=%0d compute=%0d",copy_done,compute_done);
      $display("PASS retry service: copy 3 words and compute 12 words yielded to live video/VI, 4095 mismatch passes, final allowed pass recovered");
      $finish;
    end
    initial begin #40000000; $fatal(1,"global timeout"); end
endmodule
