module awb_gain_divider_slice_ref (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [31:0] sum_g32,
    input wire [31:0] den32,
    output wire valid,
    output wire [19:0] gain20
);
    reg [35:0] rem_pipe [0:20];
    reg [31:0] den_pipe [0:20];
    reg [19:0] quot_pipe [0:20];
    reg sat_pipe [0:20];
    reg [48:0] valid_pre;
    reg valid_out;
    reg [19:0] gain_pre [0:27];
    reg [19:0] gain_out;
    integer i;

    // Match the legacy gate: its 49 internal valid/data stages have no reset;
    // only the final output registers are asynchronously reset.
    always @(posedge clk) begin
        rem_pipe[0] <= {4'b0, sum_g32};
        den_pipe[0] <= den32;
        quot_pipe[0] <= 0;
        sat_pipe[0] <= (den32 == 0) ||
                       ({4'b0, sum_g32} >= {den32, 4'b0});
        valid_pre <= {valid_pre[47:0], start};
    end

    genvar s;
    generate
        for (s = 1; s <= 20; s = s + 1) begin : divide_stage
            if (s <= 4) begin : integer_bit
                localparam integer SHIFT = 4 - s;
                always @(posedge clk) begin
                    den_pipe[s] <= den_pipe[s-1];
                    sat_pipe[s] <= sat_pipe[s-1];
                    if (rem_pipe[s-1] >= ({4'b0, den_pipe[s-1]} << SHIFT)) begin
                        rem_pipe[s] <= rem_pipe[s-1] - ({4'b0, den_pipe[s-1]} << SHIFT);
                        quot_pipe[s] <= quot_pipe[s-1] | (20'b1 << (20-s));
                    end else begin
                        rem_pipe[s] <= rem_pipe[s-1];
                        quot_pipe[s] <= quot_pipe[s-1];
                    end
                end
            end else begin : fraction_bit
                localparam integer BIT_INDEX = 20 - s;
                wire [35:0] shifted_rem = {rem_pipe[s-1][34:0], 1'b0};
                wire [35:0] denominator_ext = {4'b0, den_pipe[s-1]};
                always @(posedge clk) begin
                    den_pipe[s] <= den_pipe[s-1];
                    sat_pipe[s] <= sat_pipe[s-1];
                    if (shifted_rem >= denominator_ext) begin
                        rem_pipe[s] <= shifted_rem - denominator_ext;
                        quot_pipe[s] <= quot_pipe[s-1] | (20'b1 << BIT_INDEX);
                    end else begin
                        rem_pipe[s] <= shifted_rem;
                        quot_pipe[s] <= quot_pipe[s-1];
                    end
                end
            end
        end
    endgenerate

    always @(posedge clk) begin
        gain_pre[0] <= sat_pipe[20] ? 20'hfffff : quot_pipe[20];
        for (i = 1; i <= 27; i = i + 1)
            gain_pre[i] <= gain_pre[i-1];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0;
            gain_out <= 0;
        end else begin
            valid_out <= valid_pre[48];
            gain_out <= gain_pre[27];
        end
    end

    assign valid = valid_out;
    assign gain20 = gain_out;
endmodule
