`timescale 1ns / 1ps

module pkt_logic #(
    parameter PATTERN_APP = 16'h0000,
    parameter OR_APP = 16'h0001,
    parameter RECONF_APP = 16'h00ab,
    parameter integer APP_DELAY_CYCLES = 16
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire [512+88-1 + 1 : 0]  pkt_rx_tdata,
    input  wire                     pkt_rx_tvalid,
    output wire                     pkt_rx_tready,
    output reg  [512+32-1 + 1: 0]   pkt_tx_tdata,
    output reg                      pkt_tx_tvalid,
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
    output wire                     m_axi_rready,

    output wire                     m_axis_icap_tvalid,
    input  wire                     m_axis_icap_tready,
    output wire [31:0]              m_axis_icap_tdata,
    output wire                     m_axis_icap_tlast
);

    wire [512 + 32 + 32 + 16:0] dispatcher_tdata;
    wire                         dispatcher_tvalid;
    wire                         dispatcher_tready;

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

    wire [512 + 16 + 32 + 16:0] scheduler_tdata;
    wire                        scheduler_tvalid;
    reg                         scheduler_tready;

    scheduler scheduler_inst (
        .clk(clk),
        .rst(rst),
        .rx_tdata(dispatcher_tdata),
        .rx_tvalid(dispatcher_tvalid),
        .rx_tready(dispatcher_tready),
        .tx_tdata(scheduler_tdata),
        .tx_tvalid(scheduler_tvalid),
        .tx_tready(scheduler_tready)
    );

    wire [512:0] app_rx_payload = scheduler_tdata[512:0];
    wire [31:0]  app_rx_meta = scheduler_tdata[512+32:512+1];
    wire [15:0]  app_rx_workload = scheduler_tdata[512+32+16:512+32+1];

    wire pattern_rx_ready;
    wire or_rx_ready;
    wire reconf_rx_ready;

    reg  reconf_seen_header = 1'b0;

    wire reconf_selected = app_rx_workload == RECONF_APP;
    wire reconf_header_line = reconf_selected && !reconf_seen_header;
    wire reconf_payload_line = reconf_selected && reconf_seen_header;

    wire pattern_rx_valid = scheduler_tvalid && (app_rx_workload != OR_APP) && !reconf_selected;
    wire or_rx_valid = scheduler_tvalid && (app_rx_workload == OR_APP);
    wire reconf_rx_valid = scheduler_tvalid && reconf_payload_line;

    wire [511:0] reconf_tx_tdata;
    wire [63:0]  reconf_tx_tkeep;
    wire         reconf_tx_tlast;
    wire         reconf_tx_tvalid;
    reg          reconf_tx_tready;
    wire [3:0]   reconf_state;
    wire [7:0]   reconf_last_error;
    reg  [31:0]  reconf_tx_meta = 32'd0;

    always @* begin
        if (reconf_header_line) begin
            scheduler_tready = reconf_state == 4'd0;
        end else if (reconf_payload_line) begin
            scheduler_tready = reconf_rx_ready;
        end else if (app_rx_workload == OR_APP) begin
            scheduler_tready = or_rx_ready;
        end else begin
            scheduler_tready = pattern_rx_ready;
        end
    end

    reconfctrl #(
        .ADDR_WIDTH(33),
        .AXI_DATA_WIDTH(256),
        .AXIS_DATA_WIDTH(512),
        .ICAP_DATA_WIDTH(32)
    ) reconfctrl_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(reconf_rx_valid),
        .s_axis_tready(reconf_rx_ready),
        .s_axis_tdata(app_rx_payload[511:0]),
        .s_axis_tkeep({64{1'b1}}),
        .s_axis_tlast(app_rx_payload[512]),
        .m_axis_tvalid(reconf_tx_tvalid),
        .m_axis_tready(reconf_tx_tready),
        .m_axis_tdata(reconf_tx_tdata),
        .m_axis_tkeep(reconf_tx_tkeep),
        .m_axis_tlast(reconf_tx_tlast),
        .m_axis_icap_tvalid(m_axis_icap_tvalid),
        .m_axis_icap_tready(m_axis_icap_tready),
        .m_axis_icap_tdata(m_axis_icap_tdata),
        .m_axis_icap_tlast(m_axis_icap_tlast),
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
        .last_error(reconf_last_error)
    );

    always @(posedge clk) begin
        if (rst) begin
            reconf_seen_header <= 1'b0;
            reconf_tx_meta <= 32'd0;
        end else if (scheduler_tvalid && scheduler_tready && reconf_header_line) begin
            reconf_tx_meta <= app_rx_meta;
            reconf_seen_header <= !app_rx_payload[512];
        end else if (scheduler_tvalid && scheduler_tready && reconf_payload_line && app_rx_payload[512]) begin
            reconf_seen_header <= 1'b0;
        end
    end

    wire [512:0] pattern_tx_payload;
    wire         pattern_tx_valid;
    reg          pattern_tx_ready;
    wire [31:0]  pattern_tx_meta;
    wire         pattern_meta_valid;

    dummy_delayed_app #(
        .MODE(0),
        .DELAY_CYCLES(APP_DELAY_CYCLES)
    ) pattern_app_inst (
        .clk(clk),
        .rst(rst),
        .rx_tdata(app_rx_payload),
        .rx_tvalid(pattern_rx_valid),
        .rx_tready(pattern_rx_ready),
        .meta_tdata(app_rx_meta),
        .pkt_tx_tdata_payload(pattern_tx_payload),
        .tx_data_tvalid(pattern_tx_valid),
        .tx_data_tready(pattern_tx_ready),
        .meta_tdata_out(pattern_tx_meta),
        .meta_tvalid_out(pattern_meta_valid)
    );

    wire [512:0] or_tx_payload;
    wire         or_tx_valid;
    reg          or_tx_ready;
    wire [31:0]  or_tx_meta;
    wire         or_meta_valid;

    dummy_delayed_app #(
        .MODE(1),
        .DELAY_CYCLES(APP_DELAY_CYCLES)
    ) or_app_inst (
        .clk(clk),
        .rst(rst),
        .rx_tdata(app_rx_payload),
        .rx_tvalid(or_rx_valid),
        .rx_tready(or_rx_ready),
        .meta_tdata(app_rx_meta),
        .pkt_tx_tdata_payload(or_tx_payload),
        .tx_data_tvalid(or_tx_valid),
        .tx_data_tready(or_tx_ready),
        .meta_tdata_out(or_tx_meta),
        .meta_tvalid_out(or_meta_valid)
    );

    reg output_active = 1'b0;
    reg [1:0] output_sel = 2'd0;
    reg [1:0] arb_sel;

    always @* begin
        pattern_tx_ready = 1'b0;
        or_tx_ready = 1'b0;
        reconf_tx_tready = 1'b0;
        pkt_tx_tdata = 545'd0;
        pkt_tx_tvalid = 1'b0;

        if (output_active) begin
            arb_sel = output_sel;
        end else if (pattern_tx_valid) begin
            arb_sel = 2'd0;
        end else if (or_tx_valid) begin
            arb_sel = 2'd1;
        end else begin
            arb_sel = 2'd2;
        end

        case (arb_sel)
            2'd0: begin
                pkt_tx_tdata = {pattern_tx_meta, pattern_tx_payload};
                pkt_tx_tvalid = pattern_tx_valid;
                pattern_tx_ready = pkt_tx_tready;
            end
            2'd1: begin
                pkt_tx_tdata = {or_tx_meta, or_tx_payload};
                pkt_tx_tvalid = or_tx_valid;
                or_tx_ready = pkt_tx_tready;
            end
            default: begin
                pkt_tx_tdata = {reconf_tx_meta, reconf_tx_tlast, reconf_tx_tdata};
                pkt_tx_tvalid = reconf_tx_tvalid;
                reconf_tx_tready = pkt_tx_tready;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            output_active <= 1'b0;
            output_sel <= 2'd0;
        end else if (pkt_tx_tvalid) begin
            if (!output_active) begin
                output_active <= 1'b1;
                output_sel <= arb_sel;
            end

            if (pkt_tx_tready && pkt_tx_tdata[512]) begin
                output_active <= 1'b0;
            end
        end
    end

endmodule
