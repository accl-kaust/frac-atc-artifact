// SPDX-License-Identifier: MIT
//
// AXI-Stream PR cell blackbox shell.
//
// The static design instantiates one of these per reconfigurable slot.  The
// corresponding RM unit top exposes the same flat boundary but provides the
// real implementation during out-of-context synthesis.
//
// tdata carries the upstream offrac workload interface (echo_workload.v)
// flattened onto one stream, in both directions:
//   tdata[544:513] = meta_TDATA      {request_bytes[15:0], session_id[15:0]}
//                    meta_TDATA_out  {response_bytes[15:0], session_id[15:0]}, read
//                    by pkt_sender from the beat that carries tlast
//   tdata[512]     = tlast, in-band (the tlast line duplicates it)
//   tdata[511:0]   = payload
//
// Flow control is by credits, not ready (reassembly/rtl/slot_credit.v).  A
// beat is sent only with a credit, so tvalid is never refused and there is no
// tready.  s_axis_credit pulses once for each request beat the module has
// taken out of its input FIFO; m_axis_credit pulses once for each response
// beat static has taken out of its own.  Each side starts with as many
// credits as the other has FIFO entries, the slot_credit defaults.  Every pin
// meets a register on both sides.  rst is the slot's, held while the slot is
// decoupled.
//
// The parameter default equals the instantiation in pkt_logic.v.

`resetall
`timescale 1ns / 1ps
`default_nettype none

(* DONT_TOUCH = "yes" *)
module cell_bbx #(
    parameter int AXIS_DATA_W = 512 + 1 + 32
) (
    input  wire                   clk,
    input  wire                   rst,

    input  wire [AXIS_DATA_W-1:0] s_axis_tdata,
    input  wire                   s_axis_tvalid,
    input  wire                   s_axis_tlast,
    output wire                   s_axis_credit,

    output wire [AXIS_DATA_W-1:0] m_axis_tdata,
    output wire                   m_axis_tvalid,
    output wire                   m_axis_tlast,
    input  wire                   m_axis_credit
);

endmodule

`resetall
