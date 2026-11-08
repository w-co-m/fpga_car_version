`timescale 1ns/1ps
// 真实后台+真实算法核的小帧端到端验证：4次采集、读回重试、3张结果、CDC与重新采集。
module tb_polar_backend;
    `include "algo7_delivery_math_ref.vh"
    reg pix=0,cam=0,ddr=0;always #7 pix=~pix;always #6 cam=~cam;always #5 ddr=~ddr;
    reg rst_n=0;reg[3:0] mode=9,displayed_mode=0;
    reg cap=0,restart=0,frame=0,displayed_result=0;
    wire pause,owner,live_ready,vo_rv,we,re,result_source;
    wire [24:0]addr,base;wire[127:0]data;wire[3:0]source_mode,render;
    wire[1:0]angle;wire capbusy,compbusy,ready,error,fixed_wb;
    reg user_ready=1,rv=0;reg[127:0]rd_data=0;
    reg[127:0]mem[0:65];
    reg[127:0]read_queue[0:8191],write_queue[0:8191];
    integer write_index[0:8191],write_due[0:8191],read_due[0:8191];
    integer wh=0,wt=0,rh=0,rt=0,cycles=0,errors=0,writes=0,reads=0;
    integer a,p,b,j,k,idx,group_id=0,c,dp,yf,delta,actual,ref_pair,gain_adj;
    reg[383:0]packed;reg[23:0]expected;
    polar_video_backend #(.FRAME_BLOCKS(2),.SETTLE_FRAMES(3)) dut(
        .pixel_clk(pix),.camera_clk(cam),.ddr_clk(ddr),.rst_n(rst_n),.requested_mode(mode),.capture_pulse(cap),.restart_pulse(restart),
        .camera_frame_start(frame),.live_page(2'd2),.page_valid(4'b1111),.displayed_mode(displayed_mode),.displayed_result(displayed_result),
        .vo_busy(1'b0),.vo_frame_pending(1'b0),.vo_fill(9'd400),.vo_credit(10'd0),.vo_rd_en(1'b0),.vo_addr(25'd0),
        .vi_busy(1'b0),.vi_wr_en(1'b0),.vi_addr(25'd0),.vi_data(128'd0),
        .calibrated(1'b1),.queue_idle(1'b1),.user_ready(user_ready),.user_rd_valid(rv),.user_rd_data(rd_data),
        .display_pause(pause),.background_owner(owner),.live_ready(live_ready),.vo_return_valid(vo_rv),
        .user_wr_en(we),.user_rd_en(re),.user_addr(addr),.user_wr_data(data),.source_base(base),.source_mode(source_mode),.source_is_result(result_source),
        .render_mode(render),.polar_angle(angle),.polar_capture_busy(capbusy),.polar_compute_busy(compbusy),.polar_ready(ready),.polar_error(error),.fixed_white_balance(fixed_wb));
    function integer map_addr;
        input[24:0]x;
        integer page,off;
        begin
            if(x>=31400000)begin page=10;off=x-31400000;end
            else if(x>=30000000)begin page=9;off=x-30000000;end
            else if(x>=28600000)begin page=8;off=x-28600000;end
            else if(x>=27200000)begin page=7;off=x-27200000;end
            else if(x>=25800000)begin page=6;off=x-25800000;end
            else if(x>=24400000)begin page=5;off=x-24400000;end
            else if(x>=23000000)begin page=4;off=x-23000000;end
            else if(x>=21000000)begin page=3;off=x-21000000;end
            else if(x>=14000000)begin page=2;off=x-14000000;end
            else if(x>=7000000)begin page=1;off=x-7000000;end
            else begin page=0;off=x;end
            if(off<0 || off>=48 || off%8!=0)map_addr=-1;
            else map_addr=page*6+off/8;
        end
    endfunction
    always @(posedge ddr)begin
        if(rst_n)begin
            cycles=cycles+1;
            user_ready<=((cycles%7)!=2 && (cycles%7)!=3);
            rv<=0;
            if(wh<wt && write_due[wh]<=cycles)begin mem[write_index[wh]]=write_queue[wh];wh=wh+1;end
            if(rh<rt && read_due[rh]<=cycles)begin rv<=1;rd_data<=read_queue[rh];rh=rh+1;end
            if(we || re)begin
                idx=map_addr(addr);
                if(idx<0 || !owner || !user_ready || (we && re))begin
                    $display("FAIL bus/address owner=%b ready=%b addr=%d",owner,user_ready,addr);errors=errors+1;
                end else if(we)begin
                    write_queue[wt]=data;write_index[wt]=idx;write_due[wt]=cycles+35;wt=wt+1;writes=writes+1;
                    if(idx>=48 && displayed_result)begin $display("FAIL overwrote active result");errors=errors+1;end
                end else begin
                    // 可以先读到旧数据，块引擎必须重试ALL words直到一致。
                    read_queue[rt]=mem[idx];read_due[rt]=cycles+4;rt=rt+1;reads=reads+1;
                end
            end
        end
    end
    task pix_tick;begin @(negedge pix);end endtask
    task frame_event;begin @(negedge ddr);frame=1;@(negedge ddr);frame=0;repeat(6)@(negedge ddr);end endtask
    function [23:0] make_rgb;
        input integer r,g,b;
        begin make_rgb={r[7:0],g[7:0],b[7:0]};end
    endfunction
    function [23:0] aop_hue_ref;
        input [7:0] a;
        reg [7:0] seg,t,fr;
        begin
            if      (a<43)  begin seg=0;t=a;end
            else if (a<86)  begin seg=1;t=a-43;end
            else if (a<129) begin seg=2;t=a-86;end
            else if (a<172) begin seg=3;t=a-129;end
            else if (a<215) begin seg=4;t=a-172;end
            else            begin seg=5;t=a-215;end
            fr=(t<<2)+(t<<1);
            case(seg)
                0:aop_hue_ref={8'd255,fr,8'd0};
                1:aop_hue_ref={8'd255-fr,8'd255,8'd0};
                2:aop_hue_ref={8'd0,8'd255,fr};
                3:aop_hue_ref={8'd0,8'd255-fr,8'd255};
                4:aop_hue_ref={fr,8'd0,8'd255};
                default:aop_hue_ref={8'd255,8'd0,8'd255-fr};
            endcase
        end
    endfunction
    function integer sat8;
        input integer value;
        begin sat8=value<0?0:value>255?255:value;end
    endfunction
    task fill_live;
        input integer angle_id;
        integer block_id,pixel_id,c;reg[23:0]rgb;
        begin for(block_id=0;block_id<2;block_id=block_id+1)begin
            packed=0;
            for(pixel_id=0;pixel_id<16;pixel_id=pixel_id+1)begin
                c=64+block_id*16+pixel_id;
                if(group_id==1)case(angle_id)
                    0:c=180+block_id*16+pixel_id;
                    2:c=60+block_id*16+pixel_id;
                    default:c=120+block_id*16+pixel_id;
                endcase
                rgb=make_rgb(64+angle_id*4,c,96-angle_id*4);
                packed={packed[359:0],rgb};
            end
            for(c=0;c<3;c=c+1)mem[12+block_id*3+c]=packed[383-c*128 -:128];
        end end
    endtask
    initial begin
        for(j=0;j<66;j=j+1)mem[j]=128'hfedc;
        repeat(5)pix_tick;rst_n=1;repeat(20)pix_tick;
        if(!fixed_wb)begin $display("FAIL WB not fixed");errors=errors+1;end
        for(a=0;a<4;a=a+1)begin
            fill_live(a);cap=1;pix_tick;cap=0;wait(capbusy);
            repeat(4)frame_event;
            wait(!capbusy);repeat(10)pix_tick;
            for(j=0;j<6;j=j+1)if(mem[(4+a)*6+j]!==mem[12+j])begin $display("FAIL snapshot angle=%d word=%d",a,j);errors=errors+1;end
        end
        wait(ready);repeat(20)pix_tick;
        if(error || !result_source || base!=28600000 || wh!=wt)begin $display("FAIL publication");errors=errors+1;end
        for(b=0;b<2;b=b+1)begin
            packed=0;for(p=0;p<16;p=p+1)packed={packed[359:0],24'h000000};
            for(j=0;j<3;j=j+1)if(mem[48+b*3+j]!==packed[383-j*128 -:128])errors=errors+1;
            packed=0;for(p=0;p<16;p=p+1)packed={packed[359:0],aop_hue_ref(8'd128)};
            for(j=0;j<3;j=j+1)if(mem[54+b*3+j]!==packed[383-j*128 -:128])errors=errors+1;
            packed=0;for(p=0;p<16;p=p+1)begin expected=make_rgb(70,64+b*16+p,90);packed={packed[359:0],expected};end
            for(j=0;j<3;j=j+1)if(mem[60+b*3+j]!==packed[383-j*128 -:128])begin $display("FAIL fusion packing block=%d word=%d got=%h expected=%h",b,j,mem[60+b*3+j],packed[383-j*128 -:128]);errors=errors+1;end
        end
        // 三种模式选择已完成结果；render来自实际显示反馈。
        for(k=9;k<=11;k=k+1)begin
            mode=k;repeat(20)pix_tick;displayed_mode=source_mode;displayed_result=result_source;repeat(20)pix_tick;
            if(base!=28600000+(k-9)*1400000 || render!=k)errors=errors+1;
        end
        // READY后新的NEXT从0°开始，清ready后旧结果仍保持displayed_result直到下一VS。
        cap=1;pix_tick;cap=0;wait(capbusy);repeat(15)pix_tick;
        if(ready || result_source || angle!=0)begin $display("FAIL new group reset");errors=errors+1;end
        restart=1;pix_tick;restart=0;repeat(30)pix_tick;
        if(capbusy || compbusy || pause || ready)begin $display("FAIL restart");errors=errors+1;end
        group_id=1;
        for(a=0;a<4;a=a+1)begin
            mode=9;repeat(20)pix_tick;fill_live(a);cap=1;pix_tick;cap=0;wait(capbusy);
            if(a==0)begin
                // 采集过程中离开偏振模式，固定增益仍须保持直到整组结束/重启。
                mode=8;repeat(20)pix_tick;
                if(!fixed_wb)begin $display("FAIL WB unlocked during capture");errors=errors+1;end
            end
            repeat(4)frame_event;wait(!capbusy);repeat(10)pix_tick;
            for(j=0;j<6;j=j+1)if(mem[(4+a)*6+j]!==mem[12+j])errors=errors+1;
        end
        repeat(20)pix_tick;
        if(ready || !compbusy || writes!=66)begin $display("FAIL result overwrite before display ack writes=%d",writes);errors=errors+1;end
        displayed_result=0;wait(ready);repeat(20)pix_tick;
        for(b=0;b<2;b=b+1)begin
            packed=0;
            for(p=0;p<16;p=p+1)begin
                c=b*16+p;ref_pair=algo7_delivery_ref(180+c,120+c,60+c,120+c,16,8);
                packed={packed[359:0],{3{ref_pair[15:8]}}};
            end
            for(j=0;j<3;j=j+1)if(mem[48+b*3+j]!==packed[383-j*128 -:128])begin $display("FAIL DoLP exact packing block=%d word=%d",b,j);errors=errors+1;end
            packed=0;
            for(p=0;p<16;p=p+1)begin
                c=b*16+p;ref_pair=algo7_delivery_ref(180+c,120+c,60+c,120+c,16,8);
                packed={packed[359:0],aop_hue_ref(ref_pair[7:0])};
            end
            for(j=0;j<3;j=j+1)if(mem[54+b*3+j]!==packed[383-j*128 -:128])begin $display("FAIL AoP hue packing block=%d word=%d",b,j);errors=errors+1;end
            packed=0;
            for(p=0;p<16;p=p+1)begin
                c=b*16+p;ref_pair=algo7_delivery_ref(180+c,120+c,60+c,120+c,16,8);dp=ref_pair[15:8];
                gain_adj=(64*dp)>>7;yf=((120+c)*(256-gain_adj))>>8;delta=yf-(120+c);
                expected=make_rgb(sat8(70+delta),sat8(120+c+delta),sat8(90+delta));packed={packed[359:0],expected};
            end
            for(j=0;j<3;j=j+1)if(mem[60+b*3+j]!==packed[383-j*128 -:128])begin $display("FAIL fusion exact packing block=%d word=%d got=%h expected=%h",b,j,mem[60+b*3+j],packed[383-j*128 -:128]);errors=errors+1;end
        end
        mode=0;repeat(20)pix_tick;
        if(fixed_wb || base!=14000000)errors=errors+1;
        $display("tb_polar_backend %s errors=%0d writes=%0d reads=%0d",errors==0?"PASS":"FAIL",errors,writes,reads);$finish;
    end
    initial begin #1000000;$display("FAIL backend timeout");$finish;end
endmodule
