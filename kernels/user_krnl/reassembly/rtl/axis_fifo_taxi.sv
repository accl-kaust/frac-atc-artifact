`timescale 1ns / 1ps

module axis_fifo_taxi #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH = 16,
    parameter integer RAM_PIPELINE = 1,
    parameter OUTPUT_FIFO_EN = 1'b0
) (
    input  wire                  clk,
    input  wire                  rst,

    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,

    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire [DATA_WIDTH-1:0] m_axis_tdata
);

    localparam integer KEEP_WIDTH = (DATA_WIDTH + 7) / 8;

    taxi_axis_if #(
        .DATA_W(DATA_WIDTH),
        .KEEP_W(KEEP_WIDTH),
        .KEEP_EN(1'b0),
        .STRB_EN(1'b0),
        .LAST_EN(1'b0),
        .ID_EN(1'b0),
        .DEST_EN(1'b0),
        .USER_EN(1'b0)
    ) s_axis_if();

    taxi_axis_if #(
        .DATA_W(DATA_WIDTH),
        .KEEP_W(KEEP_WIDTH),
        .KEEP_EN(1'b0),
        .STRB_EN(1'b0),
        .LAST_EN(1'b0),
        .ID_EN(1'b0),
        .DEST_EN(1'b0),
        .USER_EN(1'b0)
    ) m_axis_if();

    assign s_axis_if.tdata = s_axis_tdata;
    assign s_axis_if.tkeep = {KEEP_WIDTH{1'b1}};
    assign s_axis_if.tstrb = {KEEP_WIDTH{1'b1}};
    assign s_axis_if.tlast = 1'b1;
    assign s_axis_if.tid = '0;
    assign s_axis_if.tdest = '0;
    assign s_axis_if.tuser = '0;
    assign s_axis_if.tvalid = s_axis_tvalid;
    assign s_axis_tready = s_axis_if.tready;

    assign m_axis_if.tready = m_axis_tready;
    assign m_axis_tdata = m_axis_if.tdata;
    assign m_axis_tvalid = m_axis_if.tvalid;

    taxi_axis_fifo #(
        .DEPTH(DEPTH),
        .RAM_PIPELINE(RAM_PIPELINE),
        .OUTPUT_FIFO_EN(OUTPUT_FIFO_EN),
        .FRAME_FIFO(1'b0)
    ) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis(s_axis_if),
        .m_axis(m_axis_if),
        .pause_req(1'b0),
        .pause_ack(),
        .status_depth(),
        .status_depth_commit(),
        .status_overflow(),
        .status_bad_frame(),
        .status_good_frame()
    );

endmodule
