`timescale 1ns/1ps

module tb_camera_init #(parameter integer AUTO_PROFILE=0);
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ae_req = 1'b0;
    reg [15:0] ae = 16'h1234;
    reg [15:0] ag = 16'd16;
    wire cam_scl;
    tri1 cam_sda;
    wire cfg_done;
    wire ae_cfg_done;
    wire iic_error;

    reg [23:0] expected [0:115];
    integer seen = 0;
    integer ae_seen = 0;
    integer delay_cycles = 0;
    integer delay_started = 0;
    reg previous_req = 1'b0;
    reg nack_test = 1'b0;
    wire [15:0] cfg_ae, cfg_ag;
    wire cfg_ae_req;
    generate if (AUTO_PROFILE) begin : actual_ae_defaults
        ae_set u_ae_set(.I_clk(clk),.I_rst(~rst_n),.I_btn(4'b1111),
            .I_ae_cfg_done(ae_cfg_done),.I_cam_cfg_done(cfg_done),
            .O_ae_req(cfg_ae_req),.O_ae(cfg_ae),.O_ag(cfg_ag));
    end else begin : manual_test_ae
        assign cfg_ae=ae;
        assign cfg_ag=ag;
        assign cfg_ae_req=ae_req;
    end endgenerate


    always #5 clk = ~clk;
    initial begin
        #12000000;
        $fatal(1,"camera init/profile timeout");
    end

`ifdef CAMERA_RED
    uicfgcs520 #(.CLK_DIV(8), .IIC_RETRY_MAX(0)) dut (
`else
    uicfgcs500_720p #(.CLK_DIV(8)) dut (
`endif
        .I_clk(clk), .I_rst_n(rst_n), .I_ae_req(cfg_ae_req),
        .I_ae(cfg_ae), .I_ag(cfg_ag), .O_cam_scl(cam_scl), .IO_cam_sda(cam_sda),
        .O_cfg_done(cfg_done), .O_ae_cfg_done(ae_cfg_done),
        .O_iic_error(iic_error)
`ifdef CAMERA_RED
        , .O_sensor_id(), .O_sensor_id_ok()
`endif
    );

    integer i;
    initial begin
        // Fixture 是从参考工程固定提取的常量，独立于被测 ROM。
                expected[0] = 24'h010301;
        expected[1] = 24'h010000;
        expected[2] = 24'h36e980;
        expected[3] = 24'h36f980;
        expected[4] = 24'h36ea3c;
        expected[5] = 24'h36ec1b;
        expected[6] = 24'h36fd14;
        expected[7] = 24'h36e904;
        expected[8] = 24'h36f904;
        expected[9] = 24'h301610;
        expected[10] = 24'h30170e;
        expected[11] = 24'h301f04;
        expected[12] = 24'h302d20;
        expected[13] = 24'h310601;
        expected[14] = 24'h320000;
        expected[15] = 24'h320114;
        expected[16] = 24'h320201;
        expected[17] = 24'h320300;
        expected[18] = 24'h32040a;
        expected[19] = 24'h32051b;
        expected[20] = 24'h320606;
        expected[21] = 24'h3207a7;
        expected[22] = 24'h320805;
        expected[23] = 24'h320900;
        expected[24] = 24'h320a02;
        expected[25] = 24'h320bd0;
        expected[26] = 24'h320c06;
        expected[27] = 24'h320d40;
        expected[28] = 24'h320e03;
        expected[29] = 24'h320fe8;
        expected[30] = 24'h321000;
        expected[31] = 24'h321102;
        expected[32] = 24'h321200;
        expected[33] = 24'h321302;
        expected[34] = 24'h321531;
        expected[35] = 24'h322001;
        expected[36] = 24'h32490f;
        expected[37] = 24'h325306;
        expected[38] = 24'h327113;
        expected[39] = 24'h327313;
        expected[40] = 24'h33010a;
        expected[41] = 24'h330960;
        expected[42] = 24'h330a00;
        expected[43] = 24'h330be8;
        expected[44] = 24'h331e41;
        expected[45] = 24'h331f51;
        expected[46] = 24'h332004;
        expected[47] = 24'h333310;
        expected[48] = 24'h335d60;
        expected[49] = 24'h336456;
        expected[50] = 24'h336b08;
        expected[51] = 24'h339008;
        expected[52] = 24'h339118;
        expected[53] = 24'h339238;
        expected[54] = 24'h33930a;
        expected[55] = 24'h339424;
        expected[56] = 24'h339540;
        expected[57] = 24'h33ad29;
        expected[58] = 24'h341c04;
        expected[59] = 24'h341d04;
        expected[60] = 24'h341e03;
        expected[61] = 24'h342500;
        expected[62] = 24'h342600;
        expected[63] = 24'h3622c7;
        expected[64] = 24'h363244;
        expected[65] = 24'h36366e;
        expected[66] = 24'h363708;
        expected[67] = 24'h36380a;
        expected[68] = 24'h36519d;
        expected[69] = 24'h36704b;
        expected[70] = 24'h3674c0;
        expected[71] = 24'h367558;
        expected[72] = 24'h36765a;
        expected[73] = 24'h367c18;
        expected[74] = 24'h367d38;
        expected[75] = 24'h369043;
        expected[76] = 24'h369153;
        expected[77] = 24'h369253;
        expected[78] = 24'h369908;
        expected[79] = 24'h369a10;
        expected[80] = 24'h369b1f;
        expected[81] = 24'h369c18;
        expected[82] = 24'h369d38;
        expected[83] = 24'h36a208;
        expected[84] = 24'h36a318;
        expected[85] = 24'h36a608;
        expected[86] = 24'h36a718;
        expected[87] = 24'h36ab40;
        expected[88] = 24'h36ac40;
        expected[89] = 24'h36ad40;
        expected[90] = 24'h390100;
        expected[91] = 24'h39040c;
        expected[92] = 24'h39063a;
        expected[93] = 24'h391d14;
        expected[94] = 24'h3e0000;
        expected[95] = 24'h3e017c;
        expected[96] = 24'h3e0260;
        expected[97] = 24'h400000;
        expected[98] = 24'h400104;
        expected[99] = 24'h4002aa;
        expected[100] = 24'h4003aa;
        expected[101] = 24'h4004aa;
        expected[102] = 24'h400500;
        expected[103] = 24'h400607;
        expected[104] = 24'h4007a5;
        expected[105] = 24'h400800;
        expected[106] = 24'h4009c8;
        expected[107] = 24'h440e02;
        expected[108] = 24'h450928;
        expected[109] = 24'h483742;
        expected[110] = 24'h50004e;
        expected[111] = 24'h590104;
        expected[112] = 24'h3e080f;
        expected[113] = 24'h3e0920;
        expected[114] = 24'h010001;
        expected[115] = 24'h302d00;
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
`ifdef CAMERA_RED
        repeat (200000) @(posedge clk);
        if (seen == 0) begin
            $display("RED observed: strict ID read prevented the first init write");
            $fatal(1, "EXPECTED RED: first reference init write 010301 was never issued");
        end
        $fatal(1, "RED unexpectedly reached an init write");
`else
        wait (cfg_done);
        if (seen != 116) $fatal(1, "expected 116 init writes, saw %0d", seen);
        if ($test$plusargs("NACK_ONCE")) begin
            nack_test = 1'b1;
            if (iic_error !== 1'b1) $fatal(1, "ACK error was not latched");
        end else if (iic_error !== 1'b0) $fatal(1, "unexpected I2C error during ACKed init");
        if (delay_cycles < 240000 || delay_cycles > 240004)
            $fatal(1, "stream-on delay was %0d cycles", delay_cycles);
        if (!ae_cfg_done) $fatal(1, "initial AE table completion missing");
        if (AUTO_PROFILE) begin
            if (cfg_ae !== 16'd1990 || cfg_ag !== 16'd80 || dut.gain_value !== 16'h0f20)
                $fatal(1,"reference AE profile defaults mismatch ae=%0d ag=%0d",cfg_ae,cfg_ag);
            repeat (1000) @(posedge clk);
            if (cfg_ae !== 16'd1990 || cfg_ag !== 16'd80 || cfg_ae_req || ae_seen!=0)
                $fatal(1,"reference AE profile changed after stream-on ae=%0d ag=%0d extra=%0d",cfg_ae,cfg_ag,ae_seen);
            // 实际ae_set与配置核一起复位，仍恢复参考默认且完整重写116项。
            seen=0; delay_cycles=0; delay_started=0;
            rst_n <= 1'b0;
            repeat (4) @(posedge clk);
            rst_n <= 1'b1;
            wait(cfg_done);
            repeat (1000) @(posedge clk);
            if(seen!=116 || cfg_ae!==16'd1990 || cfg_ag!==16'd80 || dut.gain_value!==16'h0f20 || cfg_ae_req || ae_seen!=0)
                $fatal(1,"reference AE profile reset/reinit failed");
            $display("PASS reference AE profile: 116 init writes, ae=1990 ag=80, gain=0f20, no post-init overwrite, reset/reinit");
            $finish;
        end


        // 非默认增益48：查表索引32对应0x0720，逐字节检查实际AE写值。
        ag <= 16'd48;
        ae_req <= 1'b1;
        @(posedge clk);
        ae_req <= 1'b0;
        wait (!ae_cfg_done);
        wait (ae_cfg_done);
        if (ae_seen != 5) $fatal(1, "expected 5 AE writes, saw %0d", ae_seen);
        if (iic_error !== (nack_test ? 1'b1 : 1'b0))
            $fatal(1, "I2C error latch changed during AE update");

        // 复位后必须从第 0 项重新发完整初始化表。
        seen = 0;
        delay_cycles = 0;
        delay_started = 0;
        rst_n <= 1'b0;
        repeat (4) @(posedge clk);
        if (iic_error !== 1'b0) $fatal(1, "I2C error did not clear on reset");
        rst_n <= 1'b1;
        wait (cfg_done);
        if (seen != 116) $fatal(1, "reinit expected 116 writes, saw %0d", seen);
        if (nack_test) $display("PASS: 116 writes continued after ACK error; sticky error reset and reinit");
        else $display("PASS: 116 writes, first/last order, 240000-cycle delay, AE update, reset/reinit");
        $finish;
`endif
    end

    always @(posedge clk) begin
        previous_req <= dut.iic_req;
        if (!rst_n) begin
            previous_req <= 1'b0;
        end else if (dut.iic_req && !previous_req) begin
`ifdef CAMERA_RED
            if (dut.wr_cnt == 8'd4) begin
`else
            begin
`endif
                if (seen < 116) begin
                    if (dut.wr_data[7:0] !== 8'h6c)
                        $fatal(1, "write %0d used CAM_ID %02x", seen, dut.wr_data[7:0]);
                    if ({dut.wr_data[15:8], dut.wr_data[23:16], dut.wr_data[31:24]} !== expected[seen])
                        $fatal(1, "write %0d got %06x expected %06x", seen,
                               {dut.wr_data[15:8], dut.wr_data[23:16], dut.wr_data[31:24]}, expected[seen]);
                    if (seen == 0 && expected[seen] !== 24'h010301)
                        $fatal(1, "bad independent fixture first write");
                    if (seen == 114 && expected[seen] !== 24'h010001)
                        $fatal(1, "bad independent fixture stream-on entry");
                    if (seen == 115 && expected[seen] !== 24'h302d00)
                        $fatal(1, "bad independent fixture last write");
                    if (seen == 115 && delay_cycles < 240000)
                        $fatal(1, "302d00 arrived before the 10 ms delay");
                    seen = seen + 1;
                end else if (AUTO_PROFILE) begin
                    $fatal(1,"reference AE profile issued unexpected post-init overwrite");
                end else if (ae_seen < 5) begin
                    case (ae_seen)
                        0: if ({dut.wr_data[15:8], dut.wr_data[23:16], dut.wr_data[31:24]} !== {16'h3e00, 4'h0, ae[15:12]}) $fatal(1, "AE high exposure got %06x expected %06x", {dut.wr_data[15:8], dut.wr_data[23:16], dut.wr_data[31:24]}, {16'h3e00, 4'h0, ae[15:12]});
                        1: if ({dut.wr_data[15:8], dut.wr_data[23:16], dut.wr_data[31:24]} !== {16'h3e01, ae[11:4]}) $fatal(1, "AE middle exposure mismatch");
                        2: if ({dut.wr_data[15:8], dut.wr_data[23:16], dut.wr_data[31:24]} !== {16'h3e02, ae[3:0], 4'h0}) $fatal(1, "AE low exposure mismatch");
                        3: if ({dut.wr_data[15:8], dut.wr_data[23:16], dut.wr_data[31:24]} !== 24'h3e0807) $fatal(1, "AE non-default gain high byte mismatch");
                        4: if ({dut.wr_data[15:8], dut.wr_data[23:16], dut.wr_data[31:24]} !== 24'h3e0920) $fatal(1, "AE non-default gain low byte mismatch");
                    endcase
                    ae_seen = ae_seen + 1;
                end
            end
        end
        if (rst_n && !cfg_done && (dut.reg_index == 9'd115) &&
            (dut.state == 2'd0)) begin
            delay_started = 1;
            delay_cycles = delay_cycles + 1;
        end
    end
endmodule

// 事务级 I2C stub：每个请求忙 3 个时钟；可用 NACK_ONCE 注入一次 ACK 错误。
module uii2c #(
    parameter integer WMEN_LEN = 4,
    parameter integer RMEN_LEN = 1,
    parameter integer CLK_DIV = 239
) (
    input wire I_clk,
    input wire I_rstn,
    output reg O_iic_scl,
    inout wire IO_iic_sda,
    input wire [WMEN_LEN*8-1:0] I_wr_data,
    input wire [7:0] I_wr_cnt,
    output reg [RMEN_LEN*8-1:0] O_rd_data,
    input wire [7:0] I_rd_cnt,
    input wire I_iic_mode,
    input wire I_iic_req,
    output reg O_iic_busy,
    output reg O_iic_bus_error,
    output wire IO_iic_sda_dg
);
    integer wait_count;
    reg inject_error;
    assign IO_iic_sda_dg = 1'b1;
    assign IO_iic_sda = 1'bz;
    initial inject_error = $test$plusargs("NACK_ONCE");
    always @(posedge I_clk or negedge I_rstn) begin
        if (!I_rstn) begin
            O_iic_scl <= 1'b1;
            O_rd_data <= {RMEN_LEN*8{1'b1}};
            O_iic_busy <= 1'b0;
            O_iic_bus_error <= 1'b0;
            wait_count <= 0;
        end else if (!O_iic_busy && I_iic_req) begin
            O_iic_busy <= 1'b1;
            wait_count <= 3;
            if (inject_error) begin
                O_iic_bus_error <= 1'b1;
                inject_error <= 1'b0;
            end
        end else if (O_iic_busy) begin
            if (wait_count == 0) begin
                O_iic_busy <= 1'b0;
                O_iic_bus_error <= 1'b0;
            end else wait_count <= wait_count - 1;
        end else if (!I_iic_req) begin
            O_iic_bus_error <= 1'b0;
        end
    end
endmodule



module tb_camera_profile;
    tb_camera_init #(.AUTO_PROFILE(1)) test();
endmodule
