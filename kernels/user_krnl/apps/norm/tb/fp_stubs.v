`timescale 1ns/1ps
//
// Behavioural stubs for the two Xilinx floating-point cores norm uses.
// The real .xci are not in the repo (regenerate with src/ip/gen_ip.tcl).
//
// Not float models: invertible INTEGER ops at the real cores' latencies, so a
// testbench can predict results exactly. floating_point_3 concatenates both
// operands, which proves (x-min) is paired with the correct (max-min).
//
//   floating_point_0  (Add_Subtract, latency 12)  res = a - b
//   floating_point_3  (Divide,       latency 29)  res = {a[15:0], b[15:0]}
//
module fp_pipe #(parameter integer LATENCY = 12) (
    input wire clk, input wire in_valid, input wire in_last, input wire [31:0] in_data,
    output wire out_valid, output wire out_last, output wire [31:0] out_data);
    reg [33:0] pipe [0:LATENCY-1];
    integer k;
    initial for (k = 0; k < LATENCY; k = k + 1) pipe[k] = 34'b0;
    always @(posedge clk) begin
        for (k = LATENCY-1; k > 0; k = k - 1) pipe[k] <= pipe[k-1];
        pipe[0] <= {in_valid, in_last, in_data};
    end
    assign out_valid = pipe[LATENCY-1][33];
    assign out_last  = pipe[LATENCY-1][32];
    assign out_data  = pipe[LATENCY-1][31:0];
endmodule

module floating_point_0 (
    input wire aclk,
    input wire s_axis_a_tvalid, output wire s_axis_a_tready, input wire [31:0] s_axis_a_tdata,
    input wire s_axis_b_tvalid, output wire s_axis_b_tready, input wire [31:0] s_axis_b_tdata,
    input wire s_axis_b_tlast,
    output wire m_axis_result_tvalid, input wire m_axis_result_tready,
    output wire [31:0] m_axis_result_tdata, output wire m_axis_result_tlast);
    assign s_axis_a_tready = 1'b1;
    assign s_axis_b_tready = 1'b1;
    fp_pipe #(.LATENCY(12)) u (.clk(aclk),
        .in_valid(s_axis_a_tvalid && s_axis_b_tvalid), .in_last(s_axis_b_tlast),
        .in_data(s_axis_a_tdata - s_axis_b_tdata),
        .out_valid(m_axis_result_tvalid), .out_last(m_axis_result_tlast),
        .out_data(m_axis_result_tdata));
endmodule

module floating_point_3 (
    input wire aclk,
    input wire s_axis_a_tvalid, output wire s_axis_a_tready, input wire [31:0] s_axis_a_tdata,
    input wire s_axis_a_tlast,
    input wire s_axis_b_tvalid, output wire s_axis_b_tready, input wire [31:0] s_axis_b_tdata,
    output wire m_axis_result_tvalid, input wire m_axis_result_tready,
    output wire [31:0] m_axis_result_tdata, output wire m_axis_result_tlast);
    assign s_axis_a_tready = 1'b1;
    assign s_axis_b_tready = 1'b1;
    fp_pipe #(.LATENCY(29)) u (.clk(aclk),
        .in_valid(s_axis_a_tvalid && s_axis_b_tvalid), .in_last(s_axis_a_tlast),
        .in_data({s_axis_a_tdata[15:0], s_axis_b_tdata[15:0]}),   // proves the pairing
        .out_valid(m_axis_result_tvalid), .out_last(m_axis_result_tlast),
        .out_data(m_axis_result_tdata));
endmodule
