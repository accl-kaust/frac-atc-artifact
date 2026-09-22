`resetall
`timescale 1ns / 1ps
`default_nettype none

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

    // Behavioural stand-in for the PR cells: c00 is the echo RM
    // (apps/pattern_slot), c01 is the OR RM (apps/or_slot).  Both keep
    // {meta, tlast} in tdata[544:512] untouched.
    reg is_or_slot = 1'b0;

    initial begin
        string inst_name;

        inst_name = $sformatf("%m");
        if (inst_name.len() >= 24 && inst_name.substr(inst_name.len()-24, inst_name.len()-13) == "c01_bbx_inst") begin
            is_or_slot = 1'b1;
        end
    end

    assign s_axis_tready = m_axis_tready;
    assign m_axis_tvalid = s_axis_tvalid;
    assign m_axis_tdata = is_or_slot ? {s_axis_tdata[AXIS_DATA_W-1:512], s_axis_tdata[511:0] | {512{1'b1}}}
                                     : s_axis_tdata;
    assign m_axis_tkeep = s_axis_tkeep;
    assign m_axis_tstrb = s_axis_tstrb;
    assign m_axis_tlast = s_axis_tlast;
    assign m_axis_tdest = s_axis_tdest;
    assign m_axis_tid = s_axis_tid;
    assign m_axis_tuser = s_axis_tuser;

endmodule

`resetall
