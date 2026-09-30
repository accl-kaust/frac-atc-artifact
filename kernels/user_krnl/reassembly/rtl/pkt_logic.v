`timescale 1ns / 1ps

// One pattern_slot, instantiated directly: no partial reconfiguration.
//
//   pkt_rx -> dispatcher -> scheduler -> pattern_slot -> pkt_tx
//
// Every request goes to the one kernel, whatever its workload, so the
// scheduler's whole-request grant is all the steering there is.  Nothing of
// the PR slot boundary is left: no cell_bbx, no decouplers, no second slot
// or output switch, no reconfiguration controller or ICAP, and none of the
// boundary pipelines that were there to reach the cells' pblocks.
// pattern_slot keeps a skid buffer on each side, so the scheduler's output
// FIFO, the kernel and pkt_sender's FIFOs still meet at flops.
//
// The kernel sees the same flat stream a PR cell did (pattern_slot_core.v):
//
//   tdata[544:513] = meta_TDATA      {request_bytes[15:0], session_id[15:0]}
//   tdata[512]     = tlast, in-band  (the request's last beat)
//   tdata[511:0]   = payload
//
// meta_TDATA[31:16] is the size of the whole request (the header's
// packet_size, see scheduler.v rx_req_size).  The echo sends every beat back
// with the meta unchanged, which is the format pkt_sender consumes: it takes
// the meta of the beat carrying tlast as the TCP tx metadata {length,
// session}.
//
// m_axi, the HBM master the reconfiguration controller drove, stays on the
// port list so tcp_top_loopback, user_krnl and frac_hbm are unchanged.  It is
// tied off: nothing is ever requested, and a response would be taken.

module pkt_logic (
    input  wire                     clk,
    input  wire                     rst,
    input  wire [512+88-1 + 1 : 0]  pkt_rx_tdata,
    input  wire                     pkt_rx_tvalid,
    output wire                     pkt_rx_tready,
    output wire [512+32-1 + 1: 0]   pkt_tx_tdata,
    output wire                     pkt_tx_tvalid,
    input  wire                     pkt_tx_tready,

    output wire [32:0]              m_axi_awaddr,
    output wire [1:0]               m_axi_awburst,
    output wire [5:0]               m_axi_awid,
    output wire [7:0]               m_axi_awlen,
    output wire [2:0]               m_axi_awsize,
    output wire                     m_axi_awvalid,
    input  wire                     m_axi_awready,
    output wire [255:0]             m_axi_wdata,
    output wire [31:0]              m_axi_wstrb,
    output wire [31:0]              m_axi_wdata_parity,
    output wire                     m_axi_wlast,
    output wire                     m_axi_wvalid,
    input  wire                     m_axi_wready,
    input  wire [5:0]               m_axi_bid,
    input  wire [1:0]               m_axi_bresp,
    input  wire                     m_axi_bvalid,
    output wire                     m_axi_bready,
    output wire [32:0]              m_axi_araddr,
    output wire [1:0]               m_axi_arburst,
    output wire [5:0]               m_axi_arid,
    output wire [7:0]               m_axi_arlen,
    output wire [2:0]               m_axi_arsize,
    output wire                     m_axi_arvalid,
    input  wire                     m_axi_arready,
    input  wire [5:0]               m_axi_rid,
    input  wire [255:0]             m_axi_rdata,
    input  wire [31:0]              m_axi_rdata_parity,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire                     m_axi_rvalid,
    output wire                     m_axi_rready
);

    wire [512 + 32 + 32 + 16:0] dispatcher_tdata;
    wire                        dispatcher_tvalid;
    wire                        dispatcher_tready;

    dispatcher dispatcher_inst (
        .clk(clk),
        .rst(rst),
        .rx_tdata(pkt_rx_tdata),
        .rx_tvalid(pkt_rx_tvalid),
        .rx_tready(pkt_rx_tready),
        .tx_tdata(dispatcher_tdata),
        .tx_tvalid(dispatcher_tvalid),
        .tx_tready(dispatcher_tready)
    );

    // The scheduler routes a beat -- which queue, whether it ends its request
    // -- in the cycle the beat is offered, 13-14 levels deep from rx_tdata,
    // and takes it or not on the outcome.  Fed straight from the dispatcher's
    // output FIFO, that path starts at a block RAM wherever the FIFO landed;
    // this skid buffer starts it at a flop the placer can put beside the
    // scheduler, and gives the FIFO a registered ready.  One cycle of latency.
    wire [512 + 32 + 32 + 16:0] sched_rx_tdata;
    wire                        sched_rx_tvalid;
    wire                        sched_rx_tready;

    axis_pipeline_register #(
      .DATA_WIDTH(512 + 32 + 32 + 16 + 1),
      .KEEP_ENABLE(0),
      .LAST_ENABLE(0),
      .USER_ENABLE(0),
      .LENGTH(1)
    ) sched_in_reg_inst (
      .clk(clk),
      .rst(rst),
      .s_axis_tdata(dispatcher_tdata),
      .s_axis_tvalid(dispatcher_tvalid),
      .s_axis_tready(dispatcher_tready),
      .m_axis_tdata(sched_rx_tdata),
      .m_axis_tvalid(sched_rx_tvalid),
      .m_axis_tready(sched_rx_tready)
    );

    wire [512 + 16 + 32 + 16 + 1:0] scheduler_tdata;
    wire                            scheduler_tvalid;
    wire                            scheduler_tready;

    scheduler scheduler_inst (
        .clk(clk),
        .rst(rst),
        .rx_tdata(sched_rx_tdata),
        .rx_tvalid(sched_rx_tvalid),
        .rx_tready(sched_rx_tready),
        .tx_tdata(scheduler_tdata),
        .tx_tvalid(scheduler_tvalid),
        .tx_tready(scheduler_tready)
    );

    wire [511:0] app_rx_payload  = scheduler_tdata[511:0];
    wire [31:0]  app_rx_meta     = scheduler_tdata[512+32:512+1];
    wire         app_rx_req_last = scheduler_tdata[512+32+16+16+1];

    localparam integer SLOT_DATA_W = 512 + 1 + 32;

    pattern_slot #(
        .AXIS_DATA_W(SLOT_DATA_W),
        .KEEP_W(1),
        .TDEST_W(1),
        .TID_W(1),
        .USER_W(1)
    ) pattern_slot_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata({app_rx_meta, app_rx_req_last, app_rx_payload}),
        .s_axis_tkeep(1'b1),
        .s_axis_tstrb(1'b1),
        .s_axis_tvalid(scheduler_tvalid),
        .s_axis_tready(scheduler_tready),
        .s_axis_tlast(app_rx_req_last),
        .s_axis_tdest(1'b0),
        .s_axis_tid(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(pkt_tx_tdata),
        .m_axis_tkeep(),
        .m_axis_tstrb(),
        .m_axis_tvalid(pkt_tx_tvalid),
        .m_axis_tready(pkt_tx_tready),
        .m_axis_tlast(),
        .m_axis_tdest(),
        .m_axis_tid(),
        .m_axis_tuser()
    );

    assign m_axi_awaddr       = 33'd0;
    assign m_axi_awburst      = 2'd0;
    assign m_axi_awid         = 6'd0;
    assign m_axi_awlen        = 8'd0;
    assign m_axi_awsize       = 3'd0;
    assign m_axi_awvalid      = 1'b0;
    assign m_axi_wdata        = 256'd0;
    assign m_axi_wstrb        = 32'd0;
    assign m_axi_wdata_parity = 32'd0;
    assign m_axi_wlast        = 1'b0;
    assign m_axi_wvalid       = 1'b0;
    assign m_axi_bready       = 1'b1;
    assign m_axi_araddr       = 33'd0;
    assign m_axi_arburst      = 2'd0;
    assign m_axi_arid         = 6'd0;
    assign m_axi_arlen        = 8'd0;
    assign m_axi_arsize       = 3'd0;
    assign m_axi_arvalid      = 1'b0;
    assign m_axi_rready       = 1'b1;

endmodule
