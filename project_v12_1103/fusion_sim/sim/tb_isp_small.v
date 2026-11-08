`timescale 1ns/1ps
module tb_isp_small;
 tb_isp_content #(.IMG_WIDTH(16),.IMG_HEIGHT(6),.DATA_DELAY(0),.TEST_RAMP(1)) check();
endmodule
