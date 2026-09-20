`timescale 1ns / 1ps

//
// axis_frame_fifo_taxi
//
// Frame-granular AXI-Stream FIFO, one per PR slot, sitting between the shared
// scheduler output and the slot boundary.
//
// axis_fifo_taxi is a plain word FIFO: it ties tlast high and runs the taxi
// core with FRAME_FIFO clear. This wrapper is the frame-mode sibling. It
// carries a real tlast and commits on frame boundaries, so:
//
//   * a request is presented to the accelerator only once all of it has been
//     written, and m_axis_tvalid is not deasserted within a frame -- the slot
//     sees a gapless request;
//   * a completed request waits here while the accelerator is busy, instead of
//     holding the shared path. Without it the slot's TREADY reaches all the way
//     back to the scheduler, so one busy slot blocks requests bound for an idle
//     one, and a partial reconfiguration (axis_dfx_decoupler drops TREADY for
//     the whole bitstream load) stalls every slot for milliseconds.
//
// DROP_WHEN_FULL and DROP_BAD_FRAME are left clear: this FIFO backpressures
// rather than discarding. DROP_OVERSIZE_FRAME is clear too, so a request larger
// than DEPTH degrades to cut-through for that frame rather than being silently
// dropped -- taxi's default for FRAME_FIFO would discard it.
//
// DEPTH is in cycles (KEEP_EN is clear) and taxi rounds it up to a power of two.
// It must be at least the largest request the slot accepts, which today is
// norm's MAX_LINES of 256 beats.
//
module axis_frame_fifo_taxi #(
    parameter integer DATA_WIDTH = 512,
    parameter integer DEPTH = 512,
    parameter integer RAM_PIPELINE = 1,
    parameter OUTPUT_FIFO_EN = 1'b0
) (
    input  wire                  clk,
    input  wire                  rst,

    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tlast,

    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire                  m_axis_tlast,

    // Observability: overflow should never fire while DROP_* are clear, so it
    // is worth bringing out to an ILA rather than leaving it unconnected.
    output wire                  status_overflow,
    output wire                  status_good_frame
);

    localparam integer KEEP_WIDTH = (DATA_WIDTH + 7) / 8;

    taxi_axis_if #(
        .DATA_W(DATA_WIDTH),
        .KEEP_W(KEEP_WIDTH),
        .KEEP_EN(1'b0),
        .STRB_EN(1'b0),
        .LAST_EN(1'b1),
        .ID_EN(1'b0),
        .DEST_EN(1'b0),
        .USER_EN(1'b0)
    ) s_axis_if();

    taxi_axis_if #(
        .DATA_W(DATA_WIDTH),
        .KEEP_W(KEEP_WIDTH),
        .KEEP_EN(1'b0),
        .STRB_EN(1'b0),
        .LAST_EN(1'b1),
        .ID_EN(1'b0),
        .DEST_EN(1'b0),
        .USER_EN(1'b0)
    ) m_axis_if();

    assign s_axis_if.tdata = s_axis_tdata;
    assign s_axis_if.tkeep = {KEEP_WIDTH{1'b1}};
    assign s_axis_if.tstrb = {KEEP_WIDTH{1'b1}};
    assign s_axis_if.tlast = s_axis_tlast;
    assign s_axis_if.tid = '0;
    assign s_axis_if.tdest = '0;
    assign s_axis_if.tuser = '0;
    assign s_axis_if.tvalid = s_axis_tvalid;
    assign s_axis_tready = s_axis_if.tready;

    assign m_axis_if.tready = m_axis_tready;
    assign m_axis_tdata = m_axis_if.tdata;
    assign m_axis_tvalid = m_axis_if.tvalid;
    assign m_axis_tlast = m_axis_if.tlast;

    taxi_axis_fifo #(
        .DEPTH(DEPTH),
        .RAM_PIPELINE(RAM_PIPELINE),
        .OUTPUT_FIFO_EN(OUTPUT_FIFO_EN),
        .FRAME_FIFO(1'b1),
        .DROP_OVERSIZE_FRAME(1'b0),
        .DROP_BAD_FRAME(1'b0),
        .DROP_WHEN_FULL(1'b0)
    ) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis(s_axis_if),
        .m_axis(m_axis_if),
        .pause_req(1'b0),
        .pause_ack(),
        .status_depth(),
        .status_depth_commit(),
        .status_overflow(status_overflow),
        .status_bad_frame(),
        .status_good_frame(status_good_frame)
    );

endmodule
