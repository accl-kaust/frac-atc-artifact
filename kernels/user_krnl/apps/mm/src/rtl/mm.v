`resetall
`timescale 1ns / 1ps
`default_nettype none

//
// mm
//
// Slot wrapper: presents the reconfigurable-slot AXI-Stream interface
// (identical to or_slot / pattern_slot: tdata = {meta, tlast, payload}) and
// drives the unmodified CNN_workload core underneath. No core logic is
// changed here -- this file only adapts the interface.
//
// Mapping notes:
//   * The core takes a packed {TLAST, data[511:0]} bus; that is exactly
//     s_axis_tdata[512:0] (tlast in-band, s_axis_tlast duplicates it).
//   * The core self-gates on workload_selection. Routing to the slot is done
//     by the parent, so the selection input is held at the core's own ID.
//   * meta_TDATA = s_axis_tdata[544:513], the request's {size, session}, in
//     the position upstream pkt_logic.v fed it.  packet_parser_CNN.v turns it
//     into {64, session} -- the response is always one 64-byte beat -- and
//     the core's metadata FIFO presents that as meta_TDATA_out while the
//     response beat is valid.  It goes out on m_axis_tdata[544:513], where
//     pkt_sender reads it from the beat that carries tlast as the TCP tx
//     metadata.  (Before the 545-bit boundary, meta never crossed the cell and
//     the parent re-attached the session itself; that path is gone.)
//   * The core has no reset input. rst only gates the handshakes here; it
//     does not clear core state.
//
(* DONT_TOUCH = "yes" *)
module mm #(
    parameter integer AXIS_DATA_W = 512 + 1 + 32,  // {meta, tlast, payload}
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

    localparam integer PAYLOAD_W = 512;

    // Workload id the core compares workload_selection against.
    localparam [15:0] CNN_ID = 16'b0010;

    wire [PAYLOAD_W:0] core_tx_payload;   // {tlast, payload}
    wire               core_tx_valid;
    wire               core_rx_ready;
    wire [31:0]        core_meta_out;     // {64, session} from packet_parser_CNN

    CNN_workload CNN_workload_inst (
        .clk                  (clk),
        .rx_TDATA             (s_axis_tdata[PAYLOAD_W:0]),
        .rx_TVALID            (s_axis_tvalid && !rst),
        .rx_TREADY            (core_rx_ready),
        .meta_TDATA           (s_axis_tdata[PAYLOAD_W+1 +: 32]),
        .workload_selection   (CNN_ID),
        .pkt_tx_TDATA_payload (core_tx_payload),
        .tx_data_TVALID       (core_tx_valid),
        .tx_data_TREADY       (m_axis_tready),
        .meta_TDATA_out       (core_meta_out),
        .meta_TVALID_out      ()
    );

    assign s_axis_tready = core_rx_ready && !rst;

    assign m_axis_tdata  = {core_meta_out, core_tx_payload};
    assign m_axis_tvalid = core_tx_valid && !rst;
    assign m_axis_tlast  = core_tx_payload[PAYLOAD_W];
    assign m_axis_tkeep  = {KEEP_W{1'b1}};
    assign m_axis_tstrb  = {KEEP_W{1'b1}};
    assign m_axis_tdest  = s_axis_tdest;
    assign m_axis_tid    = s_axis_tid;
    assign m_axis_tuser  = s_axis_tuser;

endmodule

`resetall
