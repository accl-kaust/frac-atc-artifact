`resetall
`timescale 1ns / 1ps
`default_nettype none

(* DONT_TOUCH = "yes" *)
module or_slot #(
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

    assign s_axis_tready = m_axis_tready;
    assign m_axis_tvalid = s_axis_tvalid;
    assign m_axis_tdata = {AXIS_DATA_W{1'b1}};
    assign m_axis_tkeep = s_axis_tkeep;
    assign m_axis_tstrb = s_axis_tstrb;
    assign m_axis_tlast = s_axis_tlast;
    assign m_axis_tdest = s_axis_tdest;
    assign m_axis_tid = s_axis_tid;
    assign m_axis_tuser = s_axis_tuser;

endmodule

`resetall
