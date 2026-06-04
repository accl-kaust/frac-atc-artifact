// SPDX-License-Identifier: CERN-OHL-S-2.0
//
// Small AXI-Stream decoupler for PR slot boundaries.
//
// When decouple=0 this module is a combinational pass-through. When
// decouple=1, it clamps the downstream source signals inactive and applies
// backpressure upstream so packets cannot enter or leave the slot boundary.

`resetall
`timescale 1ns / 1ps
`default_nettype none

module axis_dfx_decoupler #(
    parameter int DATA_W = 512,
    parameter int KEEP_W = DATA_W/8,
    parameter int ID_W   = 1,
    parameter int DEST_W = 1,
    parameter int USER_W = 1
) (
    input  wire                  decouple,

    input  wire [DATA_W-1:0]     s_axis_tdata,
    input  wire [KEEP_W-1:0]     s_axis_tkeep,
    input  wire [KEEP_W-1:0]     s_axis_tstrb,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,
    input  wire [DEST_W-1:0]     s_axis_tdest,
    input  wire [ID_W-1:0]       s_axis_tid,
    input  wire [USER_W-1:0]     s_axis_tuser,

    output wire [DATA_W-1:0]     m_axis_tdata,
    output wire [KEEP_W-1:0]     m_axis_tkeep,
    output wire [KEEP_W-1:0]     m_axis_tstrb,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,
    output wire [DEST_W-1:0]     m_axis_tdest,
    output wire [ID_W-1:0]       m_axis_tid,
    output wire [USER_W-1:0]     m_axis_tuser
);

    assign s_axis_tready = decouple ? 1'b0 : m_axis_tready;

    assign m_axis_tvalid = decouple ? 1'b0 : s_axis_tvalid;
    assign m_axis_tdata  = decouple ? {DATA_W{1'b0}} : s_axis_tdata;
    assign m_axis_tkeep  = decouple ? {KEEP_W{1'b0}} : s_axis_tkeep;
    assign m_axis_tstrb  = decouple ? {KEEP_W{1'b0}} : s_axis_tstrb;
    assign m_axis_tlast  = decouple ? 1'b0 : s_axis_tlast;
    assign m_axis_tdest  = decouple ? {DEST_W{1'b0}} : s_axis_tdest;
    assign m_axis_tid    = decouple ? {ID_W{1'b0}} : s_axis_tid;
    assign m_axis_tuser  = decouple ? {USER_W{1'b0}} : s_axis_tuser;

endmodule

`resetall
