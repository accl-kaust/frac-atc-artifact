`timescale 1ns / 1ps

module pkt_logic #(
    parameter RECONF_APP = 16'h00ab,
    parameter integer APP_DELAY_CYCLES = 16
) (
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

    // C00-C03, instantiated by name below: the PR flow finds a cell by its
    // instance name, cNN_bbx_inst.
    localparam integer SLOT_COUNT = 4;

    wire [512 + 32 + 32 + 16:0] dispatcher_tdata;
    wire                         dispatcher_tvalid;
    wire                         dispatcher_tready;
    wire                         scheduler_rx_tready;

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

    wire [512 + 16 + 32 + 16 + 1:0] scheduler_tdata;
    wire                        scheduler_tvalid;
    reg                         scheduler_tready;

    wire [512:0] dispatcher_payload = dispatcher_tdata[512:0];
    wire [31:0]  dispatcher_meta = dispatcher_tdata[512+32:512+1];
    wire [15:0]  dispatcher_workload = dispatcher_tdata[512+32+16:512+32+1];
    wire         dispatcher_reconf_selected = dispatcher_workload == RECONF_APP;

    scheduler scheduler_inst (
        .clk(clk),
        .rst(rst),
        .rx_tdata(dispatcher_tdata),
        .rx_tvalid(dispatcher_tvalid && !dispatcher_reconf_selected),
        .rx_tready(scheduler_rx_tready),
        .tx_tdata(scheduler_tdata),
        .tx_tvalid(scheduler_tvalid),
        .tx_tready(scheduler_tready)
    );

    wire [512:0] app_rx_payload = scheduler_tdata[512:0];
    wire [31:0]  app_rx_meta = scheduler_tdata[512+32:512+1]; // {request_bytes[15:0], session_id[15:0]}: upstream meta_TDATA with the whole request's size in the length field (see scheduler.v rx_req_size)
    wire [15:0]  app_rx_workload = scheduler_tdata[512+32+16:512+32+1];
    wire         app_rx_req_last = scheduler_tdata[512+32+16+16+1];

    wire reconf_rx_ready;

    reg  reconf_seen_header = 1'b0;
    reg  reconf_drain_packet = 1'b0;

    wire reconf_header_line = dispatcher_reconf_selected && !reconf_seen_header;
    wire reconf_payload_line = dispatcher_reconf_selected && reconf_seen_header;
    wire reconf_forward_line = reconf_payload_line && !reconf_drain_packet;

    wire reconf_rx_valid = dispatcher_tvalid && reconf_forward_line;

    wire [511:0] reconf_tx_tdata;
    wire [63:0]  reconf_tx_tkeep;
    wire         reconf_tx_tlast;
    wire         reconf_tx_tvalid;
    wire         reconf_tx_tready;
    wire [3:0]   reconf_state;
    wire [7:0]   reconf_last_error;
    reg  [31:0]  reconf_tx_meta = 32'd0;
    wire         reconf_axis_icap_tvalid;
    wire [31:0]  reconf_axis_icap_tdata;
    wire         reconf_axis_icap_tlast;
    wire         reconf_axis_icap_tready;
    wire         icap_pr_done;
    wire         icap_pr_err;
    wire         icap_avail;
    wire         icap_pr_done_reconf;
    wire         icap_pr_err_reconf;
    wire         icap_avail_reconf;
    (* shreg_extract = "no" *) reg icap_pr_done_reg1 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_done_reg2 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_done_reg3 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_done_reg4 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_done_reg5 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_done_reg6 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_done_reg7 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_done_reg8 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_done_reg9 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_done_reg10 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_err_reg1 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_err_reg2 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_err_reg3 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_err_reg4 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_err_reg5 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_err_reg6 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_err_reg7 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_err_reg8 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_err_reg9 = 1'b0;
    (* shreg_extract = "no" *) reg icap_pr_err_reg10 = 1'b0;
    (* shreg_extract = "no" *) reg icap_avail_reg1 = 1'b0;
    (* shreg_extract = "no" *) reg icap_avail_reg2 = 1'b0;
    (* shreg_extract = "no" *) reg icap_avail_reg3 = 1'b0;
    (* shreg_extract = "no" *) reg icap_avail_reg4 = 1'b0;
    (* shreg_extract = "no" *) reg icap_avail_reg5 = 1'b0;
    (* shreg_extract = "no" *) reg icap_avail_reg6 = 1'b0;
    (* shreg_extract = "no" *) reg icap_avail_reg7 = 1'b0;
    (* shreg_extract = "no" *) reg icap_avail_reg8 = 1'b0;
    (* shreg_extract = "no" *) reg icap_avail_reg9 = 1'b0;
    (* shreg_extract = "no" *) reg icap_avail_reg10 = 1'b0;
    wire [SLOT_COUNT-1:0] slot_decouple;
    wire         reconf_active;
    wire [7:0]   reconf_active_slot_id;
    wire [7:0]   reconf_last_slot_id;
    wire [63:0]  reconf_cycles;
    wire [63:0]  reconf_last_cycles;

    assign icap_pr_done_reconf = icap_pr_done_reg10;
    assign icap_pr_err_reconf = icap_pr_err_reg10;
    assign icap_avail_reconf = icap_avail_reg10;

    always @(posedge clk) begin
        if (rst) begin
            icap_pr_done_reg1 <= 1'b0;
            icap_pr_done_reg2 <= 1'b0;
            icap_pr_done_reg3 <= 1'b0;
            icap_pr_done_reg4 <= 1'b0;
            icap_pr_done_reg5 <= 1'b0;
            icap_pr_done_reg6 <= 1'b0;
            icap_pr_done_reg7 <= 1'b0;
            icap_pr_done_reg8 <= 1'b0;
            icap_pr_done_reg9 <= 1'b0;
            icap_pr_done_reg10 <= 1'b0;
            icap_pr_err_reg1 <= 1'b0;
            icap_pr_err_reg2 <= 1'b0;
            icap_pr_err_reg3 <= 1'b0;
            icap_pr_err_reg4 <= 1'b0;
            icap_pr_err_reg5 <= 1'b0;
            icap_pr_err_reg6 <= 1'b0;
            icap_pr_err_reg7 <= 1'b0;
            icap_pr_err_reg8 <= 1'b0;
            icap_pr_err_reg9 <= 1'b0;
            icap_pr_err_reg10 <= 1'b0;
            icap_avail_reg1 <= 1'b0;
            icap_avail_reg2 <= 1'b0;
            icap_avail_reg3 <= 1'b0;
            icap_avail_reg4 <= 1'b0;
            icap_avail_reg5 <= 1'b0;
            icap_avail_reg6 <= 1'b0;
            icap_avail_reg7 <= 1'b0;
            icap_avail_reg8 <= 1'b0;
            icap_avail_reg9 <= 1'b0;
            icap_avail_reg10 <= 1'b0;
        end else begin
            icap_pr_done_reg1 <= icap_pr_done;
            icap_pr_done_reg2 <= icap_pr_done_reg1;
            icap_pr_done_reg3 <= icap_pr_done_reg2;
            icap_pr_done_reg4 <= icap_pr_done_reg3;
            icap_pr_done_reg5 <= icap_pr_done_reg4;
            icap_pr_done_reg6 <= icap_pr_done_reg5;
            icap_pr_done_reg7 <= icap_pr_done_reg6;
            icap_pr_done_reg8 <= icap_pr_done_reg7;
            icap_pr_done_reg9 <= icap_pr_done_reg8;
            icap_pr_done_reg10 <= icap_pr_done_reg9;
            icap_pr_err_reg1 <= icap_pr_err;
            icap_pr_err_reg2 <= icap_pr_err_reg1;
            icap_pr_err_reg3 <= icap_pr_err_reg2;
            icap_pr_err_reg4 <= icap_pr_err_reg3;
            icap_pr_err_reg5 <= icap_pr_err_reg4;
            icap_pr_err_reg6 <= icap_pr_err_reg5;
            icap_pr_err_reg7 <= icap_pr_err_reg6;
            icap_pr_err_reg8 <= icap_pr_err_reg7;
            icap_pr_err_reg9 <= icap_pr_err_reg8;
            icap_pr_err_reg10 <= icap_pr_err_reg9;
            icap_avail_reg1 <= icap_avail;
            icap_avail_reg2 <= icap_avail_reg1;
            icap_avail_reg3 <= icap_avail_reg2;
            icap_avail_reg4 <= icap_avail_reg3;
            icap_avail_reg5 <= icap_avail_reg4;
            icap_avail_reg6 <= icap_avail_reg5;
            icap_avail_reg7 <= icap_avail_reg6;
            icap_avail_reg8 <= icap_avail_reg7;
            icap_avail_reg9 <= icap_avail_reg8;
            icap_avail_reg10 <= icap_avail_reg9;
        end
    end

    assign dispatcher_tready = dispatcher_reconf_selected ?
        (reconf_header_line ? (reconf_state == 4'd0) : (reconf_drain_packet ? 1'b1 : reconf_rx_ready)) :
        scheduler_rx_tready;

    reconfctrl #(
        .ADDR_WIDTH(33),
        .AXI_DATA_WIDTH(256),
        .AXIS_DATA_WIDTH(512),
        .ICAP_DATA_WIDTH(32),
        .SLOT_COUNT(SLOT_COUNT)
    ) reconfctrl_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(reconf_rx_valid),
        .s_axis_tready(reconf_rx_ready),
        .s_axis_tdata(dispatcher_payload[511:0]),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tlast(dispatcher_payload[512]),
        .m_axis_tvalid(reconf_tx_tvalid),
        .m_axis_tready(reconf_tx_tready),
        .m_axis_tdata(reconf_tx_tdata),
        .m_axis_tkeep(reconf_tx_tkeep),
        .m_axis_tlast(reconf_tx_tlast),
        .m_axis_icap_tvalid(reconf_axis_icap_tvalid),
        .m_axis_icap_tready(reconf_axis_icap_tready),
        .m_axis_icap_tdata(reconf_axis_icap_tdata),
        .m_axis_icap_tlast(reconf_axis_icap_tlast),
        .icap_pr_done(icap_pr_done_reconf),
        .icap_pr_err(icap_pr_err_reconf),
        .icap_avail(icap_avail_reconf),
        .slot_decouple(slot_decouple),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awid(m_axi_awid),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wdata_parity(m_axi_wdata_parity),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arid(m_axi_arid),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rdata_parity(m_axi_rdata_parity),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .state(reconf_state),
        .last_error(reconf_last_error),
        .reconf_active(reconf_active),
        .active_slot_id(reconf_active_slot_id),
        .last_slot_id(reconf_last_slot_id),
        .reconf_cycles(reconf_cycles),
        .last_reconf_cycles(reconf_last_cycles)
    );

    icap_ctrl #(
        .DATA_WIDTH(32)
    ) icap_ctrl_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(reconf_axis_icap_tdata),
        .s_axis_tkeep(4'hf),
        .s_axis_tlast(reconf_axis_icap_tlast),
        .s_axis_tready(reconf_axis_icap_tready),
        .s_axis_tvalid(reconf_axis_icap_tvalid),
        .pr_done(icap_pr_done),
        .pr_err(icap_pr_err),
        .avail(icap_avail)
    );

    always @(posedge clk) begin
        if (rst) begin
            reconf_seen_header <= 1'b0;
            reconf_drain_packet <= 1'b0;
            reconf_tx_meta <= 32'd0;
        end else if (dispatcher_tvalid && dispatcher_tready && reconf_header_line) begin
            reconf_tx_meta <= {16'd64, dispatcher_meta[15:0]};
            reconf_seen_header <= !dispatcher_payload[512];
            reconf_drain_packet <= 1'b0;
        end else if (dispatcher_tvalid && dispatcher_tready && reconf_payload_line && dispatcher_payload[512]) begin
            reconf_seen_header <= 1'b0;
            reconf_drain_packet <= 1'b0;
        end else if (reconf_tx_tvalid && reconf_tx_tready && reconf_tx_tlast && reconf_seen_header) begin
            reconf_drain_packet <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Accelerator slots C00-C03.
    //
    // Same data and metadata paths as the upstream offrac kernel
    // (kernel/user_krnl/offrac_krnl/src/hdl/offrac/pkt_logic.v +
    // echo_workload.v), with the workload ports flattened onto one
    // AXI-Stream so the PR cell keeps a single flat boundary:
    //
    //   tdata[544:513] = meta_TDATA      {request_bytes[15:0], session_id[15:0]}
    //   tdata[512]     = rx_TDATA[512]   tlast, in-band (tlast line duplicates it)
    //   tdata[511:0]   = rx_TDATA[511:0] payload
    //
    // meta_TDATA[31:16] is the size of the whole request (the header's
    // packet_size, put there by the scheduler), not the TCP packet's length
    // as upstream had it, so the slot can take the request length from meta.
    // Every beat of a request enters the slot.  Every beat the slot emits is
    // already {meta_TDATA_out, tlast, payload}, the format the output switch
    // and pkt_sender consume, so it is forwarded as-is (upstream pushes the
    // same word into the per-workload result FIFO); pkt_sender takes the meta
    // of the beat carrying tlast as the TCP tx metadata {length, session}.
    //
    // Workload N goes to slot N, cell C0N, for N below SLOT_COUNT; every other
    // workload but the controller's goes to C00.  The scheduler hands over
    // whole requests in order, so one waiting for a slot that cannot take it
    // holds up the rest.
    //
    // Each slot is a slot_boundary, which talks to its cell with credits
    // instead of a ready (slot_credit.v) over PIPE_LEN register stages each
    // way, then the cell.  Nothing on the way to or from a cell depends on a
    // signal coming back in the same cycle, so the stages can be spread over
    // whatever distance the cell is from here, an SLR crossing included.  The
    // round trip of a credit has to fit in the 64 the cell starts with:
    // PIPE_LEN up to 29.  The cell's reset is the slot's, held while
    // reconfctrl decouples the slot; see slot_boundary.v.
    // ------------------------------------------------------------------
    localparam integer SLOT_DATA_W = 512 + 1 + 32;

    // stages each way between a slot_boundary and its cell, C03 first
    localparam [8*SLOT_COUNT-1:0] SLOT_PIPE_LEN = {8'd16, 8'd16, 8'd16, 8'd16};

    wire [1:0]             app_slot = (app_rx_workload < SLOT_COUNT) ? app_rx_workload[1:0] : 2'd0;
    wire [SLOT_DATA_W-1:0] app_rx_tdata = {app_rx_meta, app_rx_req_last, app_rx_payload[511:0]};

    wire [SLOT_COUNT-1:0]  slot_s_tready;
    wire [SLOT_DATA_W-1:0] slot_m_tdata [0:SLOT_COUNT-1];
    wire [SLOT_COUNT-1:0]  slot_m_tvalid;
    wire [SLOT_COUNT-1:0]  slot_m_tready;

    wire [SLOT_COUNT-1:0]  cell_rst;
    wire [SLOT_DATA_W-1:0] cell_s_tdata [0:SLOT_COUNT-1];
    wire [SLOT_COUNT-1:0]  cell_s_tvalid;
    wire [SLOT_COUNT-1:0]  cell_s_tlast;
    wire [SLOT_COUNT-1:0]  cell_s_credit;
    wire [SLOT_DATA_W-1:0] cell_m_tdata [0:SLOT_COUNT-1];
    wire [SLOT_COUNT-1:0]  cell_m_tvalid;
    wire [SLOT_COUNT-1:0]  cell_m_tlast;
    wire [SLOT_COUNT-1:0]  cell_m_credit;

    always @* begin
        scheduler_tready = slot_s_tready[app_slot];
    end

    genvar slot;
    generate
        for (slot = 0; slot < SLOT_COUNT; slot = slot + 1) begin : g_slot
            slot_boundary #(
                .DATA_W(SLOT_DATA_W),
                .PIPE_LEN(SLOT_PIPE_LEN[8*slot +: 8])
            ) boundary_inst (
                .clk(clk),
                .rst(rst),
                .decouple(slot_decouple[slot]),
                .s_axis_tdata(app_rx_tdata),
                .s_axis_tvalid(scheduler_tvalid && app_slot == slot),
                .s_axis_tready(slot_s_tready[slot]),
                .s_axis_tlast(app_rx_req_last),
                .m_axis_tdata(slot_m_tdata[slot]),
                .m_axis_tvalid(slot_m_tvalid[slot]),
                .m_axis_tready(slot_m_tready[slot]),
                .m_axis_tlast(),
                .cell_rst(cell_rst[slot]),
                .cell_s_tdata(cell_s_tdata[slot]),
                .cell_s_tvalid(cell_s_tvalid[slot]),
                .cell_s_tlast(cell_s_tlast[slot]),
                .cell_s_credit(cell_s_credit[slot]),
                .cell_m_tdata(cell_m_tdata[slot]),
                .cell_m_tvalid(cell_m_tvalid[slot]),
                .cell_m_tlast(cell_m_tlast[slot]),
                .cell_m_credit(cell_m_credit[slot])
            );
        end
    endgenerate

    cell_bbx #(
        .AXIS_DATA_W(SLOT_DATA_W)
    ) c00_bbx_inst (
        .clk(clk),
        .rst(cell_rst[0]),
        .s_axis_tdata(cell_s_tdata[0]),
        .s_axis_tvalid(cell_s_tvalid[0]),
        .s_axis_tlast(cell_s_tlast[0]),
        .s_axis_credit(cell_s_credit[0]),
        .m_axis_tdata(cell_m_tdata[0]),
        .m_axis_tvalid(cell_m_tvalid[0]),
        .m_axis_tlast(cell_m_tlast[0]),
        .m_axis_credit(cell_m_credit[0])
    );

    cell_bbx #(
        .AXIS_DATA_W(SLOT_DATA_W)
    ) c01_bbx_inst (
        .clk(clk),
        .rst(cell_rst[1]),
        .s_axis_tdata(cell_s_tdata[1]),
        .s_axis_tvalid(cell_s_tvalid[1]),
        .s_axis_tlast(cell_s_tlast[1]),
        .s_axis_credit(cell_s_credit[1]),
        .m_axis_tdata(cell_m_tdata[1]),
        .m_axis_tvalid(cell_m_tvalid[1]),
        .m_axis_tlast(cell_m_tlast[1]),
        .m_axis_credit(cell_m_credit[1])
    );

    cell_bbx #(
        .AXIS_DATA_W(SLOT_DATA_W)
    ) c02_bbx_inst (
        .clk(clk),
        .rst(cell_rst[2]),
        .s_axis_tdata(cell_s_tdata[2]),
        .s_axis_tvalid(cell_s_tvalid[2]),
        .s_axis_tlast(cell_s_tlast[2]),
        .s_axis_credit(cell_s_credit[2]),
        .m_axis_tdata(cell_m_tdata[2]),
        .m_axis_tvalid(cell_m_tvalid[2]),
        .m_axis_tlast(cell_m_tlast[2]),
        .m_axis_credit(cell_m_credit[2])
    );

    cell_bbx #(
        .AXIS_DATA_W(SLOT_DATA_W)
    ) c03_bbx_inst (
        .clk(clk),
        .rst(cell_rst[3]),
        .s_axis_tdata(cell_s_tdata[3]),
        .s_axis_tvalid(cell_s_tvalid[3]),
        .s_axis_tlast(cell_s_tlast[3]),
        .s_axis_credit(cell_s_credit[3]),
        .m_axis_tdata(cell_m_tdata[3]),
        .m_axis_tvalid(cell_m_tvalid[3]),
        .m_axis_tlast(cell_m_tlast[3]),
        .m_axis_credit(cell_m_credit[3])
    );

    // Responses from the four slots and the controller's status, a frame at a
    // time.  The frame boundary the switch and pkt_sender use is the in-band
    // tdata[512], exactly as upstream.
    slot_tx_axis_switch #(
        .DATA_W(SLOT_DATA_W),
        .TLAST_IDX(512)
    ) slot_tx_axis_switch_inst (
        .clk(clk),
        .rst(rst),
        .s00_axis_tdata(slot_m_tdata[0]),
        .s00_axis_tvalid(slot_m_tvalid[0]),
        .s00_axis_tready(slot_m_tready[0]),
        .s01_axis_tdata(slot_m_tdata[1]),
        .s01_axis_tvalid(slot_m_tvalid[1]),
        .s01_axis_tready(slot_m_tready[1]),
        .s02_axis_tdata(slot_m_tdata[2]),
        .s02_axis_tvalid(slot_m_tvalid[2]),
        .s02_axis_tready(slot_m_tready[2]),
        .s03_axis_tdata(slot_m_tdata[3]),
        .s03_axis_tvalid(slot_m_tvalid[3]),
        .s03_axis_tready(slot_m_tready[3]),
        .s04_axis_tdata({reconf_tx_meta, reconf_tx_tlast, reconf_tx_tdata}),
        .s04_axis_tvalid(reconf_tx_tvalid),
        .s04_axis_tready(reconf_tx_tready),
        .m_axis_tdata(pkt_tx_tdata),
        .m_axis_tvalid(pkt_tx_tvalid),
        .m_axis_tready(pkt_tx_tready)
    );

endmodule
