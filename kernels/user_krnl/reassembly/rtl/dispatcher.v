`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 21.07.2023 14:30:04
// Design Name:
// Module Name: dispatcher
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
module dispatcher
#(ECHO  = 16'b0000, TOP_K = 16'b0001, MM = 16'b0010, LOG = 6'b0011, CRYPTO=16'b0100 , NORM=16'b0101, RECONF_APP = 16'h00ab)
(
    input wire clk,
    input wire rst,
    input wire [512 + 88 : 0] rx_tdata,
    input wire rx_tvalid,
    output wire rx_tready,
    //output wire [512 + 88 + 16 + 16:0] tx_tdata, //{packet_size, workload_selection,  session_ID, rx_tdata}
    output wire [512 + 32 + 32 + 16:0] tx_tdata, //{packet_size, workload_selection,  session_ID, rx_tdata}
    output wire tx_tvalid,
    input wire tx_tready,

    // Request-framing state, brought out for a static ILA. Header recognition
    // is `expecting_header && request_first`, so a byte-accounting desync
    // during a long upload lets a payload line be taken for a header and
    // misroute everything after it. Nothing consumes these in logic.
    //
    // header_workload_selection is deliberately absent: it is a plain slice of
    // rx_tdata, which the caller already holds, so a port for it would carry
    // nothing the caller cannot cut for itself.
    output wire        dbg_expecting_header,
    output wire        dbg_config_header_line,
    output wire [19:0] dbg_request_bytes_remaining
    );

    reg [15:0] workload_selection;
    reg [512 + 88 + 32 + 16:0] rx_tdata_combined; //{tx_selection, rx_tdata}
    reg rx_tvalid_combined;
    reg [31:0] packet_size;
    reg [31:0] meta_data;

    localparam [1:0] REQ_FLAG_FIRST = 2'b01;
    localparam [1:0] REQ_FLAG_LAST  = 2'b10;

    reg        expecting_header;
    reg [31:0] request_bytes_remaining;

    wire        fifo_s_tready;
    // The {rx_tdata_combined, rx_tvalid_combined} pair is a one-deep
    // register stage. Accept a new beat only when it is empty or is being
    // drained this cycle, so a full output FIFO backpressures upstream
    // instead of having its writes silently dropped.
    wire        rx_accept = !rx_tvalid_combined || fifo_s_tready;
    wire        rx_fire = rx_tvalid == 1'b1 && rx_accept == 1'b1;
    wire [1:0]  request_flags = rx_tdata[481:480];
    wire        request_first = request_flags[0];
    wire        request_last = request_flags[1];
    wire        config_header_line = rx_fire && expecting_header && request_first;
    wire [15:0] tcp_packet_bytes = rx_tdata[544:529];
    wire [15:0] header_workload_selection = rx_tdata[511:496];
    wire [31:0] header_packet_size = rx_tdata[479:448];
    wire [31:0] header_request_bytes = (header_workload_selection == RECONF_APP) ?
        header_packet_size + 32'd64 : header_packet_size;
    wire [31:0] active_request_bytes = config_header_line ? header_request_bytes : request_bytes_remaining;

    assign rx_tready = rx_accept;

    assign dbg_expecting_header        = expecting_header;
    assign dbg_config_header_line      = config_header_line;
    assign dbg_request_bytes_remaining = request_bytes_remaining[19:0];

    //dataline counter, recognize new configuration line
    always @(posedge clk) begin
        if (rst) begin
             workload_selection = 16'd0;
             packet_size = 32'd0;
             meta_data = 32'd0;
             expecting_header = 1'b1;
             request_bytes_remaining = 32'd0;
             rx_tdata_combined = 0;
             rx_tvalid_combined = 1'b0;
        end else begin
        //This line is configuration line,
        if (config_header_line) begin
             workload_selection = header_workload_selection;
             packet_size =  header_packet_size;   //32-bit
             rx_tdata_combined = {packet_size, workload_selection, rx_tdata[512+32: 0]};
             meta_data = rx_tdata[512+32: 513];
        end
        //This line is normal line
        else if (rx_fire) begin
             rx_tdata_combined = {packet_size, workload_selection, rx_tdata[512+32: 0]};
             meta_data = rx_tdata[512+32: 513];
        end
        if (rx_fire && rx_tdata[512]) begin
             if ((config_header_line && request_last) || active_request_bytes <= {16'd0, tcp_packet_bytes}) begin
                  expecting_header = 1'b1;
                  request_bytes_remaining = 32'd0;
             end else begin
                  expecting_header = 1'b0;
                  request_bytes_remaining = active_request_bytes - {16'd0, tcp_packet_bytes};
             end
        end else if (config_header_line) begin
             expecting_header = 1'b0;
             request_bytes_remaining = active_request_bytes;
        end
        // Last: this drives rx_accept, so every read above sees pre-edge state.
        if (rx_accept) begin
             rx_tvalid_combined = rx_tvalid;
        end
        end
    end

wire [599:0] tx_tdata_reg;
axis_data_fifo_2 fifo_inst(
  .rst(rst),
  .clk(clk),        // input wire s_axis_aclk
  .s_axis_tvalid(rx_tvalid_combined),    // input wire s_axis_tvalid
  .s_axis_tready(fifo_s_tready),    // output wire s_axis_tready
  .s_axis_tdata({7'b0, rx_tdata_combined}),      // input wire [639 : 0] s_axis_tdata
  .m_axis_tvalid(tx_tvalid),    // output wire m_axis_tvalid
  .m_axis_tready(tx_tready),    // input wire m_axis_tready
  .m_axis_tdata(tx_tdata_reg)      // output wire [639 : 0] m_axis_tdata
);
assign tx_tdata = tx_tdata_reg[592:0];

endmodule
