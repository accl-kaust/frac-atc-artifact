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


 module scheduler
 #(QUEUE_NUM = 2, TDATA_SIZE = 512 + 32 + WORKLOAD_SIZE + PACKET_SIZE + 16 + 1, CONN_ID = 16, WORKLOAD_SIZE = 16,PACKET_SIZE = 32, META_SIZE = 16,
    ECHO  = 0, TOP_K = 1, MM = 2, LOG = 3, NORM = 5)
 (
     input wire clk,
     input wire rst,
     // Input: {packet_size[31:0], workload_selection[15:0], dstPort[15:0], meta[31:0], tlast, payload[511:0]}
     input wire [TDATA_SIZE - 1: 0] rx_tdata, // {packet_size, tx_selection, dstPort, rx_tdata}
     input wire rx_tvalid,
     output reg rx_tready,
     // Output: {request_end, dstPort[15:0], workload_type[15:0], meta[31:0], tcp_tlast, payload[511:0]}
     output wire [512 + 16 + 32 + 16 + 1:0] tx_tdata,
     output wire tx_tvalid,
     input wire tx_tready
     );
     //for debug
     wire [31:0] metadata;
     assign metadata =  tx_tdata[512+32: 512 + 1];

     // Extract dstPort from input (now at MSB of dispatcher output)
     // Input format: {dstPort[15:0], packet_size[31:0], workload_selection[15:0], meta[31:0], tlast, payload[511:0]}
     // Bit positions: payload[511:0], tlast[512], meta[544:513], workload[560:545], packet_size[592:561], dstPort[608:593]
     wire [15:0] rx_dstPort = rx_tdata[608:593];
     wire        rx_is_header = rx_tdata[447:0] == {448{1'b1}};

     //Normal queues input - widened by 16 bits for dstPort
     reg  [1 + 512 + 32 + 16 + 16: 0] input_tdata [QUEUE_NUM - 1: 0]; //last of message + dstPort + workload + meta + tlast + payload
     reg  [QUEUE_NUM - 1: 0] input_tvalid;
     wire [QUEUE_NUM - 1: 0] input_tready;

     //Single-packet queue input - widened by 16 bits for dstPort
     reg  [1 + 512 + 32 + 16 + 16: 0] input_tdata_single;
     reg  input_tvalid_single;
     wire  input_tready_single;

     //Normal queues output - widened by 16 bits for dstPort
     wire [1 + 512 + 32 + 16 + 16: 0] output_tdata [QUEUE_NUM - 1: 0];
     wire [QUEUE_NUM - 1: 0] output_tvalid;
     reg [QUEUE_NUM - 1: 0] output_tready;
     reg  [7:0] credits [QUEUE_NUM - 1: 0];
     reg [7:0] output_deduct_credits [QUEUE_NUM - 1: 0];

     //Single-packet queue output - widened by 16 bits for dstPort
     wire [1 + 512 + 32 + 16 + 16: 0] output_tdata_single;
     wire output_tvalid_single;
     reg output_tready_single_FIFO;

     //meta_reg - add dstPort storage
     reg  [WORKLOAD_SIZE + CONN_ID + 16 - 1: 0] input_META [QUEUE_NUM - 1: 0]; // {dstPort, workload, connID}
     reg  [WORKLOAD_SIZE + CONN_ID + 16 - 1: 0] input_META_single;

     //input signals
     reg [31:0] counter [QUEUE_NUM - 1: 0];
     reg [31:0] counter_inst [QUEUE_NUM - 1: 0];

     // output selection control
     reg [QUEUE_NUM - 1: 0] output_tready_sel;
     reg output_tready_single = 0;

     // module-level loop temps (avoid declaring in blocks)
     integer map_i;
     integer initial_i;
     integer queue;
     integer m;
     integer alloc_i;
     integer clr_i;
     integer output_queue;
     integer active_idx;
     integer idx;
     integer step;
     integer found_next;
     integer next_idx;
     integer keep_i;
     integer hold_i;
     integer choose_i;
     integer chosen;
     integer set_i;
     integer reset_i;
     reg matched_any;
     reg allocated;

     always @(posedge clk) begin
        if (rst) begin
            for (reset_i = 0; reset_i < QUEUE_NUM; reset_i = reset_i + 1) begin
                output_tready[reset_i] <= 1'b0;
            end
            output_tready_single_FIFO <= 1'b0;
        end else begin
         // Map selected output TREADY signals to FIFO TREADYs
         for (map_i = 0; map_i < QUEUE_NUM; map_i = map_i + 1) begin
             output_tready[map_i] <= output_tready_sel[map_i];
         end
         output_tready_single_FIFO <= output_tready_single;
        end
     end


    // Per-queue input FIFOs
    genvar gi;
    generate
        for (gi = 0; gi < QUEUE_NUM; gi = gi + 1) begin : GEN_INPUT_FIFO
            axis_data_fifo_0 fifo_inst(
              .rst(rst),
              .clk(clk),
              .s_axis_tvalid(input_tvalid[gi]),
              .s_axis_tready(input_tready[gi]),
              .s_axis_tdata(input_tdata[gi]),
              .m_axis_tvalid(output_tvalid[gi]),
              .m_axis_tready(output_tready[gi]),
              .m_axis_tdata(output_tdata[gi])
            );
        end
    endgenerate

    // Single-packet FIFO
    axis_data_fifo_1 fifo_inst_single(
      .rst(rst),
      .clk(clk),
      .s_axis_tvalid(input_tvalid_single),
      .s_axis_tready(input_tready_single),
      .s_axis_tdata(input_tdata_single),
      .m_axis_tvalid(output_tvalid_single),
      .m_axis_tready(output_tready_single_FIFO),
      .m_axis_tdata(output_tdata_single)
    );

     //initialize all virtual queues and credits
     initial begin
        output_tready_sel = {QUEUE_NUM{1'b0}};
        for (initial_i = 0; initial_i < QUEUE_NUM; initial_i = initial_i + 1) begin
            credits[initial_i] = 8'b0;
            output_deduct_credits[initial_i] = 8'b0;
            input_META[initial_i] = {(WORKLOAD_SIZE + CONN_ID + 16){1'b1}}; // all ones (includes dstPort)
            counter[initial_i] = 32'b0;
            counter_inst[initial_i] = 32'b0;
        end
        input_META_single = {(WORKLOAD_SIZE + CONN_ID + 16){1'b1}};
    end


     always @(posedge clk) begin
        if (rst) begin
            rx_tready = 1'b1;
            input_tvalid_single = 1'b0;
            input_META_single = {(WORKLOAD_SIZE + CONN_ID + 16){1'b1}};
            for (reset_i = 0; reset_i < QUEUE_NUM; reset_i = reset_i + 1) begin
                credits[reset_i] = 8'b0;
                input_META[reset_i] = {(WORKLOAD_SIZE + CONN_ID + 16){1'b1}};
                counter[reset_i] = 32'd0;
                counter_inst[reset_i] = 32'd0;
                input_tvalid[reset_i] = 1'b0;
                input_tdata[reset_i] = 0;
            end
            input_tdata_single = 0;
        end else begin
         /*credits clear logic*/
        for (queue = 0; queue < QUEUE_NUM; queue = queue + 1) begin
            if (credits[queue] == output_deduct_credits[queue]) begin
                credits[queue] = 8'b0000;
            end
       end
       if(rx_tvalid == 1 && rx_tready == 1)begin
            //matches the meta

            //The complete single-request situation, concatenating the first one
            // connID is in the lower 16 bits of meta at rx_tdata[528:513]
            // New input format: {dstPort[608:593], packet_size[592:561], workload[560:545], meta[544:513], tlast[512], payload[511:0]}
            if(rx_tdata[528:513] == input_META_single[CONN_ID - 1:0] && input_tready_single == 1) begin
                input_tvalid_single = rx_tvalid;
                // Format: {message_end (1-bit), dstPort (16-bit), workload_type (16-bit), meta_data (32-bit), tlast(1-bit), payload (512_bit)}
                // Use stored dstPort and workload from META, and current meta+payload from rx_tdata
                input_tdata_single = {1'b0, input_META_single[47:32], input_META_single[31:16], rx_tdata[544:0]};
                rx_tready = 1'b1;
                if(input_tdata_single[512] == 1) begin //the last of the packet
                   input_tdata_single[512+32+16+16+1] = 1'b1; //the last of the message, always the last
                   input_META_single = {(WORKLOAD_SIZE + CONN_ID + 16){1'b1}};
                end
            end

            //The multi-packet situations (match existing metas)
            // connID is in the lower 16 bits of meta at rx_tdata[528:513]
            else begin : MATCH_EXISTING
                matched_any = 1'b0;
                for (m = 0; m < QUEUE_NUM; m = m + 1) begin
                    if (!matched_any && (rx_tdata[528:513] == input_META[m][CONN_ID - 1:0]) && (input_tready[m] == 1)) begin
                        input_tvalid[m] = rx_tvalid;
                        // Format: {message_end (1-bit), dstPort (16-bit), workload_type (16-bit), meta_data (32-bit), tlast(1-bit), payload (512_bit)}
                        // Use stored dstPort and workload from META, and current meta+payload from rx_tdata
                        input_tdata[m] = {1'b0, input_META[m][47:32], input_META[m][31:16], rx_tdata[544:0]};
                        rx_tready = 1'b1;
                        // Accumulate bytes only on TLAST; release the slot only when we have met/exceeded packet_size
                        if(rx_tdata[512]) begin // TLAST indicates end of a TCP packet
                            counter_inst[m] = counter_inst[m] + rx_tdata[544:529];
                            if(counter_inst[m] >= counter[m]) begin
                                credits[m] = credits[m] + 1;
                                input_META[m] = {(WORKLOAD_SIZE + CONN_ID + 16){1'b1}};
                                counter_inst[m] = 0;
                                counter[m] = 0;
                                input_tdata[m][512+32+16+16+1] = 1'b1; // the last of the message
                                // keep TLAST from the stream (should already be 1 on the final beat)
                            end
                            else begin   // TLAST but not the last of multi-packet yet (more TCP packets expected)
                                input_tdata[m][512+32+16+16+1] = 1'b0; // assemble these packets
                                // Get the middle last removed, only have last signal when sending
                                input_tdata[m][512] = 1'b0;
                            end
                        end
                        else begin   // not TLAST, intermediate beat within a TCP packet
                            input_tdata[m][512+32+16+16+1] = 1'b0;
                            input_tdata[m][512] = 1'b0;
                        end
                        matched_any = 1'b1; // ensure only one queue is selected
                    end
                end
                if (!matched_any) begin
                    //does not match the meta, the first dataline of the session
                    // New input format: {dstPort[608:593], packet_size[592:561], workload[560:545], meta[544:513], tlast[512], payload[511:0]}
                    // packet_size is at [592:561], length (from meta upper 16 bits) is at [544:529]
                    // Single-beat complete request: declared request size fits this TCP packet and this is its only beat.
                    if (rx_is_header && (input_META_single == {(WORKLOAD_SIZE + CONN_ID + 16){1'b1}}) && (rx_tdata[592:561] == {16'd0, rx_tdata[544:529]}) && rx_tdata[512] && (input_tready_single == 1)) begin
                        input_tvalid_single = rx_tvalid;
                        // Output format: {message_end, dstPort, workload_type, meta, tlast, payload}
                        // rx_tdata[544:0] = {meta[31:0], tlast, payload[511:0]}
                        // workload_selection is at rx_tdata[560:545]
                        input_tdata_single = {1'b1, rx_dstPort, rx_tdata[560:545], rx_tdata[544:0]};
                        input_META_single = {(WORKLOAD_SIZE + CONN_ID + 16){1'b1}};
                        rx_tready = 1'b1;
                    end else begin
                        // Multi-beat or multi-packet request: hold output until declared request size is complete.
                        allocated = 1'b0;
                        for (alloc_i = 0; alloc_i < QUEUE_NUM; alloc_i = alloc_i + 1) begin
                            if (!allocated && rx_is_header && (input_META[alloc_i] == {(WORKLOAD_SIZE + CONN_ID + 16){1'b1}})) begin
                                input_tvalid[alloc_i] = rx_tvalid;
                                // Output format: {message_end, dstPort, workload_type, meta, tlast, payload}
                                input_tdata[alloc_i] = {1'b0, rx_dstPort, rx_tdata[560:545], rx_tdata[544:0]};
                                // Store {dstPort, workload_type, connID} in META
                                input_META[alloc_i] = {rx_dstPort, rx_tdata[560:545], rx_tdata[528:513]};
                                counter[alloc_i] = rx_tdata[592:561];  // packet_size
                                // Accumulate length only on TLAST (end of TCP packet)
                                if (rx_tdata[512]) begin // TLAST on first beat (single-beat TCP packet)
                                    counter_inst[alloc_i] = rx_tdata[544:529];
                                    // Release credit only when accumulated length meets/exceeds packet_size
                                    if (counter_inst[alloc_i] >= counter[alloc_i]) begin
                                        credits[alloc_i] = credits[alloc_i] + 1;
                                        input_META[alloc_i] = {(WORKLOAD_SIZE + CONN_ID + 16){1'b1}};
                                        counter_inst[alloc_i] = 0;
                                        counter[alloc_i] = 0;
                                        input_tdata[alloc_i][512+32+16+16+1] = 1'b1; // last of the message
                                    end else begin
                                        input_tdata[alloc_i][512+32+16+16+1] = 1'b0; // more TCP packets expected
                                        input_tdata[alloc_i][512] = 1'b0; // clear TLAST for message assembly
                                    end
                                end else begin // No TLAST, multi-beat TCP packet
                                    counter_inst[alloc_i] = 0; // Initialize to 0, will accumulate on TLAST
                                    input_tdata[alloc_i][512+32+16+16+1] = 1'b0;
                                    input_tdata[alloc_i][512] = 1'b0;
                                end
                                rx_tready = 1'b1;
                                allocated = 1'b1;
                            end
                        end
                        if (!allocated) begin
                            //No queue is avaliable
                            rx_tready = 1'b0;
                        end
                    end
                end
            end
        end
        //NO data input
        else begin
            rx_tready = 1'b1;
            input_tvalid_single = 1'b0;
            for (clr_i = 0; clr_i < QUEUE_NUM; clr_i = clr_i + 1) begin
                input_tvalid[clr_i] = 1'b0;
            end
        end
        end
    end

// output queue
        // Pipeline between scheduler output and output FIFO to improve timing
        // Widened by 16 bits for dstPort: 7 + (512+32+16+16+1) = 584
        wire [584-1:0] output_tdata_pip;
        wire output_tvalid_pip;
        wire output_tready_pip;

        axis_pipeline_register #(
          .DATA_WIDTH(584),  // {7'b0, output_queue_tdata} is 7 + (512+32+16+16+1) = 584
          .USER_ENABLE(0),
          .LENGTH(10),
          .LAST_ENABLE(0)
        ) axis_pipeline_sched_inst(
          .clk(clk),
          .rst(rst),
          .s_axis_tdata(output_queue_tdata),
          .s_axis_tvalid(output_queue_tvalid_FIFO),
          .s_axis_tready(output_tready_pip),
          .m_axis_tdata(output_tdata_pip),
          .m_axis_tvalid(output_tvalid_pip),
          .m_axis_tready(1'b1)
        );

        axis_data_fifo_0 fifo_inst_output(
          .rst(rst),
          .clk(clk),
          .s_axis_tvalid(output_tvalid_pip),
          .s_axis_tready(),
          .s_axis_tdata(output_tdata_pip),
          .m_axis_tvalid(tx_tvalid),
          .m_axis_tready(tx_tready),
          .m_axis_tdata(tx_tdata)
        );



    //output signal - widened by 16 bits for dstPort
    // Format: {request_end, dstPort[15:0], workload_type[15:0], meta[31:0], tcp_tlast, payload[511:0]}
    reg [512 + 32 + 16 + 16 + 1:0] output_queue_tdata;
    wire output_queue_tvalid_FIFO;
    reg output_queue_tvalid;
    reg [7:0] output_queue_number = 8'hFF;




    assign output_queue_tvalid_FIFO = output_queue_tvalid;

    always @* begin
       if (output_queue_number < QUEUE_NUM) begin
            output_queue_tvalid = output_tvalid[output_queue_number] && output_tready_sel[output_queue_number];
            output_queue_tdata = output_tdata[output_queue_number][512 + 32 + 16 + 16 + 1:0];
       end else if (output_queue_number == QUEUE_NUM) begin
            output_queue_tvalid = output_tvalid_single && output_tready_single_FIFO;
            output_queue_tdata = output_tdata_single[512 + 32 + 16 + 16 + 1:0];
       end else begin
            output_queue_tvalid = 0;
            output_queue_tdata = 0;
       end
    end

    always @(posedge clk) begin
        if (rst) begin
            output_queue_number = 8'hFF;
            output_tready_sel = {QUEUE_NUM{1'b0}};
            output_tready_single = 1'b0;
            for (reset_i = 0; reset_i < QUEUE_NUM; reset_i = reset_i + 1) begin
                output_deduct_credits[reset_i] = 8'd0;
            end
        end else begin
        //output credits clear and update
       for (output_queue = 0; output_queue < QUEUE_NUM; output_queue = output_queue + 1) begin
            if (credits[output_queue] == output_deduct_credits[output_queue]) begin
                output_deduct_credits[output_queue] = 8'b0000;
            end
       end

       //single-packet queue output has priority
        if(output_tvalid_single == 1'b1) begin
            output_queue_number = QUEUE_NUM;
            output_tready_sel = {QUEUE_NUM{1'b0}};
            output_tready_single = 1;
        end

       //Other normal queues situations
       else begin
            output_tready_single = 0; //clear the TREADY_single, since the single packet queue is not going to be output

            // Determine active queue (one that currently has TREADY asserted and still has credits)
            active_idx = -1;
            for (idx = 0; idx < QUEUE_NUM; idx = idx + 1) begin
                if (output_tready_sel[idx] == 1'b1 && (credits[idx] > output_deduct_credits[idx])) begin
                    active_idx = idx;
                end
            end

            if (active_idx != -1) begin
                if (output_tvalid[active_idx]  == 1) begin
                    output_queue_number = active_idx[7:0];
                    if(output_tdata[active_idx][512+32+16+16+1] == 1 && output_tvalid[active_idx] == 1) begin //The last dataline in the last packet of the request
                        output_tready_sel[active_idx] = 1'b0;     //This queue need to be shifted
                        output_deduct_credits[active_idx] =  output_deduct_credits[active_idx] + 1; //decuct the credit
                        // find next ready queue in round-robin order
                        found_next = 0;
                        for (step = 1; step <= QUEUE_NUM; step = step + 1) begin
                            next_idx = active_idx + step;
                            if (next_idx >= QUEUE_NUM) next_idx = next_idx - QUEUE_NUM;
                            if (!found_next && (output_tvalid[next_idx] == 1) && (credits[next_idx] > output_deduct_credits[next_idx])) begin
                                output_tready_sel[next_idx] = 1'b1;
                                found_next = 1;
                            end
                        end
                        if (!found_next) begin
                            if(output_tvalid_single == 1'b1) begin  // single queue is ready to be output
                               output_tready_single = 1'b1;
                            end else if ((output_tvalid[active_idx] == 1) && (credits[active_idx] > output_deduct_credits[active_idx])) begin
                               output_tready_sel[active_idx] = 1'b1;
                            end
                        end
                    end else begin //Have packet to pull, but not fully pulled, keep pulling
                        output_tready_single = 0;
                        for (keep_i = 0; keep_i < QUEUE_NUM; keep_i = keep_i + 1) begin
                            output_tready_sel[keep_i] = (keep_i == active_idx);
                        end
                    end
                end else begin // active queue but not valid yet, keep pulling
                    output_tready_single = 0;
                    for (hold_i = 0; hold_i < QUEUE_NUM; hold_i = hold_i + 1) begin
                        output_tready_sel[hold_i] = (hold_i == active_idx);
                    end
                end
            end else begin  //shift TREADY when no queue is ready
               chosen = -1;
               for (choose_i = 0; choose_i < QUEUE_NUM; choose_i = choose_i + 1) begin
                    if (chosen == -1 && (credits[choose_i] > output_deduct_credits[choose_i])) begin
                        chosen = choose_i;
                    end
               end
               if (chosen != -1) begin
                    for (set_i = 0; set_i < QUEUE_NUM; set_i = set_i + 1) begin
                        output_tready_sel[set_i] = (set_i == chosen);
                    end
               end else begin
                    output_tready_sel = {QUEUE_NUM{1'b0}};
               end
            end
        end
        end
    end





endmodule
