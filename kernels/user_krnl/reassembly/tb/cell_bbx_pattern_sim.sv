`resetall
`timescale 1ns / 1ps
`default_nettype none

module cell_bbx #(
    parameter int AXIS_DATA_W = 512,
    parameter int KEEP_W      = AXIS_DATA_W/8,
    parameter int TDEST_W     = 3,
    parameter int TID_W       = 4,
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

    reg [7:0] response_byte = 8'h01;

    // Simulation-only stall, poked by the testbench to model a busy
    // accelerator. Defaults low, so tests that do not touch it are unaffected.
    reg stall /* verilator public_flat_rw */ = 1'b0;

    initial begin
        string inst_name;

        inst_name = $sformatf("%m");
        if (inst_name.len() >= 24 && inst_name.substr(inst_name.len()-24, inst_name.len()-13) == "c01_bbx_inst") begin
            response_byte = 8'hff;
        end
    end

    assign s_axis_tready = m_axis_tready && !stall;
    assign m_axis_tvalid = s_axis_tvalid && !stall;
    assign m_axis_tdata = {KEEP_W{response_byte}};
    assign m_axis_tkeep = s_axis_tkeep;
    assign m_axis_tstrb = s_axis_tstrb;
    assign m_axis_tlast = s_axis_tlast;
    assign m_axis_tdest = s_axis_tdest;
    assign m_axis_tid = s_axis_tid;
    assign m_axis_tuser = s_axis_tuser;

endmodule

`resetall
