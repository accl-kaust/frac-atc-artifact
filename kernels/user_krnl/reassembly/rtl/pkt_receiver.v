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

module pkt_receiver (
        input wire clk,
        input wire rst,

        input wire [87:0]    s_axis_notifications_tdata,
        input wire           s_axis_notifications_tvalid,
        output wire          s_axis_notifications_tready,

        input wire [511 + 1:0] 	 s_axis_rx_data_tdata, //tlast + tdata
        input wire 	         s_axis_rx_data_tvalid,
        // input wire [63:0] 	 s_axis_rx_data_tkeep,
        // input wire [0:0] 	 s_axis_rx_data_tlast,
        output wire          s_axis_rx_data_tready,

        output reg [31:0]    m_axis_read_package_tdata,
        output reg           m_axis_read_package_tvalid,
        input wire           m_axis_read_package_tready,

        output reg [512+88-1 + 1 : 0] pkt_tx_tdata,
        output reg                pkt_tx_tvalid,
        input wire                pkt_tx_tready
    );

    wire [87:0] notif_tx_tdata;
    wire        notif_tx_tvalid;
    reg         notif_tx_tready;

    axis_data_fifo_88 fifo_notif (
      .rst(rst),
      .clk(clk),        // input wire s_axis_aclk
      .s_axis_tvalid(s_axis_notifications_tvalid),    // input wire s_axis_tvalid
      .s_axis_tready(s_axis_notifications_tready),    // output wire s_axis_tready
      .s_axis_tdata(s_axis_notifications_tdata),      // input wire [87 : 0] s_axis_tdata
      .m_axis_tvalid(notif_tx_tvalid),    // output wire m_axis_tvalid
      .m_axis_tready(notif_tx_tready),    // input wire m_axis_tready
      .m_axis_tdata(notif_tx_tdata)      // output wire [87 : 0] m_axis_tdata
    );
    /**********/

    reg          payload_rx_tvalid;
    wire [511 + 1:0] payload_tx_tdata; //tlast + tdata
    wire         payload_tx_tvalid;
    reg          payload_tx_tready;

    reg          prev_rx_data_tvalid;

    always @(posedge clk) begin
        prev_rx_data_tvalid <= s_axis_rx_data_tvalid;
    end

    always @(*) begin
        // signal should be only valid for 1 clock
        payload_rx_tvalid = s_axis_rx_data_tvalid & (~prev_rx_data_tvalid);
    end

    axis_data_fifo_513 fifo_payload (
      .rst(rst),
      .clk(clk),        // input wire s_axis_aclk
      .s_axis_tvalid(s_axis_rx_data_tvalid),    // input wire s_axis_tvalid
      .s_axis_tready(s_axis_rx_data_tready),    // output wire s_axis_tready
      .s_axis_tdata({7'b0, s_axis_rx_data_tdata}),      // input wire [519 : 0] s_axis_tdata
      .m_axis_tvalid(payload_tx_tvalid),    // output wire m_axis_tvalid
      .m_axis_tready(payload_tx_tready),    // input wire m_axis_tready
      .m_axis_tdata(payload_tx_tdata)      // output wire [519 : 0] m_axis_tdata
    );

    /**********/

    reg          metadata_rx_tvalid;
    wire         metadata_rx_tready;

    wire [87:0]  metadata_tx_tdata;
    wire         metadata_tx_tvalid;
    reg          metadata_tx_tready = 0;


    axis_data_fifo_88 fifo_metadata (
      .rst(rst),
      .clk(clk),        // input wire s_axis_aclk
      .s_axis_tvalid(metadata_rx_tvalid),    // input wire s_axis_tvalid
      .s_axis_tready(metadata_rx_tready),    // output wire s_axis_tready
      .s_axis_tdata(notif_tx_tdata),      // input wire [87 : 0] s_axis_tdata
      .m_axis_tvalid(metadata_tx_tvalid),    // output wire m_axis_tvalid
      .m_axis_tready(metadata_tx_tready),    // input wire m_axis_tready
      .m_axis_tdata(metadata_tx_tdata)      // output wire [87 : 0] m_axis_tdata
    );


    /**********/

    always @(*) begin
        m_axis_read_package_tdata = notif_tx_tdata[31:0];
    if (notif_tx_tvalid == 1'b1 &&
        (notif_tx_tdata[31:16] % 64 != 0 || notif_tx_tdata[31:16] < 16'd64 || notif_tx_tdata[31:16] > 16'd8960)) begin
            // discard rx_data that are larger than 1536B
            // also handle conn_close notification (msg size = 0)
            notif_tx_tready = 1'b1;
            m_axis_read_package_tvalid = 1'b0;
            metadata_rx_tvalid = 1'b0;
        end else begin
            notif_tx_tready = metadata_rx_tready & m_axis_read_package_tready;
            m_axis_read_package_tvalid = notif_tx_tready & notif_tx_tvalid;
            metadata_rx_tvalid = m_axis_read_package_tvalid;
        end

        pkt_tx_tdata = {metadata_tx_tdata, payload_tx_tdata};  //metadata + tlast + tdata
        pkt_tx_tvalid = payload_tx_tvalid;

        if(payload_tx_tdata[512] == 1 & pkt_tx_tvalid == 1 & pkt_tx_tready == 1) begin
            metadata_tx_tready = 1;
        end
        else begin
            metadata_tx_tready = 0;
        end

        payload_tx_tready = pkt_tx_tvalid & pkt_tx_tready;
    end

endmodule
