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

// Tags every beat with the {packet_size, workload_selection} of the request
// it belongs to.  The scheduler reads the header's size; the workload travels
// with the beats, though with one kernel in pkt_logic nothing steers on it.
//
// The TOE hands over each TCP segment contiguously, but segments of different
// connections interleave, so the request a beat belongs to is a property of
// its connection.  A request spread over several segments keeps a context --
// connection, bytes still to come, its tags -- from its first segment to its
// last; up to CTX_NUM such requests can be open at once.  At the first beat of
// a segment the context of its connection is looked up: found, the segment
// continues that request; not found, the beat is a header starting a new one,
// and a context is opened if the request runs past this segment.  The rest of
// the segment carries the tags decided at its first beat.  A header that
// needs a context while all CTX_NUM are open waits for one to close.
//
// A request ends where its declared size is reached at a segment boundary,
// or at a one-beat header segment flagged LAST.  Every workload counts its
// size the same way, as the scheduler does: with no reconfiguration
// controller there is no request whose size leaves out its header line.
// Requests are assumed to start at segment boundaries.

module dispatcher
#(ECHO  = 16'b0000, TOP_K = 16'b0001, MM = 16'b0010, LOG = 6'b0011, CRYPTO=16'b0100 , NORM=16'b0101,
  CTX_NUM = 8)
(
    input wire clk,
    input wire rst,
    input wire [512 + 88 : 0] rx_tdata,
    input wire rx_tvalid,
    output wire rx_tready,
    //output wire [512 + 88 + 16 + 16:0] tx_tdata, //{packet_size, workload_selection,  session_ID, rx_tdata}
    output wire [512 + 32 + 32 + 16:0] tx_tdata, //{packet_size, workload_selection,  session_ID, rx_tdata}
    output wire tx_tvalid,
    input wire tx_tready
    );

    // Register the input so the context lookup starts from a flop.
    wire [512 + 88 : 0] in_tdata;
    wire                in_tvalid;
    wire                in_tready;

    axis_pipeline_register #(
      .DATA_WIDTH(512 + 88 + 1),
      .KEEP_ENABLE(0),
      .LAST_ENABLE(0),
      .USER_ENABLE(0),
      .LENGTH(1)
    ) in_reg_inst (
      .clk(clk),
      .rst(rst),
      .s_axis_tdata(rx_tdata),
      .s_axis_tvalid(rx_tvalid),
      .s_axis_tready(rx_tready),
      .m_axis_tdata(in_tdata),
      .m_axis_tvalid(in_tvalid),
      .m_axis_tready(in_tready)
    );

    wire        in_tlast            = in_tdata[512];
    wire [15:0] in_connid           = in_tdata[528:513];
    wire [15:0] tcp_packet_bytes    = in_tdata[544:529];
    wire [1:0]  request_flags       = in_tdata[481:480];
    wire        request_first       = request_flags[0];
    wire        request_last        = request_flags[1];
    wire [15:0] header_workload_selection = in_tdata[511:496];
    wire [31:0] header_packet_size  = in_tdata[479:448];
    wire [31:0] header_request_bytes = header_packet_size;

    integer i;

    // Open requests, one per connection.
    reg                ctx_valid     [CTX_NUM-1:0];
    reg  [15:0]        ctx_conn      [CTX_NUM-1:0];
    reg  [31:0]        ctx_remaining [CTX_NUM-1:0];   // bytes after the segments seen so far
    reg  [15:0]        ctx_workload  [CTX_NUM-1:0];
    reg  [31:0]        ctx_packet_size [CTX_NUM-1:0];

    // Inside a segment, and the tags its first beat decided.
    reg                in_segment;
    reg  [15:0]        seg_workload;
    reg  [31:0]        seg_packet_size;

    reg        hit;
    reg [7:0]  hit_idx;
    reg        free_found;
    reg [7:0]  free_idx;

    always @* begin
        hit = 1'b0;
        hit_idx = 8'd0;
        free_found = 1'b0;
        free_idx = 8'd0;
        for (i = 0; i < CTX_NUM; i = i + 1) begin
            if (!hit && ctx_valid[i] && ctx_conn[i] == in_connid) begin
                hit = 1'b1;
                hit_idx = i;
            end
            if (!free_found && !ctx_valid[i]) begin
                free_found = 1'b1;
                free_idx = i;
            end
        end
    end

    wire        seg_first      = !in_segment;
    wire        new_header     = seg_first && !hit && request_first;
    wire        new_done       = (in_tlast && request_last) ||
                                 header_request_bytes <= {16'd0, tcp_packet_bytes};
    wire        opens_context  = new_header && !new_done;
    wire        cont_done      = ctx_remaining[hit_idx] <= {16'd0, tcp_packet_bytes};

    // A header that needs a context waits until one is free.
    wire        can_accept     = !(opens_context && !free_found);

    reg  [15:0] tag_workload;
    reg  [31:0] tag_packet_size;

    always @* begin
        if (!seg_first) begin
            tag_workload = seg_workload;
            tag_packet_size = seg_packet_size;
        end else if (hit) begin
            tag_workload = ctx_workload[hit_idx];
            tag_packet_size = ctx_packet_size[hit_idx];
        end else if (request_first) begin
            tag_workload = header_workload_selection;
            tag_packet_size = header_packet_size;
        end else begin
            // starts nothing: let the scheduler drop it
            tag_workload = 16'd0;
            tag_packet_size = 32'd0;
        end
    end

    wire fifo_s_tready;
    wire in_fire = in_tvalid && in_tready;

    assign in_tready = fifo_s_tready && can_accept;

    always @(posedge clk) begin
        if (rst) begin
            in_segment <= 1'b0;
            seg_workload <= 16'd0;
            seg_packet_size <= 32'd0;
            for (i = 0; i < CTX_NUM; i = i + 1) begin
                ctx_valid[i] <= 1'b0;
                ctx_conn[i] <= 16'd0;
                ctx_remaining[i] <= 32'd0;
                ctx_workload[i] <= 16'd0;
                ctx_packet_size[i] <= 32'd0;
            end
        end else if (in_fire) begin
            in_segment <= !in_tlast;
            if (seg_first) begin
                seg_workload <= tag_workload;
                seg_packet_size <= tag_packet_size;
                if (hit) begin
                    if (cont_done) begin
                        ctx_valid[hit_idx] <= 1'b0;
                    end else begin
                        ctx_remaining[hit_idx] <= ctx_remaining[hit_idx] - {16'd0, tcp_packet_bytes};
                    end
                end else if (opens_context) begin
                    ctx_valid[free_idx] <= 1'b1;
                    ctx_conn[free_idx] <= in_connid;
                    ctx_remaining[free_idx] <= header_request_bytes - {16'd0, tcp_packet_bytes};
                    ctx_workload[free_idx] <= header_workload_selection;
                    ctx_packet_size[free_idx] <= header_packet_size;
                end
            end
        end
    end

wire [599:0] tx_tdata_reg;
axis_data_fifo_2 fifo_inst(
  .rst(rst),
  .clk(clk),        // input wire s_axis_aclk
  .s_axis_tvalid(in_tvalid && can_accept),    // input wire s_axis_tvalid
  .s_axis_tready(fifo_s_tready),    // output wire s_axis_tready
  .s_axis_tdata({7'b0, tag_packet_size, tag_workload, in_tdata[512+32: 0]}),      // input wire [639 : 0] s_axis_tdata
  .m_axis_tvalid(tx_tvalid),    // output wire m_axis_tvalid
  .m_axis_tready(tx_tready),    // input wire m_axis_tready
  .m_axis_tdata(tx_tdata_reg)      // output wire [639 : 0] m_axis_tdata
);
assign tx_tdata = tx_tdata_reg[592:0];

endmodule
