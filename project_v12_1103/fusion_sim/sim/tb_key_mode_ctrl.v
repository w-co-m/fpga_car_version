`timescale 1ns/1ps

module tb_key_mode_ctrl;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg key0_n = 1'b1;
    reg key1_n = 1'b1;
    reg frame_commit = 1'b0;
    wire [3:0] mode_pending;
    wire [3:0] mode_active;

    always #5 clk = ~clk;

    key_mode_ctrl #(
        .ALGO_COUNT(4),
        .CLK_HZ(1000),
        .DEBOUNCE_MS(20),
        .DEBOUNCE_CYCLES(3)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .key0_n(key0_n),
        .key1_n(key1_n),
        .threshold_edit(1'b0), .bin_threshold_active(), .edge_threshold_active(), .threshold_edit_active(), .frame_commit(frame_commit),
        .mode_pending(mode_pending),
        .mode_active(mode_active)
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

    task check_mode;
        input [3:0] expected_pending;
        input [3:0] expected_active;
        input [255:0] label_text;
        begin
            if (mode_pending !== expected_pending || mode_active !== expected_active) begin
                $display("FAIL %0s pending=%0d active=%0d expected=%0d/%0d at %0t",
                         label_text, mode_pending, mode_active,
                         expected_pending, expected_active, $time);
                $finish;
            end
        end
    endtask

    task release_keys;
        begin
            @(negedge clk);
            key0_n = 1'b1;
            key1_n = 1'b1;
            tick(10);
        end
    endtask

    initial begin
        tick(2);
        rst_n = 1'b1;
        tick(6);
        check_mode(0, 0, "reset initializes modes");

        // key1 advances, but active mode waits for a frame boundary.
        @(negedge clk); key1_n = 1'b0;
        tick(12);
        check_mode(1, 0, "key1 advances pending mode");
        @(negedge clk); frame_commit = 1'b1;
        tick(1);
        @(negedge clk); frame_commit = 1'b0;
        check_mode(1, 1, "frame commit copies pending mode");
        release_keys;

        // key0 goes back; previous wraps from zero to ALGO_COUNT-1.
        @(negedge clk); key0_n = 1'b0;
        tick(12);
        check_mode(0, 1, "key0 selects previous mode");
        release_keys;
        @(negedge clk); key0_n = 1'b0;
        tick(12);
        check_mode(3, 1, "previous wraps to last mode");
        release_keys;
        @(negedge clk); key1_n = 1'b0;
        tick(12);
        check_mode(0, 1, "next wraps to first mode");
        release_keys;

        // A short press that does not pass debounce must not count.
        @(negedge clk); key1_n = 1'b0;
        tick(1);
        @(negedge clk); key1_n = 1'b1;
        tick(12);
        check_mode(0, 1, "short bounce ignored");

        // Releasing just after debounce must not cancel an accepted press.
        @(negedge clk); key1_n = 1'b0;
        wait (dut.key1_released == 1'b0);
        @(negedge clk); key1_n = 1'b1;
        tick(12);
        check_mode(1, 1, "debounced press survives release during arbitration");
        release_keys;

        // Holding a key gives one event only. A stable release permits another.
        @(negedge clk); key1_n = 1'b0;
        tick(50);
        check_mode(2, 1, "long hold counts once");
        release_keys;
        @(negedge clk); key1_n = 1'b0;
        tick(12);
        check_mode(3, 1, "press after stable release counts again");
        release_keys;

        // Same-time and slightly staggered two-key presses are both ignored.
        @(negedge clk); key0_n = 1'b0; key1_n = 1'b0;
        tick(15);
        check_mode(3, 1, "simultaneous keys ignored");
        release_keys;
        @(negedge clk); key1_n = 1'b0;
        tick(2);
        @(negedge clk); key0_n = 1'b0;
        tick(15);
        check_mode(3, 1, "staggered overlapping keys ignored");
        release_keys;

        // Assert frame_commit through the key event: active must include that event.
        @(negedge clk); frame_commit = 1'b1; key1_n = 1'b0;
        tick(12);
        if (mode_pending !== 0 || mode_active !== 0) begin
            $display("FAIL same-cycle button and frame commit pending/active=%0d/%0d",
                     mode_pending, mode_active);
            $finish;
        end
        @(negedge clk); frame_commit = 1'b0;
        release_keys;

        // Reset cancels both a pending selection and the active mode.
        @(negedge clk); key1_n = 1'b0;
        tick(12);
        @(negedge clk); rst_n = 1'b0;
        tick(2);
        check_mode(0, 0, "reset clears pending and active");
        rst_n = 1'b1;
        key0_n = 1'b1;
        key1_n = 1'b1;
        tick(10);
        check_mode(0, 0, "reset release starts in first mode");

        $display("PASS tb_key_mode_ctrl");
        $finish;
    end
endmodule
