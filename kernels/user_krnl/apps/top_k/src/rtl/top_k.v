`resetall
`timescale 1ns / 1ps
`default_nettype none (* DONT_TOUCH = "yes" *)
module top_k #(
    parameter integer AXIS_DATA_W = 512,
    parameter integer KEEP_W      = AXIS_DATA_W / 8,
    parameter integer TDEST_W     = 3,
    parameter integer TID_W       = 4,
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

  localparam integer WORDS_PER_LINE = AXIS_DATA_W / VALUE_W;  // 16
  localparam integer IDX_W = $clog2(WORDS_PER_LINE);  // 4
  localparam integer MASK_W = 16;

  // ---------------------------------------------------------------- state

  reg [AXIS_DATA_W-1:0] line;  // line being unpacked
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

  // Header line: the fRAC request header writes 0xff over bytes 0-55.
  // Delete this and the `is_header` branch below if the scheduler ever
  // strips the header before the slot sees it.
  wire is_header = (s_axis_tdata[447:0] == {448{1'b1}});

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
      line         <= {AXIS_DATA_W{1'b0}};
      widx         <= {IDX_W{1'b0}};
      unpacking    <= 1'b0;
      line_last    <= 1'b0;
      frame_active <= 1'b0;
      resp_valid   <= 1'b0;
      resp_tdest   <= {TDEST_W{1'b0}};
      resp_tid     <= {TID_W{1'b0}};
      resp_tuser   <= {USER_W{1'b0}};
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
          resp_tdest <= s_axis_tdest;
          resp_tid   <= s_axis_tid;
          resp_tuser <= s_axis_tuser;
        end
        frame_active <= 1'b1;

        if (!frame_active && is_header) begin
          kmask      <= s_axis_tdata[495:480];
          resp_valid <= s_axis_tlast;  // header-only request
        end else begin
          line      <= s_axis_tdata;
          line_last <= s_axis_tlast;
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

  reg [AXIS_DATA_W-1:0] resp_data;
  integer j;
  always @* begin
    resp_data = {AXIS_DATA_W{1'b0}};
    for (j = 0; j < TOP_K_NUM; j = j + 1)
    resp_data[j*VALUE_W+:VALUE_W] = kmask[j] ? topk[j] : {VALUE_W{1'b0}};
  end

  assign m_axis_tdata  = resp_data;
  assign m_axis_tvalid = resp_valid;
  assign m_axis_tlast  = 1'b1;
  assign m_axis_tkeep  = {KEEP_W{1'b1}};
  assign m_axis_tstrb  = {KEEP_W{1'b1}};
  assign m_axis_tdest  = resp_tdest;
  assign m_axis_tid    = resp_tid;
  assign m_axis_tuser  = resp_tuser;

endmodule

`resetall
