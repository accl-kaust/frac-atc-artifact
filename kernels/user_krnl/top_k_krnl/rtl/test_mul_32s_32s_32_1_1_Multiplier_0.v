// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2020.2 (64-bit)
// Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
// ==============================================================

`timescale 1 ns / 1 ps

module test_mul_32s_32s_32_1_1_Multiplier_0(
input wire [32 - 1 : 0] a, input wire [32 - 1 : 0] b, output wire [32 - 1 : 0] p
);

assign p = $signed(a) * $signed(b);
endmodule