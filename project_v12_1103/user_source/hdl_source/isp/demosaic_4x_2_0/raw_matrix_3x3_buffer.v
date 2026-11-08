`timescale 1ns/1ps
/*
 * 4像素组的3行窗口生成：首行只预填缓存，收到下一行后输出首个中心行。
 * 真实末行后补320组虚拟有效输入，经两级行缓存冲刷中心末行。
 * 窗口字节序为{左组,中心组,右组}[71:24]；首组左字节镜像中心P1，末组右字节镜像中心P2。
 * 垂直首尾分别镜像相邻真实行；payload与valid、last、user及中心行Bayer相位同拍对齐。
 */
module raw_matrix_3x3_buffer #(
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH = 1920,
    parameter data_complete_delay = 50
)(
    input I_clk,
    input I_rst_n,
    input [39:0] axi4s_video_tdata,
    input [9:0] axi4s_video_tdest,
    input axi4s_video_tlast,
    input axi4s_video_tvalid,
    input axi4s_video_tuser,
    output axi4s_video_tready,
    output reg O_tlast,
    output reg O_tuser,
    output reg O_tvalid,
    input O_tready,
    output reg bayer_ypos,
    output reg [95:0] matrix_last_line,
    output reg [95:0] matrix_cur_line,
    output reg [95:0] matrix_next_line
);
localparam GROUPS = IMG_WIDTH >> 2;

wire [31:0] raw_data;
wire raw_data_valid, raw_last, raw_user, raw_ready;
wire [31:0] zhenghe_data;
wire zhenghe_valid, zhenghe_last, zhenghe_user;
reg [13:0] source_row;
reg fake_active;
reg [13:0] fake_group;
wire feed_valid = zhenghe_valid | fake_active;
wire [32:0] feed_data = fake_active ? {1'b0,32'b0} : {zhenghe_user,zhenghe_data};
wire feed_user = !fake_active && zhenghe_user;
wire [32:0] line_data [0:2];
wire line_valid [0:2];
reg [32:0] data_d0_d, data_d0, data_d1;
reg valid_d0, valid_d1;
reg [13:0] h_cnt, v_cnt;
reg [95:0] hist0, hist1;
reg [95:0] pending_last_line, pending_cur_line, pending_next_line;
reg [95:0] flush_left, flush_center;
reg [13:0] flush_source_row;
reg have_first, flush_pending;
reg emit_valid, emit_last, emit_user, emit_phase;
wire [31:0] src_up, src_center, src_down;
wire [95:0] current_triplet;

assign axi4s_video_tready = O_tready;
assign line_data[0] = feed_data;
assign line_valid[0] = feed_valid;
assign src_up = (v_cnt == 1) ? data_d0[31:0] : line_data[2][31:0];
assign src_center = data_d1[31:0];
assign src_down = (v_cnt == IMG_HEIGHT) ? line_data[2][31:0] : data_d0[31:0];
assign current_triplet = {src_up,src_center,src_down};

mipi_to_raw_converter mipi_to_raw_converter_r0(
    .I_clk(I_clk), .I_rst_n(I_rst_n),
    .I_raw_tdata(axi4s_video_tdata), .I_raw_tdest(axi4s_video_tdest),
    .I_raw_tlast(axi4s_video_tlast), .I_raw_tvalid(axi4s_video_tvalid), .I_raw_tuser(axi4s_video_tuser),
    .I_raw_tready(raw_ready), .O_raw_tdata(raw_data), .O_raw_tlast(raw_last),
    .O_raw_tvalid(raw_data_valid), .O_raw_tuser(raw_user), .O_raw_tready(1'b1)
);
zhenghe #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.DATA_WIDTH(32),.data_complete_delay(data_complete_delay),.INITIAL_LINE_CYCLES(((IMG_WIDTH>>2)*5+1)/2)) zhenghe_d(
    .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tlast(raw_last), .I_tuser(raw_user),
    .I_tdata(raw_data), .I_tvalid(raw_data_valid), .O_tlast(zhenghe_last), .O_tuser(zhenghe_user),
    .O_tdata(zhenghe_data), .O_tvalid(zhenghe_valid)
);
genvar k;
generate for(k=1;k<3;k=k+1) begin: line_stores
    line_buffer_demosaic #(.IMG_HEIGHT(IMG_HEIGHT),.IMG_WIDTH(IMG_WIDTH)) line_buffer_demosaic_r(
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(feed_user && feed_valid),
        .I_valid(line_valid[k-1]), .I_data(line_data[k-1]),
        .O_valid(line_valid[k]), .O_data(line_data[k])
    );
end endgenerate

// 最后一条真实输入行完成后补入一行虚拟valid，借行缓存生成镜像下邻。
always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        source_row <= 0; fake_active <= 0; fake_group <= 0;
    end else begin
        if(zhenghe_user) source_row <= 0;
        else if(zhenghe_last) begin
            if(source_row == IMG_HEIGHT-1) begin fake_active <= 1; fake_group <= 0; end
            source_row <= source_row + 1'b1;
        end
        if(fake_active) begin
            if(fake_group == GROUPS-1) begin fake_active <= 0; fake_group <= 0; end
            else fake_group <= fake_group + 1'b1;
        end
    end
end

always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        data_d0_d <= 0; data_d0 <= 0; data_d1 <= 0;
        valid_d0 <= 0; valid_d1 <= 0;
        h_cnt <= 0; v_cnt <= 0;
        hist0 <= 0; hist1 <= 0; have_first <= 0;
        flush_left <= 0; flush_center <= 0; flush_source_row <= 0; flush_pending <= 0;
        matrix_last_line <= 0; matrix_cur_line <= 0; matrix_next_line <= 0;
        pending_last_line <= 0; pending_cur_line <= 0; pending_next_line <= 0;
        emit_valid <= 0; emit_last <= 0; emit_user <= 0;
        emit_phase <= 0;
        O_tvalid <= 0; O_tlast <= 0; O_tuser <= 0; bayer_ypos <= 0;
    end else begin
        data_d0_d <= feed_data;
        data_d0 <= data_d0_d;
        data_d1 <= line_data[1];
        valid_d0 <= feed_valid;
        valid_d1 <= valid_d0;
        emit_valid <= 0; emit_last <= 0; emit_user <= 0;
        // emit_*是待输出元数据；矩阵载荷与valid同拍再登记，避免下一中心组覆盖flush尾组。
        if (emit_valid) begin
            matrix_last_line <= pending_last_line;
            matrix_cur_line <= pending_cur_line;
            matrix_next_line <= pending_next_line;
        end


        if(zhenghe_user) begin h_cnt <= 0; v_cnt <= 0; have_first <= 0; flush_pending <= 0; end
        else if(valid_d1) begin
            if(h_cnt == GROUPS-1) begin
                h_cnt <= 0;
                if(v_cnt < IMG_HEIGHT+1) v_cnt <= v_cnt + 1'b1;
                have_first <= 0;
            end else begin h_cnt <= h_cnt + 1'b1; end
        end

        if(valid_d1) begin
            if(v_cnt >= 1) begin
                if(h_cnt == 0) begin
                    hist0 <= current_triplet;
                    hist1 <= current_triplet;
                    have_first <= 1;
                end else if(have_first) begin
                    pending_last_line <= {((h_cnt == 1) ? {24'b0,hist0[87:80]} : hist1[95:64]), hist0[95:64], src_up};
                    pending_cur_line <= {((h_cnt == 1) ? {24'b0,hist0[55:48]} : hist1[63:32]), hist0[63:32], src_center};
                    pending_next_line <= {((h_cnt == 1) ? {24'b0,hist0[23:16]} : hist1[31:0]), hist0[31:0], src_down};
                    emit_valid <= 1;
                    emit_user <= (v_cnt == 1) && (h_cnt == 1);
                    emit_phase <= (v_cnt - 1'b1) & 1'b1;
                    hist1 <= hist0;
                    hist0 <= current_triplet;
                    if(h_cnt == GROUPS-1) begin
                        flush_left <= hist0;
                        flush_center <= current_triplet;
                        flush_source_row <= v_cnt;
                        flush_pending <= 1;
                    end
                end
            end else if(h_cnt == 0) begin
                hist0 <= current_triplet;
                hist1 <= current_triplet;
                have_first <= 1;
            end
        end
        // 当前行最后中心组右邻缺失时，用中心P2镜像补齐，并发出行尾标志。
        if(flush_pending && (!valid_d1 || h_cnt == 0)) begin
            pending_last_line <= {flush_left[95:64],flush_center[95:64],{flush_center[79:72],24'b0}};
            pending_cur_line <= {flush_left[63:32],flush_center[63:32],{flush_center[47:40],24'b0}};
            pending_next_line <= {flush_left[31:0],flush_center[31:0],{flush_center[15:8],24'b0}};
            emit_valid <= 1;
            emit_last <= 1;
            emit_phase <= (flush_source_row - 1'b1) & 1'b1;
            flush_pending <= 0;
        end
        O_tvalid <= emit_valid;
        O_tlast <= emit_last;
        O_tuser <= emit_user;
        bayer_ypos <= emit_phase;
    end
end
endmodule




