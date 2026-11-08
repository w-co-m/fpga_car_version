// Frozen test-only integer oracle for algorithm 7 delivery RTL.
// Source: new_algorithm/算法7交付包/rtl/算法 7：偏振信息计算（DoLP 与 AoP）.v
// SHA256: C2CE70D0014239E2DCE45454D6362FC696C9C4CEA480BD67363EF48408A85631
// Do not derive expected values from DUT internals. Keep truncations explicit.
function [15:0] algo7_delivery_ref;
    input [7:0] v0,v45,v90,v135;
    input integer dolp_min,aop_min;
    reg [9:0] s0;
    reg signed [9:0] s1,s2;
    reg signed [12:0] x,y,xs,ys;
    reg signed [15:0] z;
    reg signed [15:0] phi,phi_wrapped,half_z;
    reg [15:0] angle_sum,angle_shift;
    reg [23:0] mag_mul;
    reg [12:0] mag_q4;
    reg [16:0] numerator;
    reg [7:0] q;
    integer i;
    reg [15:0] atan_step;
    begin
        s0 = {2'b0,v0} + {2'b0,v90};
        s1 = $signed({1'b0,v0}) - $signed({1'b0,v90});
        s2 = $signed({1'b0,v45}) - $signed({1'b0,v135});
        x = s1[9] ? $signed({3'b000,(-s1[7:0]),2'b00})
                  : $signed({3'b000,s1[7:0],2'b00});
        y = $signed({s2[9],s2[9:0],2'b00});
        z = 16'sd0;
        for (i=0; i<12; i=i+1) begin
            case (i)
                0: atan_step=1024; 1: atan_step=605; 2: atan_step=319;
                3: atan_step=162; 4: atan_step=81; 5: atan_step=41;
                6: atan_step=20; 7: atan_step=10; 8: atan_step=5;
                9: atan_step=3; 10: atan_step=1; default: atan_step=1;
            endcase
            xs = x >>> i;
            ys = y >>> i;
            if ((xs != 0) || (ys != 0)) begin
                if (y > 0) begin
                    x = x + ys;
                    y = y - xs;
                    z = z + $signed({1'b0,atan_step});
                end else begin
                    x = x - ys;
                    y = y + xs;
                    z = z - $signed({1'b0,atan_step});
                end
            end
        end
        mag_mul = {11'b0,x[12:0]} * 16'd622;
        mag_q4 = mag_mul[20:8];
        numerator = {mag_q4,4'b0000};
        if (s0 < dolp_min) q=0;
        else if (s0==0) q=0;
        else if (numerator > (s0 * 255)) q=8'hff;
        else q=numerator / s0;

        half_z = z >>> 1;
        if (s1[9]) begin
            if (s2[9]) phi = -16'sd2048 - half_z;
            else       phi =  16'sd2048 - half_z;
        end else phi=half_z;
        if (phi > 16'sd2048) phi_wrapped=phi-16'sd4096;
        else if (phi <= -16'sd2048) phi_wrapped=phi+16'sd4096;
        else phi_wrapped=phi;
        angle_sum = phi_wrapped + 16'sd2056;
        angle_shift = $signed(angle_sum) >>> 4;
        if ((s1==0) && (s2==0)) algo7_delivery_ref[7:0]=8'd128;
        else if (mag_q4 < (aop_min << 4)) algo7_delivery_ref[7:0]=8'd128;
        else if (angle_shift > 255) algo7_delivery_ref[7:0]=8'hff;
        else algo7_delivery_ref[7:0]=angle_shift[7:0];
        algo7_delivery_ref[15:8]=q;
    end
endfunction
