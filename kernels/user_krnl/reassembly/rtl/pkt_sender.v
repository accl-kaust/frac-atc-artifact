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

// Hands each response to the TCP stack: a request {length, session} on
// m_axis_tx_metadata and, once the stack has accepted it, that many bytes on
// m_axis_tx_data.
//
// The stack answers every request with a status whose error field
// (s_axis_tx_status_tdata[63:62]) is 0 accepted, 1 connection not established
// or 2 no space, and it reads data only for an accepted request.  Data sent for
// a refused request is taken by the next accepted one as its own, and every
// later response on every connection comes out misaligned -- so a refused
// request's data is never sent.  A response for a connection that is gone is
// discarded.  "No space" means the session's usable send window -- the smaller
// of its congestion window and the peer's receive window, less what is in
// flight -- is shorter than the request, and the status carries that window in
// [61:32].  The response is then sent in pieces: the request is reissued for as
// many whole lines as fit, and the rest follows in further requests.  With less
// than a line free it is reissued after BACKOFF_CYCLES, the window opening as
// the peer acknowledges.  So a response longer than a fresh session's
// congestion window (10 x 1460 bytes), or than the peer's receive window, still
// gets through, and one that fits goes out as a single request as before.
//
// While the final piece of a response goes out, the next response's request is
// issued, so the stack's answer -- 21 cycles away through network_krnl's FIFOs
// and the TOE's lookups -- comes back under that data instead of idling the
// bus after it: with one request at a time a 4 KB response took 87 cycles for
// its 64 beats.  Only a final piece has a request issued behind it, and only
// one, so a refusal of that request still finds nothing else issued, and
// acceptance stays in the order of the data.  What happens next is decided as
// the piece ends: an acceptance already waiting sends the next response at
// once; anything else -- no answer yet, a refusal -- goes through S_WAIT as
// before.

module pkt_sender #(
        parameter integer BACKOFF_CYCLES = 64
    ) (
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

    localparam [1:0] TX_OK           = 2'd0;
    localparam [1:0] TX_NOCONNECTION = 2'd1;

    // Status from the TCP stack: {error, usable window}.
    wire        status_tx_tvalid;
    reg         status_tx_tready;
    wire [31:0] status_tx_tdata;

    axis_fifo_taxi #(
        .DATA_WIDTH(32),
        .DEPTH(16)
    ) fifo_status (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata({s_axis_tx_status_tdata[63:62], s_axis_tx_status_tdata[61:32]}),
        .s_axis_tvalid(s_axis_tx_status_tvalid),
        .s_axis_tready(s_axis_tx_status_tready),
        .m_axis_tdata(status_tx_tdata),
        .m_axis_tvalid(status_tx_tvalid),
        .m_axis_tready(status_tx_tready)
    );

    wire [1:0]  status_error = status_tx_tdata[31:30];
    wire [29:0] status_space = status_tx_tdata[29:0];

    /**********/
    wire [511 + 1:0] payload_rx_tdata = pkt_rx_tdata[511 + 1:0]; //tlast + tdata
    wire         payload_rx_tvalid;
    wire         payload_rx_tready;

    wire         payload_tx_tvalid;
    reg          payload_tx_tready;

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

    assign m_axis_tx_data_tdata = output_tx[511:0];

    /**********/

    // {length, session} of each response, taken from its tlast beat once the
    // whole response is in the payload FIFO.
    wire        metadata_rx_tready;
    wire [31:0] metadata_tx_tdata;
    wire        metadata_tx_tvalid;
    reg         metadata_tx_tready;
    wire [31:0] metadata_notification = pkt_rx_tdata[512 + 32: 512 + 1];

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

    assign pkt_rx_tready = metadata_rx_tready & payload_rx_tready;
    assign payload_rx_tvalid = pkt_rx_tready & pkt_rx_tvalid;

    /**********/

    localparam [2:0] S_IDLE    = 3'd0,  // waiting for a whole response
                     S_REQ     = 3'd1,  // requesting the next piece of it
                     S_WAIT    = 3'd2,  // for the stack's answer
                     S_BACKOFF = 3'd3,  // no room at all: wait, then ask again
                     S_SEND    = 3'd4,  // the accepted piece
                     S_DROP    = 3'd5;  // the connection is gone

    reg [2:0]  state;
    reg [15:0] cur_session;
    reg [15:0] cur_remaining;    // bytes of the response not yet accepted
    reg [15:0] chunk_limit;      // longest piece to ask for: all of it until refused
    reg [15:0] chunk_len;        // piece asked for
    reg [15:0] beats_left;       // beats of the accepted piece still to send
    reg [15:0] backoff_cnt;

    // The next response's request, issued ahead of the end of this one.
    localparam [1:0] NX_NONE = 2'd0,  // none
                     NX_REQ  = 2'd1,  // being offered to the stack
                     NX_WAIT = 2'd2;  // taken; its status is to come

    reg [1:0]  nx_state;
    reg [15:0] nx_session;
    reg [15:0] nx_len;

    wire [15:0] chunk_ask  = (cur_remaining > chunk_limit) ? chunk_limit : cur_remaining;
    // whole lines of the usable window the stack reported
    wire [15:0] space_lines = (status_space > 30'd65535) ? 16'hffc0 : {status_space[15:6], 6'd0};

    // S_REQ and a request issued ahead never overlap: one is only issued from
    // S_SEND, and S_REQ is only entered with none outstanding, or from the
    // hand-over below, which clears it.
    assign m_axis_tx_metadata_tdata  = (nx_state == NX_REQ) ? {nx_len, nx_session} : {chunk_ask, cur_session};
    assign m_axis_tx_metadata_tvalid = (state == S_REQ) || (nx_state == NX_REQ);

    wire response_end = output_tx[512];
    wire piece_end    = beats_left == 16'd1 || response_end;
    assign m_axis_tx_data_tlast = (state == S_SEND) && piece_end && m_axis_tx_data_tvalid;

    wire payload_fire = payload_tx_tvalid && payload_tx_tready;

    // The last beat of the response goes this cycle.  (In S_SEND the payload
    // FIFO's ready is the stack's; naming it directly keeps this out of the
    // always block below, which also drives metadata_tx_tready from it.)
    wire resp_done = (state == S_SEND) && payload_tx_tvalid && m_axis_tx_data_tready &&
                     (response_end || (beats_left == 16'd1 && cur_remaining == 16'd0));
    // Issue the next response's request: while the final piece of this one is
    // being sent, and not in its last cycle, which hands over to S_IDLE.  An
    // empty response is left to S_IDLE, which only clears it out.
    wire nx_pop = (state == S_SEND) && cur_remaining == 16'd0 && nx_state == NX_NONE &&
                  metadata_tx_tvalid && metadata_tx_tdata[31:16] != 16'd0 && !resp_done;
    wire nx_req_fire = (nx_state == NX_REQ) && m_axis_tx_metadata_tready;
    // While a request is outstanding ahead, the status at the head of the FIFO
    // is its own: every earlier one was taken in S_WAIT.  It is only taken
    // here, as the response ends, and only if it accepts.
    wire nx_ok_now = resp_done && nx_state == NX_WAIT && status_tx_tvalid && status_error == TX_OK;

    always @(*) begin
        m_axis_tx_data_tkeep = {64{1'b1}};
        metadata_tx_tready = (state == S_IDLE) || nx_pop;
        status_tx_tready = (state == S_WAIT) || nx_ok_now;
        case (state)
            S_SEND: begin
                m_axis_tx_data_tvalid = payload_tx_tvalid;
                payload_tx_tready = m_axis_tx_data_tready;
            end
            S_DROP: begin
                m_axis_tx_data_tvalid = 1'b0;
                payload_tx_tready = 1'b1;
            end
            default: begin
                m_axis_tx_data_tvalid = 1'b0;
                payload_tx_tready = 1'b0;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            cur_session <= 16'd0;
            cur_remaining <= 16'd0;
            chunk_limit <= 16'hffff;
            chunk_len <= 16'd0;
            beats_left <= 16'd0;
            backoff_cnt <= 16'd0;
            nx_state <= NX_NONE;
            nx_session <= 16'd0;
            nx_len <= 16'd0;
        end else begin
            if (nx_pop) begin
                nx_state <= NX_REQ;
                nx_session <= metadata_tx_tdata[15:0];
                nx_len <= metadata_tx_tdata[31:16];
            end else if (nx_req_fire) begin
                nx_state <= NX_WAIT;
            end

            case (state)
                S_IDLE: begin
                    if (metadata_tx_tvalid) begin
                        cur_session <= metadata_tx_tdata[15:0];
                        cur_remaining <= metadata_tx_tdata[31:16];
                        chunk_limit <= 16'hffff;
                        // nothing to announce: just clear the payload out
                        state <= (metadata_tx_tdata[31:16] == 16'd0) ? S_DROP : S_REQ;
                    end
                end
                S_REQ: begin
                    if (m_axis_tx_metadata_tready) begin
                        chunk_len <= chunk_ask;
                        state <= S_WAIT;
                    end
                end
                S_WAIT: begin
                    if (status_tx_tvalid) begin
                        if (status_error == TX_OK) begin
                            beats_left <= (chunk_len + 16'd63) >> 6;
                            cur_remaining <= cur_remaining - chunk_len;
                            state <= S_SEND;
                        end else if (status_error == TX_NOCONNECTION) begin
                            state <= S_DROP;
                        end else if (space_lines != 16'd0 && space_lines < chunk_len) begin
                            chunk_limit <= space_lines;
                            state <= S_REQ;
                        end else begin
                            backoff_cnt <= BACKOFF_CYCLES[15:0];
                            state <= S_BACKOFF;
                        end
                    end
                end
                S_BACKOFF: begin
                    if (backoff_cnt == 16'd0) begin
                        state <= S_REQ;
                    end else begin
                        backoff_cnt <= backoff_cnt - 16'd1;
                    end
                end
                S_SEND: begin
                    if (payload_fire) begin
                        beats_left <= beats_left - 16'd1;
                        if (response_end) begin
                            state <= S_IDLE;
                        end else if (beats_left == 16'd1) begin
                            state <= (cur_remaining == 16'd0) ? S_IDLE : S_REQ;
                        end
                    end
                    // Hand over to the response whose request went ahead.
                    if (resp_done && nx_state != NX_NONE) begin
                        nx_state <= NX_NONE;
                        cur_session <= nx_session;
                        chunk_limit <= 16'hffff;
                        chunk_len <= nx_len;
                        if (nx_ok_now) begin
                            // accepted whole: its data follows straight on
                            cur_remaining <= 16'd0;
                            beats_left <= (nx_len + 16'd63) >> 6;
                            state <= S_SEND;
                        end else if (nx_state == NX_REQ && !nx_req_fire) begin
                            // still on offer: S_REQ offers the same request
                            cur_remaining <= nx_len;
                            state <= S_REQ;
                        end else begin
                            // taken: its status, when it comes, decides
                            cur_remaining <= nx_len;
                            state <= S_WAIT;
                        end
                    end
                end
                S_DROP: begin
                    if (payload_fire && response_end) begin
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
