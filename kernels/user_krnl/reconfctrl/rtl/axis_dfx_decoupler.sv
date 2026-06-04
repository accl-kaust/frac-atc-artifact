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

module axis_dfx_decoupler (
    input  wire logic decouple,

    taxi_axis_if.snk  s_axis,
    taxi_axis_if.src  m_axis
);

    localparam int DATA_W = s_axis.DATA_W;
    localparam int KEEP_W = s_axis.KEEP_W;
    localparam int ID_W   = s_axis.ID_W;
    localparam int DEST_W = s_axis.DEST_W;
    localparam int USER_W = s_axis.USER_W;

    initial begin
        if (m_axis.DATA_W != DATA_W)
            $fatal(0, "axis_dfx_decoupler: DATA_W mismatch");
        if (m_axis.KEEP_W != KEEP_W)
            $fatal(0, "axis_dfx_decoupler: KEEP_W mismatch");
        if (m_axis.ID_W != ID_W)
            $fatal(0, "axis_dfx_decoupler: ID_W mismatch");
        if (m_axis.DEST_W != DEST_W)
            $fatal(0, "axis_dfx_decoupler: DEST_W mismatch");
        if (m_axis.USER_W != USER_W)
            $fatal(0, "axis_dfx_decoupler: USER_W mismatch");
        if (m_axis.KEEP_EN != s_axis.KEEP_EN)
            $fatal(0, "axis_dfx_decoupler: KEEP_EN mismatch");
        if (m_axis.LAST_EN != s_axis.LAST_EN)
            $fatal(0, "axis_dfx_decoupler: LAST_EN mismatch");
        if (m_axis.ID_EN != s_axis.ID_EN)
            $fatal(0, "axis_dfx_decoupler: ID_EN mismatch");
        if (m_axis.DEST_EN != s_axis.DEST_EN)
            $fatal(0, "axis_dfx_decoupler: DEST_EN mismatch");
        if (m_axis.USER_EN != s_axis.USER_EN)
            $fatal(0, "axis_dfx_decoupler: USER_EN mismatch");
    end

    assign s_axis.tready = decouple ? 1'b0 : m_axis.tready;

    assign m_axis.tvalid = decouple ? 1'b0 : s_axis.tvalid;
    assign m_axis.tdata  = decouple ? '0   : s_axis.tdata;
    assign m_axis.tkeep  = decouple ? '0   : s_axis.tkeep;
    assign m_axis.tstrb  = decouple ? '0   : s_axis.tstrb;
    assign m_axis.tlast  = decouple ? 1'b0 : s_axis.tlast;
    assign m_axis.tid    = decouple ? '0   : s_axis.tid;
    assign m_axis.tdest  = decouple ? '0   : s_axis.tdest;
    assign m_axis.tuser  = decouple ? '0   : s_axis.tuser;

endmodule

`resetall
