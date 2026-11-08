`timescale 1ns/1ps
module tb_key_terminal_overlap;
    reg clk=0, rst_n=0, key0_n=1, key1_n=1, edit=0, frame_commit=0;
    wire [3:0] mode_pending, mode_active;
    wire [7:0] bin_threshold, edge_threshold;
    wire edit_active, capture_pulse, restart_pulse;
    integer captures=0, restarts=0, boundary_hits=0;
    reg [7:0] saved_threshold;

    always #5 clk=~clk;
    always @(posedge clk) begin
        if (capture_pulse) captures=captures+1;
        if (restart_pulse) restarts=restarts+1;
        if (dut.arbitration_active && dut.arbitration_count==1 &&
            ((dut.key0_released && !dut.key0_sync[1] && dut.key0_count==2) ||
             (dut.key1_released && !dut.key1_sync[1] && dut.key1_count==2)))
            boundary_hits=boundary_hits+1;
    end

    key_mode_ctrl #(.ALGO_COUNT(13), .DEBOUNCE_CYCLES(3),
                    .ENABLE_THRESHOLD_CONTROL(1), .ENABLE_POLAR_CONTROL(1)) dut (
        .clk(clk), .rst_n(rst_n), .key0_n(key0_n), .key1_n(key1_n),
        .frame_commit(frame_commit), .mode_pending(mode_pending), .mode_active(mode_active),
        .threshold_edit(edit), .threshold_edit_active(edit_active),
        .bin_threshold_active(bin_threshold), .edge_threshold_active(edge_threshold),
        .polar_capture_pulse(capture_pulse), .polar_restart_pulse(restart_pulse)
    );

    task tick;
        input integer n;
        integer j;
        begin for(j=0;j<n;j=j+1) begin @(posedge clk); #1; end end
    endtask

    task reset_case;
        begin
            @(negedge clk); rst_n=0; key0_n=1; key1_n=1; edit=0; frame_commit=0;
            tick(3); @(negedge clk); rst_n=1; tick(8);
            captures=0; restarts=0; boundary_hits=0;
        end
    endtask

    task next_mode;
        begin @(negedge clk); key1_n=0; tick(12); @(negedge clk); key1_n=1; tick(10); end
    endtask

    task select_mode;
        input integer target;
        integer n;
        begin
            for(n=0;n<target;n=n+1) next_mode();
            @(negedge clk); frame_commit=1; tick(1); @(negedge clk); frame_commit=0; tick(2);
            if(mode_active !== target[3:0]) $fatal(1,"mode setup wanted %0d got %0d",target,mode_active);
        end
    endtask

    task collide_capture_then_restart;
        begin
            @(negedge clk); key1_n=0; tick(5);
            @(negedge clk); key0_n=0; tick(20);
            @(negedge clk); key0_n=1; key1_n=1; tick(12);
        end
    endtask

    task collide_restart_then_capture;
        begin
            // One cycle later than the other ordering: the second key's final debounce
            // count is expected to complete on the arbitration event sampling edge.
            @(negedge clk); key0_n=0; tick(6);
            @(negedge clk); key1_n=0; tick(20);
            @(negedge clk); key0_n=1; key1_n=1; tick(12);
        end
    endtask

    initial begin
        reset_case();
        collide_capture_then_restart();
        if(captures!=0 || restarts!=0 || mode_pending!=0)
            $fatal(1,"mode action escaped terminal two-key overlap: mode=%0d capture=%0d restart=%0d",mode_pending,captures,restarts);

        reset_case(); select_mode(2); @(negedge clk); edit=1; tick(10);
        saved_threshold=bin_threshold;
        collide_capture_then_restart();
        @(negedge clk); frame_commit=1; tick(1); @(negedge clk); frame_commit=0; tick(2);
        if(bin_threshold !== saved_threshold || captures!=0 || restarts!=0)
            $fatal(1,"threshold/polar action escaped overlap: threshold=%0d expected=%0d capture=%0d restart=%0d",bin_threshold,saved_threshold,captures,restarts);

        reset_case(); select_mode(9); @(negedge clk); edit=1; tick(10);
        collide_capture_then_restart();
        if(captures!=0 || restarts!=0 || mode_active!=9)
            $fatal(1,"KEY3 then KEY2 overlap: mode=%0d capture=%0d restart=%0d",mode_active,captures,restarts);
        // A stable release must re-arm a later single-key action in the next adjacent press.
        @(negedge clk); key1_n=0; tick(14); @(negedge clk); key1_n=1; tick(12);
        if(captures!=1 || restarts!=0)
            $fatal(1,"single capture did not re-enable after stable release: %0d/%0d",captures,restarts);

        reset_case(); select_mode(9); @(negedge clk); edit=1; tick(10);
        collide_restart_then_capture();
        if(captures!=0 || restarts!=0 || mode_active!=9 || boundary_hits==0)
            $fatal(1,"KEY2 then KEY3 overlap: mode=%0d capture=%0d restart=%0d",mode_active,captures,restarts);

        $display("PASS tb_key_terminal_overlap: mode, threshold, polar, both key orders, stable release re-arm");
        $finish;
    end
endmodule
