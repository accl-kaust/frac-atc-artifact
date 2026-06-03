`timescale 1ns / 1ps

module pkt_logic #(
    parameter PATTERN_APP = 16'h0000,
    parameter OR_APP = 16'h0001,
    parameter integer APP_DELAY_CYCLES = 16
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire [512+88-1 + 1 : 0]  pkt_rx_tdata,
    input  wire                     pkt_rx_tvalid,
    output wire                     pkt_rx_tready,
    output reg  [512+32-1 + 1: 0]   pkt_tx_tdata,
    output reg                      pkt_tx_tvalid,
    input  wire                     pkt_tx_tready
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

    wire pattern_rx_valid = scheduler_tvalid && (app_rx_workload != OR_APP);
    wire or_rx_valid = scheduler_tvalid && (app_rx_workload == OR_APP);

    always @* begin
        if (app_rx_workload == OR_APP) begin
            scheduler_tready = or_rx_ready;
        end else begin
            scheduler_tready = pattern_rx_ready;
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
    reg output_sel = 1'b0;
    reg arb_sel;

    always @* begin
        pattern_tx_ready = 1'b0;
        or_tx_ready = 1'b0;
        pkt_tx_tdata = 545'd0;
        pkt_tx_tvalid = 1'b0;

        if (output_active) begin
            arb_sel = output_sel;
        end else if (pattern_tx_valid) begin
            arb_sel = 1'b0;
        end else begin
            arb_sel = 1'b1;
        end

        if (arb_sel == 1'b0) begin
            pkt_tx_tdata = {pattern_tx_meta, pattern_tx_payload};
            pkt_tx_tvalid = pattern_tx_valid;
            pattern_tx_ready = pkt_tx_tready;
        end else begin
            pkt_tx_tdata = {or_tx_meta, or_tx_payload};
            pkt_tx_tvalid = or_tx_valid;
            or_tx_ready = pkt_tx_tready;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            output_active <= 1'b0;
            output_sel <= 1'b0;
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
