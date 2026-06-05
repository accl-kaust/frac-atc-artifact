`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 03/17/2023 11:41:12 AM
// Design Name:
// Module Name: packet_parser
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module pkt_sender (
        input wire clk,
        input wire rst,

        input wire [512+32-1 + 1: 0] pkt_rx_tdata,  //metadata + tlast + tdata
        input wire                pkt_rx_tvalid,
        output wire               pkt_rx_tready,

        input wire [63:0]    s_axis_tx_status_tdata,
        input wire           s_axis_tx_status_tvalid,
        output wire          s_axis_tx_status_tready,

        output wire [31:0]   m_axis_tx_metadata_tdata,
        output wire          m_axis_tx_metadata_tvalid,
        input wire           m_axis_tx_metadata_tready,

        output wire [511:0]  m_axis_tx_data_tdata,
        output reg           m_axis_tx_data_tvalid,
        output reg [63:0] 	 m_axis_tx_data_tkeep,
        output wire         	 m_axis_tx_data_tlast,
        input wire           m_axis_tx_data_tready
    );

    wire status_tx_tvalid;
    reg  status_tx_tready;
    wire status_tx_tdata;

    // FIFO for storing TX status from the TCP stack.
    axis_fifo_taxi #(
        .DATA_WIDTH(1),
        .DEPTH(256)
    ) fifo_status (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tx_status_tdata[62:62]), // 1'b0: OK 1'b1: Error (Send to closed conn)
        .s_axis_tvalid(s_axis_tx_status_tvalid),
        .s_axis_tready(s_axis_tx_status_tready),
        .m_axis_tdata(status_tx_tdata),
        .m_axis_tvalid(status_tx_tvalid),
        .m_axis_tready(status_tx_tready)
    );

    /**********/
    reg [511 + 1:0]  payload_rx_tdata;
    reg          payload_rx_tvalid;
    wire         payload_rx_tready;

    wire         payload_tx_tvalid;
    reg          payload_tx_tready = 0;

    wire [512: 0] output_tx;


    //FIFO for storing payload
  axis_data_fifo_513 fifo_payload (
  .rst(rst),
  .clk(clk),        // input wire s_axis_aclk
  .s_axis_tvalid(payload_rx_tvalid),    // input wire s_axis_tvalid
  .s_axis_tready(payload_rx_tready),    // output wire s_axis_tready
  .s_axis_tdata(payload_rx_tdata),      // input wire [519 : 0] s_axis_tdata
  .m_axis_tvalid(payload_tx_tvalid),    // output wire m_axis_tvalid
  .m_axis_tready(payload_tx_tready),    // input wire m_axis_tready
  .m_axis_tdata(output_tx)      // output wire [519 : 0] m_axis_tdata
);

    assign m_axis_tx_data_tlast = output_tx[512] && m_axis_tx_data_tvalid;
    assign m_axis_tx_data_tdata = output_tx[511:0];

    /**********/

    //reg [31:0]  metadata_rx_tdata;//original 16-bit
    wire        metadata_rx_tready;
    wire [31:0] metadata_tx_tdata;
    wire        metadata_tx_tvalid;
    wire        metadata_tx_tready;
    //For debug
    wire [31:0] metadata_notification;
    assign metadata_notification = pkt_rx_tdata[512 + 32: 512 + 1];


    axis_fifo_taxi #(
        .DATA_WIDTH(32),
        .DEPTH(256)
    ) fifo_metadata (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(metadata_notification),
        .s_axis_tvalid(payload_rx_tvalid && pkt_rx_tdata[512]),
        .s_axis_tready(metadata_rx_tready),
        .m_axis_tdata(metadata_tx_tdata),
        .m_axis_tvalid(metadata_tx_tvalid),
        .m_axis_tready(metadata_tx_tready)
    );
    /**********/



reg tx_payload_active = 1'b0;
reg tx_status_consumed = 1'b0;

assign m_axis_tx_metadata_tdata = metadata_tx_tdata;
assign m_axis_tx_metadata_tvalid = metadata_tx_tvalid && !tx_payload_active;
assign metadata_tx_tready = m_axis_tx_metadata_tready && !tx_payload_active;

assign pkt_rx_tready = metadata_rx_tready & payload_rx_tready;

always @(posedge clk) begin
    if (rst) begin
        tx_payload_active <= 1'b0;
        tx_status_consumed <= 1'b0;
    end else begin
        if (!tx_payload_active && metadata_tx_tvalid && metadata_tx_tready) begin
            tx_payload_active <= 1'b1;
            tx_status_consumed <= 1'b0;
        end else if (tx_payload_active && payload_tx_tvalid && payload_tx_tready) begin
            if (!tx_status_consumed && status_tx_tvalid && !status_tx_tdata && !output_tx[512]) begin
                tx_status_consumed <= 1'b1;
            end
            if (output_tx[512]) begin
                tx_payload_active <= 1'b0;
                tx_status_consumed <= 1'b0;
            end
        end
    end
end

reg m_axis_tx_data_tvalid_inst = 0;
always @(*) begin
    //metadata_rx_tdata = pkt_rx_tdata[512+16-1 + 1 : 512 + 1]; // Packet Size: 64 Byte
    m_axis_tx_data_tvalid_inst = 1'b0;
    payload_rx_tdata = pkt_rx_tdata[511 + 1:0]; //tlast + tdata
    payload_rx_tvalid = pkt_rx_tready & pkt_rx_tvalid;
    m_axis_tx_data_tkeep = {64{1'b1}};

    if (tx_payload_active == 1'b1 && tx_status_consumed == 1'b0 && status_tx_tvalid == 1'b1 && payload_tx_tvalid == 1'b1 && status_tx_tdata == 1'b1) begin //Payload sent the same time as status
        // exception handler: sent to closed connection
        // discard payload and status
        m_axis_tx_data_tvalid = 1'b0;
        status_tx_tready = 1'b1;
        payload_tx_tready = 1'b1;
    end else begin
        m_axis_tx_data_tvalid_inst = tx_payload_active & payload_tx_tvalid & (tx_status_consumed | status_tx_tvalid);
        status_tx_tready = m_axis_tx_data_tvalid_inst & !tx_status_consumed & m_axis_tx_data_tready;
        payload_tx_tready = m_axis_tx_data_tvalid_inst & m_axis_tx_data_tready;
        m_axis_tx_data_tvalid = payload_tx_tvalid & payload_tx_tready;
    end
end

endmodule
