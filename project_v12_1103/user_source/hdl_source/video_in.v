`include "../ddr_page_map.vh"
module video_in #(
    parameter integer FRAME_WORDS = `DDR_MAP_FRAME_WORDS,
    parameter integer BURST_WORDS = 240,
    parameter integer REQUIRE_COMPLETE_FRAME = 0,
    parameter integer ENABLE_DISPLAY_PAGE_GUARD = 0
)(
    input wire         I_rst_n,
    input wire         I_camera_clk,
    input wire         I_camera_frame_start,
    input wire         I_camera_valid,
    input wire [127:0] I_camera_data,
    input wire         I_mipi_rx_error,
    input wire         I_ddr_clk,
    input wire         I_display_pause,
    input wire         I_video_out_rd_busy,
    output wire        O_video_in_wr_busy,
    output reg  [1:0]  O_video_out_rp,
    output reg         O_ddr_user_wr_en,
    output reg  [24:0] O_ddr_user_addr,
    output wire [127:0] O_ddr_user_wr_data,
    input wire         I_ddr_user_ready,
    output reg         O_frame_start_ddr,
    output reg  [3:0]  O_page_valid,
    input wire [3:0] I_display_page_mask,
    output reg O_good_frame_ddr
);
    wire S_camera_rst_n, S_ddr_rst_n;
    reset_sync u_reset_camera(.clk(I_camera_clk),.async_rst_n(I_rst_n),.rst_n(S_camera_rst_n));
    reset_sync u_reset_ddr(.clk(I_ddr_clk),.async_rst_n(I_rst_n),.rst_n(S_ddr_rst_n));
    reg S_camera_frame_start_extend;
    reg [3:0] S_extend_cnt;
    reg S_camera_frame_start_extend_1d, S_camera_frame_start_extend_2d;
    reg S_camera_frame_start_extend_3d;
    wire S_frame_start = ~S_camera_frame_start_extend_3d & S_camera_frame_start_extend_2d;
    wire S_fifo_rst = !I_rst_n | S_camera_frame_start_extend_3d;
    reg [1:0] S_video_in_wp;
    wire [8:0] S_fifo_rd_num;
    wire S_fifo_rd_en, S_fifo_write_take, S_fifo_empty, S_fifo_full;
    reg S_ddr_wr_valid;
    reg [9:0] S_ddr_wr_cnt;
    reg [17:0] S_frame_words_written;
    reg [17:0] S_camera_words_seen;
    reg S_camera_bad, S_completed_camera_bad;
    reg S_completed_bad_meta, S_completed_bad_sync;
    reg [1:0] S_active_write_page;
    reg S_have_frame;
    reg S_frame_writable;
    reg S_cam_fifo_rst_meta, S_cam_fifo_rst_sync;
    reg S_cam_fifo_rst_seen, S_camera_capture_open;
    reg [1:0] S_camera_release_count;
    wire S_camera_accept;

    localparam [24:0] IMAGE_BASE_ADDR_0 = `DDR_MAP_LIVE0_BASE;
    localparam [24:0] IMAGE_BASE_ADDR_1 = `DDR_MAP_LIVE1_BASE;
    localparam [24:0] IMAGE_BASE_ADDR_2 = `DDR_MAP_LIVE2_BASE;
    localparam [24:0] IMAGE_BASE_ADDR_3 = `DDR_MAP_LIVE3_BASE;

    function [24:0] page_base;
        input [1:0] page;
        begin
            case (page)
                2'd0: page_base = IMAGE_BASE_ADDR_0;
                2'd1: page_base = IMAGE_BASE_ADDR_1;
                2'd2: page_base = IMAGE_BASE_ADDR_2;
                default: page_base = IMAGE_BASE_ADDR_3;
            endcase
        end
    endfunction

    function [3:0] page_mask;
        input [1:0] page;
        begin page_mask = 4'b0001 << page; end
    endfunction

    assign S_camera_accept = S_camera_rst_n && S_camera_capture_open &&
        !I_camera_frame_start && I_camera_valid && !S_fifo_full &&
        (!REQUIRE_COMPLETE_FRAME || (S_camera_words_seen < FRAME_WORDS));

    // 一个DDR组最多BURST_WORDS拍；显示仲裁只在组间切换。
    assign O_video_in_wr_busy = S_ddr_wr_valid | O_ddr_user_wr_en;

    w128_d512_fifo U_w128_d512_fifo(
        .rst(S_fifo_rst), .clkw(I_camera_clk), .we(S_camera_accept),
        .di(I_camera_data), .afull(), .full_flag(S_fifo_full), .wrusedw(),
        .clkr(I_ddr_clk), .re(S_fifo_rd_en), .dout(O_ddr_user_wr_data),
        .rdusedw(S_fifo_rd_num), .valid(), .empty_flag(S_fifo_empty), .aempty()
    );

    always @(posedge I_camera_clk or negedge S_camera_rst_n) begin
        if (!S_camera_rst_n) begin
            S_camera_frame_start_extend <= 1'b0;
            S_extend_cnt <= 4'd0;
            S_camera_words_seen <= 18'd0;
            S_camera_bad <= 1'b0;
            S_completed_camera_bad <= 1'b0;
            S_cam_fifo_rst_meta <= 1'b0;
            S_cam_fifo_rst_sync <= 1'b0;
            S_cam_fifo_rst_seen <= 1'b0;
            S_camera_capture_open <= 1'b0;
            S_camera_release_count <= 2'd0;
        end else begin
            S_cam_fifo_rst_meta <= S_fifo_rst;
            S_cam_fifo_rst_sync <= S_cam_fifo_rst_meta;

            if (I_camera_frame_start) begin
                S_camera_frame_start_extend <= 1'b1;
                S_completed_camera_bad <= S_camera_bad | I_mipi_rx_error |
                    (REQUIRE_COMPLETE_FRAME && (S_camera_words_seen != FRAME_WORDS));
                S_camera_bad <= I_camera_valid;
                S_camera_words_seen <= I_camera_valid ? 18'd1 : 18'd0;
                S_cam_fifo_rst_seen <= 1'b0;
                S_camera_capture_open <= 1'b0;
                S_camera_release_count <= 2'd0;
            end else if (S_extend_cnt == 4'd7) begin
                S_camera_frame_start_extend <= 1'b0;
            end

            if (!I_camera_frame_start) begin
                if (S_cam_fifo_rst_sync) begin
                    S_cam_fifo_rst_seen <= 1'b1;
                    S_camera_release_count <= 2'd0;
                    S_camera_capture_open <= 1'b0;
                end else if (S_cam_fifo_rst_seen) begin
                    if (S_camera_release_count == 2'd2) begin
                        S_camera_release_count <= 2'd0;
                        S_cam_fifo_rst_seen <= 1'b0;
                        S_camera_capture_open <= 1'b1;
                    end else begin
                        S_camera_release_count <= S_camera_release_count + 1'b1;
                    end
                end
            end

            if (S_camera_frame_start_extend)
                S_extend_cnt <= S_extend_cnt + 1'b1;
            else
                S_extend_cnt <= 4'd0;

            if (!I_camera_frame_start && I_camera_valid) begin
                if (S_camera_words_seen < 18'h3ffff)
                    S_camera_words_seen <= S_camera_words_seen + 1'b1;
                if (!S_camera_capture_open || S_fifo_full || (REQUIRE_COMPLETE_FRAME &&
                                    S_camera_words_seen >= FRAME_WORDS))
                    S_camera_bad <= 1'b1;
            end
        end
    end

    always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
        if (!S_ddr_rst_n) begin
            S_camera_frame_start_extend_1d <= 1'b0;
            S_camera_frame_start_extend_2d <= 1'b0;
            S_camera_frame_start_extend_3d <= 1'b0;
            S_completed_bad_meta <= 1'b0;
            S_completed_bad_sync <= 1'b0;
            O_frame_start_ddr <= 1'b0;
        end else begin
            S_camera_frame_start_extend_1d <= S_camera_frame_start_extend;
            S_camera_frame_start_extend_2d <= S_camera_frame_start_extend_1d;
            S_camera_frame_start_extend_3d <= S_camera_frame_start_extend_2d;
            S_completed_bad_meta <= S_completed_camera_bad;
            S_completed_bad_sync <= S_completed_bad_meta;
            O_frame_start_ddr <= S_frame_start;
        end
    end

    generate if (!REQUIRE_COMPLETE_FRAME) begin : g_legacy_capture
        // 默认参数保留原有四页轮转和显示指针语义。
        always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
            if (!S_ddr_rst_n) S_video_in_wp <= 2'd0;
            else if (I_display_pause) S_video_in_wp <= S_video_in_wp;
            else if (S_frame_start) begin
                if (!I_mipi_rx_error) S_video_in_wp <= S_video_in_wp + 1'b1;
            end
        end

        always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
            if (!S_ddr_rst_n) O_video_out_rp <= 2'd0;
            else if (I_display_pause) O_video_out_rp <= O_video_out_rp;
            else if (S_frame_start) begin
                case (S_video_in_wp)
                    2'd0: O_video_out_rp <= 2'd2;
                    2'd1: O_video_out_rp <= 2'd3;
                    2'd2: O_video_out_rp <= 2'd0;
                    2'd3: O_video_out_rp <= 2'd1;
                endcase
            end
        end

        always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
            if (!S_ddr_rst_n) begin
                S_ddr_wr_valid <= 1'b0; S_ddr_wr_cnt <= 10'd0;
                O_ddr_user_wr_en <= 1'b0; O_ddr_user_addr <= 25'd0;
                O_page_valid <= 4'd0;
                O_good_frame_ddr <= 1'b0;
            end else begin
                O_good_frame_ddr <= 1'b0;
                if (S_frame_start || S_fifo_rst) S_ddr_wr_valid <= 1'b0;
                else if (S_fifo_rd_en && S_ddr_wr_cnt == BURST_WORDS-1)
                    S_ddr_wr_valid <= 1'b0;
                else if (!S_ddr_wr_valid && !O_ddr_user_wr_en && S_fifo_rd_num >= BURST_WORDS && !I_video_out_rd_busy)
                    S_ddr_wr_valid <= 1'b1;

                if (S_frame_start || S_fifo_rst || !S_ddr_wr_valid) S_ddr_wr_cnt <= 10'd0;
                else if (S_fifo_rd_en) S_ddr_wr_cnt <= S_ddr_wr_cnt + 1'b1;

                if (S_frame_start || S_fifo_rst) O_ddr_user_wr_en <= 1'b0;
                else O_ddr_user_wr_en <= S_fifo_rd_en;

                if (S_frame_start && !I_mipi_rx_error)
                    O_ddr_user_addr <= page_base(S_video_in_wp);
                else if (S_frame_start && I_mipi_rx_error)
                    O_ddr_user_addr <= page_base(S_video_in_wp - 2'd1);
                else if (O_ddr_user_wr_en)
                    O_ddr_user_addr <= O_ddr_user_addr + 25'd8;
                O_page_valid <= 4'd0;
            end
        end
        assign S_fifo_write_take = S_ddr_wr_valid && I_ddr_user_ready &&
                                   !S_frame_start && !S_fifo_rst && !S_fifo_empty;
        assign S_fifo_rd_en = S_fifo_write_take;
    end else begin : g_complete_capture
        reg [1:0] S_next_page;
        reg [18:0] S_written_with_tail;
        reg S_good_completed_frame;
        reg [3:0] S_reserved_mask, S_rp_mask;
        reg [1:0] S_alloc_start, S_alloc_page;
        reg S_alloc_found;
        integer S_alloc_try;
        wire S_fifo_drop_drain = ENABLE_DISPLAY_PAGE_GUARD && S_have_frame &&
            !S_frame_writable && !S_frame_start && !S_fifo_rst && !S_fifo_empty;
        always @* begin
            S_next_page = S_active_write_page + 2'd1;
            if (!ENABLE_DISPLAY_PAGE_GUARD && I_display_pause && (S_next_page == O_video_out_rp))
                S_next_page = S_next_page + 2'd1;
            S_written_with_tail = {1'b0,S_frame_words_written} + O_ddr_user_wr_en;
            S_good_completed_frame = S_have_frame &&
                S_frame_writable && (S_written_with_tail == FRAME_WORDS) && !S_completed_bad_sync;
            S_rp_mask = (O_page_valid[O_video_out_rp] || I_display_pause) ?
                page_mask(O_video_out_rp) : 4'b0000;
            S_reserved_mask = I_display_page_mask | S_rp_mask;
            if (S_good_completed_frame && !I_display_pause)
                S_reserved_mask = S_reserved_mask | page_mask(S_active_write_page);
            S_alloc_start = S_have_frame ? (S_active_write_page + 2'd1) : 2'd0;
            S_alloc_page = S_alloc_start;
            S_alloc_found = 1'b0;
            for (S_alloc_try=0; S_alloc_try<4; S_alloc_try=S_alloc_try+1) begin
                if (!S_alloc_found && !S_reserved_mask[(S_alloc_start + S_alloc_try) & 2'b11]) begin
                    S_alloc_page = S_alloc_start + S_alloc_try;
                    S_alloc_found = 1'b1;
                end
            end
        end

        always @(posedge I_ddr_clk or negedge S_ddr_rst_n) begin
            if (!S_ddr_rst_n) begin
                S_video_in_wp <= 2'd0;
                S_active_write_page <= 2'd0;
                S_have_frame <= 1'b0;
                S_frame_writable <= 1'b0;
                S_frame_words_written <= 18'd0;
                O_video_out_rp <= 2'd0;
                O_page_valid <= 4'd0;
                O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                O_ddr_user_wr_en <= 1'b0;
                S_ddr_wr_valid <= 1'b0;
                S_ddr_wr_cnt <= 10'd0;
                O_good_frame_ddr <= 1'b0;
            end else begin
                O_good_frame_ddr <= 1'b0;
                if (O_ddr_user_wr_en && S_frame_words_written < FRAME_WORDS)
                    S_frame_words_written <= S_frame_words_written + 1'b1;

                if (S_frame_start) begin
                    if (!S_have_frame) begin
                        // 首帧也进行页分配，默认从第0页开始。
                        S_have_frame <= 1'b1;
                        if (!ENABLE_DISPLAY_PAGE_GUARD || S_alloc_found) begin
                            S_frame_writable <= 1'b1;
                            S_active_write_page <= ENABLE_DISPLAY_PAGE_GUARD ? S_alloc_page : S_active_write_page;
                            S_video_in_wp <= ENABLE_DISPLAY_PAGE_GUARD ? S_alloc_page : S_active_write_page;
                            O_page_valid[ENABLE_DISPLAY_PAGE_GUARD ? S_alloc_page : S_active_write_page] <= 1'b0;
                            O_ddr_user_addr <= page_base(ENABLE_DISPLAY_PAGE_GUARD ? S_alloc_page : S_active_write_page);
                        end else begin
                            S_frame_writable <= 1'b0;
                        end
                    end else begin
                        if (S_good_completed_frame) begin
                            O_page_valid[S_active_write_page] <= 1'b1;
                            if (!I_display_pause) begin
                                O_video_out_rp <= S_active_write_page;
                                if (ENABLE_DISPLAY_PAGE_GUARD) O_good_frame_ddr <= 1'b1;
                            end
                        end else if (!ENABLE_DISPLAY_PAGE_GUARD) begin
                            O_page_valid[S_active_write_page] <= 1'b0;
                        end

                        if (!ENABLE_DISPLAY_PAGE_GUARD || S_alloc_found) begin
                            S_frame_writable <= 1'b1;
                            S_active_write_page <= ENABLE_DISPLAY_PAGE_GUARD ? S_alloc_page : S_next_page;
                            S_video_in_wp <= ENABLE_DISPLAY_PAGE_GUARD ? S_alloc_page : S_next_page;
                            O_ddr_user_addr <= page_base(ENABLE_DISPLAY_PAGE_GUARD ? S_alloc_page : S_next_page);
                            O_page_valid[ENABLE_DISPLAY_PAGE_GUARD ? S_alloc_page : S_next_page] <= 1'b0;
                        end else begin
                            // 所有页都受保护时丢弃整帧，且不改动有效位。
                            S_frame_writable <= 1'b0;
                        end
                    end
                    S_frame_words_written <= 18'd0;
                    S_ddr_wr_valid <= 1'b0;
                    S_ddr_wr_cnt <= 10'd0;
                    O_ddr_user_wr_en <= 1'b0;
                end else begin
                    if (S_fifo_rst) begin
                        S_ddr_wr_valid <= 1'b0;
                        S_ddr_wr_cnt <= 10'd0;
                        O_ddr_user_wr_en <= 1'b0;
                    end else begin
                        if (S_fifo_write_take && S_ddr_wr_cnt == BURST_WORDS-1) begin
                            S_ddr_wr_valid <= 1'b0;
                            S_ddr_wr_cnt <= 10'd0;
                        end else if (!S_ddr_wr_valid && !O_ddr_user_wr_en && S_fifo_rd_num >= BURST_WORDS &&
                                     !I_video_out_rd_busy &&
                                     (!ENABLE_DISPLAY_PAGE_GUARD || S_frame_writable) &&
                                     ({1'b0,S_frame_words_written} + O_ddr_user_wr_en < FRAME_WORDS)) begin
                            S_ddr_wr_valid <= 1'b1;
                            S_ddr_wr_cnt <= 10'd0;
                        end else if (S_fifo_write_take) begin
                            S_ddr_wr_cnt <= S_ddr_wr_cnt + 1'b1;
                        end
                        O_ddr_user_wr_en <= S_fifo_write_take;
                        if (O_ddr_user_wr_en)
                            O_ddr_user_addr <= O_ddr_user_addr + 25'd8;
                    end
                end

                if (S_frame_start || S_fifo_rst || !S_ddr_wr_valid)
                    S_ddr_wr_cnt <= 10'd0;
            end
        end

        assign S_fifo_write_take = S_frame_writable && S_ddr_wr_valid && I_ddr_user_ready &&
            !S_frame_start && !S_fifo_rst && !S_fifo_empty &&
            ({1'b0,S_frame_words_written} + O_ddr_user_wr_en < FRAME_WORDS);
        assign S_fifo_rd_en = S_fifo_write_take | S_fifo_drop_drain;
    end endgenerate
endmodule
