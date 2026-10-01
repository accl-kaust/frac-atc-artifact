`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 08.08.2023 15:50:27
// Design Name:
// Module Name: schedular
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

// Reassembles requests from the TCP segments the dispatcher tags, and hands
// them on one whole request at a time.
//
// Input.  The TOE delivers each segment contiguously, but segments of
// different connections interleave.  Every beat is routed by its connection:
//   - to the single-packet FIFO while it is taking a request that arrived
//     whole in one segment (single_active / single_conn);
//   - to the queue its connection holds, for a request spread over segments;
//   - otherwise the beat starts a new request, and must carry the FIRST flag.
//     One that is complete in this segment goes to the single-packet FIFO, as
//     upstream offrac does; a longer one takes a free queue and holds it until
//     its declared size has arrived.  A beat that starts nothing is dropped.
// A beat is accepted only when the FIFO it belongs in can take it, and it is
// written in the cycle it is accepted, so nothing is lost or written twice.
//
// A new multi-segment request waits while every queue holds an unfinished
// one.  The segments that would finish those arrive behind it, so more
// concurrent multi-segment requests than QUEUE_NUM stall the input for good.
// Requests that fit one segment never take a queue.
//
// Output.  A grant is taken at a request boundary -- round robin over the
// queues holding a finished request and the single-packet FIFO -- and held
// until that request's last beat has been accepted downstream.  Backpressure
// runs from tx_tready back to the FIFOs.  Finished and handed-on requests are
// counted per queue by the input and output side respectively, one writer
// each.

 module scheduler
 #(QUEUE_NUM = 4, TDATA_SIZE = 512 + 32 + WORKLOAD_SIZE + PACKET_SIZE + 16 + 1, CONN_ID = 16, WORKLOAD_SIZE = 16,PACKET_SIZE = 32, META_SIZE = 16,
    ECHO  = 0, TOP_K = 1, MM = 2, LOG = 3, NORM = 5)
 (
     input wire clk,
     input wire rst,
     // Input: {dstPort[15:0], packet_size[31:0], workload_selection[15:0], meta[31:0], tlast, payload[511:0]}
     input wire [TDATA_SIZE - 1: 0] rx_tdata,
     input wire rx_tvalid,
     output reg rx_tready,
     // Output: {request_end, dstPort[15:0], workload_type[15:0], meta[31:0], tcp_tlast, payload[511:0]}
     //   meta = {request_size[15:0], connID[15:0]} -- the header's packet_size, not one segment's length
     output wire [512 + 16 + 32 + 16 + 1:0] tx_tdata,
     output wire tx_tvalid,
     input wire tx_tready
     );
     //for debug
     wire [31:0] metadata;
     assign metadata =  tx_tdata[512+32: 512 + 1];

     localparam integer ENTRY_W = 512 + 16 + 32 + 16 + 2;  // {request_end, dstPort, workload, meta, tlast, payload}
     localparam integer FIFO_W  = 584;
     // Lines each request queue holds, upstream offrac's 4096 (axis_data_fifo_0
     // in its gen_ip.tcl): 256 KB of payload, so a multi-segment request of up
     // to 4096 lines fits one queue.  The single-packet and output FIFOs stay
     // at 512.
     localparam integer QUEUE_DEPTH = 4096;
     localparam integer SINGLE  = QUEUE_NUM;             // grant index of the single-packet FIFO

     // Bit positions: payload[511:0], tlast[512], meta[544:513] = {length, connID},
     // workload[560:545], packet_size[592:561], dstPort[608:593]
     wire [512:0]         rx_beat      = rx_tdata[512:0];
     wire                 rx_tlast     = rx_tdata[512];
     wire [CONN_ID-1:0]   rx_connid    = rx_tdata[528:513];
     wire [15:0]          rx_tcp_bytes = rx_tdata[544:529];
     wire [15:0]          rx_workload  = rx_tdata[560:545];
     wire [31:0]          rx_pkt_size  = rx_tdata[592:561];
     wire [15:0]          rx_req_size  = rx_tdata[576:561];   // packet_size[15:0]
     wire [15:0]          rx_dstPort   = rx_tdata[608:593];
     wire                 rx_is_header = rx_tdata[480];       // FIRST request flag
     wire                 rx_fire      = rx_tvalid && rx_tready;

     integer i;
     integer step;
     integer src;

     // ------------------------------------------------------------ queues

     reg  [ENTRY_W-1:0]   in_entry;
     reg  [QUEUE_NUM-1:0] input_tvalid;
     wire [QUEUE_NUM-1:0] input_tready;
     wire [FIFO_W-1:0]    output_tdata  [QUEUE_NUM-1:0];
     wire [QUEUE_NUM-1:0] output_tvalid;
     reg  [QUEUE_NUM-1:0] output_tready;

     reg                  input_tvalid_single;
     wire                 input_tready_single;
     wire [FIFO_W-1:0]    output_tdata_single;
     wire                 output_tvalid_single;
     reg                  output_tready_single;

     genvar gi;
     generate
         for (gi = 0; gi < QUEUE_NUM; gi = gi + 1) begin : GEN_INPUT_FIFO
             axis_data_fifo_0 #(.DEPTH(QUEUE_DEPTH)) fifo_inst(
               .rst(rst),
               .clk(clk),
               .s_axis_tvalid(input_tvalid[gi]),
               .s_axis_tready(input_tready[gi]),
               .s_axis_tdata({{(FIFO_W-ENTRY_W){1'b0}}, in_entry}),
               .m_axis_tvalid(output_tvalid[gi]),
               .m_axis_tready(output_tready[gi]),
               .m_axis_tdata(output_tdata[gi])
             );
         end
     endgenerate

     axis_data_fifo_1 fifo_inst_single(
       .rst(rst),
       .clk(clk),
       .s_axis_tvalid(input_tvalid_single),
       .s_axis_tready(input_tready_single),
       .s_axis_tdata({{(FIFO_W-ENTRY_W){1'b0}}, in_entry}),
       .m_axis_tvalid(output_tvalid_single),
       .m_axis_tready(output_tready_single),
       .m_axis_tdata(output_tdata_single)
     );

     // A queue held by an unfinished request, and whose connection holds it.
     reg                  q_busy     [QUEUE_NUM-1:0];
     reg  [CONN_ID-1:0]   q_conn     [QUEUE_NUM-1:0];
     reg  [15:0]          q_dstPort  [QUEUE_NUM-1:0];
     reg  [15:0]          q_workload [QUEUE_NUM-1:0];
     reg  [31:0]          q_size     [QUEUE_NUM-1:0];   // declared request size
     reg  [31:0]          q_rem      [QUEUE_NUM-1:0];   // bytes still to come after its segments so far
     reg  [15:0]          q_done     [QUEUE_NUM-1:0];   // requests finished (input side)
     reg  [15:0]          q_sent     [QUEUE_NUM-1:0];   // requests handed on (output side)

     // The request streaming into the single-packet FIFO, when its segment
     // has more than one beat.
     reg                  single_active;
     reg  [CONN_ID-1:0]   single_conn;
     reg  [15:0]          single_dstPort;
     reg  [15:0]          single_workload;
     reg  [15:0]          single_req_size;

     // ------------------------------------------------------------ input

     localparam [2:0] R_SINGLE     = 3'd0,  // rest of a whole-segment request
                      R_QUEUE      = 3'd1,  // next part of a multi-segment request
                      R_NEW_SINGLE = 3'd2,  // new request, whole in this segment
                      R_NEW_QUEUE  = 3'd3,  // new request, spread over segments
                      R_DROP       = 3'd4;  // starts nothing

     // The lookup is one bit per queue.  A connection takes a queue only while
     // it holds none, so at most one bit of hit_vec is set, and each queue is
     // read and updated through its own bit rather than through an index: at
     // 250 MHz the index, the select behind it and the sum and compare behind
     // that did not fit one cycle.  Each queue counts the bytes still to come,
     // so whether this segment ends its request is one compare, made for every
     // queue alongside the lookup.
     reg  [QUEUE_NUM-1:0] hit_vec;
     reg  [QUEUE_NUM-1:0] done_vec;
     reg                  free_found;
     reg  [7:0]           free_idx;

     always @* begin
         free_found = 1'b0;
         free_idx = 8'd0;
         for (i = 0; i < QUEUE_NUM; i = i + 1) begin
             hit_vec[i] = q_busy[i] && q_conn[i] == rx_connid;
             done_vec[i] = rx_tlast && {16'd0, rx_tcp_bytes} >= q_rem[i];
             if (!free_found && !q_busy[i]) begin
                 free_found = 1'b1;
                 free_idx = i;
             end
         end
     end

     reg  [15:0] hit_dstPort;
     reg  [15:0] hit_workload;
     reg  [15:0] hit_req_size;

     always @* begin
         hit_dstPort = 16'd0;
         hit_workload = 16'd0;
         hit_req_size = 16'd0;
         for (i = 0; i < QUEUE_NUM; i = i + 1) begin
             hit_dstPort = hit_dstPort | ({16{hit_vec[i]}} & q_dstPort[i]);
             hit_workload = hit_workload | ({16{hit_vec[i]}} & q_workload[i]);
             hit_req_size = hit_req_size | ({16{hit_vec[i]}} & q_size[i][15:0]);
         end
     end

     wire        hit              = |hit_vec;
     wire        in_single        = single_active && rx_connid == single_conn;
     wire        whole_in_segment = {16'd0, rx_tcp_bytes} >= rx_pkt_size;
     wire        hit_request_done = |(hit_vec & done_vec);

     reg [2:0] route;
     always @* begin
         if (in_single)             route = R_SINGLE;
         else if (hit)              route = R_QUEUE;
         else if (!rx_is_header)    route = R_DROP;
         else if (whole_in_segment) route = R_NEW_SINGLE;
         else                       route = R_NEW_QUEUE;
     end

     always @* begin
         case (route)
             R_SINGLE:     rx_tready = input_tready_single;
             R_NEW_SINGLE: rx_tready = input_tready_single && !single_active;
             R_QUEUE:      rx_tready = |(hit_vec & input_tready);
             R_NEW_QUEUE:  rx_tready = free_found && input_tready[free_idx];
             default:      rx_tready = 1'b1;
         endcase
     end

     // The beat as the slot sees it.  A multi-segment request keeps tlast only
     // on its final beat, and every beat carries the request's size as meta.
     always @* begin
         case (route)
             R_SINGLE:
                 in_entry = {rx_tlast, single_dstPort, single_workload, single_req_size, rx_connid, rx_beat};
             R_QUEUE:
                 in_entry = {hit_request_done, hit_dstPort, hit_workload, hit_req_size,
                             rx_connid, hit_request_done, rx_beat[511:0]};
             R_NEW_QUEUE:
                 in_entry = {1'b0, rx_dstPort, rx_workload, rx_req_size, rx_connid, 1'b0, rx_beat[511:0]};
             default:
                 in_entry = {rx_tlast, rx_dstPort, rx_workload, rx_req_size, rx_connid, rx_beat};
         endcase
     end

     always @* begin
         for (i = 0; i < QUEUE_NUM; i = i + 1) begin
             input_tvalid[i] = rx_fire && ((route == R_QUEUE && hit_vec[i]) ||
                                           (route == R_NEW_QUEUE && free_idx == i));
         end
         input_tvalid_single = rx_fire && (route == R_SINGLE || route == R_NEW_SINGLE);
     end

     always @(posedge clk) begin
         if (rst) begin
             single_active <= 1'b0;
             single_conn <= {CONN_ID{1'b0}};
             single_dstPort <= 16'd0;
             single_workload <= 16'd0;
             single_req_size <= 16'd0;
             for (i = 0; i < QUEUE_NUM; i = i + 1) begin
                 q_busy[i] <= 1'b0;
                 q_conn[i] <= {CONN_ID{1'b0}};
                 q_dstPort[i] <= 16'd0;
                 q_workload[i] <= 16'd0;
                 q_size[i] <= 32'd0;
                 q_rem[i] <= 32'd0;
                 q_done[i] <= 16'd0;
             end
         end else if (rx_fire) begin
             case (route)
                 R_NEW_SINGLE: begin
                     if (!rx_tlast) begin
                         single_active <= 1'b1;
                         single_conn <= rx_connid;
                         single_dstPort <= rx_dstPort;
                         single_workload <= rx_workload;
                         single_req_size <= rx_req_size;
                     end
                 end
                 R_SINGLE: begin
                     if (rx_tlast) begin
                         single_active <= 1'b0;
                     end
                 end
                 R_NEW_QUEUE: begin
                     q_busy[free_idx] <= 1'b1;
                     q_conn[free_idx] <= rx_connid;
                     q_dstPort[free_idx] <= rx_dstPort;
                     q_workload[free_idx] <= rx_workload;
                     q_size[free_idx] <= rx_pkt_size;
                     q_rem[free_idx] <= rx_tlast ? rx_pkt_size - {16'd0, rx_tcp_bytes} : rx_pkt_size;
                 end
                 R_QUEUE: begin
                     for (i = 0; i < QUEUE_NUM; i = i + 1) begin
                         if (hit_vec[i]) begin
                             if (done_vec[i]) begin
                                 q_busy[i] <= 1'b0;
                                 q_rem[i] <= 32'd0;
                                 q_done[i] <= q_done[i] + 16'd1;
                             end else if (rx_tlast) begin
                                 q_rem[i] <= q_rem[i] - {16'd0, rx_tcp_bytes};
                             end
                         end
                     end
                 end
                 default: begin
                 end
             endcase
         end
     end

     // ------------------------------------------------------------ output

     reg        grant_valid;
     reg [7:0]  grant_idx;
     reg [7:0]  rr_ptr;

     wire       grant_is_single = grant_valid && grant_idx == SINGLE;
     wire [7:0] grant_q         = (grant_idx < QUEUE_NUM) ? grant_idx : 8'd0;

     wire [ENTRY_W-1:0] output_queue_tdata = grant_is_single ? output_tdata_single[ENTRY_W-1:0]
                                                              : output_tdata[grant_q][ENTRY_W-1:0];
     wire               output_queue_tvalid = grant_valid &&
                                              (grant_is_single ? output_tvalid_single : output_tvalid[grant_q]);
     wire               output_tready_pip;
     wire               output_queue_fire = output_queue_tvalid && output_tready_pip;
     wire               output_queue_last = output_queue_tdata[ENTRY_W-1];

     always @* begin
         for (i = 0; i < QUEUE_NUM; i = i + 1) begin
             output_tready[i] = grant_valid && !grant_is_single && grant_q == i && output_tready_pip;
         end
         output_tready_single = grant_is_single && output_tready_pip;
     end

     // A source is ready once it holds a whole request: a queue when a finished
     // request is still in it, the single-packet FIFO as soon as a request
     // starts to come out, since everything in it arrived in one segment.
     function src_ready;
         input integer s;
         begin
             if (s == SINGLE)
                 src_ready = output_tvalid_single;
             else
                 src_ready = q_done[s] != q_sent[s];
         end
     endfunction

     // Next source in round-robin order from rr_ptr.
     reg       next_found;
     reg [7:0] next_idx;
     always @* begin
         next_found = 1'b0;
         next_idx = 8'd0;
         for (step = 0; step <= QUEUE_NUM; step = step + 1) begin
             src = rr_ptr + step;
             if (src > QUEUE_NUM) src = src - (QUEUE_NUM + 1);
             if (!next_found && src_ready(src)) begin
                 next_found = 1'b1;
                 next_idx = src;
             end
         end
     end

     always @(posedge clk) begin
         if (rst) begin
             grant_valid <= 1'b0;
             grant_idx <= 8'd0;
             rr_ptr <= 8'd0;
             for (i = 0; i < QUEUE_NUM; i = i + 1) begin
                 q_sent[i] <= 16'd0;
             end
         end else if (!grant_valid) begin
             if (next_found) begin
                 grant_valid <= 1'b1;
                 grant_idx <= next_idx;
             end
         end else if (output_queue_fire && output_queue_last) begin
             if (!grant_is_single) begin
                 q_sent[grant_q] <= q_sent[grant_q] + 16'd1;
             end
             grant_valid <= 1'b0;
             rr_ptr <= (grant_idx >= QUEUE_NUM) ? 8'd0 : grant_idx + 8'd1;
         end
     end

     // Pipeline between scheduler output and output FIFO to improve timing
     wire [FIFO_W-1:0] output_tdata_pip;
     wire              output_tvalid_pip;
     wire              output_fifo_s_tready;

     axis_pipeline_register #(
       .DATA_WIDTH(FIFO_W),
       .USER_ENABLE(0),
       .LENGTH(10),
       .LAST_ENABLE(0)
     ) axis_pipeline_sched_inst(
       .clk(clk),
       .rst(rst),
       .s_axis_tdata({{(FIFO_W-ENTRY_W){1'b0}}, output_queue_tdata}),
       .s_axis_tvalid(output_queue_tvalid),
       .s_axis_tready(output_tready_pip),
       .m_axis_tdata(output_tdata_pip),
       .m_axis_tvalid(output_tvalid_pip),
       .m_axis_tready(output_fifo_s_tready)
     );

     wire [FIFO_W-1:0] tx_tdata_fifo;

     axis_data_fifo_0 fifo_inst_output(
       .rst(rst),
       .clk(clk),
       .s_axis_tvalid(output_tvalid_pip),
       .s_axis_tready(output_fifo_s_tready),
       .s_axis_tdata(output_tdata_pip),
       .m_axis_tvalid(tx_tvalid),
       .m_axis_tready(tx_tready),
       .m_axis_tdata(tx_tdata_fifo)
     );

     assign tx_tdata = tx_tdata_fifo[ENTRY_W-1:0];

endmodule
