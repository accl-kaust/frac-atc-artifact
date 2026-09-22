// SPDX-License-Identifier: CERN-OHL-S-2.0
//
// AXI-Stream PR cell blackbox shell.
//
// The static design instantiates one of these per reconfigurable slot.  The
// corresponding RM unit top exposes the same flat AXIS boundary but provides
// the real implementation during out-of-context synthesis.
//
// tdata carries the upstream offrac workload interface (echo_workload.v)
// flattened onto one stream, in both directions:
//   tdata[544:513] = meta_TDATA / meta_TDATA_out   {tcp_len[15:0], session_id[15:0]}
//   tdata[512]     = tlast, in-band (the tlast line duplicates it)
//   tdata[511:0]   = payload
// The parameter defaults equal the instantiation in pkt_logic.v.

`resetall
`timescale 1ns / 1ps
`default_nettype none

(* DONT_TOUCH = "yes" *)
module cell_bbx #(
    parameter int AXIS_DATA_W = 512 + 1 + 32,
    parameter int KEEP_W      = 1,
    parameter int TDEST_W     = 1,
    parameter int TID_W       = 1,
    parameter int USER_W      = 1
) (
    input  wire                   clk,
    input  wire                   rst,

    input  wire [AXIS_DATA_W-1:0] s_axis_tdata,
    input  wire [KEEP_W-1:0]      s_axis_tkeep,
    input  wire [KEEP_W-1:0]      s_axis_tstrb,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [TDEST_W-1:0]     s_axis_tdest,
    input  wire [TID_W-1:0]       s_axis_tid,
    input  wire [USER_W-1:0]      s_axis_tuser,

    output wire [AXIS_DATA_W-1:0] m_axis_tdata,
    output wire [KEEP_W-1:0]      m_axis_tkeep,
    output wire [KEEP_W-1:0]      m_axis_tstrb,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [TDEST_W-1:0]     m_axis_tdest,
    output wire [TID_W-1:0]       m_axis_tid,
    output wire [USER_W-1:0]      m_axis_tuser
);

endmodule

`resetall
