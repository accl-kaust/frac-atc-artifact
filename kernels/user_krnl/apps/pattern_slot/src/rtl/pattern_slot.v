`resetall
`timescale 1ns / 1ps
`default_nettype none

// pattern_slot, the reconfigurable module: pattern_slot_core between the two
// ends of the slot boundary's credit links, so that every partition pin meets a
// flop.
//
// The core, the echo, is a pure wire: tready, tvalid and tdata cross it
// combinationally.  Without these stages the slot's whole round trip -- a
// static flop, the input decoupler, the partition pin, straight across the
// cell, the other partition pin, the output decoupler, a static flop -- was
// one path, the ready running the other way along the same route, and
// implementing the cell against an abstract shell stretched it past a cycle.
//
// The request side is a slot_credit_sink: it registers the boundary, queues
// every beat in its FIFO and pulses s_axis_credit for each beat the core takes
// out of it.  The response side is a slot_credit_source: it sends a beat only
// with a credit from static, which comes back on m_axis_credit.  See
// reassembly/rtl/slot_credit.v.  Every pin meets a register, a beat still
// moves every cycle, and no ready crosses the boundary.  tkeep, tstrb, tdest,
// tid and tuser are not carried: static drove constants into them and never
// read them back.
//
// The reset gets the same treatment: it is the slot's reset from
// slot_boundary.v, held while the slot is decoupled, and rst_q takes it at the
// partition pin, so its fan-out to every register here starts inside the
// cell.  In reset the request FIFO empties and the response side gets all its
// credits back.  rst_q starts high, so a freshly configured module begins in
// reset too.
//
// See pattern_slot_core.v for the slot boundary format.  The core itself is
// AXI-Stream with tready; the credit ends here stand between it and the pins.

(* DONT_TOUCH = "yes" *)
module pattern_slot #(
    parameter integer AXIS_DATA_W = 512 + 1 + 32,
    parameter integer KEEP_W      = 1,
    parameter integer TDEST_W     = 1,
    parameter integer TID_W       = 1,
    parameter integer USER_W      = 1
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

    reg rst_q = 1'b1;
    always @(posedge clk) rst_q <= rst;

    // request: boundary -> req_inst -> core
    wire [AXIS_DATA_W-1:0] req_tdata;
    wire                   req_tvalid, req_tready, req_tlast;

    // response: core -> resp_inst -> boundary
    wire [AXIS_DATA_W-1:0] resp_tdata;
    wire                   resp_tvalid, resp_tready, resp_tlast;

    slot_credit_sink #(
        .DATA_W(AXIS_DATA_W)
    ) req_inst (
        .clk          (clk),
        .rst          (rst_q),
        .in_tdata     (s_axis_tdata),
        .in_tvalid    (s_axis_tvalid),
        .in_tlast     (s_axis_tlast),
        .out_credit   (s_axis_credit),
        .m_axis_tdata (req_tdata),
        .m_axis_tvalid(req_tvalid),
        .m_axis_tready(req_tready),
        .m_axis_tlast (req_tlast)
    );

    pattern_slot_core #(
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
        .s_axis_tdest ({TDEST_W{1'b0}}),
        .s_axis_tid   ({TID_W{1'b0}}),
        .s_axis_tuser ({USER_W{1'b0}}),
        .m_axis_tdata (resp_tdata),
        .m_axis_tkeep (),
        .m_axis_tstrb (),
        .m_axis_tvalid(resp_tvalid),
        .m_axis_tready(resp_tready),
        .m_axis_tlast (resp_tlast),
        .m_axis_tdest (),
        .m_axis_tid   (),
        .m_axis_tuser ()
    );

    slot_credit_source #(
        .DATA_W(AXIS_DATA_W)
    ) resp_inst (
        .clk          (clk),
        .rst          (rst_q),
        .s_axis_tdata (resp_tdata),
        .s_axis_tvalid(resp_tvalid),
        .s_axis_tready(resp_tready),
        .s_axis_tlast (resp_tlast),
        .out_tdata    (m_axis_tdata),
        .out_tvalid   (m_axis_tvalid),
        .out_tlast    (m_axis_tlast),
        .in_credit    (m_axis_credit)
    );

endmodule

`resetall
