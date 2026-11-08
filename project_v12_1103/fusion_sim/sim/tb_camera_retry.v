`timescale 1ns / 1ps

// 摄像头配置重试专项回归。uii2c stub 保留真实控制器的错误握手：
// NACK 后 bus_error 拉高并保持到 req 已撤销后的后续时钟，busy 最后才清零。
module tb_camera_retry;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg ae_req = 1'b0;
    reg [15:0] ae = 16'h1234;
    reg [15:0] ag = 16'd32;
    wire scl;
    tri1 sda;
    wire cfg_done, ae_done, id_ok, iic_error;
    wire [15:0] sensor_id;

    // 第一次 ID 高字节读和第一条初始化写各模拟一次 NACK。
    // 随后的 AE 最后一条写可选择模拟三次连续 NACK。
    reg fail_ae_last = 1'b0;
    reg fail_init_last = 1'b0;
    integer timeout;
    integer errors_cleared_while_busy = 0;

    // 错误标志比 busy 早一个以上时钟清除时，控制器仍须锁住本次失败。
    always @(negedge dut.iic_bus_error) begin
        if (rst_n && dut.iic_busy)
            errors_cleared_while_busy = errors_cleared_while_busy + 1;
    end

    uicfgcs520 #(.CLK_DIV(1)) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_ae_req(ae_req),
        .I_ae(ae), .I_ag(ag), .O_cam_scl(scl), .IO_cam_sda(sda),
        .O_cfg_done(cfg_done), .O_ae_cfg_done(ae_done),
        .O_sensor_id(sensor_id), .O_sensor_id_ok(id_ok),
        .O_iic_error(iic_error)
    );

    // 参数边界使用独立控制器，持续ID读NACK，不能影响正常配置用例。
    reg limit0_rst = 1'b0, limit256_rst = 1'b0;
    wire limit0_cfg, limit0_ae, limit0_idok, limit0_error;
    wire limit256_cfg, limit256_ae, limit256_idok, limit256_error;
    wire [15:0] limit0_id, limit256_id;
    wire limit0_scl, limit256_scl;
    tri1 limit0_sda, limit256_sda;
    uicfgcs520 #(.CLK_DIV(1), .IIC_RETRY_MAX(0)) dut_limit0 (
        .I_clk(clk), .I_rst_n(limit0_rst), .I_ae_req(1'b0), .I_ae(16'd0), .I_ag(16'd0),
        .O_cam_scl(limit0_scl), .IO_cam_sda(limit0_sda), .O_cfg_done(limit0_cfg),
        .O_ae_cfg_done(limit0_ae), .O_sensor_id(limit0_id), .O_sensor_id_ok(limit0_idok), .O_iic_error(limit0_error));
    uicfgcs520 #(.CLK_DIV(1), .IIC_RETRY_MAX(256)) dut_limit256 (
        .I_clk(clk), .I_rst_n(limit256_rst), .I_ae_req(1'b0), .I_ae(16'd0), .I_ag(16'd0),
        .O_cam_scl(limit256_scl), .IO_cam_sda(limit256_sda), .O_cfg_done(limit256_cfg),
        .O_ae_cfg_done(limit256_ae), .O_sensor_id(limit256_id), .O_sensor_id_ok(limit256_idok), .O_iic_error(limit256_error));

    task reset_case;
        begin
            rst_n = 1'b0;
            ae_req = 1'b0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task wait_cfg_done;
        begin
            timeout = 0;
            while (!cfg_done && timeout < 500000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!cfg_done) $fatal(1, "timeout waiting init cfg_done: state=%0d id=%h id_ok=%b busy=%b bus_error=%b index=%0d reads=%0d/%0d init0=%0d req=%b active=%b phase=%0d errphase=%0d fail=%b",
                dut.state, sensor_id, id_ok, dut.iic_busy, dut.iic_bus_error,
                dut.reg_index,
                dut.u_i2c.read_high_count, dut.u_i2c.read_low_count, dut.u_i2c.init0_count,
                dut.iic_req, dut.u_i2c.active, dut.u_i2c.phase,
                dut.u_i2c.error_clear_phase, dut.u_i2c.fail_this);
        end
    endtask

    initial begin
        // 回归1：ID读与首条初始化写在一次NACK后必须重发并成功。
        reset_case();
        wait_cfg_done();
        if (!id_ok || sensor_id !== 16'hee4b)
            $fatal(1, "sensor ID did not complete successfully: %h", sensor_id);
        if (dut.u_i2c.read_high_count != 2 || dut.u_i2c.read_low_count != 2)
            $fatal(1, "ID retry count mismatch: high=%0d low=%0d", dut.u_i2c.read_high_count, dut.u_i2c.read_low_count);
        if (dut.u_i2c.init0_count != 2)
            $fatal(1, "init register 0 retry count=%0d, expected 2", dut.u_i2c.init0_count);
        if (!iic_error)
            $fatal(1, "O_iic_error must retain NACK history after recovery");

        // 回归2：AE最后一条寄存器连续NACK三次后停止，不能报告AE完成。
        fail_ae_last = 1'b1;
        ae_req = 1'b1;
        @(posedge clk);
        ae_req = 1'b0;
        timeout = 0;
        while ((dut.u_i2c.ae_last_count < 3) && timeout < 30000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (dut.u_i2c.ae_last_count != 3)
            $fatal(1, "AE final register did not exhaust three attempts: %0d", dut.u_i2c.ae_last_count);
        repeat (10) @(posedge clk);
        if (ae_done)
            $fatal(1, "AE completion asserted after final register NACK exhaustion");
        if (dut.u_i2c.ae_last_count != 3)
            $fatal(1, "controller did not stop after retry exhaustion");
        if (errors_cleared_while_busy < 3)
            $fatal(1, "stub did not exercise error-clear-before-busy timing: %0d", errors_cleared_while_busy);
        if (!iic_error)
            $fatal(1, "O_iic_error lost prior NACK history");

        // 回归3：初始化表最后一项(0100=01)耗尽重试后不能置 cfg_done。
        fail_ae_last = 1'b0;
        fail_init_last = 1'b1;
        reset_case();
        timeout = 0;
        while ((dut.u_i2c.init_last_count < 3) && timeout < 500000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (dut.u_i2c.init_last_count != 3)
            $fatal(1, "init final register did not exhaust three attempts: %0d", dut.u_i2c.init_last_count);
        repeat (24) @(posedge clk);
        if (cfg_done)
            $fatal(1, "cfg_done asserted after init final register NACK exhaustion");
        if (dut.u_i2c.init_last_count != 3)
            $fatal(1, "controller continued after init retry exhaustion");

        // MAX=0 一次失败即停止；MAX=256 必须在257次尝试后停止，不能8位回绕。
        @(negedge clk);
        dut_limit0.u_i2c.fail_id_always = 1'b1;
        dut_limit256.u_i2c.fail_id_always = 1'b1;
        limit0_rst = 1'b1; limit256_rst = 1'b1;
        timeout = 0;
        while (dut_limit256.state != 4'd11 && timeout < 6000) begin
            @(negedge clk); timeout = timeout + 1;
        end
        repeat (32) @(negedge clk);
        if (dut_limit0.state != 4'd11 || dut_limit0.u_i2c.read_high_count != 1 || limit0_cfg || !limit0_error)
            $fatal(1, "MAX=0 must stop after one NACK");
        if (dut_limit256.state != 4'd11 || dut_limit256.u_i2c.read_high_count != 257 || limit256_cfg || !limit256_error)
            $fatal(1, "MAX=256 must stop after257 attempts, count=%0d state=%0d", dut_limit256.u_i2c.read_high_count, dut_limit256.state);

        $display("PASS tb_camera_retry: ID retries, init retry/exhaustion, AE final exhaustion, sticky error, limits0/256");
        $finish;
    end
endmodule

// 仅用于本专项TB的同名替身；其 bus_error/busy 清除顺序仿照 uii2c.v。
module uii2c #(
    parameter WMEN_LEN = 4,
    parameter RMEN_LEN = 1,
    parameter CLK_DIV = 239
) (
    input wire I_clk,
    input wire I_rstn,
    output wire O_iic_scl,
    inout wire IO_iic_sda,
    input wire [WMEN_LEN*8-1:0] I_wr_data,
    input wire [7:0] I_wr_cnt,
    output reg [RMEN_LEN*8-1:0] O_rd_data,
    input wire [7:0] I_rd_cnt,
    input wire I_iic_req,
    input wire I_iic_mode,
    output reg O_iic_busy,
    output reg O_iic_bus_error,
    output wire IO_iic_sda_dg
);
    reg active;
    reg [3:0] phase;
    reg [2:0] error_clear_phase;
    reg fail_this;
    reg fail_id_always = 1'b0;
    reg [31:0] request_data;
    reg [7:0] request_wr_cnt;
    reg [7:0] request_rd_cnt;
    reg request_mode;
    integer read_high_count;
    integer read_low_count;
    integer init0_count;
    integer init_last_count;
    integer ae_last_count;
    wire [15:0] request_reg = {request_data[23:16], request_data[15:8]};
    wire [7:0] request_value = request_data[31:24];
    assign O_iic_scl = I_clk;
    assign IO_iic_sda = 1'bz;
    assign IO_iic_sda_dg = 1'b1;

    always @(posedge I_clk or negedge I_rstn) begin
        if (!I_rstn) begin
            active <= 1'b0;
            phase <= 0;
            error_clear_phase <= 0;
            O_iic_busy <= 1'b0;
            O_iic_bus_error <= 1'b0;
            O_rd_data <= 0;
            read_high_count <= 0;
            read_low_count <= 0;
            init0_count <= 0;
            init_last_count <= 0;
            ae_last_count <= 0;
            fail_this <= 1'b0;
            request_data <= 0;
            request_wr_cnt <= 0;
            request_rd_cnt <= 0;
            request_mode <= 0;
        end else begin
            if (!active && !O_iic_busy && I_iic_req) begin
                active <= 1'b1;
                phase <= 0;
                O_iic_busy <= 1'b1;
                request_data <= I_wr_data;
                request_wr_cnt <= I_wr_cnt;
                request_rd_cnt <= I_rd_cnt;
                request_mode <= I_iic_mode;
                fail_this <= 1'b0;
                if (I_iic_mode && I_wr_data[23:8] == 16'h0731) begin
                    read_high_count <= read_high_count + 1;
                    fail_this <= fail_id_always || (read_high_count == 0);
                end else if (I_iic_mode && I_wr_data[23:8] == 16'h0831) begin
                    read_low_count <= read_low_count + 1;
                    fail_this <= (read_low_count == 0);
                end else if (!I_iic_mode && I_wr_data[23:16] == 8'h03 && I_wr_data[15:8] == 8'h01) begin
                    init0_count <= init0_count + 1;
                    fail_this <= (init0_count == 0);
                end else if (!I_iic_mode && I_wr_data[23:16] == 8'h00 && I_wr_data[15:8] == 8'h01 && I_wr_data[31:24] == 8'h01) begin
                    init_last_count <= init_last_count + 1;
                    fail_this <= tb_camera_retry.fail_init_last;
                end else if (!I_iic_mode && I_wr_data[23:16] == 8'h12 && I_wr_data[15:8] == 8'h38 && I_wr_data[31:24] == 8'h30) begin
                    ae_last_count <= ae_last_count + 1;
                    fail_this <= tb_camera_retry.fail_ae_last;
                end
            end else if (active) begin
                if (phase == 4) begin
                    active <= 1'b0;
                    if (request_mode && request_rd_cnt != 0) begin
                        if (fail_this)
                            O_rd_data <= 8'h00;
                        else if (request_data[23:8] == 16'h0731)
                            O_rd_data <= 8'hee;
                        else
                            O_rd_data <= 8'h4b;
                    end
                    if (fail_this) begin
                        O_iic_bus_error <= 1'b1;
                        error_clear_phase <= 0;
                    end else begin
                        O_iic_busy <= 1'b0;
                    end
                end else begin
                    phase <= phase + 1'b1;
                end
            end else if (!active && O_iic_busy && !I_iic_req && error_clear_phase == 3) begin
                O_iic_busy <= 1'b0;
                error_clear_phase <= 4;
            end else if (O_iic_bus_error && !I_iic_req) begin
                // 真实uii2c在req撤销后的负沿清error，随后busy才清零。
                if (error_clear_phase == 2) begin
                    O_iic_bus_error <= 1'b0;
                    error_clear_phase <= 3;
                end else begin
                    error_clear_phase <= error_clear_phase + 1'b1;
                end
            end
        end
    end
endmodule
