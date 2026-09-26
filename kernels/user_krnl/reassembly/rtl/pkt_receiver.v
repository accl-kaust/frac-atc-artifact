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

    // Longest TCP segment accepted; longer ones are refused like any other
    // bad length, see below.  A request may be larger than this: the
    // scheduler reassembles it across segments up to the header's declared
    // size.  A 4096-byte segment is 64 beats; every FIFO on the path holds 512.
    localparam [15:0] MAX_PACKET_BYTES = 16'd4096;

    wire [87:0] notif_tx_tdata;
    wire        notif_tx_tvalid;
    reg         notif_tx_tready;

    // The TOE runs with RX_DDR_BYPASS: every segment it accepts goes into one
    // FIFO shared by all sessions (rx_buffer_fifo in tcp_stack.sv), and each
    // read_package releases the segment at its head -- whichever session it
    // belongs to, whatever length the read names.  So every notification that
    // carries data must be answered with exactly one read, in order.
    //
    // A segment whose length is not a whole number of 64-byte lines, or is
    // over MAX_PACKET_BYTES, is refused, but it is still read: its metadata is
    // queued with REFUSED_BIT set and its beats are thrown away at the output.
    // Left unread, it would be handed out in answer to the next read, and
    // every later segment on every connection would arrive one read late
    // until the board was reprogrammed.  Discarding it does not repair the
    // request it belonged to -- the dispatcher and scheduler still wait for
    // its bytes -- but a request sent entirely in refused segments leaves no
    // trace.  Only a notification without data, a close, goes unread.
    //
    // Normally nothing is refused: the host cuts its writes at the MSS the
    // TOE advertises (Makefile TCP_STACK_MSS, a multiple of 64), provided its
    // own MTU is large enough to carry that MSS.
    localparam integer REFUSED_BIT = 87;  // padding above appNotification's 81 bits

    wire [15:0] notif_length   = notif_tx_tdata[31:16];
    wire        notif_has_data = notif_length != 16'd0;
    wire        notif_refused  = notif_length[5:0] != 6'd0 || notif_length < 16'd64 || notif_length > MAX_PACKET_BYTES;

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
      .s_axis_tdata({notif_refused, notif_tx_tdata[REFUSED_BIT-1:0]}),      // input wire [87 : 0] s_axis_tdata
      .m_axis_tvalid(metadata_tx_tvalid),    // output wire m_axis_tvalid
      .m_axis_tready(metadata_tx_tready),    // input wire m_axis_tready
      .m_axis_tdata(metadata_tx_tdata)      // output wire [87 : 0] m_axis_tdata
    );


    /**********/

    wire payload_refused = metadata_tx_tdata[REFUSED_BIT];

    always @(*) begin
        m_axis_read_package_tdata = notif_tx_tdata[31:0];
        if (notif_tx_tvalid == 1'b1 && !notif_has_data) begin
            // conn_close notification (msg size = 0): nothing to read
            notif_tx_tready = 1'b1;
            m_axis_read_package_tvalid = 1'b0;
            metadata_rx_tvalid = 1'b0;
        end else begin
            notif_tx_tready = metadata_rx_tready & m_axis_read_package_tready;
            m_axis_read_package_tvalid = notif_tx_tready & notif_tx_tvalid;
            metadata_rx_tvalid = m_axis_read_package_tvalid;
        end

        // REFUSED_BIT is clear on every segment that goes out
        pkt_tx_tdata = {metadata_tx_tdata, payload_tx_tdata};  //metadata + tlast + tdata
        pkt_tx_tvalid = payload_tx_tvalid & metadata_tx_tvalid & ~payload_refused;

        // a refused segment is consumed here, beat by beat, up to its tlast
        payload_tx_tready = payload_tx_tvalid & metadata_tx_tvalid & (pkt_tx_tready | payload_refused);
        metadata_tx_tready = payload_tx_tready & payload_tx_tdata[512];
    end

endmodule
