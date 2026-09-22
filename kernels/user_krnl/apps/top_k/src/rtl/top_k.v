`resetall
`timescale 1ns / 1ps
`default_nettype none

// Top-k selection as a reconfigurable-slot module.
//
// Slot boundary, the same as pattern_slot.v / or_slot.v (the upstream offrac
// workload ports flattened onto one AXI-Stream), in both directions:
//   tdata[544:513] = meta      request: {request_bytes, session}  (meta_TDATA)
//                              response: {resp_bytes, session} (meta_TDATA_out)
//   tdata[512]     = tlast, in-band (the tlast line duplicates it)
//   tdata[511:0]   = payload
// pkt_sender takes the meta of the response beat that carries tlast as the
// TCP tx metadata, so resp_bytes must be the number of bytes in the response.
// The response is always one 64-byte beat, so the meta is {64, session} --
// the constant upstream pkt_logic.v applied to top_k ("All top-k workload has
// 64B content in the packet").  The session is taken from the request's first
// beat; the request size in meta_TDATA[31:16] is not needed here.

(* DONT_TOUCH = "yes" *)
module top_k #(
    parameter integer AXIS_DATA_W = 512 + 1 + 32,  // {meta, tlast, payload}
    parameter integer KEEP_W      = 1,
    parameter integer TDEST_W     = 1,
    parameter integer TID_W       = 1,
    parameter integer USER_W      = 1,
    parameter integer VALUE_W     = 32,
    parameter integer TOP_K_NUM   = 16                // <= 16: the mask field is 16 bits
) (
    input wire clk,
    input wire rst,

    input  wire [AXIS_DATA_W-1:0] s_axis_tdata,
    input  wire [     KEEP_W-1:0] s_axis_tkeep,
    input  wire [     KEEP_W-1:0] s_axis_tstrb,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [    TDEST_W-1:0] s_axis_tdest,
    input  wire [      TID_W-1:0] s_axis_tid,
    input  wire [     USER_W-1:0] s_axis_tuser,

    output wire [AXIS_DATA_W-1:0] m_axis_tdata,
    output wire [     KEEP_W-1:0] m_axis_tkeep,
    output wire [     KEEP_W-1:0] m_axis_tstrb,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [    TDEST_W-1:0] m_axis_tdest,
    output wire [      TID_W-1:0] m_axis_tid,
    output wire [     USER_W-1:0] m_axis_tuser
);

  localparam integer PAYLOAD_W  = 512;
  localparam integer LINE_BYTES = PAYLOAD_W / 8;  // 64
  localparam integer WORDS_PER_LINE = PAYLOAD_W / VALUE_W;  // 16
  localparam integer IDX_W = $clog2(WORDS_PER_LINE);  // 4
  localparam integer MASK_W = 16;

  // ---------------------------------------------------------------- state

  reg [PAYLOAD_W-1:0] line;  // line being unpacked
  reg [IDX_W-1:0] widx;  // word index within `line`
  reg unpacking;
  reg line_last;  // `line` was the last of the request
  reg frame_active;  // a request is in progress
  reg resp_valid;

  reg [VALUE_W-1:0] topk[0:TOP_K_NUM-1];  // descending
  reg [MASK_W-1:0] kmask;

  reg [TDEST_W-1:0] resp_tdest;
  reg [TID_W-1:0] resp_tid;
  reg [USER_W-1:0] resp_tuser;
  reg [15:0] resp_session;  // meta_TDATA[15:0] of the request's first beat

  // Slot boundary fields (see the header comment).
  wire [PAYLOAD_W-1:0] rx_payload = s_axis_tdata[PAYLOAD_W-1:0];
  wire                 rx_last    = s_axis_tdata[PAYLOAD_W];
  wire [         15:0] rx_session = s_axis_tdata[PAYLOAD_W+1 +: 16];

  // Header line: the fRAC request header writes 0xff over bytes 0-55.
  // Delete this and the `is_header` branch below if the scheduler ever
  // strips the header before the slot sees it.
  wire is_header = (rx_payload[447:0] == {448{1'b1}});

  wire rx_fire = s_axis_tvalid && s_axis_tready;

  // Value presented to the array this cycle.
  wire [VALUE_W-1:0] ins_val = line[widx*VALUE_W+:VALUE_W];
  wire ins_en = unpacking;
  wire last_word = (widx == {IDX_W{1'b1}});  // WORDS_PER_LINE is 2**IDX_W

  assign s_axis_tready = !unpacking && !resp_valid;

  // ------------------------------------------------------------- datapath

  integer i;
  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < TOP_K_NUM; i = i + 1) topk[i] <= {VALUE_W{1'b0}};
      kmask        <= {MASK_W{1'b1}};
      line         <= {PAYLOAD_W{1'b0}};
      widx         <= {IDX_W{1'b0}};
      unpacking    <= 1'b0;
      line_last    <= 1'b0;
      frame_active <= 1'b0;
      resp_valid   <= 1'b0;
      resp_tdest   <= {TDEST_W{1'b0}};
      resp_tid     <= {TID_W{1'b0}};
      resp_tuser   <= {USER_W{1'b0}};
      resp_session <= 16'd0;
    end else begin

      // Sorted-array insertion. Cell i compares only against its own
      // register and its neighbour's, so the combinational path is one
      // comparator plus a mux regardless of TOP_K_NUM.
      if (ins_en) begin
        if (ins_val > topk[0]) topk[0] <= ins_val;
        for (i = 1; i < TOP_K_NUM; i = i + 1) begin
          if (ins_val > topk[i]) topk[i] <= (ins_val > topk[i-1]) ? topk[i-1] : ins_val;
        end
      end

      if (ins_en) begin
        widx <= widx + 1'b1;
        if (last_word) begin
          unpacking  <= 1'b0;
          resp_valid <= line_last;
        end
      end

      if (rx_fire) begin
        if (!frame_active) begin
          resp_tdest   <= s_axis_tdest;
          resp_tid     <= s_axis_tid;
          resp_tuser   <= s_axis_tuser;
          resp_session <= rx_session;
        end
        frame_active <= 1'b1;

        if (!frame_active && is_header) begin
          kmask      <= rx_payload[495:480];
          resp_valid <= rx_last;  // header-only request
        end else begin
          line      <= rx_payload;
          line_last <= rx_last;
          widx      <= {IDX_W{1'b0}};
          unpacking <= 1'b1;
        end
      end

      // Response accepted: clear down for the next request.
      if (resp_valid && m_axis_tready) begin
        resp_valid   <= 1'b0;
        frame_active <= 1'b0;
        kmask        <= {MASK_W{1'b1}};
        for (i = 0; i < TOP_K_NUM; i = i + 1) topk[i] <= {VALUE_W{1'b0}};
      end
    end
  end

  // --------------------------------------------------------------- output

  reg [PAYLOAD_W-1:0] resp_data;
  integer j;
  always @* begin
    resp_data = {PAYLOAD_W{1'b0}};
    for (j = 0; j < TOP_K_NUM; j = j + 1)
    resp_data[j*VALUE_W+:VALUE_W] = kmask[j] ? topk[j] : {VALUE_W{1'b0}};
  end

  // {meta_TDATA_out = {64, session}, tlast, payload}: one beat per request
  assign m_axis_tdata  = {LINE_BYTES[15:0], resp_session, 1'b1, resp_data};
  assign m_axis_tvalid = resp_valid;
  assign m_axis_tlast  = 1'b1;
  assign m_axis_tkeep  = {KEEP_W{1'b1}};
  assign m_axis_tstrb  = {KEEP_W{1'b1}};
  assign m_axis_tdest  = resp_tdest;
  assign m_axis_tid    = resp_tid;
  assign m_axis_tuser  = resp_tuser;

endmodule

`resetall
