`include "../ddr_page_map.vh"
module video_out #(
    parameter integer USE_EXTERNAL_SOURCE = 0,
    parameter integer FRAME_WORDS = `DDR_MAP_FRAME_WORDS,
    parameter integer BURST_WORDS = 240,
    parameter integer ENABLE_UNDERFLOW_GUARD = 0,
    parameter integer ENABLE_DISPLAY_PAGE_GUARD = 0,
    parameter integer ENABLE_FRAME_TRANSACTION = 0
)(
    input wire I_rst_n,
    input wire I_ddr_clk,
    output wire O_video_out_rd_busy,
    input wire I_video_in_wr_busy,
    input wire [1:0] I_video_out_rp,
    output wire O_ddr_user_rd_en,
    output reg [24:0] O_ddr_user_addr,
    input wire I_ddr_user_ready,
    input wire I_ddr_user_rd_valid,
    input wire [127:0] I_ddr_user_rd_data,
    input wire I_dsi_clk,
    input wire I_video_vsync,
    input wire I_video_rd_en,
    output reg [23:0] O_vdieo_data,
    input wire [24:0] I_source_base,
    input wire [3:0] I_source_mode,
    input wire I_source_is_result,
    input wire I_source_valid,
    output reg [3:0] O_frame_mode,
    output reg O_result_source_active,
    output wire [8:0] O_fifo_fill,
    output wire [9:0] O_read_credit,
    output wire O_frame_pending,
    output reg O_underflow,
    output wire [3:0] O_display_page_mask,
    output reg [3:0] O_pixel_mode,
    output wire O_pixel_frame_valid,
    output reg O_pixel_result_active
);
    wire S_pixel_rst_n, S_ddr_rst_n;
    reset_sync u_reset_pixel(.clk(I_dsi_clk),.async_rst_n(I_rst_n),.rst_n(S_pixel_rst_n));
    reset_sync u_reset_ddr(.clk(I_ddr_clk),.async_rst_n(I_rst_n),.rst_n(S_ddr_rst_n));
    generate if(ENABLE_FRAME_TRANSACTION && (!USE_EXTERNAL_SOURCE || !ENABLE_DISPLAY_PAGE_GUARD || FRAME_WORDS%3!=0))begin:g_bad_frame_config
        ERROR_FRAME_TRANSACTION_REQUIRES_EXTERNAL_GUARDED_COMPLETE_RGB_FRAME invalid_configuration();
    end endgenerate
    reg S_fifo_rst;
    reg [7:0] S_fifo_rst_cnt;
    wire [8:0] S_fifo_wr_num;
    wire S_fifo_rd_en;
    wire [127:0] S_fifo_rd_data;
    reg S_video_vsync_1d, S_video_vsync_2d, S_video_vsync_3d;
    wire S_legacy_frame_start = ~S_video_vsync_3d & S_video_vsync_2d;
    wire S_ticket_received;
    wire [15:0] S_ticket_ddr;
    wire S_video_frame_start = ENABLE_FRAME_TRANSACTION ? S_ticket_received : S_legacy_frame_start;
    wire S_ddr_rd_trig;
    reg S_ddr_rd_valid;
    reg [9:0] S_ddr_rd_cnt;
    reg [17:0] S_frame_read_count;
    reg [3:0] S_fifo_rd_cnt;
    reg S_video_rd_en_1d;
    reg [3:0] S_fifo_rd_cnt_1d;
    reg [127:0] S_fifo_rd_data_1d;
    wire S_fifo_empty;
    reg [9:0] S_read_credit;
    reg S_frame_pending;
    reg [24:0] S_pending_base_addr;
    reg [3:0] S_pending_mode;
    reg S_pending_is_result;
    reg S_pending_selected, S_pending_source_valid, S_active_source_valid;
    reg [24:0] S_active_base_addr;
    reg [1:0] S_fifo_warmup;
    wire [10:0] S_projected_fifo_occupancy = {2'b0,S_fifo_wr_num} + {1'b0,S_read_credit};
    wire S_fifo_ready = !S_fifo_rst && (S_fifo_warmup == 2'd3);
    wire S_ddr_return_accept;
    reg [24:0] S_source_base_meta, S_source_base_sync;
    reg [3:0] S_source_mode_meta, S_source_mode_sync;
    reg S_source_result_meta, S_source_result_sync;
    reg S_pixel_vsync_d;
    reg S_pixel_frame_bad;
    wire S_pixel_frame_start = I_video_vsync && !S_pixel_vsync_d;
    reg [15:0] S_pixel_ticket,S_ticket_payload,S_pending_ticket;
    reg S_ticket_pending;
    wire S_ticket_ready,S_ack_ready,S_ack_received;
    wire [21:0] S_ack_data;
    reg [21:0] S_pixel_ack;
    reg S_ack_have,S_pixel_frame_locked,S_pixel_frame_admitted;
    wire S_frame_commit_ddr = !S_video_frame_start && S_frame_pending && S_fifo_ready && (S_read_credit == 0) &&
        (!ENABLE_DISPLAY_PAGE_GUARD || S_pending_selected) &&
        (!ENABLE_FRAME_TRANSACTION || S_ack_ready);
    frame_mailbox_cdc #(.WIDTH(16)) u_frame_ticket(
        .src_clk(I_dsi_clk),.src_rst_n(S_pixel_rst_n),.src_valid(S_ticket_pending),
        .src_data(S_ticket_payload),.src_ready(S_ticket_ready),
        .dst_clk(I_ddr_clk),.dst_rst_n(S_ddr_rst_n),.dst_valid(S_ticket_received),.dst_data(S_ticket_ddr));
    frame_mailbox_cdc #(.WIDTH(22)) u_frame_ack(
        .src_clk(I_ddr_clk),.src_rst_n(S_ddr_rst_n),.src_valid(S_frame_commit_ddr && ENABLE_FRAME_TRANSACTION),
        .src_data({S_pending_ticket,S_pending_mode,S_pending_is_result,S_pending_source_valid}),.src_ready(S_ack_ready),
        .dst_clk(I_dsi_clk),.dst_rst_n(S_pixel_rst_n),.dst_valid(S_ack_received),.dst_data(S_ack_data));
    wire S_admission_ready = S_ack_have && S_pixel_ack[21:6]==S_pixel_ticket && S_pixel_ack[0];
    wire S_pixel_eligible = !ENABLE_FRAME_TRANSACTION ||
        (S_pixel_frame_locked ? S_pixel_frame_admitted : S_admission_ready);
    always @(posedge I_dsi_clk or negedge S_pixel_rst_n)begin
        if(!S_pixel_rst_n)begin
            S_pixel_ticket<=0;S_ticket_payload<=0;S_ticket_pending<=0;
            S_pixel_ack<=0;S_ack_have<=0;S_pixel_frame_locked<=0;S_pixel_frame_admitted<=0;
            O_pixel_mode<=0;O_pixel_result_active<=0;
        end else begin
            if(S_ticket_pending && S_ticket_ready)S_ticket_pending<=0;
            // Pending tickets may coalesce; an in-flight mailbox payload never changes.
            if(S_pixel_frame_start)begin
                S_pixel_ticket<=S_pixel_ticket+1'b1;S_ticket_payload<=S_pixel_ticket+1'b1;
                S_ticket_pending<=1;S_pixel_frame_locked<=0;S_pixel_frame_admitted<=0;
            end else if(I_video_rd_en && !S_pixel_frame_locked)begin
                S_pixel_frame_locked<=1;S_pixel_frame_admitted<=S_admission_ready;
                if(S_admission_ready)begin O_pixel_mode<=S_pixel_ack[5:2];O_pixel_result_active<=S_pixel_ack[1];end
            end
            // An ACK arriving on the first request edge is deliberately too late.
            if(S_ack_received)begin S_pixel_ack<=S_ack_data;S_ack_have<=1;end
        end
    end
    wire S_pixel_need_word = I_video_rd_en &&
        ((S_fifo_rd_cnt == 4'd0) || (S_fifo_rd_cnt == 4'd5) || (S_fifo_rd_cnt == 4'd10));
    wire S_pixel_underflow_now = ENABLE_UNDERFLOW_GUARD && S_pixel_eligible && S_pixel_need_word && S_fifo_empty;
    assign O_pixel_frame_valid=S_pixel_rst_n && S_pixel_eligible &&
        !(ENABLE_UNDERFLOW_GUARD && (S_pixel_frame_bad || S_pixel_underflow_now));

    localparam [24:0] IMAGE_BASE_ADDR_0 = `DDR_MAP_LIVE0_BASE;
    localparam [24:0] IMAGE_BASE_ADDR_1 = `DDR_MAP_LIVE1_BASE;
    localparam [24:0] IMAGE_BASE_ADDR_2 = `DDR_MAP_LIVE2_BASE;
    localparam [24:0] IMAGE_BASE_ADDR_3 = `DDR_MAP_LIVE3_BASE;

    function [24:0] legacy_page_base;
        input [1:0] page;
        begin
            case (page)
                2'd0: legacy_page_base = IMAGE_BASE_ADDR_0;
                2'd1: legacy_page_base = IMAGE_BASE_ADDR_1;
                2'd2: legacy_page_base = IMAGE_BASE_ADDR_2;
                default: legacy_page_base = IMAGE_BASE_ADDR_3;
            endcase
        end
    endfunction

    function [3:0] live_base_mask;
        input [24:0] base;
        begin
            case (base)
                IMAGE_BASE_ADDR_0: live_base_mask = 4'b0001;
                IMAGE_BASE_ADDR_1: live_base_mask = 4'b0010;
                IMAGE_BASE_ADDR_2: live_base_mask = 4'b0100;
                IMAGE_BASE_ADDR_3: live_base_mask = 4'b1000;
                default: live_base_mask = 4'b0000;
            endcase
        end
    endfunction

    assign O_display_page_mask = ENABLE_DISPLAY_PAGE_GUARD ?
        ((S_active_source_valid && !O_result_source_active ? live_base_mask(S_active_base_addr) : 4'b0) |
         (S_pending_selected && S_pending_source_valid && !S_pending_is_result ? live_base_mask(S_pending_base_addr) : 4'b0)) : 4'b0000;

    always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
        if (!S_ddr_rst_n) begin
            S_video_vsync_1d <= 0; S_video_vsync_2d <= 0; S_video_vsync_3d <= 0;
            S_source_base_meta <= 0; S_source_base_sync <= 0;
            S_source_mode_meta <= 0; S_source_mode_sync <= 0;
            S_source_result_meta <= 0; S_source_result_sync <= 0;
        end else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            S_video_vsync_3d <= S_video_vsync_2d;
            S_source_base_meta <= I_source_base;
            S_source_base_sync <= S_source_base_meta;
            S_source_mode_meta <= I_source_mode;
            S_source_mode_sync <= S_source_mode_meta;
            S_source_result_meta <= I_source_is_result;
            S_source_result_sync <= S_source_result_meta;
        end
    end

    // 每个VS重置预取FIFO；旧读请求仍计入credit，直到回包后才切换基址。
    always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
        if (!S_ddr_rst_n) begin S_fifo_rst <= 1'b1; S_fifo_rst_cnt <= 0; end
        else if (S_video_frame_start) begin S_fifo_rst <= 1'b1; S_fifo_rst_cnt <= 0; end
        else if (S_fifo_rst) begin
            if (S_fifo_rst_cnt == 8'd10) begin S_fifo_rst <= 1'b0; S_fifo_rst_cnt <= 0; end
            else S_fifo_rst_cnt <= S_fifo_rst_cnt + 1'b1;
        end
    end
    always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
        if (!S_ddr_rst_n) S_fifo_warmup <= 0;
        else if (S_fifo_rst) S_fifo_warmup <= 0;
        else if (S_fifo_warmup != 2'd3) S_fifo_warmup <= S_fifo_warmup + 1'b1;
    end

    assign O_fifo_fill = S_fifo_wr_num;
    assign O_read_credit = S_read_credit;
    assign O_frame_pending = S_frame_pending;
    assign S_ddr_rd_trig = S_ddr_rst_n && S_fifo_ready && !S_frame_pending &&
        !S_video_frame_start && !I_video_in_wr_busy && !S_ddr_rd_valid &&
        (!ENABLE_DISPLAY_PAGE_GUARD || S_active_source_valid) &&
        (S_projected_fifo_occupancy <= 11'd260) &&
        (S_frame_read_count + BURST_WORDS <= FRAME_WORDS);
    assign O_ddr_user_rd_en = S_ddr_rd_valid && I_ddr_user_ready &&
        S_fifo_ready && !S_frame_pending && !S_video_frame_start &&
        (S_frame_read_count < FRAME_WORDS);
    assign S_ddr_return_accept = I_ddr_user_rd_valid && S_fifo_ready &&
        !S_frame_pending && !S_video_frame_start;

    always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
        if (!S_ddr_rst_n) S_read_credit <= 0;
        else case ({O_ddr_user_rd_en,I_ddr_user_rd_valid})
            2'b10: S_read_credit <= S_read_credit + 1'b1;
            2'b01: if (S_read_credit != 0) S_read_credit <= S_read_credit - 1'b1;
            default: S_read_credit <= S_read_credit;
        endcase
    end

    always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
        if (!S_ddr_rst_n) begin
            S_ddr_rd_valid <= 0; S_ddr_rd_cnt <= 0;
        end else if (S_video_frame_start) begin
            S_ddr_rd_valid <= 0; S_ddr_rd_cnt <= 0;
        end else if (O_ddr_user_rd_en) begin
            if (S_ddr_rd_cnt == BURST_WORDS-1) begin
                S_ddr_rd_valid <= 0; S_ddr_rd_cnt <= 0;
            end else S_ddr_rd_cnt <= S_ddr_rd_cnt + 1'b1;
        end else if (S_ddr_rd_trig) begin
            S_ddr_rd_valid <= 1; S_ddr_rd_cnt <= 0;
        end
    end

    always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
        if (!S_ddr_rst_n) begin
            S_frame_pending <= 1'b1;
            S_pending_base_addr <= IMAGE_BASE_ADDR_0;
            S_pending_mode <= 4'd0; S_pending_is_result <= 1'b0;
            S_pending_selected <= 1'b0; S_pending_source_valid <= 1'b0;
            S_active_source_valid <= 1'b0; S_active_base_addr <= IMAGE_BASE_ADDR_0;
            O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
            O_result_source_active <= 1'b0;
            O_frame_mode <= 4'd0;
            S_pending_ticket <= 0;
        end else if (S_video_frame_start) begin
            S_frame_pending <= 1'b1;
            S_pending_ticket <= S_ticket_ddr;
            if (USE_EXTERNAL_SOURCE) begin
                if (ENABLE_DISPLAY_PAGE_GUARD) begin
                    // 同DDR域时序下VS直接锁存同一拍的完整source组，避免同步器留下旧页候选。
                    S_pending_base_addr <= I_source_base;
                    S_pending_mode <= I_source_mode;
                    S_pending_is_result <= I_source_is_result;
                    S_pending_source_valid <= I_source_valid;
                    S_pending_selected <= 1'b1;
                end else begin
                    S_pending_base_addr <= S_source_base_sync;
                    S_pending_mode <= S_source_mode_sync;
                    S_pending_is_result <= S_source_result_sync;
                end
            end else begin
                S_pending_base_addr <= legacy_page_base(I_video_out_rp);
                S_pending_mode <= 4'd0;
                S_pending_is_result <= 1'b0;
                if (ENABLE_DISPLAY_PAGE_GUARD) begin
                    S_pending_source_valid <= 1'b1;
                    S_pending_selected <= 1'b1;
                end
            end
        end else if (S_frame_commit_ddr) begin
            S_frame_pending <= 1'b0;
            O_ddr_user_addr <= S_pending_base_addr;
            O_result_source_active <= USE_EXTERNAL_SOURCE ? S_pending_is_result : 1'b0;
            O_frame_mode <= USE_EXTERNAL_SOURCE ? S_pending_mode : 4'd0;
            if (ENABLE_DISPLAY_PAGE_GUARD) begin
                S_active_source_valid <= S_pending_source_valid;
                S_active_base_addr <= S_pending_base_addr;
                S_pending_selected <= 1'b0;
            end
        end else if (O_ddr_user_rd_en) begin
            O_ddr_user_addr <= O_ddr_user_addr + 25'd8;
        end
    end

    always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
        if (!S_ddr_rst_n) S_frame_read_count <= 0;
        else if (S_frame_commit_ddr)
            S_frame_read_count <= 0;
        else if (O_ddr_user_rd_en)
            S_frame_read_count <= S_frame_read_count + 1'b1;
    end

    assign O_video_out_rd_busy = S_ddr_rd_trig | S_ddr_rd_valid;

    w128_d512_fifo U_w128_d512_fifo(
        .rst(S_fifo_rst), .clkw(I_ddr_clk), .we(S_ddr_return_accept),
        .di(I_ddr_user_rd_data), .wrusedw(S_fifo_wr_num), .afull(), .full_flag(),
        .clkr(I_dsi_clk), .re(S_fifo_rd_en), .dout(S_fifo_rd_data), .rdusedw(),
        .valid(), .empty_flag(S_fifo_empty), .aempty()
    );

    assign S_fifo_rd_en = S_pixel_rst_n && I_video_rd_en &&
        ((S_fifo_rd_cnt == 4'd0) || (S_fifo_rd_cnt == 4'd5) || (S_fifo_rd_cnt == 4'd10)) &&
        S_pixel_eligible && !(ENABLE_UNDERFLOW_GUARD && (S_pixel_frame_bad || S_fifo_empty));

    always @(posedge I_dsi_clk or negedge S_pixel_rst_n) begin
        if (!S_pixel_rst_n) begin
            S_fifo_rd_cnt <= 0; S_video_rd_en_1d <= 0; S_fifo_rd_cnt_1d <= 0;
            S_fifo_rd_data_1d <= 0; S_pixel_vsync_d <= 0; S_pixel_frame_bad <= 0;
            O_underflow <= 0;
            O_vdieo_data <= 0;
        end else begin
            S_pixel_vsync_d <= I_video_vsync;
            if (S_pixel_frame_start) begin
                S_pixel_frame_bad <= 0;
                O_underflow <= 0;
                S_fifo_rd_cnt <= 0;
            end else if (I_video_rd_en) begin
                S_fifo_rd_cnt <= S_fifo_rd_cnt + 1'b1;
            end else begin
                S_fifo_rd_cnt <= 0;
            end

            S_video_rd_en_1d <= I_video_rd_en;
            S_fifo_rd_cnt_1d <= S_fifo_rd_cnt;
            S_fifo_rd_data_1d <= S_fifo_rd_data;

            if (S_pixel_underflow_now) begin
                S_pixel_frame_bad <= 1'b1;
                O_underflow <= 1'b1;
            end

            if (S_video_rd_en_1d) begin
                if (!S_pixel_eligible || (ENABLE_UNDERFLOW_GUARD && (S_pixel_frame_bad || S_pixel_underflow_now)))
                    O_vdieo_data <= 24'd0;
                else case (S_fifo_rd_cnt_1d)
                    4'd0: O_vdieo_data <= S_fifo_rd_data[127:104];
                    4'd1: O_vdieo_data <= S_fifo_rd_data[103:80];
                    4'd2: O_vdieo_data <= S_fifo_rd_data[79:56];
                    4'd3: O_vdieo_data <= S_fifo_rd_data[55:32];
                    4'd4: O_vdieo_data <= S_fifo_rd_data[31:8];
                    4'd5: O_vdieo_data <= {S_fifo_rd_data_1d[7:0],S_fifo_rd_data[127:112]};
                    4'd6: O_vdieo_data <= S_fifo_rd_data[111:88];
                    4'd7: O_vdieo_data <= S_fifo_rd_data[87:64];
                    4'd8: O_vdieo_data <= S_fifo_rd_data[63:40];
                    4'd9: O_vdieo_data <= S_fifo_rd_data[39:16];
                    4'd10: O_vdieo_data <= {S_fifo_rd_data_1d[15:0],S_fifo_rd_data[127:120]};
                    4'd11: O_vdieo_data <= S_fifo_rd_data[119:96];
                    4'd12: O_vdieo_data <= S_fifo_rd_data[95:72];
                    4'd13: O_vdieo_data <= S_fifo_rd_data[71:48];
                    4'd14: O_vdieo_data <= S_fifo_rd_data[47:24];
                    default: O_vdieo_data <= S_fifo_rd_data[23:0];
                endcase
            end else O_vdieo_data <= 0;
        end
    end
endmodule
