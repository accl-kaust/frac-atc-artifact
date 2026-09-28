`resetall
`timescale 1ns / 1ps
`default_nettype none

// or_slot, the reconfigurable module: or_slot_core behind a register stage on
// each side of the slot boundary, so that every partition pin meets a flop.
//
// The core, the payload OR-ed with all ones, is a pure wire: tready, tvalid
// and tdata cross it combinationally.  Without these stages the slot's whole
// round trip -- a static flop, the input decoupler, the partition pin,
// straight across the cell, the other partition pin, the output decoupler, a
// static flop -- was one path, the ready running the other way along the same
// route, and implementing the cell against an abstract shell stretched it past
// a cycle.
//
// Each stage is a skid buffer (axis_register, REG_TYPE 2): a beat every
// cycle, two beats of buffering and one cycle of latency, so a request and
// its response each take a cycle longer and nothing else changes.  tkeep and
// tstrb are not carried: pkt_logic drives them high into the cell and never
// reads them back, and this drives them high.
//
// The reset gets the same treatment: it comes from a static synchroniser,
// and rst_q takes it at the partition pin, so its fan-out to every register
// here starts inside the cell.  The module leaves reset a cycle after the
// slot does, and the request stage takes nothing while it is in reset.
// rst_q starts high, so a freshly configured module begins in reset too.
//
// Same interface as the core; see or_slot_core.v for the slot boundary format.

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

    reg rst_q = 1'b1;
    always @(posedge clk) rst_q <= rst;

    // request: boundary -> req_reg_inst -> core
    wire [AXIS_DATA_W-1:0] req_tdata;
    wire                   req_tvalid, req_tready, req_tlast;
    wire [TDEST_W-1:0]     req_tdest;
    wire [TID_W-1:0]       req_tid;
    wire [USER_W-1:0]      req_tuser;

    // response: core -> resp_reg_inst -> boundary
    wire [AXIS_DATA_W-1:0] resp_tdata;
    wire                   resp_tvalid, resp_tready, resp_tlast;
    wire [TDEST_W-1:0]     resp_tdest;
    wire [TID_W-1:0]       resp_tid;
    wire [USER_W-1:0]      resp_tuser;

    axis_register #(
        .DATA_WIDTH (AXIS_DATA_W),
        .KEEP_ENABLE(0),
        .KEEP_WIDTH (1),
        .LAST_ENABLE(1),
        .ID_ENABLE  (1),
        .ID_WIDTH   (TID_W),
        .DEST_ENABLE(1),
        .DEST_WIDTH (TDEST_W),
        .USER_ENABLE(1),
        .USER_WIDTH (USER_W),
        .REG_TYPE   (2)
    ) req_reg_inst (
        .clk          (clk),
        .rst          (rst_q),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tkeep (1'b1),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (s_axis_tlast),
        .s_axis_tid   (s_axis_tid),
        .s_axis_tdest (s_axis_tdest),
        .s_axis_tuser (s_axis_tuser),
        .m_axis_tdata (req_tdata),
        .m_axis_tkeep (),
        .m_axis_tvalid(req_tvalid),
        .m_axis_tready(req_tready),
        .m_axis_tlast (req_tlast),
        .m_axis_tid   (req_tid),
        .m_axis_tdest (req_tdest),
        .m_axis_tuser (req_tuser)
    );

    or_slot_core #(
        .AXIS_DATA_W(AXIS_DATA_W),
        .KEEP_W     (KEEP_W),
        .TDEST_W    (TDEST_W),
        .TID_W      (TID_W),
        .USER_W     (USER_W)
    ) core_inst (
        .clk          (clk),
        .rst          (rst_q),
        .s_axis_tdata (req_tdata),
        .s_axis_tkeep ({KEEP_W{1'b1}}),
        .s_axis_tstrb ({KEEP_W{1'b1}}),
        .s_axis_tvalid(req_tvalid),
        .s_axis_tready(req_tready),
        .s_axis_tlast (req_tlast),
        .s_axis_tdest (req_tdest),
        .s_axis_tid   (req_tid),
        .s_axis_tuser (req_tuser),
        .m_axis_tdata (resp_tdata),
        .m_axis_tkeep (),
        .m_axis_tstrb (),
        .m_axis_tvalid(resp_tvalid),
        .m_axis_tready(resp_tready),
        .m_axis_tlast (resp_tlast),
        .m_axis_tdest (resp_tdest),
        .m_axis_tid   (resp_tid),
        .m_axis_tuser (resp_tuser)
    );

    axis_register #(
        .DATA_WIDTH (AXIS_DATA_W),
        .KEEP_ENABLE(0),
        .KEEP_WIDTH (1),
        .LAST_ENABLE(1),
        .ID_ENABLE  (1),
        .ID_WIDTH   (TID_W),
        .DEST_ENABLE(1),
        .DEST_WIDTH (TDEST_W),
        .USER_ENABLE(1),
        .USER_WIDTH (USER_W),
        .REG_TYPE   (2)
    ) resp_reg_inst (
        .clk          (clk),
        .rst          (rst_q),
        .s_axis_tdata (resp_tdata),
        .s_axis_tkeep (1'b1),
        .s_axis_tvalid(resp_tvalid),
        .s_axis_tready(resp_tready),
        .s_axis_tlast (resp_tlast),
        .s_axis_tid   (resp_tid),
        .s_axis_tdest (resp_tdest),
        .s_axis_tuser (resp_tuser),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tkeep (),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast),
        .m_axis_tid   (m_axis_tid),
        .m_axis_tdest (m_axis_tdest),
        .m_axis_tuser (m_axis_tuser)
    );

    assign m_axis_tkeep = {KEEP_W{1'b1}};
    assign m_axis_tstrb = {KEEP_W{1'b1}};

endmodule

`resetall
