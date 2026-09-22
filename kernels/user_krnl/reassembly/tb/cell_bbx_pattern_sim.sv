`resetall
`timescale 1ns / 1ps
`default_nettype none

// Simulation stand-in for the PR cells.  The static design instantiates the
// blackbox cell_bbx (reconfctrl/rtl/cell_bbx.sv); here it resolves to the real
// RM tops from apps/, so the bench verifies the RTL that is synthesised into
// the slots: c00 is pattern_slot (echo), c01 is or_slot.  Which one an
// instance stands for follows from its name, as pkt_logic.v names them
// c00_bbx_inst / c01_bbx_inst.  Both RMs are instantiated and the one that is
// not selected is held idle (tvalid / tready gated off).
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

    reg is_or_slot = 1'b0;

    initial begin
        string inst_name;

        inst_name = $sformatf("%m");
        if (inst_name.len() >= 24 && inst_name.substr(inst_name.len()-24, inst_name.len()-13) == "c01_bbx_inst") begin
            is_or_slot = 1'b1;
        end
    end

    wire                   echo_s_tready, or_s_tready;
    wire [AXIS_DATA_W-1:0] echo_m_tdata,  or_m_tdata;
    wire [KEEP_W-1:0]      echo_m_tkeep,  or_m_tkeep;
    wire [KEEP_W-1:0]      echo_m_tstrb,  or_m_tstrb;
    wire                   echo_m_tvalid, or_m_tvalid;
    wire                   echo_m_tlast,  or_m_tlast;
    wire [TDEST_W-1:0]     echo_m_tdest,  or_m_tdest;
    wire [TID_W-1:0]       echo_m_tid,    or_m_tid;
    wire [USER_W-1:0]      echo_m_tuser,  or_m_tuser;

    pattern_slot #(
        .AXIS_DATA_W(AXIS_DATA_W),
        .KEEP_W(KEEP_W),
        .TDEST_W(TDEST_W),
        .TID_W(TID_W),
        .USER_W(USER_W)
    ) echo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tstrb(s_axis_tstrb),
        .s_axis_tvalid(s_axis_tvalid && !is_or_slot),
        .s_axis_tready(echo_s_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tdest(s_axis_tdest),
        .s_axis_tid(s_axis_tid),
        .s_axis_tuser(s_axis_tuser),
        .m_axis_tdata(echo_m_tdata),
        .m_axis_tkeep(echo_m_tkeep),
        .m_axis_tstrb(echo_m_tstrb),
        .m_axis_tvalid(echo_m_tvalid),
        .m_axis_tready(m_axis_tready && !is_or_slot),
        .m_axis_tlast(echo_m_tlast),
        .m_axis_tdest(echo_m_tdest),
        .m_axis_tid(echo_m_tid),
        .m_axis_tuser(echo_m_tuser)
    );

    or_slot #(
        .AXIS_DATA_W(AXIS_DATA_W),
        .KEEP_W(KEEP_W),
        .TDEST_W(TDEST_W),
        .TID_W(TID_W),
        .USER_W(USER_W)
    ) or_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tstrb(s_axis_tstrb),
        .s_axis_tvalid(s_axis_tvalid && is_or_slot),
        .s_axis_tready(or_s_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tdest(s_axis_tdest),
        .s_axis_tid(s_axis_tid),
        .s_axis_tuser(s_axis_tuser),
        .m_axis_tdata(or_m_tdata),
        .m_axis_tkeep(or_m_tkeep),
        .m_axis_tstrb(or_m_tstrb),
        .m_axis_tvalid(or_m_tvalid),
        .m_axis_tready(m_axis_tready && is_or_slot),
        .m_axis_tlast(or_m_tlast),
        .m_axis_tdest(or_m_tdest),
        .m_axis_tid(or_m_tid),
        .m_axis_tuser(or_m_tuser)
    );

    assign s_axis_tready = is_or_slot ? or_s_tready : echo_s_tready;
    assign m_axis_tdata  = is_or_slot ? or_m_tdata  : echo_m_tdata;
    assign m_axis_tkeep  = is_or_slot ? or_m_tkeep  : echo_m_tkeep;
    assign m_axis_tstrb  = is_or_slot ? or_m_tstrb  : echo_m_tstrb;
    assign m_axis_tvalid = is_or_slot ? or_m_tvalid : echo_m_tvalid;
    assign m_axis_tlast  = is_or_slot ? or_m_tlast  : echo_m_tlast;
    assign m_axis_tdest  = is_or_slot ? or_m_tdest  : echo_m_tdest;
    assign m_axis_tid    = is_or_slot ? or_m_tid    : echo_m_tid;
    assign m_axis_tuser  = is_or_slot ? or_m_tuser  : echo_m_tuser;

endmodule

`resetall
