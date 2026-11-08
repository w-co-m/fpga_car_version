`timescale 1ns/1ps
// 像素域状态叠加层。参考安路 SC520 第三例程 hdmi_mixer.v 的字符/Logo 混合方式。
    // OSD 放在算法输出之后；地址/字模与底图、同步先后寄存，输出固定延迟两拍。
module video_status_osd #(
    parameter integer ENABLE_POLAR_STATUS = 0,
    parameter integer ENABLE_DDR_STATUS = 0,
    parameter integer ENABLE_PREVIEW_GAMMA = 0,
    parameter integer ENABLE_MOTION_THRESHOLD = 0,
    parameter integer DECIMAL_COUNTER = 0,
    parameter integer GIMBAL_STATUS_ENABLE = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [23:0] rgb_in,
    input  wire        de_in,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire [3:0]  mode_active,
    input  wire [7:0]  bin_threshold_active, edge_threshold_active,
    input  wire [7:0]  bright_gain_active, contrast_gain_active,
    input  wire        threshold_edit_active,
    input  wire [1:0]  polar_angle,
    input  wire        polar_capture_busy,
    input  wire        polar_compute_busy,
    input  wire        polar_ready,
    input  wire        polar_error,
    input  wire [1:0]  ddr_state,
    output reg  [23:0] rgb_out,
    output reg         de_out,
    output reg         hs_out,
    output reg         vs_out,
    input wire gimbal_armed,gimbal_live,
    input  wire [7:0]  motion_threshold_active
);
    function [7:0] gamma07;
        input [7:0] value;
        reg [7:0] base, delta;
        reg [11:0] scaled_delta, interpolation;
        begin
            case (value[7:4])
                4'h0: begin base=8'd0;   delta=8'd37; end
                4'h1: begin base=8'd37;  delta=8'd23; end
                4'h2: begin base=8'd60;  delta=8'd19; end
                4'h3: begin base=8'd79;  delta=8'd18; end
                4'h4: begin base=8'd97;  delta=8'd16; end
                4'h5: begin base=8'd113; delta=8'd16; end
                4'h6: begin base=8'd129; delta=8'd14; end
                4'h7: begin base=8'd143; delta=8'd14; end
                4'h8: begin base=8'd157; delta=8'd14; end
                4'h9: begin base=8'd171; delta=8'd13; end
                4'ha: begin base=8'd184; delta=8'd13; end
                4'hb: begin base=8'd197; delta=8'd12; end
                4'hc: begin base=8'd209; delta=8'd12; end
                4'hd: begin base=8'd221; delta=8'd12; end
                4'he: begin base=8'd233; delta=8'd11; end
                default: begin base=8'd244; delta=8'd11; end
            endcase
            scaled_delta = {4'd0,delta} * {8'd0,value[3:0]};
            interpolation = scaled_delta + 12'd8;
            if (value == 8'hff) gamma07 = 8'hff;
            else gamma07 = base + (interpolation >> 4);
        end
    endfunction

    function [23:0] gamma_rgb24;
        input [23:0] value;
        begin
            gamma_rgb24 = {gamma07(value[23:16]),gamma07(value[15:8]),gamma07(value[7:0])};
        end
    endfunction

    localparam [11:0] LOGO_X = 12'd20, LOGO_Y = 12'd20;
    localparam [11:0] TEXT_X = 12'd200, TEXT_Y = 12'd20;
    localparam [23:0] TEXT_COLOR = 24'h00e6ff;

    reg [11:0] pixel_x, pixel_y;
    reg de_d, vs_d;
    reg [31:0] frame_count;
    reg [23:0] frame_bcd;
    (* async_reg="true" *) reg [1:0] armed_sync,live_sync;
    reg s1_gimbal_on;
    reg [23:0] s1_gimbal_color;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin armed_sync<=0;live_sync<=0;end
        else begin armed_sync<={armed_sync[0],gimbal_armed};live_sync<={live_sync[0],gimbal_live};end
    function [23:0] next_bcd;
        input [23:0] value;integer i;reg carry;
        begin next_bcd=value;carry=1;
            for(i=0;i<6;i=i+1)if(carry)begin
                if(value[i*4+:4]==9)next_bcd[i*4+:4]=0;
                else begin next_bcd[i*4+:4]=value[i*4+:4]+1'b1;carry=0;end
            end
        end
    endfunction
    reg [14:0] logo_addr;
    reg [11:0] logo_x_offset, logo_y_offset;
    reg logo_enable;
    wire [24:0] logo_pixel;
    reg [7:0] char_code;
    reg [1:0] text_line;
    reg [5:0] char_index;
    reg [3:0] char_row, char_col;
    reg [4:0] text_pixel_in_cell;
    reg [5:0] text_cell_index;
    wire [15:0] char_bits;
    reg text_on;
    reg glyph_col_valid;

    // 第一级寄存器：切断坐标/地址到大型 ROM 和字库再到输出的长组合路径。
    reg s1_logo_enable, s1_text_on, s1_glyph_col_valid;
    reg [7:0] s1_char_code;
    reg [3:0] s1_char_row, s1_char_col;
    reg [23:0] s1_rgb;
    reg s1_de, s1_hs, s1_vs;

    // 取指定模式名称字符，未知模式显示 UNKNOWN。
    function [7:0] mode_char;
        input [3:0] mode;
        input [5:0] index;
        begin
            mode_char = 8'h20;
            case (mode)
                4'd0: case(index) 0:mode_char="R"; 1:mode_char="A"; 2:mode_char="W"; endcase
                4'd1: case(index) 0:mode_char="G"; 1:mode_char="R"; 2:mode_char="A"; 3:mode_char="Y"; endcase
                4'd2: case(index) 0:mode_char="B"; 1:mode_char="I"; 2:mode_char="N"; 3:mode_char="A"; 4:mode_char="R"; 5:mode_char="Y"; endcase
                4'd3: case(index) 0:mode_char="S"; 1:mode_char="O"; 2:mode_char="B"; 3:mode_char="E"; 4:mode_char="L"; endcase
                4'd4: case(index) 0:mode_char="B"; 1:mode_char="R"; 2:mode_char="I"; 3:mode_char="G"; 4:mode_char="H"; 5:mode_char="T"; endcase
                4'd5: case(index) 0:mode_char="C"; 1:mode_char="O"; 2:mode_char="N"; 3:mode_char="T"; 4:mode_char="R"; 5:mode_char="A"; 6:mode_char="S"; 7:mode_char="T"; endcase
                4'd6: case(index) 0:mode_char="H"; 1:mode_char="I"; 2:mode_char="S"; 3:mode_char="T"; 4:mode_char="E"; 5:mode_char="Q"; endcase
                4'd7: case(index) 0:mode_char="E"; 1:mode_char="R"; 2:mode_char="O"; 3:mode_char="D"; 4:mode_char="E"; endcase
                4'd8: case(index) 0:mode_char="D"; 1:mode_char="I"; 2:mode_char="L"; 3:mode_char="A"; 4:mode_char="T"; 5:mode_char="E"; endcase
                4'd9: case(index) 0:mode_char="D"; 1:mode_char="O"; 2:mode_char="L"; 3:mode_char="P"; endcase
                4'd10: case(index) 0:mode_char="A"; 1:mode_char="O"; 2:mode_char="P"; endcase
                4'd11: case(index) 0:mode_char="F"; 1:mode_char="U"; 2:mode_char="S"; 3:mode_char="I"; 4:mode_char="O"; 5:mode_char="N"; endcase
                4'd12: case(index) 0:mode_char="P"; 1:mode_char="E"; 2:mode_char="D"; 3:mode_char="G"; 4:mode_char="E"; endcase
                4'd13: case(index) 0:mode_char="C"; 1:mode_char="O"; 2:mode_char="L"; 3:mode_char="O"; 4:mode_char="R"; 5:mode_char="B"; 6:mode_char="O"; 7:mode_char="X"; endcase
                4'd14: case(index) 0:mode_char="M"; 1:mode_char="O"; 2:mode_char="T"; 3:mode_char="I"; 4:mode_char="O"; 5:mode_char="N"; endcase
                4'd15: case(index) 0:mode_char="T"; 1:mode_char="R"; 2:mode_char="A"; 3:mode_char="C"; 4:mode_char="K"; endcase
                default: case(index) 0:mode_char="U"; 1:mode_char="N"; 2:mode_char="K"; 3:mode_char="N"; 4:mode_char="O"; 5:mode_char="W"; 6:mode_char="N"; endcase
            endcase
        end
    endfunction

    // 生成四行状态文字；帧号明确标成十六进制，不表示算法延迟。
    function [7:0] text_char;
        input [1:0] line_no;
        input [5:0] index;
        input [3:0] mode;
        input [31:0] frame_value;
        input [7:0] bin_value, edge_value;
        input edit_value;
        input [1:0] angle_value;
        input capture_value, compute_value, ready_value, error_value;
        input [1:0] ddr_value;
        reg [7:0] threshold_value;
        reg [3:0] nibble;
        begin
            text_char = 8'h20;
            // 4/5调用时复用两个数值参数承载增益，函数签名及旧阈值路径保持。
            threshold_value = (ENABLE_MOTION_THRESHOLD && mode == 4'd14) ? edge_value :
                              ((mode == 2 || mode == 4) ? bin_value : edge_value);
            case (line_no)
                2'd0: begin
                    case (index)
                        0:text_char="M"; 1:text_char="O"; 2:text_char="D";
                        3:text_char="E"; 4:text_char=":"; 5:text_char=" ";
                        default: if ((index >= 6) && (index <= 13))
                                     text_char=mode_char(mode,index-6);
                    endcase
                end
                2'd1: begin
                    case (index)
                        0:text_char="C"; 1:text_char="N"; 2:text_char="T";
                        3:text_char=":";
                        default: if ((index >= 5) && (index <= (DECIMAL_COUNTER ? 10 : 12))) begin
                            nibble = (frame_value >> (((DECIMAL_COUNTER ? 10 : 12)-index)*4)) & 4'hf;
                            if (nibble < 10) text_char = 8'h30 + nibble;
                            else            text_char = 8'h41 + nibble - 10;
                        end
                    endcase
                end
                2'd2: begin
                    if (ENABLE_POLAR_STATUS && mode >= 4'd9 && mode <= 4'd12) begin
                        case (index)
                            0:text_char="A"; 1:text_char="N"; 2:text_char="G"; 3:text_char="L";
                            4:text_char="E"; 5:text_char=":";
                            6:text_char=(angle_value==3) ? "1" : "0";
                            7:text_char=(angle_value==0) ? "0" : (angle_value==1) ? "4" : (angle_value==2) ? "9" : "3";
                            8:text_char=(angle_value==1 || angle_value==3) ? "5" : "0";
                            10:text_char="S"; 11:text_char="W"; 12:text_char="1"; 13:text_char="="; 14:text_char="1";
                            default:text_char=8'h20;
                        endcase
                    end else case (index)
                        0:text_char="P"; 1:text_char="O"; 2:text_char="L";
                        3:text_char=" "; 4:text_char="F"; 5:text_char="I";
                        6:text_char="L"; 7:text_char="T"; 8:text_char="E";
                        9:text_char="R"; default:text_char=8'h20;
                    endcase
                end
                default: begin
                    if (ENABLE_DDR_STATUS && ddr_value != 2'd0) begin
                        case (index)
                            0:text_char="D"; 1:text_char="D"; 2:text_char="R";
                            3:text_char=8'h20; 4:text_char=(ddr_value==2'd1) ? "W" : "E";
                            5:text_char=(ddr_value==2'd1) ? "A" : "R";
                            6:text_char=(ddr_value==2'd1) ? "I" : "R";
                            7:text_char=(ddr_value==2'd1) ? "T" : "O";
                            8:text_char=(ddr_value==2'd1) ? 8'h20 : "R";
                            default:text_char=8'h20;
                        endcase
                    end else if (ENABLE_POLAR_STATUS && mode >= 4'd9 && mode <= 4'd12) begin
                        case (index)
                            0:if(error_value) text_char="R"; else if(compute_value || capture_value) text_char="C"; else if(ready_value) text_char="R";
                            1:if(error_value) text_char="E"; else if(compute_value) text_char="O"; else if(capture_value) text_char="A"; else if(ready_value) text_char="E";
                            2:if(error_value) text_char="T"; else if(compute_value) text_char="M"; else if(capture_value) text_char="P"; else if(ready_value) text_char="A";
                            3:if(error_value) text_char="R"; else if(compute_value) text_char="P"; else if(capture_value) text_char="T"; else if(ready_value) text_char="D";
                            4:if(error_value) text_char="Y"; else if(compute_value) text_char="U"; else if(capture_value) text_char="U"; else if(ready_value) text_char="Y";
                            5:if(compute_value) text_char="T"; else if(capture_value) text_char="R"; else text_char=8'h20;
                            6:if(compute_value) text_char="E"; else if(capture_value) text_char="E"; else text_char=8'h20;
                            7:text_char=8'h20;
                            8:text_char="N"; 9:text_char="E"; 10:text_char="X"; 11:text_char="T";
                            12:text_char="/"; 13:text_char="R"; 14:text_char="E"; 15:text_char="S"; 16:text_char="E"; 17:text_char="T";
                            default:text_char=8'h20;
                        endcase
                    end else if (ENABLE_MOTION_THRESHOLD && mode == 4'd14) begin
                        case (index)
                            0:text_char="M"; 1:text_char="O"; 2:text_char="T"; 4:text_char="T";
                            5:text_char="H"; 6:text_char="R"; 7:text_char=":";
                            8:text_char=8'h30 + threshold_value/100;
                            9:text_char=8'h30 + (threshold_value/10)%10;
                            10:text_char=8'h30 + threshold_value%10;
                            14:text_char="K"; 15:text_char="E"; 16:text_char="Y"; 17:text_char=":";
                            18:text_char=edit_value ? "T" : "M";
                            19:text_char=edit_value ? "H" : "O";
                            20:text_char=edit_value ? "R" : "D";
                            21:if(!edit_value) text_char="E";
                            default:text_char=8'h20;
                        endcase
                    end else if (mode == 4'd4 || mode == 4'd5) begin
                        case (index)
                            0:text_char=(mode==4'd4) ? "B" : "C";
                            1:text_char=(mode==4'd4) ? "R" : "O";
                            2:text_char=(mode==4'd4) ? "I" : "N";
                            4:text_char="G"; 5:text_char="A"; 6:text_char="I"; 7:text_char="N"; 8:text_char=":";
                            9:text_char=8'h30 + threshold_value/100;
                            10:text_char=8'h30 + (threshold_value/10)%10;
                            11:text_char=8'h30 + threshold_value%10;
                            14:text_char="K"; 15:text_char="E"; 16:text_char="Y"; 17:text_char=":";
                            18:text_char=edit_value ? "G" : "M";
                            19:text_char=edit_value ? "A" : "O";
                            20:text_char=edit_value ? "I" : "D";
                            21:text_char=edit_value ? "N" : "E";
                            default:text_char=8'h20;
                        endcase
                    end else case (index)
                        0:if(mode==2) text_char="B"; else if(mode==3) text_char="S";
                        1:if(mode==2) text_char="I"; else if(mode==3) text_char="O";
                        2:if(mode==2) text_char="N"; else if(mode==3) text_char="B";
                        4:text_char="T"; 5:text_char="H"; 6:text_char="R"; 7:text_char=":";
                        // 十进制三位数；其它算法没有阈值，显示---。
                        8: text_char=(mode==2 || mode==3) ? (8'h30 + threshold_value/100) : "-";
                        9: text_char=(mode==2 || mode==3) ? (8'h30 + (threshold_value/10)%10) : "-";
                        10:text_char=(mode==2 || mode==3) ? (8'h30 + threshold_value%10) : "-";
                        14:text_char="K"; 15:text_char="E"; 16:text_char="Y"; 17:text_char=":";
                        18:text_char=edit_value ? "T" : "M";
                        19:text_char=edit_value ? "H" : "O";
                        20:text_char=edit_value ? "R" : "D";
                        21:if(!edit_value) text_char="E";
                        default:text_char=8'h20;
                    endcase
                end
            endcase
        end
    endfunction

    // 字库与 Logo ROM 沿用安路例程源文件。
    osd_char_lib u_osd_char_lib (
        .I_char(s1_char_code), .I_row(s1_char_row), .O_row_bits(char_bits)
    );
    anlogic_logo_sync_rom_direct u_anlogic_logo_rom (
        .clk(clk), .I_addr(logo_addr), .O_pixel(logo_pixel)
    );

    always @* begin
        logo_addr = 15'd0;
        char_code = 8'h20;
        text_line = 2'd0;
        char_index = 6'd0;
        char_row = 4'd0;
        char_col = 4'd0;
        text_on = 1'b0;
        glyph_col_valid = 1'b0;
        logo_enable = 1'b0;
        logo_x_offset = 12'd0;
        logo_y_offset = 12'd0;

        if ((pixel_x >= LOGO_X) && (pixel_x < LOGO_X + 12'd160) &&
            (pixel_y >= LOGO_Y) && (pixel_y < LOGO_Y + 12'd160)) begin
            logo_enable = 1'b1;
            logo_x_offset = pixel_x - LOGO_X;
            logo_y_offset = pixel_y - LOGO_Y;
            logo_addr = ({3'd0, logo_y_offset} << 7) + ({3'd0, logo_y_offset} << 5) + {3'd0, logo_x_offset};
        end

        if ((pixel_x >= TEXT_X) && (pixel_x < TEXT_X + 12'd540)) begin
            if ((pixel_y >= TEXT_Y) && (pixel_y < TEXT_Y + 12'd16)) begin
                text_line = 2'd0;
                text_on = 1'b1;
            end else if ((pixel_y >= TEXT_Y + 12'd22) && (pixel_y < TEXT_Y + 12'd38)) begin
                text_line = 2'd1;
                text_on = 1'b1;
            end else if ((pixel_y >= TEXT_Y + 12'd44) && (pixel_y < TEXT_Y + 12'd60)) begin
                text_line = 2'd2;
                text_on = 1'b1;
            end else if ((pixel_y >= TEXT_Y + 12'd66) && (pixel_y < TEXT_Y + 12'd82)) begin
                text_line = 2'd3;
                text_on = 1'b1;
            end
            if (text_on) begin
                char_index = text_cell_index;
                char_col = text_pixel_in_cell[3:0];
                char_row = pixel_y - TEXT_Y - text_line * 22;
                char_code = text_char(text_line, char_index, mode_active, DECIMAL_COUNTER ? {8'd0,frame_bcd} : frame_count,
                                      (mode_active==4'd4) ? bright_gain_active : bin_threshold_active,
                                      (ENABLE_MOTION_THRESHOLD && mode_active==4'd14) ? motion_threshold_active :
                                      ((mode_active==4'd5) ? contrast_gain_active : edge_threshold_active),
                                      threshold_edit_active,
                                      polar_angle, polar_capture_busy, polar_compute_busy,
                                      polar_ready, polar_error, ddr_state);
                // 5位列计数保留完整0..17范围，16/17列属于字符间隔。
                glyph_col_valid = (text_pixel_in_cell < 5'd16);
            end
        end
    end

    // 第一级保存地址、字码、底图与同步；x/y 仍按有效 DE 连续计数。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_x <= 12'd0;
            pixel_y <= 12'd0;
            text_pixel_in_cell <= 5'd0;
            text_cell_index <= 6'd0;
            de_d <= 1'b0;
            vs_d <= 1'b0;
            frame_count <= 32'd0;frame_bcd<=0;s1_gimbal_on<=0;s1_gimbal_color<=0;
            s1_logo_enable <= 1'b0;
            s1_text_on <= 1'b0;
            s1_glyph_col_valid <= 1'b0;
            s1_char_code <= 8'h20;
            s1_char_row <= 4'd0;
            s1_char_col <= 4'd0;
            s1_rgb <= 24'd0;
            s1_de <= 1'b0;
            s1_hs <= 1'b0;
            s1_vs <= 1'b0;
            rgb_out <= 24'd0;
            de_out <= 1'b0;
            hs_out <= 1'b0;
            vs_out <= 1'b0;
        end else begin
            s1_gimbal_on <= GIMBAL_STATUS_ENABLE && mode_active==4'hF &&
                pixel_x>=12'd560 && pixel_x<12'd576 && pixel_y>=12'd20 && pixel_y<12'd36;
            s1_gimbal_color <= !armed_sync[1] ? 24'h808080 : live_sync[1] ? 24'h00ff00 : 24'h00ffff;
            s1_logo_enable <= logo_enable;
            s1_text_on <= text_on;
            s1_glyph_col_valid <= glyph_col_valid;
            s1_char_code <= char_code;
            s1_char_row <= char_row;
            s1_char_col <= char_col;
            if (ENABLE_PREVIEW_GAMMA &&
                (mode_active == 4'd0 || mode_active == 4'd13 || mode_active == 4'd15))
                s1_rgb <= gamma_rgb24(rgb_in);
            else
                s1_rgb <= rgb_in;
            s1_de <= de_in;
            s1_hs <= hs_in;
            s1_vs <= vs_in;

            rgb_out <= s1_rgb;
            if(s1_gimbal_on) rgb_out<=s1_gimbal_color;
            else if (s1_logo_enable && logo_pixel[24])
                rgb_out <= logo_pixel[23:0];
            else if (s1_text_on && s1_glyph_col_valid && char_bits[15-s1_char_col])
                rgb_out <= TEXT_COLOR;
            de_out <= s1_de;
            hs_out <= s1_hs;
            vs_out <= s1_vs;
            de_d <= de_in;
            vs_d <= vs_in;

            if (vs_in) begin
                pixel_x <= 12'd0;
                pixel_y <= 12'd0;
                text_pixel_in_cell <= 5'd0;
                text_cell_index <= 6'd0;
            end else if (de_in) begin
                if (pixel_x != 12'hfff) pixel_x <= pixel_x + 1'b1;
                if ((pixel_x < TEXT_X) || (pixel_x >= TEXT_X + 12'd540)) begin
                    text_pixel_in_cell <= 5'd0;
                    text_cell_index <= 6'd0;
                end else if (text_pixel_in_cell == 5'd17) begin
                    text_pixel_in_cell <= 5'd0;
                    text_cell_index <= text_cell_index + 1'b1;
                end else begin
                    text_pixel_in_cell <= text_pixel_in_cell + 1'b1;
                end
            end else if (de_d) begin
                pixel_x <= 12'd0;
                text_pixel_in_cell <= 5'd0;
                text_cell_index <= 6'd0;
                if (pixel_y != 12'hfff) pixel_y <= pixel_y + 1'b1;
            end

            if (vs_in && !vs_d) begin frame_count <= frame_count + 1'b1;frame_bcd<=next_bcd(frame_bcd);end
        end
    end
endmodule
