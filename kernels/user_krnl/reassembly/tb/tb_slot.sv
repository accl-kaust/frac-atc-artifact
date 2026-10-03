`timescale 1ns / 1ps

// A reconfigurable module behind the static side of its slot, for the apps'
// testbenches: slot_boundary.v's request source, response sink and PIPE_LEN
// register stages each way, then the module (`SLOT_RM, e.g. +define+SLOT_RM=log)
// as it is built into a cell.  The bench drives plain AXI-Stream, as the
// scheduler and the output switch do on the board.
//
// The boundary carries {meta, tlast, payload}, tvalid and tlast only:
// tkeep, tstrb, tdest, tid and tuser stop here, as they do in static.  They
// are ports only so that cocotbext-axi finds the bus it expects.
module tb_slot #(
    parameter integer DATA_W   = 545,
    parameter integer PIPE_LEN = 16
) (
    input  wire              clk,
    input  wire              rst,
    input  wire              decouple,

    input  wire [DATA_W-1:0] s_axis_tdata,
    input  wire [0:0]        s_axis_tkeep,
    input  wire [0:0]        s_axis_tstrb,
    input  wire              s_axis_tvalid,
    output wire              s_axis_tready,
    input  wire              s_axis_tlast,

    output wire [DATA_W-1:0] m_axis_tdata,
    output wire [0:0]        m_axis_tkeep,
    output wire              m_axis_tvalid,
    input  wire              m_axis_tready,
    output wire              m_axis_tlast
);

    assign m_axis_tkeep = 1'b1;

    wire              cell_rst;
    wire [DATA_W-1:0] cell_s_tdata, cell_m_tdata;
    wire              cell_s_tvalid, cell_s_tlast, cell_s_credit;
    wire              cell_m_tvalid, cell_m_tlast, cell_m_credit;

    slot_boundary #(
        .DATA_W  (DATA_W),
        .PIPE_LEN(PIPE_LEN)
    ) boundary_inst (
        .clk          (clk),
        .rst          (rst),
        .decouple     (decouple),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (s_axis_tlast),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast),
        .cell_rst     (cell_rst),
        .cell_s_tdata (cell_s_tdata),
        .cell_s_tvalid(cell_s_tvalid),
        .cell_s_tlast (cell_s_tlast),
        .cell_s_credit(cell_s_credit),
        .cell_m_tdata (cell_m_tdata),
        .cell_m_tvalid(cell_m_tvalid),
        .cell_m_tlast (cell_m_tlast),
        .cell_m_credit(cell_m_credit)
    );

    `SLOT_RM rm_inst (
        .clk          (clk),
        .rst          (cell_rst),
        .s_axis_tdata (cell_s_tdata),
        .s_axis_tvalid(cell_s_tvalid),
        .s_axis_tlast (cell_s_tlast),
        .s_axis_credit(cell_s_credit),
        .m_axis_tdata (cell_m_tdata),
        .m_axis_tvalid(cell_m_tvalid),
        .m_axis_tlast (cell_m_tlast),
        .m_axis_credit(cell_m_credit)
    );

endmodule
