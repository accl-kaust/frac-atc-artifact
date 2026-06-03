`timescale 1ns / 1ps

module dummy_delayed_app #(
    parameter integer MODE = 0,
    parameter integer DELAY_CYCLES = 16
) (
    input  wire        clk,
    input  wire        rst,

    input  wire [512:0] rx_tdata,
    input  wire         rx_tvalid,
    output wire         rx_tready,
    input  wire [31:0]  meta_tdata,

    output reg  [512:0] pkt_tx_tdata_payload,
    output reg          tx_data_tvalid,
    input  wire         tx_data_tready,
    output reg  [31:0]  meta_tdata_out,
    output reg          meta_tvalid_out
);

    localparam [511:0] ONE_PATTERN = {64{8'h01}};
    localparam [511:0] ALL_ONES = {512{1'b1}};

    reg busy = 1'b0;
    reg output_pending = 1'b0;
    reg [31:0] delay_count = 32'd0;

    wire [511:0] result_payload = (MODE == 0) ? ONE_PATTERN : (rx_tdata[511:0] | ALL_ONES);

    assign rx_tready = !busy && !output_pending;

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            output_pending <= 1'b0;
            delay_count <= 32'd0;
            pkt_tx_tdata_payload <= 513'd0;
            tx_data_tvalid <= 1'b0;
            meta_tdata_out <= 32'd0;
            meta_tvalid_out <= 1'b0;
        end else begin
            if (output_pending) begin
                tx_data_tvalid <= 1'b1;
                meta_tvalid_out <= pkt_tx_tdata_payload[512];

                if (tx_data_tvalid && tx_data_tready) begin
                    output_pending <= 1'b0;
                    tx_data_tvalid <= 1'b0;
                    meta_tvalid_out <= 1'b0;
                end
            end else begin
                tx_data_tvalid <= 1'b0;
                meta_tvalid_out <= 1'b0;

                if (busy) begin
                    if (delay_count == 32'd0) begin
                        busy <= 1'b0;
                        output_pending <= 1'b1;
                    end else begin
                        delay_count <= delay_count - 1'b1;
                    end
                end else if (rx_tvalid && rx_tready) begin
                    pkt_tx_tdata_payload <= {rx_tdata[512], result_payload};
                    meta_tdata_out <= meta_tdata;

                    if (DELAY_CYCLES == 0) begin
                        output_pending <= 1'b1;
                    end else begin
                        busy <= 1'b1;
                        delay_count <= DELAY_CYCLES - 1;
                    end
                end
            end
        end
    end

endmodule
