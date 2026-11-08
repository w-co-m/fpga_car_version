

module mc_to_user_interface #(
    parameter integer STALL_LIMIT = 4194304
)(
    input wire          I_clk,
    input wire          I_rst_n,

    /*
        ddr user interface
        当I_ddr_user_ready拉低时，还能写入8个长度数据
    */
    input wire          I_ddr_user_wr_en,
    input wire          I_ddr_user_rd_en,  //synthesis keep
    input wire[24:0]    I_ddr_user_addr,
    input wire[127:0]   I_ddr_user_wr_data,
    output wire         O_ddr_user_ready,
    output wire         O_queue_idle,
    output wire         O_ddr_user_rd_valid,
    output wire[127:0]  O_ddr_user_rd_data,

    /*
        ddr memory controller interface
    */
    output  wire        O_mc_app_en,
    output  wire [24:0] O_mc_app_addr,
    output  wire [2:0]  O_mc_app_cmd,
    input  wire         I_mc_app_rdy,
    output wire         O_mc_app_wdf_wren,
    output wire [127:0] O_mc_app_wdf_data,
    output wire         O_mc_app_wdf_end,
    output wire [15:0]  O_mc_app_wdf_mask,
    input wire          I_mc_app_wdf_rdy,
    input wire [127:0]  I_mc_app_rd_data,
    input wire          I_mc_app_rd_data_end,
    input wire          I_mc_app_rd_data_valid,
    output wire         reset_required
);

    wire        S_fifo_wr_en;    
    wire[154:0] S_fifo_wr_data;
    wire        S_fifio_pro_full;
    wire        S_fifo_rd_en;    
    wire[154:0] S_fifo_rd_data;
    wire        S_fifo_rd_valid;
    wire        S_fifo_empty;   

    localparam integer STALL_COUNT_WIDTH = (STALL_LIMIT <= 2) ? 1 : $clog2(STALL_LIMIT);
    reg S_fault;
    reg [STALL_COUNT_WIDTH-1:0] S_head_stall_count;
    wire S_head_activity = S_fifo_rd_en |
        (O_mc_app_en & I_mc_app_rdy) |
        (O_mc_app_wdf_wren & I_mc_app_wdf_rdy);

    assign reset_required = S_fault;
    assign S_fifo_wr_en = I_rst_n & !S_fault &
        (I_ddr_user_wr_en ^ I_ddr_user_rd_en);

    assign S_fifo_wr_data = {I_ddr_user_wr_en,I_ddr_user_rd_en,I_ddr_user_addr,I_ddr_user_wr_data};

    // FIFO 为 SHOW_AHEAD：队首在非空时有效，直到 re 才切换下一笔。
    // AW 与 W 可在不同周期接收；记录已接收通道，防止重发地址或数据。
    reg S_addr_accepted;
    reg S_data_accepted;
    wire S_head_read = S_fifo_rd_data[153];
    wire S_addr_done = S_addr_accepted | (O_mc_app_en & I_mc_app_rdy);
    wire S_data_done = S_data_accepted | (O_mc_app_wdf_wren & I_mc_app_wdf_rdy);

    // Also quarantine the head on the edge which first detects an illegal
    // double submission. Otherwise a completed head could expose a new VALID.
    assign S_fifo_rd_en = I_rst_n & !S_fault &
                          !(I_ddr_user_wr_en & I_ddr_user_rd_en) & (~S_fifo_empty) & S_addr_done &
                          (S_head_read | S_data_done);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_addr_accepted <= 1'b0;
            S_data_accepted <= 1'b0;
        end else if (S_fifo_rd_en) begin
            // 本笔全部握手完成，下一笔重新独立握手。
            S_addr_accepted <= 1'b0;
            S_data_accepted <= 1'b0;
        end else if (!S_fifo_empty) begin
            if (O_mc_app_en & I_mc_app_rdy)
                S_addr_accepted <= 1'b1;
            if (O_mc_app_wdf_wren & I_mc_app_wdf_rdy)
                S_data_accepted <= 1'b1;
        end
    end

    assign O_ddr_user_ready = ~S_fifio_pro_full & !S_fault;
    // 表示用户命令FIFO和AW/W握手状态已空，不代表DDR物理写入完成。
    assign O_queue_idle = S_fifo_empty && !S_addr_accepted && !S_data_accepted;

    // Fault freezes the queue head, while a pending controller VALID is held
    // until handshake or full reset.
    assign O_mc_app_en = I_rst_n & (~S_fifo_empty) & (~S_addr_accepted);

    assign O_mc_app_addr = S_fifo_empty ? 25'd0 : S_fifo_rd_data[152:128];

    // cmd 必须独立于 VALID 保持，否则读 READY 选择会形成错误的反馈。
    assign O_mc_app_cmd = (~S_fifo_empty) && S_head_read ? 3'd1 : 3'd0;

    assign O_mc_app_wdf_wren = I_rst_n & (~S_fifo_empty) & (~S_head_read) &
                               S_fifo_rd_data[154] & (~S_data_accepted);

    assign O_mc_app_wdf_end = O_mc_app_wdf_wren;

    assign O_mc_app_wdf_mask = 16'd0;

    assign O_mc_app_wdf_data = S_fifo_empty ? 128'd0 : S_fifo_rd_data[127:0];

    assign O_ddr_user_rd_valid = I_mc_app_rd_data_valid;
    
    assign O_ddr_user_rd_data = I_mc_app_rd_data;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_fault <= 1'b0;
            S_head_stall_count <= 32'd0;
        end else if (S_fault) begin
            S_fault <= 1'b1;
            S_head_stall_count <= S_head_stall_count;
        end else if (I_ddr_user_wr_en & I_ddr_user_rd_en) begin
            S_fault <= 1'b1;
        end else if (S_fifo_empty || S_fifo_rd_en) begin
            S_head_stall_count <= 32'd0;
        end else if (S_head_activity) begin
            S_head_stall_count <= 32'd0;
        end else if (S_head_stall_count >= STALL_LIMIT-1) begin
            S_fault <= 1'b1;
        end else begin
            S_head_stall_count <= S_head_stall_count + 1'b1;
        end
    end

    w155_d512_fifo U_w155_d512_fifo(
        .clk        ( I_clk            ),     
        .rst        ( ~I_rst_n         ),     

        .we         ( S_fifo_wr_en     ),
        .di         ( S_fifo_wr_data   ),
        .afull      ( S_fifio_pro_full ),
        .full_flag  (),
        .wrusedw    (),
 
        .re         ( S_fifo_rd_en & !S_fault ), 
        .valid      ( S_fifo_rd_valid  ), 
        .dout       ( S_fifo_rd_data   ),  
        .empty_flag ( S_fifo_empty     ),
        .aempty     (),
        .rdusedw    ()
    );
    
endmodule
