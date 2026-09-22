`resetall
`timescale 1ns / 1ps
`default_nettype none

module slot_tx_axis_switch #(
    parameter int DATA_W = 545,
    parameter int TLAST_IDX = 512
) (
    input  wire              clk,
    input  wire              rst,

    input  wire [DATA_W-1:0] s00_axis_tdata,
    input  wire              s00_axis_tvalid,
    output wire              s00_axis_tready,

    input  wire [DATA_W-1:0] s01_axis_tdata,
    input  wire              s01_axis_tvalid,
    output wire              s01_axis_tready,

    input  wire [DATA_W-1:0] s02_axis_tdata,
    input  wire              s02_axis_tvalid,
    output wire              s02_axis_tready,

    input  wire [DATA_W-1:0] s03_axis_tdata,
    input  wire              s03_axis_tvalid,
    output wire              s03_axis_tready,

    input  wire [DATA_W-1:0] s04_axis_tdata,
    input  wire              s04_axis_tvalid,
    output wire              s04_axis_tready,

    output wire [DATA_W-1:0] m_axis_tdata,
    output wire              m_axis_tvalid,
    input  wire              m_axis_tready
);

    localparam int S_COUNT = 5;
    localparam int ID_W = $clog2(S_COUNT);

    taxi_axis_if #(
        .DATA_W(DATA_W),
        .KEEP_EN(1'b0),
        .STRB_EN(1'b0),
        .LAST_EN(1'b1),
        .ID_EN(1'b0),
        .ID_W(ID_W),
        .DEST_EN(1'b0),
        .DEST_W(1),
        .USER_EN(1'b0),
        .USER_W(1)
    ) s_axis[5]();

    taxi_axis_if #(
        .DATA_W(DATA_W),
        .KEEP_EN(1'b0),
        .STRB_EN(1'b0),
        .LAST_EN(1'b1),
        .ID_EN(1'b0),
        .ID_W(ID_W),
        .DEST_EN(1'b0),
        .DEST_W(1),
        .USER_EN(1'b0),
        .USER_W(1)
    ) m_axis[1]();

    assign s_axis[0].tdata = s00_axis_tdata;
    assign s_axis[0].tkeep = '1;
    assign s_axis[0].tstrb = '1;
    assign s_axis[0].tvalid = s00_axis_tvalid;
    assign s_axis[0].tlast = s00_axis_tdata[TLAST_IDX];
    assign s_axis[0].tid = '0;
    assign s_axis[0].tdest = '0;
    assign s_axis[0].tuser = '0;
    assign s00_axis_tready = s_axis[0].tready;

    assign s_axis[1].tdata = s01_axis_tdata;
    assign s_axis[1].tkeep = '1;
    assign s_axis[1].tstrb = '1;
    assign s_axis[1].tvalid = s01_axis_tvalid;
    assign s_axis[1].tlast = s01_axis_tdata[TLAST_IDX];
    assign s_axis[1].tid = '0;
    assign s_axis[1].tdest = '0;
    assign s_axis[1].tuser = '0;
    assign s01_axis_tready = s_axis[1].tready;

    assign s_axis[2].tdata = s02_axis_tdata;
    assign s_axis[2].tkeep = '1;
    assign s_axis[2].tstrb = '1;
    assign s_axis[2].tvalid = s02_axis_tvalid;
    assign s_axis[2].tlast = s02_axis_tdata[TLAST_IDX];
    assign s_axis[2].tid = '0;
    assign s_axis[2].tdest = '0;
    assign s_axis[2].tuser = '0;
    assign s02_axis_tready = s_axis[2].tready;

    assign s_axis[3].tdata = s03_axis_tdata;
    assign s_axis[3].tkeep = '1;
    assign s_axis[3].tstrb = '1;
    assign s_axis[3].tvalid = s03_axis_tvalid;
    assign s_axis[3].tlast = s03_axis_tdata[TLAST_IDX];
    assign s_axis[3].tid = '0;
    assign s_axis[3].tdest = '0;
    assign s_axis[3].tuser = '0;
    assign s03_axis_tready = s_axis[3].tready;

    assign s_axis[4].tdata = s04_axis_tdata;
    assign s_axis[4].tkeep = '1;
    assign s_axis[4].tstrb = '1;
    assign s_axis[4].tvalid = s04_axis_tvalid;
    assign s_axis[4].tlast = s04_axis_tdata[TLAST_IDX];
    assign s_axis[4].tid = '0;
    assign s_axis[4].tdest = '0;
    assign s_axis[4].tuser = '0;
    assign s04_axis_tready = s_axis[4].tready;

    assign m_axis_tdata = m_axis[0].tdata;
    assign m_axis_tvalid = m_axis[0].tvalid;
    assign m_axis[0].tready = m_axis_tready;

    taxi_axis_switch #(
        .S_COUNT(S_COUNT),
        .M_COUNT(1),
        .S_REG_TYPE(0),
        .M_REG_TYPE(2),
        .UPDATE_TID(1'b0),
        .ARB_ROUND_ROBIN(1'b0),
        .ARB_LSB_HIGH_PRIO(1'b1)
    ) taxi_axis_switch_inst (
        .clk(clk),
        .rst(rst),
        .s_axis(s_axis),
        .m_axis(m_axis)
    );

endmodule

`resetall
