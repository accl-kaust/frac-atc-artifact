`resetall
`timescale 1ns / 1ps
`default_nettype none

//
// mm
//
// Slot wrapper: presents the reconfigurable-slot AXI-Stream interface
// (identical to or_slot / pattern_slot, widened to 512-bit tdata) and drives
// the unmodified CNN_workload core underneath. No core logic is changed
// here -- this file only adapts the interface.
//
// Mapping notes:
//   * The core takes a packed {TLAST, data[511:0]} bus; tlast rides bit 512.
//   * The core self-gates on workload_selection. Routing to the slot is done
//     by the parent, so the selection input is held at the core's own ID.
//   * The 32-bit session id (meta_TDATA) is not carried across the slot
//     boundary: the parent captures it on the RX side and re-attaches it on
//     the TX side (see the per-slot meta FIFO in pkt_logic.v). The core's
//     meta outputs are therefore left unconnected.
//   * The core has no reset input. rst only gates the handshakes here; it
//     does not clear core state.
//
(* DONT_TOUCH = "yes" *)
module mm #(
    parameter integer AXIS_DATA_W = 512,
    parameter integer KEEP_W      = AXIS_DATA_W/8,
    parameter integer TDEST_W     = 3,
    parameter integer TID_W       = 4,
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

    // Workload id the core compares workload_selection against.
    localparam [15:0] CNN_ID = 16'b0010;

    wire [512:0] core_tx_payload;
    wire         core_tx_valid;
    wire         core_rx_ready;

    CNN_workload CNN_workload_inst (
        .clk                  (clk),
        .rx_TDATA             ({s_axis_tlast, s_axis_tdata}),
        .rx_TVALID            (s_axis_tvalid && !rst),
        .rx_TREADY            (core_rx_ready),
        .meta_TDATA           (32'd0),
        .workload_selection   (CNN_ID),
        .pkt_tx_TDATA_payload (core_tx_payload),
        .tx_data_TVALID       (core_tx_valid),
        .tx_data_TREADY       (m_axis_tready),
        .meta_TDATA_out       (),
        .meta_TVALID_out      ()
    );

    assign s_axis_tready = core_rx_ready && !rst;

    assign m_axis_tdata  = core_tx_payload[511:0];
    assign m_axis_tvalid = core_tx_valid && !rst;
    assign m_axis_tlast  = core_tx_payload[512];
    assign m_axis_tkeep  = {KEEP_W{1'b1}};
    assign m_axis_tstrb  = {KEEP_W{1'b1}};
    assign m_axis_tdest  = s_axis_tdest;
    assign m_axis_tid    = s_axis_tid;
    assign m_axis_tuser  = s_axis_tuser;

endmodule

`resetall
