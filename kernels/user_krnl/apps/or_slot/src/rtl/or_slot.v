`resetall
`timescale 1ns / 1ps
`default_nettype none

// OR accelerator for one PR cell: payload is OR-ed with all ones, metadata and
// tlast are echoed unchanged.
//
// Same behaviour and the same data / metadata paths as the upstream offrac
// kernel (kernel/user_krnl/offrac_krnl/src/hdl/offrac), with the workload
// ports flattened onto the PR cell's single AXI-Stream boundary:
//
//   upstream echo_workload.v          this module
//   -------------------------------   --------------------------------------
//   rx_TDATA[511:0]   payload         s_axis_tdata[511:0]
//   rx_TDATA[512]     tlast           s_axis_tdata[512]   (s_axis_tlast too)
//   meta_TDATA[31:0]  {len, session}  s_axis_tdata[544:513]
//   rx_TVALID / rx_TREADY             s_axis_tvalid / s_axis_tready
//   pkt_tx_TDATA_payload[512:0]       m_axis_tdata[512:0]
//   meta_TDATA_out[31:0]              m_axis_tdata[544:513]
//   tx_data_TVALID / tx_data_TREADY   m_axis_tvalid / m_axis_tready
//   meta_TVALID_out                   implied: meta is read on the tlast beat
//
// meta_TDATA[31:16] is the size of the whole request in bytes (see
// pattern_slot.v).  One response beat per request beat, so the meta goes out
// unchanged and names the response length.
//
// workload_selection is not needed: pkt_logic.v only steers this slot's own
// requests onto s_axis.  The parameter defaults must match the cell_bbx
// instantiation in pkt_logic.v (c00_bbx_inst / c01_bbx_inst).

(* DONT_TOUCH = "yes" *)
module or_slot #(
    parameter integer AXIS_DATA_W = 512 + 1 + 32,
    parameter integer KEEP_W      = 1,
    parameter integer TDEST_W     = 1,
    parameter integer TID_W       = 1,
    parameter integer USER_W      = 1
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

    assign s_axis_tready = m_axis_tready;
    assign m_axis_tvalid = s_axis_tvalid;
    // {meta_TDATA_out, tlast} pass through; payload OR all ones.
    assign m_axis_tdata  = {s_axis_tdata[AXIS_DATA_W-1:512], s_axis_tdata[511:0] | {512{1'b1}}};
    assign m_axis_tkeep  = s_axis_tkeep;
    assign m_axis_tstrb  = s_axis_tstrb;
    assign m_axis_tlast  = s_axis_tlast;
    assign m_axis_tdest  = s_axis_tdest;
    assign m_axis_tid    = s_axis_tid;
    assign m_axis_tuser  = s_axis_tuser;

endmodule

`resetall
