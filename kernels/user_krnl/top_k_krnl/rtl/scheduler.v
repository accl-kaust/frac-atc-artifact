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
#(QUEUE_NUM = 4, TDATA_SIZE = 512 + 32 + WORKLOAD_SIZE + PACKET_SIZE + 1, CONN_ID = 16, WORKLOAD_SIZE = 16,PACKET_SIZE = 32, META_SIZE = 16,
    ECHO  = 0, TOP_K = 1, MM = 2, LOG = 3, CRYPTO = 4, NORM = 5)
(
    input wire clk,
    input wire [TDATA_SIZE - 1: 0] rx_TDATA, // {packet_size, tx_selection,  rx_TDATA}
    input wire rx_TVALID,
    output reg rx_TREADY,
    output wire [512 + 16 + 32 :0] tx_TDATA, // {32-bit ConnID, 16-bit Workload_type. 512+1 payload}
    output wire tx_TVALID,
    input wire tx_TREADY
    );
    //for debug
    wire [31:0] metadata;
    assign metadata =  tx_TDATA[512+32: 512 + 1];


    //Normal queues input
    reg  [1 + 512 + 32 + 16: 0] input_TDATA [QUEUE_NUM - 1: 0]; //last of message + tdata + meta
    reg  [QUEUE_NUM - 1: 0] input_TVALID;
    wire [QUEUE_NUM - 1: 0] input_TREADY;

    //Single-packet queue input
    reg  [1 + 512 + 32 + 16: 0] input_TDATA_single;
    reg  input_TVALID_single;
    wire  input_TREADY_single;

    //Normal queues output
    //wire [71 * 8 - 1: 0] output_TDATA [QUEUE_NUM - 1: 0];
    wire [1 + 512 + 32 + 16: 0] output_TDATA [QUEUE_NUM - 1: 0];
    wire [QUEUE_NUM - 1: 0] output_TVALID;
    reg [QUEUE_NUM - 1: 0] output_TREADY;
    reg  [7:0] credits [QUEUE_NUM - 1: 0];
    reg [7:0] output_deduct_credits [QUEUE_NUM - 1: 0];

    //Single-packet queue output
    wire [1 + 512 + 32 + 16: 0] output_TDATA_single;
    wire output_TVALID_single;
    reg output_TREADY_single_FIFO;

    //meta_reg
    reg  [WORKLOAD_SIZE + CONN_ID - 1: 0] input_META_0 = 32'hffffffff;
    reg  [WORKLOAD_SIZE + CONN_ID - 1: 0] input_META_1 = 32'hffffffff;
    reg  [WORKLOAD_SIZE + CONN_ID - 1: 0] input_META_2 = 32'hffffffff;
    reg  [WORKLOAD_SIZE + CONN_ID - 1: 0] input_META_3 = 32'hffffffff;
    reg  [WORKLOAD_SIZE + CONN_ID - 1: 0] input_META_single = 32'hffffffff;



   always @(posedge clk) begin
        output_TREADY[0] <= output_TREADY_0;
        output_TREADY[1] <= output_TREADY_1;
        output_TREADY[2] <= output_TREADY_2;
        output_TREADY[3] <= output_TREADY_3;
        output_TREADY_single_FIFO <= output_TREADY_single;
   end

    //initialize all virtual queues and credits
    genvar i;
    generate
        for (i=0; i< QUEUE_NUM; i=i+1) begin
            //  axis_data_fifo_0 fifo_inst(
            //   .s_axis_aresetn(1'b1),
            //   .s_axis_aclk(clk),
            //   .s_axis_tvalid(input_TVALID[i]),
            //   .s_axis_tready(input_TREADY[i]),
            //   .s_axis_tdata({7'b0, input_TDATA[i]}),
            //   .m_axis_tvalid(output_TVALID[i]),
            //   .m_axis_tready(output_TREADY[i]),
            //   .m_axis_tdata(output_TDATA[i])
            // );

            axis_fifo_ultra #
                (
                .DEPTH(512),
                .KEEP_ENABLE(0),
                .DATA_WIDTH(561),
                .USER_ENABLE(0),
                .RAM_PIPELINE(5)
            )
            reassm_buff
                (
                .clk(clk),
                .rst(0),
                .s_axis_tdata(input_TDATA[i]),
                .s_axis_tkeep(),
                .s_axis_tvalid(input_TVALID[i]),
                .s_axis_tready(input_TREADY[i]),
                .s_axis_tlast(),
                .s_axis_tid(),
                .s_axis_tdest(),
                .s_axis_tuser(),

                /*
                 * AXI output
                 */
                .m_axis_tdata(output_TDATA[i]),
                .m_axis_tkeep(),
                .m_axis_tvalid(output_TVALID[i]),
                .m_axis_tready(output_TREADY[i]),
                .m_axis_tlast(),
                .m_axis_tid(),
                .m_axis_tdest(),
                .m_axis_tuser(),

                /*
                 * Pause
                 */
                .pause_req(),
                .pause_ack(),

                /*
                 * Status
                 */
                .status_depth(),
                .status_depth_commit(),
                .status_overflow(),
                .status_bad_frame(),
                .status_good_frame()
            );

        end
    endgenerate

    //Single-packet FIFO
    //  axis_data_fifo_1 fifo_inst(
    //   .s_axis_aresetn(1'b1),
    //   .s_axis_aclk(clk),
    //   .s_axis_tvalid(input_TVALID_single),
    //   .s_axis_tready(input_TREADY_single),
    //   .s_axis_tdata({7'b0, input_TDATA_single}),
    //   .m_axis_tvalid(output_TVALID_single),
    //   .m_axis_tready(output_TREADY_single_FIFO),
    //   .m_axis_tdata(output_TDATA_single)
    // );

 axis_fifo #
(
     // 16384
    .DEPTH(16384),
    .KEEP_ENABLE(0),
    .DATA_WIDTH(561),
    .USER_ENABLE(0),
    .RAM_PIPELINE(5)
)
single_packet_fifo
(
    .clk(clk),
    .rst(0),
    .s_axis_tdata(input_TDATA_single),
    .s_axis_tkeep(),
    .s_axis_tvalid(input_TVALID_single),
    .s_axis_tready(input_TREADY_single),
    .s_axis_tlast(),
    .s_axis_tid(),
    .s_axis_tdest(),
    .s_axis_tuser(),

    /*
     * AXI output
     */
    .m_axis_tdata(output_TDATA_single),
    .m_axis_tkeep(),
    .m_axis_tvalid(output_TVALID_single),
    .m_axis_tready(output_TREADY_single_FIFO),
    .m_axis_tlast(),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(),

    /*
     * Pause
     */
    .pause_req(),
    .pause_ack(),

    /*
     * Status
     */
    .status_depth(),
    .status_depth_commit(),
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);



    integer initial_i;
    initial begin
        for (initial_i = 0; initial_i < QUEUE_NUM; initial_i = initial_i + 1) begin
            credits[initial_i] = 8'b0;
            output_deduct_credits[initial_i] = 8'b0;
        end
    end

    //input signals
    reg [31:0] counter_0, counter_inst_0;
    reg [31:0] counter_1, counter_inst_1;
    reg [31:0] counter_2, counter_inst_2;
    reg [31:0] counter_3, counter_inst_3;


    integer queue;
    always @(posedge clk) begin
        /*credits clear logic*/
       for (queue = 0; queue < QUEUE_NUM; queue = queue + 1) begin
            if (credits[queue] == output_deduct_credits[queue]) begin
                credits[queue] = 8'b0000;
            end
       end
       if(rx_TVALID == 1 && rx_TREADY == 1)begin
            //matches the meta

            //The single packet situation, concatenating the first one
            if(rx_TDATA[512 + CONN_ID: 512 + 1] == input_META_single[CONN_ID - 1:0] && input_TREADY_single == 1) begin
                input_TVALID_single = rx_TVALID;
                input_TDATA_single = {1'b0, input_META_single[31:16],rx_TDATA[512 + 32: 0]}; //{message_end (1-bit), workload_type (16-bit), meta_data (32-bit),tlast(1-bit), payload (512_bit)}
                rx_TREADY = 1'b1;
                if(input_TDATA_single[512] == 1) begin //the last of the packet
                   input_TDATA_single[512+32+16+1] = 1'b1; //the last of the message, always the last
                   input_META_single = 32'hffffffff;
                end
            end

            //The multi-packet situations
            else if(rx_TDATA[512 + CONN_ID: 512 + 1] == input_META_0[CONN_ID - 1:0] && input_TREADY[0] == 1) begin //send to FIFO 0
                input_TVALID[0] = rx_TVALID;
                input_TDATA[0] = {1'b0, input_META_0[31:16],rx_TDATA[512 + 32: 0]};
                rx_TREADY = 1'b1;
                if(input_TDATA[0][512] == 1) begin //the last of the packet
                    //counter_inst_0 = counter_inst_0 + 1;
                    counter_inst_0 = counter_inst_0 + rx_TDATA[512 + META_SIZE + CONN_ID: 512+ CONN_ID + 1];
                    if(counter_inst_0 == counter_0) begin //the last of the multi-packet, reset_everything
                        credits[0] = credits[0] + 1;
                        input_META_0 = 32'hffffffff;
                        counter_inst_0 = 0;
                        counter_0 = 0;
                        input_TDATA[0][512+32+16+1] = 1'b1; //the last of the message
                    end
                    else begin   //not the last of multi-packet
                        input_TDATA[0][512+32+16+1] = 1'b0; //assemble these packets
                        //Get the middle last removed, only have last signal when sending
                          if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] != ECHO) begin
                            input_TDATA[0][512] = 1'b0;
                          end
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == TOP_K) begin
//                            input_TDATA[0][512] = 1'b0;
//                        end
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == NORM) begin
//                            input_TDATA[0][512] = 1'b0;
//                        end
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == LOG) begin
//                            input_TDATA[0][512] = 1'b0;
//                        end
                    end
                end
            end
            else if (rx_TDATA[512 + CONN_ID: 512 + 1] == input_META_1[CONN_ID - 1:0] && input_TREADY[1] == 1) begin
                input_TVALID[1] = rx_TVALID;
                input_TDATA[1] = {1'b0, input_META_1[31:16],rx_TDATA[512 + 32: 0]};
                rx_TREADY = 1'b1;;
                if(input_TDATA[1][512] == 1) begin //the last of the packet
                    counter_inst_1 = counter_inst_1 + rx_TDATA[512 + META_SIZE + CONN_ID: 512+ CONN_ID + 1];
                    if(counter_inst_1 == counter_1) begin //the last of the multi-packet, reset_everything
                        credits[1] = credits[1] + 1;
                        input_META_1 = 32'hffffffff;
                        counter_inst_1 = 0;
                        counter_1 = 0;
                        input_TDATA[1][512+32+16+1] = 1'b1; //the last of the message
                    end
                    else begin   //not the last of multi-packet
                        input_TDATA[1][512+32+16+1] = 1'b0; //assemble these packets
                        //Get the middle last removed, only have last signal when sending
                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] != ECHO) begin
                            input_TDATA[1][512] = 1'b0;
                        end
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == TOP_K) begin
//                            input_TDATA[1][512] = 1'b0;
//                        end
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == NORM) begin
//                            input_TDATA[1][512] = 1'b0;
//                        end
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == LOG) begin
//                            input_TDATA[1][512] = 1'b0;
//                        end
                    end
                end
            end
            else if (rx_TDATA[512 + CONN_ID: 512 + 1] == input_META_2[CONN_ID - 1:0] && input_TREADY[2] == 1) begin
                input_TVALID[2] = rx_TVALID;
                input_TDATA[2] = {1'b0, input_META_2[31:16],rx_TDATA[512 + 32: 0]};
                rx_TREADY = 1'b1;
                if(input_TDATA[2][512] == 1) begin //the last of the packet
                    counter_inst_2 = counter_inst_2 + rx_TDATA[512 + META_SIZE + CONN_ID: 512+ CONN_ID + 1];
                    if(counter_inst_2 == counter_2) begin //the last of the multi-packet, reset_everything
                        credits[2] = credits[2] + 1;
                        input_META_2 = 32'hffffffff;
                        counter_inst_2 = 0;
                        counter_2 = 0;
                        input_TDATA[2][512+32+16+1] = 1'b1;
                    end
                    else begin   //not the last of multi-packet
                        input_TDATA[2][512+32+16+1] = 1'b0; //assemble these packets
                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] != ECHO) begin
                            input_TDATA[2][512] = 1'b0;
                        end
                        //Get the middle last removed, only have last signal when sending
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == TOP_K) begin
//                            input_TDATA[2][512] = 1'b0;
//                        end
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == NORM) begin
//                            input_TDATA[2][512] = 1'b0;
//                        end
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == LOG) begin
//                            input_TDATA[2][512] = 1'b0;
//                        end
                    end
                end
            end
            else if (rx_TDATA[512 + CONN_ID: 512 + 1] == input_META_3[CONN_ID - 1:0] && input_TREADY[3] == 1) begin
                input_TVALID[3] = rx_TVALID;
                input_TDATA[3] = {1'b0, input_META_3[31:16],rx_TDATA[512 + 32: 0]};
                rx_TREADY = 1'b1;
                if(input_TDATA[3][512] == 1) begin //the last of the packet
                    counter_inst_3 = counter_inst_3 + rx_TDATA[512 + META_SIZE + CONN_ID: 512+ CONN_ID + 1];
                    if(counter_inst_3 == counter_3) begin //the last of the multi-packet, reset_everything
                        credits[3] = credits[3] + 1;
                        input_META_3 = 32'hffffffff;
                        counter_inst_3 = 0;
                        counter_3 = 0;
                        input_TDATA[3][512+32+16+1] = 1'b1;
                    end
                    else begin   //not the last of multi-packet
                        input_TDATA[3][512+32+16+1] = 1'b0; //assemble these packets
                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] != ECHO) begin
                            input_TDATA[3][512] = 1'b0;
                        end
                       //Get the middle last removed, only have last signal when sending
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == TOP_K) begin
//                            input_TDATA[3][512] = 1'b0;
//                        end
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == NORM) begin
//                            input_TDATA[3][512] = 1'b0;
//                        end
//                        if (rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32] == LOG) begin
//                            input_TDATA[3][512] = 1'b0;
//                        end
                    end
                end
            end

            //does not match the meta, the first dataline of the session
            else if ((input_META_single == 32'hffffffff) && (rx_TDATA[TDATA_SIZE - 1: TDATA_SIZE - PACKET_SIZE] == rx_TDATA[512 + META_SIZE + CONN_ID: 512+ CONN_ID + 1])) begin
                input_TVALID_single = rx_TVALID;
                input_TDATA_single = {1'b0, rx_TDATA[512 + 32 + 16: 0]};
                input_META_single = {rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32], rx_TDATA[512 + CONN_ID: 512 + 1]};
                rx_TREADY = 1'b1;
            end
            else if ((input_META_0 == 32'hffffffff) && (rx_TDATA[TDATA_SIZE - 1: TDATA_SIZE - PACKET_SIZE] != rx_TDATA[512 + META_SIZE + CONN_ID: 512+ CONN_ID + 1])) begin
                input_TVALID[0] = rx_TVALID;
                input_TDATA[0] = {1'b0, rx_TDATA[512 + 32 + 16: 0]};
                input_META_0 = {rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32], rx_TDATA[512 + CONN_ID: 512 + 1]};
                counter_0 = rx_TDATA[TDATA_SIZE - 1: TDATA_SIZE - PACKET_SIZE];
                counter_inst_0 = 0;
                rx_TREADY = 1'b1;
            end
            else if((input_META_1 == 32'hffffffff) && (rx_TDATA[TDATA_SIZE - 1: TDATA_SIZE - PACKET_SIZE] != rx_TDATA[512 + META_SIZE + CONN_ID: 512+ CONN_ID + 1])) begin
                input_TVALID[1] = rx_TVALID;
                input_TDATA[1] = {1'b0, rx_TDATA[512 + 32 + 16: 0]};
                input_META_1 = {rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32], rx_TDATA[512 + CONN_ID: 512 + 1]};
                counter_1 = rx_TDATA[TDATA_SIZE - 1: TDATA_SIZE - PACKET_SIZE];
                counter_inst_1 = 0;
                rx_TREADY = 1'b1;
            end
            else if((input_META_2 == 32'hffffffff) && (rx_TDATA[TDATA_SIZE - 1: TDATA_SIZE - PACKET_SIZE] != rx_TDATA[512 + META_SIZE + CONN_ID: 512+ CONN_ID + 1])) begin
                input_TVALID[2] = rx_TVALID;
                input_TDATA[2] = {1'b0, rx_TDATA[512 + 32 + 16: 0]};
                input_META_2 = {rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 1 + 32], rx_TDATA[512 + CONN_ID: 512 + 1]};
                counter_2 = rx_TDATA[TDATA_SIZE - 1: TDATA_SIZE - PACKET_SIZE];
                counter_inst_2 = 0;
                rx_TREADY = 1'b1;
            end
            else if((input_META_3 == 32'hffffffff) && (rx_TDATA[TDATA_SIZE - 1: TDATA_SIZE - PACKET_SIZE] != rx_TDATA[512 + META_SIZE + CONN_ID: 512+ CONN_ID + 1])) begin
                input_TVALID[3] = rx_TVALID;
                input_TDATA[3] = {1'b0, rx_TDATA[512 + 32 + 16: 0]};
                input_META_3 = {rx_TDATA[512 + 32 + WORKLOAD_SIZE: 512 + 32 + 1], rx_TDATA[512 + CONN_ID: 512 + 1]};
                counter_3 = rx_TDATA[TDATA_SIZE - 1: TDATA_SIZE - PACKET_SIZE];
                counter_inst_3 = 0;
                rx_TREADY = 1'b1;
            end
        //No queue is avaliable
            else begin
                rx_TREADY = 1'b0;
            end
        end
        //NO data input
        else begin
            rx_TREADY = 1'b1;
            input_TVALID_single = 1'b0;
            input_TVALID[0] = 1'b0;
            input_TVALID[1] = 1'b0;
            input_TVALID[2] = 1'b0;
            input_TVALID[3] = 1'b0;
        end
    end

// output queue
        // axis_data_fifo_0 fifo_inst_output(
        //   .s_axis_aresetn(1'b1),
        //   .s_axis_aclk(clk),
        //   .s_axis_tvalid(output_queue_tvalid_FIFO),
        //   .s_axis_tready(),
        //   .s_axis_tdata({7'b0, output_queue_tdata}),
        //   .m_axis_tvalid(tx_TVALID),
        //   .m_axis_tready(tx_TREADY),
        //   .m_axis_tdata(tx_TDATA)
        // );

    //output signal
    reg [512 + 32 + 16 :0] output_queue_tdata; // {16-bit ConnID, 16-bit Workload_type. 32-bit payload_size, 512+1 payload}
    wire output_queue_tvalid_FIFO;
    reg output_queue_tvalid;
    reg [3:0] output_queue_number = 4'b1111;

    reg output_TREADY_0 = 0;
    reg output_TREADY_1 = 0;
    reg output_TREADY_2 = 0;
    reg output_TREADY_3 = 0;
    reg output_TREADY_single = 0;


    assign output_queue_tvalid_FIFO = output_queue_tvalid;


 axis_fifo_ultra #
(
     // 16384
    .DEPTH(512),
    .KEEP_ENABLE(0),
    .DATA_WIDTH(561),
    .USER_ENABLE(0),
    .RAM_PIPELINE(5)
)
fifo_output_inst
(
    .clk(clk),
    .rst(0),
    .s_axis_tdata(output_queue_tdata),
    .s_axis_tkeep(),
    .s_axis_tvalid(output_queue_tvalid_FIFO),
    .s_axis_tready(),
    .s_axis_tlast(),
    .s_axis_tid(),
    .s_axis_tdest(),
    .s_axis_tuser(),

    /*
     * AXI output
     */
    .m_axis_tdata(tx_TDATA),
    .m_axis_tkeep(),
    .m_axis_tvalid(tx_TVALID),
    .m_axis_tready(tx_TREADY),
    .m_axis_tlast(),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(),

    /*
     * Pause
     */
    .pause_req(),
    .pause_ack(),

    /*
     * Status
     */
    .status_depth(),
    .status_depth_commit(),
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);


    always @* begin
       case (output_queue_number)
           4'b0000:begin
                output_queue_tvalid = output_TVALID[0] && output_TREADY_0;
                output_queue_tdata = output_TDATA[0][512 + 32 + 16 :0];
           end
           4'b0001:begin
                output_queue_tvalid = output_TVALID[1] && output_TREADY_1;
                output_queue_tdata = output_TDATA[1][512 + 32 + 16 :0];
           end
           4'b0010:begin
                output_queue_tvalid = output_TVALID[2] && output_TREADY_2;
                output_queue_tdata = output_TDATA[2][512 + 32 + 16 :0];
           end
           4'b0011:begin
                output_queue_tvalid = output_TVALID[3] && output_TREADY_3;
                output_queue_tdata = output_TDATA[3][512 + 32 + 16 :0];
           end
           4'b0100:begin
                output_queue_tvalid = output_TVALID_single && output_TREADY_single_FIFO;
                output_queue_tdata = output_TDATA_single[512 + 32 + 16 :0];
           end
           default begin
                output_queue_tvalid = 0;
                output_queue_tdata = 0;
           end

        endcase
    end

    integer output_queue;
    always @(posedge clk) begin
        //output credits clear and update
       for (output_queue = 0; output_queue < QUEUE_NUM; output_queue = output_queue + 1) begin
            if (credits[output_queue] == output_deduct_credits[output_queue]) begin
                output_deduct_credits[output_queue] = 8'b0000;
            end
       end

       //single-packet queue output
        if(output_TVALID_single == 1'b1) begin
            output_queue_number = 4;
            output_TREADY_0 = 0;
            output_TREADY_1 = 0;
            output_TREADY_2 = 0;
            output_TREADY_3 = 0;
            output_TREADY_single = 1;
        end

       //Other normal queues situations
       else begin
            output_TREADY_single = 0; //clear the TREADY_single, since the single packet queue is not going to be output

            //Queue 0 get the polling chance
            if(output_TREADY_0 == 1 && (credits[0] > output_deduct_credits[0])) begin //have packet to pull
                if(output_TVALID[0]  == 1) begin
                    output_queue_number = 0;
                    if(output_TDATA[0][512+32+16+1] == 1 && output_TVALID[0] == 1) begin //The last dataline in the last packet of the request
                        output_TREADY_0 = 0;     //This queue need to be shifted
                        output_deduct_credits[0] =  output_deduct_credits[0] + 1; //decuct the credit
                        if(output_TVALID_single == 1'b1) begin  // single queue is ready to be output
                           output_TREADY_single = 1'b1;
                        end
                        else if(output_TVALID[1] == 1 && (credits[1] > output_deduct_credits[1]))begin //First queue is ready to be output
                            output_TREADY_1 = 1;
                        end
                        else if(output_TVALID[2] == 1 && (credits[2] > output_deduct_credits[2]))begin //Second queue is ready to be output
                            output_TREADY_2 = 1;
                        end
                        else if(output_TVALID[3] == 1 && (credits[3] > output_deduct_credits[3]))begin //Third queue is ready to be output
                            output_TREADY_3 = 1;
                        end
                        else if(output_TVALID[0] == 1 && (credits[0] > output_deduct_credits[0]))begin //Forth queue is ready to be output
                            output_TREADY_0 = 1;
                        end
                    end
                end
                else begin //Have packet to pull, but not fulling pulled, keep pulling
                    output_TREADY_single = 0;
                    output_TREADY_0 = 1;
                    output_TREADY_1 = 0;
                    output_TREADY_2 = 0;
                    output_TREADY_3 = 0;
                end
            end

            //Queue 1 get the polling chance
            else if (output_TREADY_1 == 1 && (credits[1] > output_deduct_credits[1])) begin
                if(output_TVALID[1]  == 1) begin
                    output_queue_number = 1;
                    if(output_TDATA[1][512+32+16+1] == 1 && output_TVALID[1] == 1) begin
                        output_TREADY_1 = 0;
                        output_deduct_credits[1] =  output_deduct_credits[1] + 1;
                        if(output_TVALID_single == 1'b1) begin
                           output_TREADY_single = 1'b1;
                        end
                        else if(output_TVALID[2] == 1 && (credits[2] > output_deduct_credits[2]))begin
                            output_TREADY_2 = 1;
                        end
                        else if(output_TVALID[3] == 1 && (credits[3] > output_deduct_credits[3]))begin
                            output_TREADY_3 = 1;
                        end
                        else if(output_TVALID[0] == 1 && (credits[0] > output_deduct_credits[0]))begin
                            output_TREADY_0 = 1;
                        end
                        else if(output_TVALID[1] == 1  && (credits[1] > output_deduct_credits[1]))begin
                            output_TREADY_1 = 1;
                        end
                    end
                end
                else begin
                    output_TREADY_single = 0;
                    output_TREADY_0 = 0;
                    output_TREADY_1 = 1;
                    output_TREADY_2 = 0;
                    output_TREADY_3 = 0;
                end
            end
            else if (output_TREADY_2 == 1 && (credits[2] > output_deduct_credits[2])) begin
                if(output_TVALID[2]  == 1) begin
                     output_queue_number = 2;
                    if(output_TDATA[2][512+32+16+1] == 1 && output_TVALID[2] == 1) begin
                        output_TREADY_2 = 0;
                        output_deduct_credits[2] =  output_deduct_credits[2] + 1;
                        if(output_TVALID_single == 1'b1) begin
                           output_TREADY_single = 1'b1;
                        end
                        else if(output_TVALID[3] == 1 && (credits[3] > output_deduct_credits[3]))begin
                            output_TREADY_3 = 1;
                        end
                        else if(output_TVALID[0] == 1 && (credits[0] > output_deduct_credits[0]))begin
                            output_TREADY_0 = 1;
                        end
                        else if(output_TVALID[1] == 1  && (credits[1] > output_deduct_credits[1]))begin
                            output_TREADY_1 = 1;
                        end
                        else if(output_TVALID[2] == 1 && (credits[2] > output_deduct_credits[2]))begin
                            output_TREADY_2 = 1;
                        end
                    end
                end
                else begin
                    output_TREADY_single = 0;
                    output_TREADY_0 = 0;
                    output_TREADY_1 = 0;
                    output_TREADY_2 = 1;
                    output_TREADY_3 = 0;
                end
            end
            else if (output_TREADY_3 == 1 && (credits[3] > output_deduct_credits[3])) begin
                if (output_TVALID[3]  == 1) begin
                      output_queue_number = 3;
                    if(output_TDATA[3][512+32+16+1] == 1 && output_TVALID[3] == 1) begin
                        output_TREADY_3 = 0;
                        output_deduct_credits[3] =  output_deduct_credits[3] + 1;
                        if(output_TVALID_single == 1'b1) begin
                           output_TREADY_single = 1'b1;
                        end
                        else if(output_TVALID[0] == 1 && (credits[0] > output_deduct_credits[0]))begin
                            output_TREADY_0 = 1;
                        end
                        else if(output_TVALID[1] == 1  && (credits[1] > output_deduct_credits[1]))begin
                            output_TREADY_1 = 1;
                        end
                        else if(output_TVALID[2] == 1 && (credits[2] > output_deduct_credits[2]))begin
                            output_TREADY_2 = 1;
                        end
                        else if(output_TVALID[3] == 1 && (credits[3] > output_deduct_credits[3]))begin
                            output_TREADY_3 = 1;
                        end
                    end
                end
                else begin
                    output_TREADY_single = 0;
                    output_TREADY_0 = 0;
                    output_TREADY_1 = 0;
                    output_TREADY_2 = 0;
                    output_TREADY_3 = 1;
                end
            end

            else begin  //shift TREADY when no queue is ready
               if(credits[0] > output_deduct_credits[0]) begin
                    output_TREADY_0 = 1;
                    output_TREADY_1 = 0;
                    output_TREADY_2 = 0;
                    output_TREADY_3 = 0;
               end
               else if (credits[1] > output_deduct_credits[1]) begin
                    output_TREADY_0 = 0;
                    output_TREADY_1 = 1;
                    output_TREADY_2 = 0;
                    output_TREADY_3 = 0;
               end
               else if (credits[2] > output_deduct_credits[2]) begin
                    output_TREADY_0 = 0;
                    output_TREADY_1 = 0;
                    output_TREADY_2 = 1;
                    output_TREADY_3 = 0;
               end
               else if (credits[3] > output_deduct_credits[3]) begin
                    output_TREADY_0 = 0;
                    output_TREADY_1 = 0;
                    output_TREADY_2 = 0;
                    output_TREADY_3 = 1;
               end
            end
        end
    end




endmodule
