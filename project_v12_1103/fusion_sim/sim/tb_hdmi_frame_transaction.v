`timescale 1ns/1ps
module tb_hdmi_frame_transaction;
 tb_hdmi_vtc_stream #(.FRAME_TRANSACTION(1)) real_stream();
endmodule
