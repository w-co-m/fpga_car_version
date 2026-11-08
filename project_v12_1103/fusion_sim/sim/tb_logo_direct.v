`timescale 1ns/1ps
module tb_logo_direct;
    reg clk = 1'b0;
    reg [14:0] addr = 15'd0;
    wire [24:0] direct_pixel, reference_pixel;
    reg [14:0] sampled_addr = 15'd0;
    reg sampled_valid = 1'b0;
    integer i;

    always #5 clk = ~clk;

    anlogic_logo_sync_rom_direct dut (
        .clk(clk), .I_addr(addr), .O_pixel(direct_pixel)
    );
    anlogic_logo_rom reference (
        .I_addr(sampled_addr), .O_pixel(reference_pixel)
    );

    always @(posedge clk) begin
        sampled_addr <= addr;
        sampled_valid <= 1'b1;
        #1;
        if (sampled_valid && direct_pixel !== reference_pixel)
            $fatal(1, "Logo ROM mismatch sampled_addr=%0d direct=%h reference=%h",
                   sampled_addr, direct_pixel, reference_pixel);
    end

    initial begin
        for (i = 0; i < 32768; i = i + 1) begin
            @(negedge clk);
            addr = i[14:0];
        end
        @(negedge clk);
        addr = 15'd0;
        repeat (2) @(posedge clk);
        #1;
        $display("PASS tb_logo_direct: compared all 32768 addresses with one-cycle synchronous read");
        $finish;
    end
endmodule
