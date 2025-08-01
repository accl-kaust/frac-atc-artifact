`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 05/17/2023 02:42:04 PM
// Design Name:
// Module Name: pkt_logic
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


module pkt_logic
#(ECHO_0  = 16'b0000, ECHO_1 = 16'b0001, ECHO_2 = 16'b0010)
(
    input wire clk,
    input wire rst,
    input wire [512+88-1 + 1 : 0] pkt_rx_TDATA,
    input wire pkt_rx_TVALID,
    output wire pkt_rx_TREADY,
    output reg [512+32-1 + 1: 0] pkt_tx_TDATA,
    output reg pkt_tx_TVALID,
    input wire pkt_tx_TREADY
);

/**dispatcher**/

// wire [512 + 88 + 16 + 16: 0] pkt_out_TDATA;  // {packet_size,tx_selection, rx_TDATA}
// wire pkt_out_TVALID;
// wire pkt_out_TREADY;


//dispatcher dispatcher_inst(
//    .clk(clk),
//    .rx_TDATA(pkt_rx_TDATA),
//    .rx_TVALID(pkt_rx_TVALID),
//    .rx_TREADY(pkt_rx_TREADY),
//    .tx_TDATA(pkt_out_TDATA),
//    .tx_TVALID(pkt_out_TVALID),
//    .tx_TREADY(pkt_out_TREADY)
//    );

///**scheduler**/
//wire [512 + 32 + 16 :0] pkt_rx_TDATA_int;
////wire [512 + 88 + 16 :0] pkt_rx_TDATA_int; //{tx_selection, rx_TDATA}
//wire pkt_rx_TVALID_int;

//scheduler scheduler_inst
//(
//    .clk(clk),
//    .rx_TDATA( { pkt_out_TDATA[512 + 88 + 32: 512 + 88 + 1], pkt_out_TDATA[512 + 32: 0]}),
//    .rx_TVALID(pkt_out_TVALID),
//    .rx_TREADY(pkt_out_TREADY),
//    .tx_TDATA(pkt_rx_TDATA_int),
//    .tx_TVALID(pkt_rx_TVALID_int),
//    .tx_TREADY(pkt_rx_TREADY_int)
//);

/**dispatcher**/

wire [512 + 32 + 32 + 16: 0] pkt_out_TDATA;  //{packet_size, workload_selection,  session_ID, rx_TDATA}
wire pkt_out_TVALID;
wire pkt_out_TREADY;


dispatcher dispatcher_inst(
    .clk(clk),
    .rx_TDATA(pkt_rx_TDATA),
    .rx_TVALID(pkt_rx_TVALID),
    .rx_TREADY(pkt_rx_TREADY),
    .tx_TDATA(pkt_out_TDATA),
    .tx_TVALID(pkt_out_TVALID),
    .tx_TREADY(pkt_out_TREADY)
    );

/**scheduler**/
wire [512 + 32 + 16 :0] pkt_rx_TDATA_int; // {16-bit Workload_type. 32-bit ConnID, 512+1 payload}
//wire [512 + 88 + 16 :0] pkt_rx_TDATA_int; //{tx_selection, rx_TDATA}
wire pkt_rx_TVALID_int;

scheduler scheduler_inst
(
    .clk(clk),
    .rx_TDATA( pkt_out_TDATA),
    .rx_TVALID(pkt_out_TVALID),
    .rx_TREADY(pkt_out_TREADY),
    .tx_TDATA(pkt_rx_TDATA_int),
    .tx_TVALID(pkt_rx_TVALID_int),
    .tx_TREADY(pkt_rx_TREADY_int)
);

/*Workload modules*/

wire [512:0] pkt_tx_TDATA_payload_echo_0, pkt_tx_TDATA_payload_echo_1, pkt_tx_TDATA_payload_echo_2;
reg [31:0] meta_TDATA_out;
wire [31:0] meta_TDATA_out_echo_0, meta_TDATA_out_echo_1, meta_TDATA_out_echo_2;
reg meta_TVALID_out;
wire meta_TVALID_out_echo_0, meta_TVALID_out_echo_1, meta_TVALID_out_echo_2;
reg pkt_rx_TREADY_int;
wire pkt_rx_TREADY_echo_0_int, pkt_rx_TREADY_echo_1_int, pkt_rx_TREADY_echo_2_int;
wire pkt_tx_TVALID_echo_0, pkt_tx_TVALID_echo_1, pkt_tx_TVALID_echo_2;

/* For receiving */
always@* begin
   //case (pkt_rx_TDATA_int[512 + 88 + 16: 512 + 88 + 1])
   case (pkt_rx_TDATA_int[512 + 32 + 16: 512 + 32 + 1])
       ECHO_0: begin
             pkt_rx_TREADY_int = pkt_rx_TREADY_echo_0_int;
             end
       ECHO_1: begin
             pkt_rx_TREADY_int = pkt_rx_TREADY_echo_1_int;
            end
       ECHO_2 :begin
             pkt_rx_TREADY_int = pkt_rx_TREADY_echo_2_int;
            end
       default: begin
             pkt_rx_TREADY_int = pkt_rx_TREADY_echo_0_int;
            end
   endcase
end



echo_workload #(
    .ECHO(16'b0000)
)echo_workload_inst_0
(
    .clk(clk),
    .rx_TDATA(pkt_rx_TDATA_int[512:0]),
    .rx_TVALID(pkt_rx_TVALID_int),
    .rx_TREADY(pkt_rx_TREADY_echo_0_int),
    .meta_TDATA(pkt_rx_TDATA_int[512+32: 512+1]),
    //.workload_selection(pkt_rx_TDATA_int[512 + 88 + 16: 512 + 88 + 1]),
    .workload_selection(pkt_rx_TDATA_int[512 + 32 + 16: 512 + 32 + 1]),
    .pkt_tx_TDATA_payload(pkt_tx_TDATA_payload_echo_0),
    .tx_data_TVALID(pkt_tx_TVALID_echo_0),
    .tx_data_TREADY(1'b1),
    .meta_TDATA_out(meta_TDATA_out_echo_0),
    .meta_TVALID_out(meta_TVALID_out_echo_0)
);

echo_workload #(
    .ECHO(16'b0001)
)echo_workload_inst_1
(
    .clk(clk),
    .rx_TDATA(pkt_rx_TDATA_int[512:0]),
    .rx_TVALID(pkt_rx_TVALID_int),
    .rx_TREADY(pkt_rx_TREADY_echo_1_int),
    .meta_TDATA(pkt_rx_TDATA_int[512+32: 512+1]),
    //.workload_selection(pkt_rx_TDATA_int[512 + 88 + 16: 512 + 88 + 1]),
    .workload_selection(pkt_rx_TDATA_int[512 + 32 + 16: 512 + 32 + 1]),
    .pkt_tx_TDATA_payload(pkt_tx_TDATA_payload_echo_1),
    .tx_data_TVALID(pkt_tx_TVALID_echo_1),
    .tx_data_TREADY(1'b1),
    .meta_TDATA_out(meta_TDATA_out_echo_1),
    .meta_TVALID_out(meta_TVALID_out_echo_1)
);

echo_workload #(
    .ECHO(16'b0010)
    )echo_workload_inst_2
(
    .clk(clk),
    .rx_TDATA(pkt_rx_TDATA_int[512:0]),
    .rx_TVALID(pkt_rx_TVALID_int),
    .rx_TREADY(pkt_rx_TREADY_echo_2_int),
    .meta_TDATA(pkt_rx_TDATA_int[512+32: 512+1]),
    //.workload_selection(pkt_rx_TDATA_int[512 + 88 + 16: 512 + 88 + 1]),
    .workload_selection(pkt_rx_TDATA_int[512 + 32 + 16: 512 + 32 + 1]),
    .pkt_tx_TDATA_payload(pkt_tx_TDATA_payload_echo_2),
    .tx_data_TVALID(pkt_tx_TVALID_echo_2),
    .tx_data_TREADY(1'b1),
    .meta_TDATA_out(meta_TDATA_out_echo_2),
    .meta_TVALID_out(meta_TVALID_out_echo_2)
);


reg pkt_tx_TVALID_result_FIFO_echo_0, pkt_tx_TVALID_result_FIFO_echo_1, pkt_tx_TVALID_result_FIFO_echo_2;
reg [512:0] pkt_tx_TDATA_payload_echo_0_reg, pkt_tx_TDATA_payload_echo_1_reg, pkt_tx_TDATA_payload_echo_2_reg;
reg [31:0] meta_TDATA_out_echo_0_reg, meta_TDATA_out_echo_1_reg, meta_TDATA_out_echo_2_reg;



/*results of all workloads, generate input of FIFO, flow control*/
always@(posedge clk) begin
     pkt_tx_TDATA_payload_echo_0_reg <= pkt_tx_TDATA_payload_echo_0;
     meta_TDATA_out_echo_0_reg <= meta_TDATA_out_echo_0;   //metadata size exactly the same
     pkt_tx_TVALID_result_FIFO_echo_0 <= pkt_tx_TVALID_echo_0;

     pkt_tx_TDATA_payload_echo_1_reg <= pkt_tx_TDATA_payload_echo_1;
     meta_TDATA_out_echo_1_reg <= meta_TDATA_out_echo_1;   //metadata size exactly the same
     pkt_tx_TVALID_result_FIFO_echo_1 <= pkt_tx_TVALID_echo_1;


     pkt_tx_TDATA_payload_echo_2_reg <= pkt_tx_TDATA_payload_echo_2;
     meta_TDATA_out_echo_2_reg <= meta_TDATA_out_echo_2;   //metadata size exactly the same
     pkt_tx_TVALID_result_FIFO_echo_2 <= pkt_tx_TVALID_echo_2;
end


wire pkt_tx_TREADY_echo_0,pkt_tx_TREADY_echo_1,pkt_tx_TREADY_echo_2;
//Put result into each FIFO
wire [512 + 32 + 1 -1: 0] pkt_tx_TDATA_echo_0_out, pkt_tx_TDATA_echo_1_out, pkt_tx_TDATA_echo_2_out;
wire pkt_tx_TVALID_echo_0_out, pkt_tx_TVALID_echo_1_out, pkt_tx_TVALID_echo_2_out;
reg output_ready_echo_0, output_ready_echo_1, output_ready_echo_2;

// axis_data_fifo_3 Echo_FIFO_0 (
//   .s_axis_aresetn(1'b1),  // input wire s_axis_aresetn
//   .s_axis_aclk(clk),        // input wire s_axis_aclk
//   .s_axis_tvalid(pkt_tx_TVALID_result_FIFO_echo_0),    // input wire s_axis_tvalid
//   .s_axis_tready(pkt_tx_TREADY_echo_0),    // output wire s_axis_tready
//   .s_axis_tdata({7'b0, meta_TDATA_out_echo_0_reg, pkt_tx_TDATA_payload_echo_0_reg}),      // input wire [39 : 0] s_axis_tdata
//   .m_axis_tvalid(pkt_tx_TVALID_echo_0_out),    // output wire m_axis_tvalid
//   .m_axis_tready(output_ready_echo_0),    // input wire m_axis_tready
//   .m_axis_tdata(pkt_tx_TDATA_echo_0_out)      // output wire [39 : 0] m_axis_tdata
// );


// axis_data_fifo_3 Echo_FIFO_1 (
//   .s_axis_aresetn(1'b1),  // input wire s_axis_aresetn
//   .s_axis_aclk(clk),        // input wire s_axis_aclk
//   .s_axis_tvalid(pkt_tx_TVALID_result_FIFO_echo_1),    // input wire s_axis_tvalid
//   .s_axis_tready(pkt_tx_TREADY_echo_1),    // output wire s_axis_tready
//   .s_axis_tdata({7'b0, meta_TDATA_out_echo_1_reg, pkt_tx_TDATA_payload_echo_1_reg}),      // input wire [39 : 0] s_axis_tdata
//   .m_axis_tvalid(pkt_tx_TVALID_echo_1_out),    // output wire m_axis_tvalid
//   .m_axis_tready(output_ready_echo_1),    // input wire m_axis_tready
//   .m_axis_tdata(pkt_tx_TDATA_echo_1_out)      // output wire [39 : 0] m_axis_tdata
// );


// axis_data_fifo_3 Echo_FIFO_2 (
//   .s_axis_aresetn(1'b1),  // input wire s_axis_aresetn
//   .s_axis_aclk(clk),        // input wire s_axis_aclk
//   .s_axis_tvalid(pkt_tx_TVALID_result_FIFO_echo_2),    // input wire s_axis_tvalid
//   .s_axis_tready(pkt_tx_TREADY_echo_2),    // output wire s_axis_tready
//   .s_axis_tdata({7'b0, meta_TDATA_out_echo_2_reg, pkt_tx_TDATA_payload_echo_2_reg}),      // input wire [39 : 0] s_axis_tdata
//   .m_axis_tvalid(pkt_tx_TVALID_echo_2_out),    // output wire m_axis_tvalid
//   .m_axis_tready(output_ready_echo_2),    // input wire m_axis_tready
//   .m_axis_tdata(pkt_tx_TDATA_echo_2_out)      // output wire [39 : 0] m_axis_tdata
// );

 axis_fifo #
(
    .DEPTH(2),
    .KEEP_ENABLE(0),
    .DATA_WIDTH(545),
    .USER_ENABLE(0),
    .RAM_PIPELINE(2)
)
ECHO_FIFO_0
(
    .clk(clk),
    .rst(0),
    .s_axis_tdata({meta_TDATA_out_echo_0_reg, pkt_tx_TDATA_payload_echo_0_reg}),
    .s_axis_tkeep(),
    .s_axis_tvalid(pkt_tx_TVALID_result_FIFO_echo_0),
    .s_axis_tready(pkt_tx_TREADY_echo_0),
    .s_axis_tlast(),
    .s_axis_tid(),
    .s_axis_tdest(),
    .s_axis_tuser(),

    /*
     * AXI output
     */
    .m_axis_tdata(pkt_tx_TDATA_echo_0_out),
    .m_axis_tkeep(),
    .m_axis_tvalid(pkt_tx_TVALID_echo_0_out),
    .m_axis_tready(output_ready_echo_0),
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

 axis_fifo #
(
    .DEPTH(2),
    .KEEP_ENABLE(0),
    .DATA_WIDTH(545),
    .USER_ENABLE(0),
    .RAM_PIPELINE(2)
)
ECHO_FIFO_1
(
    .clk(clk),
    .rst(0),
    .s_axis_tdata({meta_TDATA_out_echo_1_reg, pkt_tx_TDATA_payload_echo_1_reg}),
    .s_axis_tkeep(),
    .s_axis_tvalid(pkt_tx_TVALID_result_FIFO_echo_1),
    .s_axis_tready(pkt_tx_TREADY_echo_1),
    .s_axis_tlast(),
    .s_axis_tid(),
    .s_axis_tdest(),
    .s_axis_tuser(),

    /*
     * AXI output
     */
    .m_axis_tdata(pkt_tx_TDATA_echo_1_out),
    .m_axis_tkeep(),
    .m_axis_tvalid(pkt_tx_TVALID_echo_1_out),
    .m_axis_tready(output_ready_echo_1),
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


 axis_fifo #
(
    .DEPTH(2),
    .KEEP_ENABLE(0),
    .DATA_WIDTH(545),
    .USER_ENABLE(0),
    .RAM_PIPELINE(2)
)
ECHO_FIFO_2
(
    .clk(clk),
    .rst(0),
    .s_axis_tdata({meta_TDATA_out_echo_2_reg, pkt_tx_TDATA_payload_echo_2_reg}),
    .s_axis_tkeep(),
    .s_axis_tvalid(pkt_tx_TVALID_result_FIFO_echo_2),
    .s_axis_tready(pkt_tx_TREADY_echo_2),
    .s_axis_tlast(),
    .s_axis_tid(),
    .s_axis_tdest(),
    .s_axis_tuser(),

    /*
     * AXI output
     */
    .m_axis_tdata(pkt_tx_TDATA_echo_2_out),
    .m_axis_tkeep(),
    .m_axis_tvalid(pkt_tx_TVALID_echo_2_out),
    .m_axis_tready(output_ready_echo_2),
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


reg [1:0] current_workload = 2'b0; // 2-bit register to keep track of the current workload
// 00: echo, 01: top_k, 10: MM_4_4

always @(posedge clk) begin
    if (current_workload == 2'b00) begin
        if (pkt_tx_TVALID_echo_0_out) begin
            output_ready_echo_0 = pkt_tx_TREADY;
            output_ready_echo_1 = 0;
            output_ready_echo_2 = 0;
            if (pkt_tx_TDATA_echo_0_out[512] == 1'b1) begin
                current_workload = 2'b01; // Switch to top_k
            end
        end
        else begin
            current_workload = 2'b01;
        end
    end else if (current_workload == 2'b01) begin
        if (pkt_tx_TVALID_echo_1_out) begin
            output_ready_echo_1 = pkt_tx_TREADY;
            output_ready_echo_0 = 0;
            output_ready_echo_2 = 0;
            if (pkt_tx_TDATA_echo_1_out[512] == 1'b1) begin
                current_workload = 2'b10; // Switch to MM_4_4
            end
        end
        else begin
            current_workload = 2'b10;
        end
    end else if (current_workload == 2'b10) begin
        if (pkt_tx_TVALID_echo_2_out) begin
            output_ready_echo_2 = pkt_tx_TREADY;
            output_ready_echo_1 = 0;
            output_ready_echo_0 = 0;
            if (pkt_tx_TDATA_echo_2_out[512] == 1'b1) begin
                current_workload = 2'b00; // Switch back to echo
            end
        end
        else begin
            current_workload = 2'b00;
        end
    end else begin
        output_ready_echo_0 = 0;
        output_ready_echo_1 = 0;
        output_ready_echo_2 = 0;
        current_workload = 2'b00; // Default to echo if no valid workload
    end
end

always @* begin
    if(pkt_tx_TVALID_echo_0_out && output_ready_echo_0) begin
        pkt_tx_TDATA = pkt_tx_TDATA_echo_0_out;
        pkt_tx_TVALID = pkt_tx_TDATA_echo_0_out && output_ready_echo_0;
    end
    else if(pkt_tx_TVALID_echo_1_out && output_ready_echo_1) begin
        pkt_tx_TDATA = pkt_tx_TDATA_echo_1_out;
        pkt_tx_TVALID = pkt_tx_TDATA_echo_1_out && output_ready_echo_1;
    end

    else if(pkt_tx_TVALID_echo_2_out && output_ready_echo_2) begin
        pkt_tx_TDATA = pkt_tx_TDATA_echo_2_out;
        pkt_tx_TVALID = pkt_tx_TDATA_echo_2_out && output_ready_echo_2;
    end

    else begin
       pkt_tx_TVALID = 0;
    end
end


//assign pkt_tx_TDATA = {meta_TDATA_out, 1'b1, pkt_tx_TDATA_payload};

endmodule
