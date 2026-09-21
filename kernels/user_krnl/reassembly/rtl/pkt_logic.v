`timescale 1ns / 1ps

module pkt_logic #(
    parameter PATTERN_APP = 16'h0000,
    parameter OR_APP = 16'h0001,
    parameter C02_APP = 16'h0002,
    parameter RECONF_APP = 16'h00ab,
    parameter integer APP_DELAY_CYCLES = 16,
    parameter integer SLOT_COUNT = 3
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

    localparam integer PR_AXIS_PIPELINE_LENGTH = 10;
    // Per-slot request FIFO depth, in 512-bit beats. Must be at least the
    // largest request a slot accepts (norm's MAX_LINES = 256 beats).
    localparam integer SLOT_RX_FIFO_DEPTH = 512;

    wire [512 + 32 + 32 + 16:0] dispatcher_tdata;
    wire                         dispatcher_tvalid;
    wire                         dispatcher_tready;
    wire                         scheduler_rx_tready;

    // Dispatcher request-framing state, for the static ILA only. The workload
    // field is the same slice the dispatcher cuts from its own rx_tdata; it is
    // read here rather than exported, so the dispatcher needs no port for it.
    wire         disp_expecting_header;
    wire         disp_config_header_line;
    wire [15:0]  disp_header_workload = pkt_rx_tdata[511:496];
    wire [19:0]  disp_request_bytes_remaining;

    dispatcher dispatcher_inst (
        .clk(clk),
        .rst(rst),
        .rx_tdata(pkt_rx_tdata),
        .rx_tvalid(pkt_rx_tvalid),
        .rx_tready(pkt_rx_tready),
        .tx_tdata(dispatcher_tdata),
        .tx_tvalid(dispatcher_tvalid),
        .tx_tready(dispatcher_tready),
        .dbg_expecting_header(disp_expecting_header),
        .dbg_config_header_line(disp_config_header_line),
        .dbg_request_bytes_remaining(disp_request_bytes_remaining)
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
    wire [31:0]  app_rx_meta = scheduler_tdata[512+32:512+1];
    wire [15:0]  app_rx_workload = scheduler_tdata[512+32+16:512+32+1];
    wire         app_rx_req_last = scheduler_tdata[512+32+16+16+1];

    wire pattern_rx_ready;
    wire or_rx_ready;
    wire c02_rx_ready;
    wire reconf_rx_ready;

    reg  reconf_seen_header = 1'b0;
    reg  reconf_drain_packet = 1'b0;

    wire reconf_header_line = dispatcher_reconf_selected && !reconf_seen_header;
    wire reconf_payload_line = dispatcher_reconf_selected && reconf_seen_header;
    wire reconf_forward_line = reconf_payload_line && !reconf_drain_packet;

    wire pattern_rx_valid = scheduler_tvalid && (app_rx_workload != OR_APP) && (app_rx_workload != C02_APP);
    wire or_rx_valid = scheduler_tvalid && (app_rx_workload == OR_APP);
    wire c02_rx_valid = scheduler_tvalid && (app_rx_workload == C02_APP);
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

    // The ICAPE3 pins as the primitive actually sees them, for the static ILA.
    wire         icap_csib;
    wire         icap_rdwrb;
    wire [31:0]  icap_o;

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

    always @* begin
        if (app_rx_workload == OR_APP) begin
            scheduler_tready = or_rx_ready;
        end else if (app_rx_workload == C02_APP) begin
            scheduler_tready = c02_rx_ready;
        end else begin
            scheduler_tready = pattern_rx_ready;
        end
    end

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
        .avail(icap_avail),
        .icap_csib(icap_csib),
        .icap_rdwrb(icap_rdwrb),
        .icap_o(icap_o)
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

    wire [512:0] pattern_tx_payload;
    wire         pattern_tx_valid;
    wire         pattern_tx_ready;
    wire         pattern_switch_ready;
    wire [31:0]  pattern_tx_meta;
    wire         pattern_meta_s_ready;
    wire         pattern_meta_valid;
    wire         pattern_meta_ready;
    reg          pattern_rx_in_frame = 1'b0;
    wire         pattern_app_ready;
    wire [511:0]   pattern_decoupled_tdata;
    wire         pattern_decoupled_tvalid;
    wire         pattern_decoupled_tready;
    wire         pattern_decoupled_tlast;
    wire [511:0]   pattern_pr_rx_tdata;
    wire         pattern_pr_rx_tvalid;
    wire         pattern_pr_rx_tready;
    wire         pattern_pr_rx_tlast;
    wire [511:0]   pattern_pr_tx_tdata;
    wire         pattern_pr_tx_tvalid;
    wire         pattern_pr_tx_tready;
    wire         pattern_pr_tx_tlast;
    wire [511:0]   pattern_slot_tx_data_raw;
    wire         pattern_slot_tx_valid_raw;
    wire         pattern_slot_tx_ready_raw;
    wire         pattern_slot_tx_last_raw;
    wire [511:0]   pattern_tx_decoupled_tdata;
    wire         pattern_tx_decoupled_tvalid;
    wire         pattern_tx_decoupled_tready;
    wire         pattern_tx_decoupled_tlast;
    wire [511:0]   pattern_slot_tx_data;
    wire         pattern_slot_tx_last;

    wire [511:0] pattern_ff_tdata;
    wire         pattern_ff_tvalid;
    wire         pattern_ff_tlast;
    wire         pattern_ff_s_tready;

    assign pattern_rx_ready = pattern_ff_s_tready && (pattern_rx_in_frame || pattern_meta_s_ready);
    assign pattern_tx_payload = {pattern_slot_tx_last, pattern_slot_tx_data};
    assign pattern_tx_ready = pattern_slot_tx_last ? (pattern_meta_valid && pattern_switch_ready) : 1'b1;
    assign pattern_meta_ready = pattern_tx_valid && pattern_slot_tx_last && pattern_switch_ready;

    always @(posedge clk) begin
        if (rst) begin
            pattern_rx_in_frame <= 1'b0;
        end else if (pattern_rx_valid && pattern_rx_ready) begin
            pattern_rx_in_frame <= !app_rx_req_last;
        end
    end

    axis_fifo_taxi #(
        .DATA_WIDTH(32),
        .DEPTH(32)
    ) pattern_meta_fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(app_rx_meta),
        .s_axis_tvalid(pattern_rx_valid && pattern_rx_ready && !pattern_rx_in_frame),
        .s_axis_tready(pattern_meta_s_ready),
        .m_axis_tdata(pattern_tx_meta),
        .m_axis_tvalid(pattern_meta_valid),
        .m_axis_tready(pattern_meta_ready)
    );

    axis_frame_fifo_taxi #(
        .DATA_WIDTH(512),
        .DEPTH(SLOT_RX_FIFO_DEPTH)
    ) pattern_slot_rx_fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(app_rx_payload[511:0]),
        .s_axis_tvalid(pattern_rx_valid && (pattern_rx_in_frame || pattern_meta_s_ready)),
        .s_axis_tready(pattern_ff_s_tready),
        .s_axis_tlast(app_rx_req_last),
        .m_axis_tdata(pattern_ff_tdata),
        .m_axis_tvalid(pattern_ff_tvalid),
        .m_axis_tready(pattern_decoupled_tready),
        .m_axis_tlast(pattern_ff_tlast),
        .status_overflow(),
        .status_good_frame()
    );

    axis_dfx_decoupler #(
        .DATA_W(512),
        .KEEP_W(64),
        .DEST_W(1),
        .ID_W(1),
        .USER_W(1)
    ) pattern_slot_decoupler_inst (
        .decouple(slot_decouple[0]),
        .s_axis_tdata(pattern_ff_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tstrb({64{1'b1}}),
        .s_axis_tvalid(pattern_ff_tvalid),
        .s_axis_tready(pattern_decoupled_tready),
        .s_axis_tlast(pattern_ff_tlast),
        .s_axis_tdest(1'b0),
        .s_axis_tid(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(pattern_decoupled_tdata),
        .m_axis_tkeep(),
        .m_axis_tstrb(),
        .m_axis_tvalid(pattern_decoupled_tvalid),
        .m_axis_tready(pattern_app_ready),
        .m_axis_tlast(pattern_decoupled_tlast),
        .m_axis_tdest(),
        .m_axis_tid(),
        .m_axis_tuser()
    );

    axis_pipeline_register #(
        .DATA_WIDTH(512),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(64),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .ID_WIDTH(1),
        .DEST_ENABLE(0),
        .DEST_WIDTH(1),
        .USER_ENABLE(0),
        .USER_WIDTH(1),
        .REG_TYPE(2),
        .LENGTH(PR_AXIS_PIPELINE_LENGTH)
    ) pattern_slot_pr_in_pipe_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(pattern_decoupled_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tvalid(pattern_decoupled_tvalid),
        .s_axis_tready(pattern_app_ready),
        .s_axis_tlast(pattern_decoupled_tlast),
        .s_axis_tid(1'b0),
        .s_axis_tdest(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(pattern_pr_rx_tdata),
        .m_axis_tkeep(),
        .m_axis_tvalid(pattern_pr_rx_tvalid),
        .m_axis_tready(pattern_pr_rx_tready),
        .m_axis_tlast(pattern_pr_rx_tlast),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    cell_bbx #(
        .AXIS_DATA_W(512),
        .KEEP_W(64),
        .TDEST_W(1),
        .TID_W(1),
        .USER_W(1)
    ) c00_bbx_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(pattern_pr_rx_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tstrb({64{1'b1}}),
        .s_axis_tvalid(pattern_pr_rx_tvalid),
        .s_axis_tready(pattern_pr_rx_tready),
        .s_axis_tlast(pattern_pr_rx_tlast),
        .s_axis_tdest(1'b0),
        .s_axis_tid(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(pattern_pr_tx_tdata),
        .m_axis_tkeep(),
        .m_axis_tstrb(),
        .m_axis_tvalid(pattern_pr_tx_tvalid),
        .m_axis_tready(pattern_pr_tx_tready),
        .m_axis_tlast(pattern_pr_tx_tlast),
        .m_axis_tdest(),
        .m_axis_tid(),
        .m_axis_tuser()
    );

    axis_pipeline_register #(
        .DATA_WIDTH(512),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(64),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .ID_WIDTH(1),
        .DEST_ENABLE(0),
        .DEST_WIDTH(1),
        .USER_ENABLE(0),
        .USER_WIDTH(1),
        .REG_TYPE(2),
        .LENGTH(PR_AXIS_PIPELINE_LENGTH)
    ) pattern_slot_pr_out_pipe_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(pattern_pr_tx_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tvalid(pattern_pr_tx_tvalid),
        .s_axis_tready(pattern_pr_tx_tready),
        .s_axis_tlast(pattern_pr_tx_tlast),
        .s_axis_tid(1'b0),
        .s_axis_tdest(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(pattern_slot_tx_data_raw),
        .m_axis_tkeep(),
        .m_axis_tvalid(pattern_slot_tx_valid_raw),
        .m_axis_tready(pattern_slot_tx_ready_raw),
        .m_axis_tlast(pattern_slot_tx_last_raw),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    axis_dfx_decoupler #(
        .DATA_W(512),
        .KEEP_W(64),
        .DEST_W(1),
        .ID_W(1),
        .USER_W(1)
    ) pattern_slot_tx_decoupler_inst (
        .decouple(slot_decouple[0]),
        .s_axis_tdata(pattern_slot_tx_data_raw),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tstrb({64{1'b1}}),
        .s_axis_tvalid(pattern_slot_tx_valid_raw),
        .s_axis_tready(pattern_slot_tx_ready_raw),
        .s_axis_tlast(pattern_slot_tx_last_raw),
        .s_axis_tdest(1'b0),
        .s_axis_tid(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(pattern_tx_decoupled_tdata),
        .m_axis_tkeep(),
        .m_axis_tstrb(),
        .m_axis_tvalid(pattern_tx_decoupled_tvalid),
        .m_axis_tready(pattern_tx_decoupled_tready),
        .m_axis_tlast(pattern_tx_decoupled_tlast),
        .m_axis_tdest(),
        .m_axis_tid(),
        .m_axis_tuser()
    );

    axis_register #(
        .DATA_WIDTH(512),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(64),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .REG_TYPE(2)
    ) pattern_slot_tx_reg_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(pattern_tx_decoupled_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tvalid(pattern_tx_decoupled_tvalid),
        .s_axis_tready(pattern_tx_decoupled_tready),
        .s_axis_tlast(pattern_tx_decoupled_tlast),
        .s_axis_tid(1'b0),
        .s_axis_tdest(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(pattern_slot_tx_data),
        .m_axis_tkeep(),
        .m_axis_tvalid(pattern_tx_valid),
        .m_axis_tready(pattern_tx_ready),
        .m_axis_tlast(pattern_slot_tx_last),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    wire [512:0] or_tx_payload;
    wire         or_tx_valid;
    wire         or_tx_ready;
    wire         or_switch_ready;
    wire [31:0]  or_tx_meta;
    wire         or_meta_s_ready;
    wire         or_meta_valid;
    wire         or_meta_ready;
    reg          or_rx_in_frame = 1'b0;
    wire         or_app_ready;
    wire [511:0]   or_decoupled_tdata;
    wire         or_decoupled_tvalid;
    wire         or_decoupled_tready;
    wire         or_decoupled_tlast;
    wire [511:0]   or_pr_rx_tdata;
    wire         or_pr_rx_tvalid;
    wire         or_pr_rx_tready;
    wire         or_pr_rx_tlast;
    wire [511:0]   or_pr_tx_tdata;
    wire         or_pr_tx_tvalid;
    wire         or_pr_tx_tready;
    wire         or_pr_tx_tlast;
    wire [511:0]   or_slot_tx_data_raw;
    wire         or_slot_tx_valid_raw;
    wire         or_slot_tx_ready_raw;
    wire         or_slot_tx_last_raw;
    wire [511:0]   or_tx_decoupled_tdata;
    wire         or_tx_decoupled_tvalid;
    wire         or_tx_decoupled_tready;
    wire         or_tx_decoupled_tlast;
    wire [511:0]   or_slot_tx_data;
    wire         or_slot_tx_last;

    wire [511:0] or_ff_tdata;
    wire         or_ff_tvalid;
    wire         or_ff_tlast;
    wire         or_ff_s_tready;

    assign or_rx_ready = or_ff_s_tready && (or_rx_in_frame || or_meta_s_ready);
    assign or_tx_payload = {or_slot_tx_last, or_slot_tx_data};
    assign or_tx_ready = or_slot_tx_last ? (or_meta_valid && or_switch_ready) : 1'b1;
    assign or_meta_ready = or_tx_valid && or_slot_tx_last && or_switch_ready;

    always @(posedge clk) begin
        if (rst) begin
            or_rx_in_frame <= 1'b0;
        end else if (or_rx_valid && or_rx_ready) begin
            or_rx_in_frame <= !app_rx_req_last;
        end
    end

    axis_fifo_taxi #(
        .DATA_WIDTH(32),
        .DEPTH(32)
    ) or_meta_fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(app_rx_meta),
        .s_axis_tvalid(or_rx_valid && or_rx_ready && !or_rx_in_frame),
        .s_axis_tready(or_meta_s_ready),
        .m_axis_tdata(or_tx_meta),
        .m_axis_tvalid(or_meta_valid),
        .m_axis_tready(or_meta_ready)
    );

    axis_frame_fifo_taxi #(
        .DATA_WIDTH(512),
        .DEPTH(SLOT_RX_FIFO_DEPTH)
    ) or_slot_rx_fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(app_rx_payload[511:0]),
        .s_axis_tvalid(or_rx_valid && (or_rx_in_frame || or_meta_s_ready)),
        .s_axis_tready(or_ff_s_tready),
        .s_axis_tlast(app_rx_req_last),
        .m_axis_tdata(or_ff_tdata),
        .m_axis_tvalid(or_ff_tvalid),
        .m_axis_tready(or_decoupled_tready),
        .m_axis_tlast(or_ff_tlast),
        .status_overflow(),
        .status_good_frame()
    );

    axis_dfx_decoupler #(
        .DATA_W(512),
        .KEEP_W(64),
        .DEST_W(1),
        .ID_W(1),
        .USER_W(1)
    ) or_slot_decoupler_inst (
        .decouple(slot_decouple[1]),
        .s_axis_tdata(or_ff_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tstrb({64{1'b1}}),
        .s_axis_tvalid(or_ff_tvalid),
        .s_axis_tready(or_decoupled_tready),
        .s_axis_tlast(or_ff_tlast),
        .s_axis_tdest(1'b0),
        .s_axis_tid(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(or_decoupled_tdata),
        .m_axis_tkeep(),
        .m_axis_tstrb(),
        .m_axis_tvalid(or_decoupled_tvalid),
        .m_axis_tready(or_app_ready),
        .m_axis_tlast(or_decoupled_tlast),
        .m_axis_tdest(),
        .m_axis_tid(),
        .m_axis_tuser()
    );

    axis_pipeline_register #(
        .DATA_WIDTH(512),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(64),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .ID_WIDTH(1),
        .DEST_ENABLE(0),
        .DEST_WIDTH(1),
        .USER_ENABLE(0),
        .USER_WIDTH(1),
        .REG_TYPE(2),
        .LENGTH(PR_AXIS_PIPELINE_LENGTH)
    ) or_slot_pr_in_pipe_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(or_decoupled_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tvalid(or_decoupled_tvalid),
        .s_axis_tready(or_app_ready),
        .s_axis_tlast(or_decoupled_tlast),
        .s_axis_tid(1'b0),
        .s_axis_tdest(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(or_pr_rx_tdata),
        .m_axis_tkeep(),
        .m_axis_tvalid(or_pr_rx_tvalid),
        .m_axis_tready(or_pr_rx_tready),
        .m_axis_tlast(or_pr_rx_tlast),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    cell_bbx #(
        .AXIS_DATA_W(512),
        .KEEP_W(64),
        .TDEST_W(1),
        .TID_W(1),
        .USER_W(1)
    ) c01_bbx_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(or_pr_rx_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tstrb({64{1'b1}}),
        .s_axis_tvalid(or_pr_rx_tvalid),
        .s_axis_tready(or_pr_rx_tready),
        .s_axis_tlast(or_pr_rx_tlast),
        .s_axis_tdest(1'b0),
        .s_axis_tid(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(or_pr_tx_tdata),
        .m_axis_tkeep(),
        .m_axis_tstrb(),
        .m_axis_tvalid(or_pr_tx_tvalid),
        .m_axis_tready(or_pr_tx_tready),
        .m_axis_tlast(or_pr_tx_tlast),
        .m_axis_tdest(),
        .m_axis_tid(),
        .m_axis_tuser()
    );

    axis_pipeline_register #(
        .DATA_WIDTH(512),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(64),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .ID_WIDTH(1),
        .DEST_ENABLE(0),
        .DEST_WIDTH(1),
        .USER_ENABLE(0),
        .USER_WIDTH(1),
        .REG_TYPE(2),
        .LENGTH(PR_AXIS_PIPELINE_LENGTH)
    ) or_slot_pr_out_pipe_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(or_pr_tx_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tvalid(or_pr_tx_tvalid),
        .s_axis_tready(or_pr_tx_tready),
        .s_axis_tlast(or_pr_tx_tlast),
        .s_axis_tid(1'b0),
        .s_axis_tdest(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(or_slot_tx_data_raw),
        .m_axis_tkeep(),
        .m_axis_tvalid(or_slot_tx_valid_raw),
        .m_axis_tready(or_slot_tx_ready_raw),
        .m_axis_tlast(or_slot_tx_last_raw),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    axis_dfx_decoupler #(
        .DATA_W(512),
        .KEEP_W(64),
        .DEST_W(1),
        .ID_W(1),
        .USER_W(1)
    ) or_slot_tx_decoupler_inst (
        .decouple(slot_decouple[1]),
        .s_axis_tdata(or_slot_tx_data_raw),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tstrb({64{1'b1}}),
        .s_axis_tvalid(or_slot_tx_valid_raw),
        .s_axis_tready(or_slot_tx_ready_raw),
        .s_axis_tlast(or_slot_tx_last_raw),
        .s_axis_tdest(1'b0),
        .s_axis_tid(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(or_tx_decoupled_tdata),
        .m_axis_tkeep(),
        .m_axis_tstrb(),
        .m_axis_tvalid(or_tx_decoupled_tvalid),
        .m_axis_tready(or_tx_decoupled_tready),
        .m_axis_tlast(or_tx_decoupled_tlast),
        .m_axis_tdest(),
        .m_axis_tid(),
        .m_axis_tuser()
    );

    axis_register #(
        .DATA_WIDTH(512),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(64),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .REG_TYPE(2)
    ) or_slot_tx_reg_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(or_tx_decoupled_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tvalid(or_tx_decoupled_tvalid),
        .s_axis_tready(or_tx_decoupled_tready),
        .s_axis_tlast(or_tx_decoupled_tlast),
        .s_axis_tid(1'b0),
        .s_axis_tdest(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(or_slot_tx_data),
        .m_axis_tkeep(),
        .m_axis_tvalid(or_tx_valid),
        .m_axis_tready(or_tx_ready),
        .m_axis_tlast(or_slot_tx_last),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    wire [512:0] c02_tx_payload;
    wire         c02_tx_valid;
    wire         c02_tx_ready;
    wire         c02_switch_ready;
    wire [31:0]  c02_tx_meta;
    wire         c02_meta_s_ready;
    wire         c02_meta_valid;
    wire         c02_meta_ready;
    reg          c02_rx_in_frame = 1'b0;
    wire         c02_app_ready;
    wire [511:0]   c02_decoupled_tdata;
    wire         c02_decoupled_tvalid;
    wire         c02_decoupled_tready;
    wire         c02_decoupled_tlast;
    wire [511:0]   c02_pr_rx_tdata;
    wire         c02_pr_rx_tvalid;
    wire         c02_pr_rx_tready;
    wire         c02_pr_rx_tlast;
    wire [511:0]   c02_pr_tx_tdata;
    wire         c02_pr_tx_tvalid;
    wire         c02_pr_tx_tready;
    wire         c02_pr_tx_tlast;
    wire [511:0]   c02_slot_tx_data_raw;
    wire         c02_slot_tx_valid_raw;
    wire         c02_slot_tx_ready_raw;
    wire         c02_slot_tx_last_raw;
    wire [511:0]   c02_tx_decoupled_tdata;
    wire         c02_tx_decoupled_tvalid;
    wire         c02_tx_decoupled_tready;
    wire         c02_tx_decoupled_tlast;
    wire [511:0]   c02_slot_tx_data;
    wire         c02_slot_tx_last;

    wire [511:0] c02_ff_tdata;
    wire         c02_ff_tvalid;
    wire         c02_ff_tlast;
    wire         c02_ff_s_tready;

    assign c02_rx_ready = c02_ff_s_tready && (c02_rx_in_frame || c02_meta_s_ready);
    assign c02_tx_payload = {c02_slot_tx_last, c02_slot_tx_data};
    assign c02_tx_ready = c02_slot_tx_last ? (c02_meta_valid && c02_switch_ready) : 1'b1;
    assign c02_meta_ready = c02_tx_valid && c02_slot_tx_last && c02_switch_ready;

    always @(posedge clk) begin
        if (rst) begin
            c02_rx_in_frame <= 1'b0;
        end else if (c02_rx_valid && c02_rx_ready) begin
            c02_rx_in_frame <= !app_rx_req_last;
        end
    end

    axis_fifo_taxi #(
        .DATA_WIDTH(32),
        .DEPTH(32)
    ) c02_meta_fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(app_rx_meta),
        .s_axis_tvalid(c02_rx_valid && c02_rx_ready && !c02_rx_in_frame),
        .s_axis_tready(c02_meta_s_ready),
        .m_axis_tdata(c02_tx_meta),
        .m_axis_tvalid(c02_meta_valid),
        .m_axis_tready(c02_meta_ready)
    );

    axis_frame_fifo_taxi #(
        .DATA_WIDTH(512),
        .DEPTH(SLOT_RX_FIFO_DEPTH)
    ) c02_slot_rx_fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(app_rx_payload[511:0]),
        .s_axis_tvalid(c02_rx_valid && (c02_rx_in_frame || c02_meta_s_ready)),
        .s_axis_tready(c02_ff_s_tready),
        .s_axis_tlast(app_rx_req_last),
        .m_axis_tdata(c02_ff_tdata),
        .m_axis_tvalid(c02_ff_tvalid),
        .m_axis_tready(c02_decoupled_tready),
        .m_axis_tlast(c02_ff_tlast),
        .status_overflow(),
        .status_good_frame()
    );

    axis_dfx_decoupler #(
        .DATA_W(512),
        .KEEP_W(64),
        .DEST_W(1),
        .ID_W(1),
        .USER_W(1)
    ) c02_slot_decoupler_inst (
        .decouple(slot_decouple[2]),
        .s_axis_tdata(c02_ff_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tstrb({64{1'b1}}),
        .s_axis_tvalid(c02_ff_tvalid),
        .s_axis_tready(c02_decoupled_tready),
        .s_axis_tlast(c02_ff_tlast),
        .s_axis_tdest(1'b0),
        .s_axis_tid(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(c02_decoupled_tdata),
        .m_axis_tkeep(),
        .m_axis_tstrb(),
        .m_axis_tvalid(c02_decoupled_tvalid),
        .m_axis_tready(c02_app_ready),
        .m_axis_tlast(c02_decoupled_tlast),
        .m_axis_tdest(),
        .m_axis_tid(),
        .m_axis_tuser()
    );

    axis_pipeline_register #(
        .DATA_WIDTH(512),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(64),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .ID_WIDTH(1),
        .DEST_ENABLE(0),
        .DEST_WIDTH(1),
        .USER_ENABLE(0),
        .USER_WIDTH(1),
        .REG_TYPE(2),
        .LENGTH(PR_AXIS_PIPELINE_LENGTH)
    ) c02_slot_pr_in_pipe_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(c02_decoupled_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tvalid(c02_decoupled_tvalid),
        .s_axis_tready(c02_app_ready),
        .s_axis_tlast(c02_decoupled_tlast),
        .s_axis_tid(1'b0),
        .s_axis_tdest(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(c02_pr_rx_tdata),
        .m_axis_tkeep(),
        .m_axis_tvalid(c02_pr_rx_tvalid),
        .m_axis_tready(c02_pr_rx_tready),
        .m_axis_tlast(c02_pr_rx_tlast),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    cell_bbx #(
        .AXIS_DATA_W(512),
        .KEEP_W(64),
        .TDEST_W(1),
        .TID_W(1),
        .USER_W(1)
    ) c02_bbx_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(c02_pr_rx_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tstrb({64{1'b1}}),
        .s_axis_tvalid(c02_pr_rx_tvalid),
        .s_axis_tready(c02_pr_rx_tready),
        .s_axis_tlast(c02_pr_rx_tlast),
        .s_axis_tdest(1'b0),
        .s_axis_tid(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(c02_pr_tx_tdata),
        .m_axis_tkeep(),
        .m_axis_tstrb(),
        .m_axis_tvalid(c02_pr_tx_tvalid),
        .m_axis_tready(c02_pr_tx_tready),
        .m_axis_tlast(c02_pr_tx_tlast),
        .m_axis_tdest(),
        .m_axis_tid(),
        .m_axis_tuser()
    );

    axis_pipeline_register #(
        .DATA_WIDTH(512),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(64),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .ID_WIDTH(1),
        .DEST_ENABLE(0),
        .DEST_WIDTH(1),
        .USER_ENABLE(0),
        .USER_WIDTH(1),
        .REG_TYPE(2),
        .LENGTH(PR_AXIS_PIPELINE_LENGTH)
    ) c02_slot_pr_out_pipe_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(c02_pr_tx_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tvalid(c02_pr_tx_tvalid),
        .s_axis_tready(c02_pr_tx_tready),
        .s_axis_tlast(c02_pr_tx_tlast),
        .s_axis_tid(1'b0),
        .s_axis_tdest(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(c02_slot_tx_data_raw),
        .m_axis_tkeep(),
        .m_axis_tvalid(c02_slot_tx_valid_raw),
        .m_axis_tready(c02_slot_tx_ready_raw),
        .m_axis_tlast(c02_slot_tx_last_raw),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    axis_dfx_decoupler #(
        .DATA_W(512),
        .KEEP_W(64),
        .DEST_W(1),
        .ID_W(1),
        .USER_W(1)
    ) c02_slot_tx_decoupler_inst (
        .decouple(slot_decouple[2]),
        .s_axis_tdata(c02_slot_tx_data_raw),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tstrb({64{1'b1}}),
        .s_axis_tvalid(c02_slot_tx_valid_raw),
        .s_axis_tready(c02_slot_tx_ready_raw),
        .s_axis_tlast(c02_slot_tx_last_raw),
        .s_axis_tdest(1'b0),
        .s_axis_tid(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(c02_tx_decoupled_tdata),
        .m_axis_tkeep(),
        .m_axis_tstrb(),
        .m_axis_tvalid(c02_tx_decoupled_tvalid),
        .m_axis_tready(c02_tx_decoupled_tready),
        .m_axis_tlast(c02_tx_decoupled_tlast),
        .m_axis_tdest(),
        .m_axis_tid(),
        .m_axis_tuser()
    );

    axis_register #(
        .DATA_WIDTH(512),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(64),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .REG_TYPE(2)
    ) c02_slot_tx_reg_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(c02_tx_decoupled_tdata),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tvalid(c02_tx_decoupled_tvalid),
        .s_axis_tready(c02_tx_decoupled_tready),
        .s_axis_tlast(c02_tx_decoupled_tlast),
        .s_axis_tid(1'b0),
        .s_axis_tdest(1'b0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(c02_slot_tx_data),
        .m_axis_tkeep(),
        .m_axis_tvalid(c02_tx_valid),
        .m_axis_tready(c02_tx_ready),
        .m_axis_tlast(c02_slot_tx_last),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    slot_tx_axis_switch #(
        .DATA_W(545),
        .TLAST_IDX(512)
    ) slot_tx_axis_switch_inst (
        .clk(clk),
        .rst(rst),
        .s00_axis_tdata({pattern_tx_meta, pattern_tx_payload}),
        .s00_axis_tvalid(pattern_tx_valid && pattern_slot_tx_last && pattern_meta_valid),
        .s00_axis_tready(pattern_switch_ready),
        .s01_axis_tdata({or_tx_meta, or_tx_payload}),
        .s01_axis_tvalid(or_tx_valid && or_slot_tx_last && or_meta_valid),
        .s01_axis_tready(or_switch_ready),
        .s02_axis_tdata({c02_tx_meta, c02_tx_payload}),
        .s02_axis_tvalid(c02_tx_valid && c02_slot_tx_last && c02_meta_valid),
        .s02_axis_tready(c02_switch_ready),
        .s03_axis_tdata({reconf_tx_meta, reconf_tx_tlast, reconf_tx_tdata}),
        .s03_axis_tvalid(reconf_tx_tvalid),
        .s03_axis_tready(reconf_tx_tready),
        .m_axis_tdata(pkt_tx_tdata),
        .m_axis_tvalid(pkt_tx_tvalid),
        .m_axis_tready(pkt_tx_tready)
    );

`ifndef SIMULATION
    // Static-only. Every net below is driven or loaded in the static region:
    // the cell handshakes are the partition-pin nets at each cNN_bbx_inst, not
    // anything inside one. An ILA net reaching into a reconfigurable partition
    // would break DFX, so none of these may be moved inward.
    ila_icap ila_icap_inst (
        .clk(clk),
        // --- reconfctrl -> ICAP stream -----------------------------------
        .probe0(reconf_axis_icap_tvalid),
        .probe1(reconf_axis_icap_tready),
        .probe2(reconf_axis_icap_tdata),
        .probe3(reconf_axis_icap_tlast),
        .probe4(icap_pr_done),
        .probe5(icap_pr_err),
        .probe6(icap_avail),
        .probe7(slot_decouple),
        .probe8(reconf_active),
        .probe9(reconf_active_slot_id),
        .probe10(reconf_last_slot_id),
        .probe11(reconf_cycles),
        .probe12(reconf_last_cycles),
        .probe13(reconf_state),
        .probe14(reconf_last_error),
        // --- the ICAPE3 pins themselves ----------------------------------
        .probe15(icap_csib),
        .probe16(icap_rdwrb),
        .probe17(icap_o),
        // --- slot boundary handshakes, static side of each partition -----
        .probe18(pattern_pr_rx_tvalid),   // c00 s_axis_tvalid
        .probe19(pattern_pr_rx_tready),   // c00 s_axis_tready
        .probe20(pattern_pr_tx_tvalid),   // c00 m_axis_tvalid
        .probe21(pattern_pr_tx_tready),   // c00 m_axis_tready
        .probe22(or_pr_rx_tvalid),        // c01 s_axis_tvalid
        .probe23(or_pr_rx_tready),        // c01 s_axis_tready
        .probe24(or_pr_tx_tvalid),        // c01 m_axis_tvalid
        .probe25(or_pr_tx_tready),        // c01 m_axis_tready
        .probe26(c02_pr_rx_tvalid),       // c02 s_axis_tvalid
        .probe27(c02_pr_rx_tready),       // c02 s_axis_tready
        .probe28(c02_pr_tx_tvalid),       // c02 m_axis_tvalid
        .probe29(c02_pr_tx_tready),       // c02 m_axis_tready
        // --- dispatcher request framing ----------------------------------
        .probe30(disp_expecting_header),
        .probe31(disp_config_header_line),
        .probe32(disp_header_workload),
        .probe33(disp_request_bytes_remaining),
        .probe34(pkt_rx_tvalid),
        .probe35(pkt_rx_tready)
    );
`endif

endmodule
