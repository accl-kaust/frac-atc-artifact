// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2020.2 (64-bit)
// Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
// ==============================================================

`timescale 1 ns / 1 ps
module test_mul_32s_32s_32_1_1(
input wire [din0_WIDTH - 1:0] din0,
input wire [din1_WIDTH - 1:0] din1,
output wire [dout_WIDTH - 1:0] dout);

parameter ID = 32'd1;
parameter NUM_STAGE = 32'd1;
parameter din0_WIDTH = 32'd1;
parameter din1_WIDTH = 32'd1;
parameter dout_WIDTH = 32'd1;



test_mul_32s_32s_32_1_1_Multiplier_0 test_mul_32s_32s_32_1_1_Multiplier_0_U(
    .a( din0 ),
    .b( din1 ),
    .p( dout ));

endmodule
