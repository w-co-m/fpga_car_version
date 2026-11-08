// 字符格为16x16；大写字母和数字均用5x7字形并静态展开为2x2像素。
// 英数有效笔画固定在y=1..14，左右字宽范围x=3..12；窄体I/1在范围内居中。
// O_row_bits[15-x]对应格内从左到右的像素；组合接口和行宽保持不变。
module osd_char_lib (
    input wire [7:0] I_char,
    input wire [3:0] I_row,
    output reg [15:0] O_row_bits
);
    localparam CHAR_AN = 8'h80;
    localparam CHAR_LU = 8'h81;
    localparam CHAR_A = 8'h41;
    localparam CHAR_B = 8'h42;
    localparam CHAR_C = 8'h43;
    localparam CHAR_D = 8'h44;
    localparam CHAR_E = 8'h45;
    localparam CHAR_F = 8'h46;
    localparam CHAR_G = 8'h47;
    localparam CHAR_H = 8'h48;
    localparam CHAR_I = 8'h49;
    localparam CHAR_J = 8'h4a;
    localparam CHAR_K = 8'h4b;
    localparam CHAR_L = 8'h4c;
    localparam CHAR_M = 8'h4d;
    localparam CHAR_N = 8'h4e;
    localparam CHAR_O = 8'h4f;
    localparam CHAR_P = 8'h50;
    localparam CHAR_Q = 8'h51;
    localparam CHAR_R = 8'h52;
    localparam CHAR_S = 8'h53;
    localparam CHAR_T = 8'h54;
    localparam CHAR_U = 8'h55;
    localparam CHAR_V = 8'h56;
    localparam CHAR_W = 8'h57;
    localparam CHAR_X = 8'h58;
    localparam CHAR_Y = 8'h59;
    localparam CHAR_Z = 8'h5a;
    localparam CHAR_0 = 8'h30;
    localparam CHAR_1 = 8'h31;
    localparam CHAR_2 = 8'h32;
    localparam CHAR_3 = 8'h33;
    localparam CHAR_4 = 8'h34;
    localparam CHAR_5 = 8'h35;
    localparam CHAR_6 = 8'h36;
    localparam CHAR_7 = 8'h37;
    localparam CHAR_8 = 8'h38;
    localparam CHAR_9 = 8'h39;
    localparam CHAR_COLON = 8'h3a;
    localparam CHAR_DASH = 8'h2d;
    localparam CHAR_SLASH = 8'h2f;
    localparam CHAR_EQUAL = 8'h3d;

    always @* begin
        O_row_bits = 16'h0000;
        case (I_char)
            CHAR_A: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07e0;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h1ff8;
                    4'd9, 4'd10: O_row_bits = 16'h1818;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h1818;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_B: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1fe0;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h1fe0;
                    4'd9, 4'd10: O_row_bits = 16'h1818;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h1fe0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_C: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07f8;
                    4'd3, 4'd4: O_row_bits = 16'h1800;
                    4'd5, 4'd6: O_row_bits = 16'h1800;
                    4'd7, 4'd8: O_row_bits = 16'h1800;
                    4'd9, 4'd10: O_row_bits = 16'h1800;
                    4'd11, 4'd12: O_row_bits = 16'h1800;
                    4'd13, 4'd14: O_row_bits = 16'h07f8;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_D: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1fe0;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h1818;
                    4'd9, 4'd10: O_row_bits = 16'h1818;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h1fe0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_E: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1ff8;
                    4'd3, 4'd4: O_row_bits = 16'h1800;
                    4'd5, 4'd6: O_row_bits = 16'h1800;
                    4'd7, 4'd8: O_row_bits = 16'h1fe0;
                    4'd9, 4'd10: O_row_bits = 16'h1800;
                    4'd11, 4'd12: O_row_bits = 16'h1800;
                    4'd13, 4'd14: O_row_bits = 16'h1ff8;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_F: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1ff8;
                    4'd3, 4'd4: O_row_bits = 16'h1800;
                    4'd5, 4'd6: O_row_bits = 16'h1800;
                    4'd7, 4'd8: O_row_bits = 16'h1fe0;
                    4'd9, 4'd10: O_row_bits = 16'h1800;
                    4'd11, 4'd12: O_row_bits = 16'h1800;
                    4'd13, 4'd14: O_row_bits = 16'h1800;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_G: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07f8;
                    4'd3, 4'd4: O_row_bits = 16'h1800;
                    4'd5, 4'd6: O_row_bits = 16'h1800;
                    4'd7, 4'd8: O_row_bits = 16'h19f8;
                    4'd9, 4'd10: O_row_bits = 16'h1818;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h07f8;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_H: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1818;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h1ff8;
                    4'd9, 4'd10: O_row_bits = 16'h1818;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h1818;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_I: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07e0;
                    4'd3, 4'd4: O_row_bits = 16'h0180;
                    4'd5, 4'd6: O_row_bits = 16'h0180;
                    4'd7, 4'd8: O_row_bits = 16'h0180;
                    4'd9, 4'd10: O_row_bits = 16'h0180;
                    4'd11, 4'd12: O_row_bits = 16'h0180;
                    4'd13, 4'd14: O_row_bits = 16'h07e0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_J: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h01f8;
                    4'd3, 4'd4: O_row_bits = 16'h0060;
                    4'd5, 4'd6: O_row_bits = 16'h0060;
                    4'd7, 4'd8: O_row_bits = 16'h0060;
                    4'd9, 4'd10: O_row_bits = 16'h1860;
                    4'd11, 4'd12: O_row_bits = 16'h1860;
                    4'd13, 4'd14: O_row_bits = 16'h0780;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_K: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1818;
                    4'd3, 4'd4: O_row_bits = 16'h1860;
                    4'd5, 4'd6: O_row_bits = 16'h1980;
                    4'd7, 4'd8: O_row_bits = 16'h1e00;
                    4'd9, 4'd10: O_row_bits = 16'h1980;
                    4'd11, 4'd12: O_row_bits = 16'h1860;
                    4'd13, 4'd14: O_row_bits = 16'h1818;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_L: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1800;
                    4'd3, 4'd4: O_row_bits = 16'h1800;
                    4'd5, 4'd6: O_row_bits = 16'h1800;
                    4'd7, 4'd8: O_row_bits = 16'h1800;
                    4'd9, 4'd10: O_row_bits = 16'h1800;
                    4'd11, 4'd12: O_row_bits = 16'h1800;
                    4'd13, 4'd14: O_row_bits = 16'h1ff8;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_M: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1818;
                    4'd3, 4'd4: O_row_bits = 16'h1e78;
                    4'd5, 4'd6: O_row_bits = 16'h1998;
                    4'd7, 4'd8: O_row_bits = 16'h1998;
                    4'd9, 4'd10: O_row_bits = 16'h1818;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h1818;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_N: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1818;
                    4'd3, 4'd4: O_row_bits = 16'h1e18;
                    4'd5, 4'd6: O_row_bits = 16'h1998;
                    4'd7, 4'd8: O_row_bits = 16'h1878;
                    4'd9, 4'd10: O_row_bits = 16'h1818;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h1818;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_O: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07e0;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h1818;
                    4'd9, 4'd10: O_row_bits = 16'h1818;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h07e0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_P: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1fe0;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h1fe0;
                    4'd9, 4'd10: O_row_bits = 16'h1800;
                    4'd11, 4'd12: O_row_bits = 16'h1800;
                    4'd13, 4'd14: O_row_bits = 16'h1800;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_Q: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07e0;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h1818;
                    4'd9, 4'd10: O_row_bits = 16'h1998;
                    4'd11, 4'd12: O_row_bits = 16'h1860;
                    4'd13, 4'd14: O_row_bits = 16'h0798;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_R: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1fe0;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h1fe0;
                    4'd9, 4'd10: O_row_bits = 16'h1980;
                    4'd11, 4'd12: O_row_bits = 16'h1860;
                    4'd13, 4'd14: O_row_bits = 16'h1818;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_S: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07f8;
                    4'd3, 4'd4: O_row_bits = 16'h1800;
                    4'd5, 4'd6: O_row_bits = 16'h1800;
                    4'd7, 4'd8: O_row_bits = 16'h07e0;
                    4'd9, 4'd10: O_row_bits = 16'h0018;
                    4'd11, 4'd12: O_row_bits = 16'h0018;
                    4'd13, 4'd14: O_row_bits = 16'h1fe0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_T: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1ff8;
                    4'd3, 4'd4: O_row_bits = 16'h0180;
                    4'd5, 4'd6: O_row_bits = 16'h0180;
                    4'd7, 4'd8: O_row_bits = 16'h0180;
                    4'd9, 4'd10: O_row_bits = 16'h0180;
                    4'd11, 4'd12: O_row_bits = 16'h0180;
                    4'd13, 4'd14: O_row_bits = 16'h0180;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_U: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1818;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h1818;
                    4'd9, 4'd10: O_row_bits = 16'h1818;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h07e0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_V: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1818;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h1818;
                    4'd9, 4'd10: O_row_bits = 16'h0660;
                    4'd11, 4'd12: O_row_bits = 16'h0660;
                    4'd13, 4'd14: O_row_bits = 16'h0180;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_W: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1818;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h1998;
                    4'd9, 4'd10: O_row_bits = 16'h1998;
                    4'd11, 4'd12: O_row_bits = 16'h1998;
                    4'd13, 4'd14: O_row_bits = 16'h0660;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_X: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1818;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h0660;
                    4'd7, 4'd8: O_row_bits = 16'h0180;
                    4'd9, 4'd10: O_row_bits = 16'h0660;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h1818;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_Y: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1818;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h0660;
                    4'd7, 4'd8: O_row_bits = 16'h0180;
                    4'd9, 4'd10: O_row_bits = 16'h0180;
                    4'd11, 4'd12: O_row_bits = 16'h0180;
                    4'd13, 4'd14: O_row_bits = 16'h0180;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_Z: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1ff8;
                    4'd3, 4'd4: O_row_bits = 16'h0018;
                    4'd5, 4'd6: O_row_bits = 16'h0060;
                    4'd7, 4'd8: O_row_bits = 16'h0180;
                    4'd9, 4'd10: O_row_bits = 16'h0600;
                    4'd11, 4'd12: O_row_bits = 16'h1800;
                    4'd13, 4'd14: O_row_bits = 16'h1ff8;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_0: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07e0;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1878;
                    4'd7, 4'd8: O_row_bits = 16'h1998;
                    4'd9, 4'd10: O_row_bits = 16'h1e18;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h07e0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_1: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h0180;
                    4'd3, 4'd4: O_row_bits = 16'h0780;
                    4'd5, 4'd6: O_row_bits = 16'h0180;
                    4'd7, 4'd8: O_row_bits = 16'h0180;
                    4'd9, 4'd10: O_row_bits = 16'h0180;
                    4'd11, 4'd12: O_row_bits = 16'h0180;
                    4'd13, 4'd14: O_row_bits = 16'h07e0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_2: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07e0;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h0018;
                    4'd7, 4'd8: O_row_bits = 16'h0060;
                    4'd9, 4'd10: O_row_bits = 16'h0180;
                    4'd11, 4'd12: O_row_bits = 16'h0600;
                    4'd13, 4'd14: O_row_bits = 16'h1ff8;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_3: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1fe0;
                    4'd3, 4'd4: O_row_bits = 16'h0018;
                    4'd5, 4'd6: O_row_bits = 16'h0018;
                    4'd7, 4'd8: O_row_bits = 16'h07e0;
                    4'd9, 4'd10: O_row_bits = 16'h0018;
                    4'd11, 4'd12: O_row_bits = 16'h0018;
                    4'd13, 4'd14: O_row_bits = 16'h1fe0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_4: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h0060;
                    4'd3, 4'd4: O_row_bits = 16'h01e0;
                    4'd5, 4'd6: O_row_bits = 16'h0660;
                    4'd7, 4'd8: O_row_bits = 16'h1860;
                    4'd9, 4'd10: O_row_bits = 16'h1ff8;
                    4'd11, 4'd12: O_row_bits = 16'h0060;
                    4'd13, 4'd14: O_row_bits = 16'h0060;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_5: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1ff8;
                    4'd3, 4'd4: O_row_bits = 16'h1800;
                    4'd5, 4'd6: O_row_bits = 16'h1800;
                    4'd7, 4'd8: O_row_bits = 16'h1fe0;
                    4'd9, 4'd10: O_row_bits = 16'h0018;
                    4'd11, 4'd12: O_row_bits = 16'h0018;
                    4'd13, 4'd14: O_row_bits = 16'h1fe0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_6: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07e0;
                    4'd3, 4'd4: O_row_bits = 16'h1800;
                    4'd5, 4'd6: O_row_bits = 16'h1800;
                    4'd7, 4'd8: O_row_bits = 16'h1fe0;
                    4'd9, 4'd10: O_row_bits = 16'h1818;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h07e0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_7: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h1ff8;
                    4'd3, 4'd4: O_row_bits = 16'h0018;
                    4'd5, 4'd6: O_row_bits = 16'h0060;
                    4'd7, 4'd8: O_row_bits = 16'h0180;
                    4'd9, 4'd10: O_row_bits = 16'h0600;
                    4'd11, 4'd12: O_row_bits = 16'h0600;
                    4'd13, 4'd14: O_row_bits = 16'h0600;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_8: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07e0;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h07e0;
                    4'd9, 4'd10: O_row_bits = 16'h1818;
                    4'd11, 4'd12: O_row_bits = 16'h1818;
                    4'd13, 4'd14: O_row_bits = 16'h07e0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_9: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h07e0;
                    4'd3, 4'd4: O_row_bits = 16'h1818;
                    4'd5, 4'd6: O_row_bits = 16'h1818;
                    4'd7, 4'd8: O_row_bits = 16'h07f8;
                    4'd9, 4'd10: O_row_bits = 16'h0018;
                    4'd11, 4'd12: O_row_bits = 16'h0018;
                    4'd13, 4'd14: O_row_bits = 16'h07e0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_COLON: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h0000;
                    4'd3, 4'd4: O_row_bits = 16'h0180;
                    4'd5, 4'd6: O_row_bits = 16'h0180;
                    4'd7, 4'd8: O_row_bits = 16'h0000;
                    4'd9, 4'd10: O_row_bits = 16'h0180;
                    4'd11, 4'd12: O_row_bits = 16'h0180;
                    4'd13, 4'd14: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_DASH: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h0000;
                    4'd3, 4'd4: O_row_bits = 16'h0000;
                    4'd5, 4'd6: O_row_bits = 16'h0000;
                    4'd7, 4'd8: O_row_bits = 16'h07e0;
                    4'd9, 4'd10: O_row_bits = 16'h07e0;
                    4'd11, 4'd12: O_row_bits = 16'h0000;
                    4'd13, 4'd14: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_SLASH: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h0018;
                    4'd3, 4'd4: O_row_bits = 16'h0060;
                    4'd5, 4'd6: O_row_bits = 16'h0060;
                    4'd7, 4'd8: O_row_bits = 16'h0180;
                    4'd9, 4'd10: O_row_bits = 16'h0600;
                    4'd11, 4'd12: O_row_bits = 16'h0600;
                    4'd13, 4'd14: O_row_bits = 16'h1800;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_EQUAL: begin
                case (I_row)
                    4'd1, 4'd2: O_row_bits = 16'h0000;
                    4'd3, 4'd4: O_row_bits = 16'h0000;
                    4'd5, 4'd6: O_row_bits = 16'h1ff8;
                    4'd7, 4'd8: O_row_bits = 16'h0000;
                    4'd9, 4'd10: O_row_bits = 16'h1ff8;
                    4'd11, 4'd12: O_row_bits = 16'h0000;
                    4'd13, 4'd14: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_AN: begin
                case (I_row)
                    4'd0: O_row_bits = 16'h0200;
                    4'd1: O_row_bits = 16'h7ff0;
                    4'd2: O_row_bits = 16'h4410;
                    4'd3: O_row_bits = 16'h0400;
                    4'd4: O_row_bits = 16'h7ff0;
                    4'd5: O_row_bits = 16'h0840;
                    4'd6: O_row_bits = 16'h1040;
                    4'd7: O_row_bits = 16'h1c80;
                    4'd8: O_row_bits = 16'h0300;
                    4'd9: O_row_bits = 16'h0cc0;
                    4'd10: O_row_bits = 16'h7020;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_LU: begin
                case (I_row)
                    4'd0: O_row_bits = 16'h79e0;
                    4'd1: O_row_bits = 16'h4a20;
                    4'd2: O_row_bits = 16'h4d40;
                    4'd3: O_row_bits = 16'h7880;
                    4'd4: O_row_bits = 16'h1140;
                    4'd5: O_row_bits = 16'h1630;
                    4'd6: O_row_bits = 16'h5be0;
                    4'd7: O_row_bits = 16'h5220;
                    4'd8: O_row_bits = 16'h5220;
                    4'd9: O_row_bits = 16'h5be0;
                    4'd10: O_row_bits = 16'h6220;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            default: O_row_bits = 16'h0000;
        endcase
    end
endmodule
