`timescale 1ns/1ps
// Streaming run CCL. Only two lines of runs are stored, never a frame mask.
// One object is selected; disconnected colors cannot enlarge its rectangle.
// ponytail: bounded to 32 runs/line and 15 live labels. Overflow discards the
// frame measurement (short hold, then invalid), never silently unions regions.
// A row is processed while the next row arrives. At 1280 pixels this also fits
// the worst 32-run interval join. Tiny test images must supply extra blanking.
module red_region_selector #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter integer XW=$clog2(IMG_WIDTH), YW=$clog2(IMG_HEIGHT),
    parameter integer HIT_W=$clog2(IMG_WIDTH*IMG_HEIGHT+1),
    parameter integer MIN_PIX=16,
    parameter integer MAX_RUNS=32, RUN_AW=5,
    parameter integer LABELS=16, LABEL_W=4,
    parameter integer RUN_GAP=3, MIN_RUN_HITS=2,
    parameter integer HOLD_FRAMES=2, JITTER_PIX=2,
    parameter integer ASSOC_MARGIN=(IMG_WIDTH/40<4)?4:IMG_WIDTH/40
)(
    input wire clk,rst_n,enable_in,frame_start,de_in,hit_in,
    input wire [XW-1:0] x_in,
    input wire [YW-1:0] y_in,
    output reg [XW-1:0] x_min,x_max,
    output reg [YW-1:0] y_min,y_max,
    output reg valid,
    output reg [HIT_W-1:0] hits,
    output reg measurement_valid, // published at VS; never true for a held box
    output wire overflow
);
    localparam RAW_W=3*XW+1, LAB_W=2*XW+LABEL_W;
    localparam IDLE=0,RETIRE=1,LOAD_CUR=2,USE_CUR=3,
               LOAD_PREV=4,USE_PREV=5,ADD_RUN=6,ROW_DONE=7;
    reg [3:0] state;
    reg [RAW_W-1:0] run_mem[0:2*MAX_RUNS-1];
    reg [LAB_W-1:0] label_mem[0:2*MAX_RUNS-1];
    reg [RAW_W-1:0] raw_word;
    reg [LAB_W-1:0] prev_word;
    reg de_prev,run_open,capture_bank;
    reg [XW-1:0] run_lo,run_hi;
    reg [XW:0] run_hits;
    reg [3:0] gap;
    reg [RUN_AW:0] capture_count;
    reg [YW-1:0] capture_y;
    reg capture_bad,engine_bad;
    wire line_done=de_prev && !de_in;
    wire close_run=run_open && (line_done || (de_in && !hit_in && gap==RUN_GAP));
    wire save_run=close_run && run_hits>=MIN_RUN_HITS;
    assign overflow=capture_bad || engine_bad;

    reg job_bank,prev_bank;
    reg [RUN_AW:0] job_count,prev_count,cur_index,prev_index;
    reg [YW-1:0] job_y;
    reg [LABEL_W-1:0] retire_index,cur_root;
    reg [XW-1:0] cur_lo,cur_hi;
    reg [XW:0] cur_hits;

    // alias[] always maps directly to a live root, no unbounded root walk.
    reg [LABEL_W-1:0] alias[0:LABELS-1];
    reg [LABELS-1:0] rec_valid,label_used;
    reg [XW-1:0] rx0[0:LABELS-1],rx1[0:LABELS-1];
    reg [YW-1:0] ry0[0:LABELS-1],ry1[0:LABELS-1];
    reg [HIT_W-1:0] count[0:LABELS-1];
    reg [YW-1:0] last_label_y[0:LABELS-1];
    reg best_valid,near_valid;
    reg [XW-1:0] best_x0,best_x1,near_x0,near_x1;
    reg [YW-1:0] best_y0,best_y1,near_y0,near_y1;
    reg [HIT_W-1:0] best_hits,near_hits;
    reg pending_valid;
    reg [XW-1:0] pending_x0,pending_x1;
    reg [YW-1:0] pending_y0,pending_y1;
    reg [3:0] missed;
    integer j,k;
    reg [LABEL_W-1:0] free_id;
    // A retired alias can only be reused after every run that names it has
    // left both current/previous rows. This also protects merged components.
    always @* begin
        free_id=0;
        for(k=LABELS-1;k>0;k=k-1)
            if(!rec_valid[k] && (!label_used[k] ||
               ({1'b0,last_label_y[k]}+1 < {1'b0,job_y}))) free_id=k;
    end
    wire [LABEL_W-1:0] prev_id=prev_word[LABEL_W-1:0];
    wire [LABEL_W-1:0] prev_root=alias[prev_id];
    wire [XW-1:0] prev_lo=prev_word[LAB_W-1:LAB_W-XW];
    wire [XW-1:0] prev_hi=prev_word[LABEL_W+XW-1:LABEL_W];
    wire prev_left=({1'b0,prev_hi}+1 < {1'b0,cur_lo});
    wire prev_right=({1'b0,cur_hi}+1 < {1'b0,prev_lo});
    wire [LABEL_W-1:0] add_id=(cur_root!=0)?cur_root:free_id;
    wire add_existing=rec_valid[add_id];
    wire [XW-1:0] add_x0=(!add_existing || cur_lo<rx0[add_id])?cur_lo:rx0[add_id];
    wire [XW-1:0] add_x1=(!add_existing || cur_hi>rx1[add_id])?cur_hi:rx1[add_id];
    wire [YW-1:0] add_y0=add_existing?ry0[add_id]:job_y;
    wire [YW-1:0] add_y1=job_y;
    wire [HIT_W-1:0] add_hits=(add_existing?count[add_id]:{HIT_W{1'b0}})+cur_hits;
    wire add_good=(add_id!=0) && (add_hits>=MIN_PIX);
    wire add_near=valid &&
        ({1'b0,add_x0}<={1'b0,x_max}+ASSOC_MARGIN) &&
        ({1'b0,x_min}<={1'b0,add_x1}+ASSOC_MARGIN) &&
        ({1'b0,add_y0}<={1'b0,y_max}+ASSOC_MARGIN) &&
        ({1'b0,y_min}<={1'b0,add_y1}+ASSOC_MARGIN);
    wire pending_match=pending_valid && best_x0<=pending_x1 && best_x1>=pending_x0 &&
                       best_y0<=pending_y1 && best_y1>=pending_y0;

    function [XW-1:0] stable_x;
        input [XW-1:0] old_value,new_value;
        reg [XW-1:0] delta;
        begin delta=(old_value>new_value)?old_value-new_value:new_value-old_value;
            stable_x=(delta<=JITTER_PIX)?old_value:new_value;end
    endfunction
    wire [XW-1:0] filtered_x0=stable_x(x_min,near_x0);
    wire [XW-1:0] filtered_x1=stable_x(x_max,near_x1);
    wire [YW-1:0] filtered_y0=stable_y(y_min,near_y0);
    wire [YW-1:0] filtered_y1=stable_y(y_max,near_y1);
    function [YW-1:0] stable_y;
        input [YW-1:0] old_value,new_value;
        reg [YW-1:0] delta;
        begin delta=(old_value>new_value)?old_value-new_value:new_value-old_value;
            stable_y=(delta<=JITTER_PIX)?old_value:new_value;end
    endfunction

    // Capture runs independently of the interval join. Memories are not reset:
    // counts and banks guarantee that every read follows a write.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            de_prev<=0;run_open<=0;capture_bank<=0;capture_count<=0;
            capture_y<=0;run_lo<=0;run_hi<=0;run_hits<=0;gap<=0;capture_bad<=0;
        end else if(!enable_in || frame_start) begin
            de_prev<=0;run_open<=0;capture_bank<=0;capture_count<=0;
            capture_y<=0;run_lo<=0;run_hi<=0;run_hits<=0;gap<=0;capture_bad<=0;
        end else begin
            de_prev<=de_in;
            if(de_in && !de_prev) capture_y<=y_in;
            if(de_in && hit_in) begin
                if(!run_open) begin run_lo<=x_in;run_hits<=1;end
                else run_hits<=run_hits+1'b1;
                run_hi<=x_in;run_open<=1;gap<=0;
            end else if(close_run) begin run_open<=0;run_hits<=0;gap<=0;end
            else if(de_in && run_open) gap<=gap+1'b1;
            if(save_run) begin
                if(capture_count<MAX_RUNS) begin
                    run_mem[{capture_bank,capture_count[RUN_AW-1:0]}]<={run_lo,run_hi,run_hits};
                    capture_count<=capture_count+1'b1;
                end else capture_bad<=1;
            end
            if(line_done) begin
                capture_count<=0;capture_bank<=!capture_bank;
                if(state!=IDLE) capture_bad<=1;
            end
        end
    end

    // Interval join is linear in sorted runs, rather than MAX_RUNS squared.
    // Two arms that meet on a later row merge both statistics and all aliases.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;job_bank<=0;prev_bank<=0;job_count<=0;prev_count<=0;
            cur_index<=0;prev_index<=0;job_y<=0;retire_index<=1;cur_root<=0;
            cur_lo<=0;cur_hi<=0;cur_hits<=0;raw_word<=0;prev_word<=0;
            rec_valid<=0;label_used<=0;engine_bad<=0;
            best_valid<=0;near_valid<=0;best_hits<=0;near_hits<=0;
            best_x0<=0;best_x1<=0;best_y0<=0;best_y1<=0;
            near_x0<=0;near_x1<=0;near_y0<=0;near_y1<=0;
            measurement_valid<=0;valid<=0;x_min<=0;x_max<=0;y_min<=0;y_max<=0;hits<=0;
            pending_valid<=0;pending_x0<=0;pending_x1<=0;pending_y0<=0;pending_y1<=0;missed<=0;
            for(j=0;j<LABELS;j=j+1) begin
                alias[j]<=j;rx0[j]<=0;rx1[j]<=0;ry0[j]<=0;ry1[j]<=0;
                count[j]<=0;last_label_y[j]<=0;
            end
        end else if(!enable_in || frame_start) begin
            // Publish only at VS: never move the box part way through a frame.
            measurement_valid <= enable_in && !overflow && state==IDLE &&
                ((valid && near_valid) || (!valid && best_valid && pending_match));
            if(!enable_in) begin
                valid<=0;pending_valid<=0;missed<=0;hits<=0;
                x_min<=0;x_max<=0;y_min<=0;y_max<=0;
            end else if(valid && near_valid && !overflow && state==IDLE) begin
                // Filter each axis as a pair: a narrow moving measurement can
                // otherwise cross a retained opposite edge and invert the box.
                x_min<=(filtered_x0<=filtered_x1)?filtered_x0:near_x0;
                x_max<=(filtered_x0<=filtered_x1)?filtered_x1:near_x1;
                y_min<=(filtered_y0<=filtered_y1)?filtered_y0:near_y0;
                y_max<=(filtered_y0<=filtered_y1)?filtered_y1:near_y1;
                hits<=near_hits;missed<=0;pending_valid<=0;
            end else if(valid) begin
                if(missed<HOLD_FRAMES) missed<=missed+1'b1;
                else begin valid<=0;hits<=0;missed<=0;pending_valid<=0;end
            end else if(best_valid && !overflow && state==IDLE) begin
                pending_valid<=1;pending_x0<=best_x0;pending_x1<=best_x1;
                pending_y0<=best_y0;pending_y1<=best_y1;
                if(pending_match) begin
                    valid<=1;x_min<=best_x0;x_max<=best_x1;y_min<=best_y0;y_max<=best_y1;
                    hits<=best_hits;missed<=0;pending_valid<=0;
                end
            end else pending_valid<=0;
            state<=IDLE;prev_count<=0;rec_valid<=0;label_used<=0;engine_bad<=0;
            best_valid<=0;near_valid<=0;best_hits<=0;near_hits<=0;
            for(j=0;j<LABELS;j=j+1) alias[j]<=j;
        end else begin
            case(state)
                IDLE: if(line_done && !overflow) begin
                    job_bank<=capture_bank;
                    job_count<=capture_count+((save_run && capture_count<MAX_RUNS)?1'b1:1'b0);
                    job_y<=capture_y;cur_index<=0;prev_index<=0;retire_index<=1;
                    state<=RETIRE;
                end
                RETIRE: begin
                    if(rec_valid[retire_index] &&
                       ({1'b0,ry1[retire_index]}+1 < {1'b0,job_y})) rec_valid[retire_index]<=0;
                    if(retire_index==LABELS-1) state<=LOAD_CUR;
                    else retire_index<=retire_index+1'b1;
                end
                LOAD_CUR: if(cur_index<job_count) begin
                    raw_word<=run_mem[{job_bank,cur_index[RUN_AW-1:0]}];state<=USE_CUR;
                end else state<=ROW_DONE;
                USE_CUR: begin
                    cur_lo<=raw_word[RAW_W-1:RAW_W-XW];
                    cur_hi<=raw_word[2*XW:XW+1];cur_hits<=raw_word[XW:0];
                    cur_root<=0;state<=LOAD_PREV;
                end
                LOAD_PREV: if(prev_index<prev_count) begin
                    prev_word<=label_mem[{prev_bank,prev_index[RUN_AW-1:0]}];state<=USE_PREV;
                end else state<=ADD_RUN;
                USE_PREV: begin
                    if(prev_left) begin prev_index<=prev_index+1'b1;state<=LOAD_PREV;end
                    else if(prev_right) state<=ADD_RUN;
                    else begin
                        if(cur_root==0) cur_root<=prev_root;
                        else if(prev_root!=cur_root && prev_root!=0) begin
                            rx0[cur_root]<=(rx0[cur_root]<rx0[prev_root])?rx0[cur_root]:rx0[prev_root];
                            rx1[cur_root]<=(rx1[cur_root]>rx1[prev_root])?rx1[cur_root]:rx1[prev_root];
                            ry0[cur_root]<=(ry0[cur_root]<ry0[prev_root])?ry0[cur_root]:ry0[prev_root];
                            ry1[cur_root]<=(ry1[cur_root]>ry1[prev_root])?ry1[cur_root]:ry1[prev_root];
                            count[cur_root]<=count[cur_root]+count[prev_root];rec_valid[prev_root]<=0;
                            for(j=1;j<LABELS;j=j+1) if(alias[j]==prev_root) alias[j]<=cur_root;
                        end
                        if(prev_hi<=cur_hi) begin prev_index<=prev_index+1'b1;state<=LOAD_PREV;end
                        else state<=ADD_RUN;
                    end
                end
                ADD_RUN: begin
                    if(add_id==0) engine_bad<=1;
                    else begin
                        alias[add_id]<=add_id;rec_valid[add_id]<=1;
                        rx0[add_id]<=add_x0;rx1[add_id]<=add_x1;ry0[add_id]<=add_y0;ry1[add_id]<=job_y;
                        count[add_id]<=add_hits;label_used[add_id]<=1;last_label_y[add_id]<=job_y;
                        label_mem[{job_bank,cur_index[RUN_AW-1:0]}]<={cur_lo,cur_hi,add_id};
                        if(add_good && (!best_valid || add_hits>=best_hits)) begin
                            best_valid<=1;best_hits<=add_hits;
                            best_x0<=add_x0;best_x1<=add_x1;best_y0<=add_y0;best_y1<=add_y1;
                        end
                        if(add_good && add_near && (!near_valid || add_hits>=near_hits)) begin
                            near_valid<=1;near_hits<=add_hits;
                            near_x0<=add_x0;near_x1<=add_x1;near_y0<=add_y0;near_y1<=add_y1;
                        end
                    end
                    cur_index<=cur_index+1'b1;state<=LOAD_CUR;
                end
                ROW_DONE: begin prev_bank<=job_bank;prev_count<=job_count;state<=IDLE;end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
