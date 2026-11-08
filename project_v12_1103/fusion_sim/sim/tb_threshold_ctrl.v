`timescale 1ns/1ps

module tb_threshold_ctrl;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg key0_n = 1'b1;
    reg key1_n = 1'b1;
    reg frame_commit = 1'b0;
    reg threshold_edit = 1'b0;
    wire [3:0] mode_pending;
    wire [3:0] mode_active;
    wire threshold_edit_active;
    wire [7:0] bin_threshold_active;
    wire [7:0] edge_threshold_active;

    always #5 clk = ~clk;

    key_mode_ctrl #(
        .ALGO_COUNT(4),
        .CLK_HZ(1000),
        .DEBOUNCE_MS(20),
        .DEBOUNCE_CYCLES(3),
        .ENABLE_THRESHOLD_CONTROL(1),
        .BIN_THRESHOLD(128),
        .EDGE_THRESHOLD(32)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .key0_n(key0_n),
        .key1_n(key1_n),
        .frame_commit(frame_commit),
        .mode_pending(mode_pending),
        .mode_active(mode_active),
        .threshold_edit(threshold_edit),
        .threshold_edit_active(threshold_edit_active),
        .bin_threshold_active(bin_threshold_active),
        .edge_threshold_active(edge_threshold_active)
    );

    task tick;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    task check_state;
        input [3:0] expected_pending;
        input [3:0] expected_mode;
        input [7:0] expected_bin;
        input [7:0] expected_edge;
        input expected_selector;
        input [255:0] label_text;
        begin
            if (mode_pending !== expected_pending || mode_active !== expected_mode ||
                bin_threshold_active !== expected_bin || edge_threshold_active !== expected_edge ||
                threshold_edit_active !== expected_selector) begin
                $display("FAIL %0s mode=%0d/%0d thresholds=%0d/%0d selector=%b expected=%0d/%0d %0d/%0d %b at %0t",
                         label_text, mode_pending, mode_active, bin_threshold_active,
                         edge_threshold_active, threshold_edit_active, expected_pending,
                         expected_mode, expected_bin, expected_edge, expected_selector, $time);
                $display("DEBUG armed=%b arb=%b suppressed=%b count=%0d keys=%b%b lock=%b/%b/%0d selector_sync=%b confirmed=%b",
                         dut.armed, dut.arbitration_active, dut.arbitration_suppressed,
                         dut.arbitration_count, dut.key0_released, dut.key1_released,
                         dut.arbitration_selector_sample, dut.arbitration_selector_confirmed,
                         dut.arbitration_mode, dut.selector_sync[1], dut.selector_confirmed);
                $fatal(1);
            end
        end
    endtask

    task commit_frame;
        begin
            @(negedge clk); frame_commit = 1'b1;
            tick(1);
            @(negedge clk); frame_commit = 1'b0;
        end
    endtask

    task release_keys;
        begin
            @(negedge clk); key0_n = 1'b1; key1_n = 1'b1;
            tick(10);
        end
    endtask

    task press_next;
        begin
            @(negedge clk); key1_n = 1'b0;
            tick(12);
            release_keys;
        end
    endtask

    task press_previous;
        begin
            @(negedge clk); key0_n = 1'b0;
            tick(12);
            release_keys;
        end
    endtask

    task set_selector;
        input value;
        begin
            @(negedge clk); threshold_edit = value;
            tick(8);
        end
    endtask

    integer i;
    initial begin
        tick(2); rst_n = 1'b1; tick(8);
        check_state(0, 0, 128, 32, 0, "reset defaults");

        // 选档0/1时阈值事件无效果，模式事件仍按旧规则循环。
        set_selector(1); press_next;
        check_state(0, 0, 128, 32, 1, "non-algorithm threshold ignored");
        set_selector(0); press_next;
        check_state(1, 0, 128, 32, 0, "legacy next updates pending only");
        commit_frame;
        check_state(1, 1, 128, 32, 0, "mode waits for frame commit");
        press_next; commit_frame;
        check_state(2, 2, 128, 32, 0, "select binary mode");

        // 二值阈值只在提交帧后可见，且阈值事件不改模式。
        set_selector(1); press_next;
        check_state(2, 2, 128, 32, 1, "binary threshold pending isolation");
        commit_frame;
        check_state(2, 2, 129, 32, 1, "binary threshold committed");
        press_next; commit_frame;
        check_state(2, 2, 130, 32, 1, "second binary press counts after release");
        press_next; commit_frame;
        check_state(2, 2, 131, 32, 1, "third binary press counts after release");

        // 切到模式3，边缘阈值独立保存；退回模式2仍保留二值阈值。
        set_selector(0); press_next; commit_frame;
        check_state(3, 3, 131, 32, 0, "select edge mode");
        set_selector(1); press_previous; commit_frame;
        check_state(3, 3, 131, 31, 1, "edge threshold independent");
        set_selector(0); press_previous; commit_frame;
        check_state(2, 2, 131, 31, 0, "return to binary keeps edge value");

        // 越界饱和到0/255，不回绕。
        set_selector(1);
        @(negedge clk); key1_n = 1'b0;
        tick(50);
        check_state(2, 2, 131, 31, 1, "threshold long hold stays pending");
        release_keys; commit_frame;
        check_state(2, 2, 132, 31, 1, "threshold long hold counts once");
        for (i = 0; i < 130; i = i + 1) begin press_next; commit_frame; end
        check_state(2, 2, 255, 31, 1, "binary upper saturation");
        for (i = 0; i < 260; i = i + 1) begin press_previous; commit_frame; end
        check_state(2, 2, 0, 31, 1, "binary lower saturation");
        set_selector(0); press_next; commit_frame; // mode 3
        set_selector(1);
        for (i = 0; i < 40; i = i + 1) begin press_previous; commit_frame; end
        check_state(3, 3, 0, 0, 1, "edge lower saturation");
        for (i = 0; i < 300; i = i + 1) begin press_next; commit_frame; end
        check_state(3, 3, 0, 255, 1, "edge upper saturation");

        // SW1 抖动短于消抖窗不会切换选择。
        @(negedge clk); threshold_edit = 1'b0; tick(1);
        @(negedge clk); threshold_edit = 1'b1; tick(8);
        check_state(3, 3, 0, 255, 1, "selector bounce ignored");

        // 仲裁期间拨动 SW1 会取消该按键，按住开关和按键也不能重放动作。
        @(negedge clk); key1_n = 1'b0; tick(4);
        @(negedge clk); threshold_edit = 1'b0; tick(12);
        check_state(3, 3, 0, 255, 0, "selector change suppresses in-flight event");
        release_keys;
        check_state(3, 3, 0, 255, 0, "held key and selector do not replay");

        // 双键相撞保持抑制，单键长按只触发一次。
        @(negedge clk); key0_n = 1'b0; key1_n = 1'b0; tick(20);
        check_state(3, 3, 0, 255, 0, "two-key overlap suppressed");
        release_keys;
        @(negedge clk); key1_n = 1'b0; tick(50);
        check_state(0, 3, 0, 255, 0, "long hold counts once");
        release_keys;

        // 模式切换事件和帧提交同拍时，active 模式包含本拍事件。
        @(negedge clk); frame_commit = 1'b1; key1_n = 1'b0;
        tick(12);
        check_state(1, 1, 0, 255, 0, "legacy same-cycle event and commit");
        @(negedge clk); frame_commit = 1'b0;
        release_keys;

        // 阈值事件和帧提交同拍时，新阈值本拍生效。
        set_selector(1);
        @(negedge clk); frame_commit = 1'b1; key1_n = 1'b0;
        tick(12);
        check_state(1, 1, 0, 255, 1, "non-threshold mode unaffected");
        @(negedge clk); frame_commit = 1'b0;
        release_keys;
        set_selector(0); press_next; commit_frame; // mode2
        set_selector(1);
        @(negedge clk); frame_commit = 1'b1; key1_n = 1'b0;
        tick(12);
        check_state(2, 2, 1, 255, 1, "threshold event and commit same cycle");
        @(negedge clk); frame_commit = 1'b0;
        release_keys;

        // 前一次pending模式在第二次按键仲裁中提交，不应吞掉后一次正常模式事件。
        @(negedge clk); rst_n=0; threshold_edit=0;
        tick(3); @(negedge clk); rst_n=1; tick(10);
        press_next;
        check_state(1,0,128,32,0,"queued first mode event");
        @(negedge clk); key1_n=0;
        while(!dut.arbitration_active) tick(1);
        commit_frame; tick(10); release_keys;
        check_state(2,1,128,32,0,"mode commit during arbitration keeps next event");
        commit_frame;
        check_state(2,2,128,32,0,"queued second mode commits");
        // 旧接口省略新增端口/参数时由默认关闭保证模式语义；单独旧 TB 验证。
        $display("PASS tb_threshold_ctrl");
        $finish;
    end
    initial begin #1000000; $fatal(1,"threshold controller timeout"); end
endmodule
