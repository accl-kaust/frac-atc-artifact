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
#(ECHO  = 16'b0000, TOP_K = 16'b0001, MM = 16'b0010)
(
    input wire clk,
    input wire [512 + 88 : 0] rx_TDATA,
    input wire rx_TVALID,
    output wire rx_TREADY,
    output wire [512 + 88 + 16 + 16:0] tx_TDATA, //{packet_size, priority, workload_selection, rx_TDATA}
    output wire tx_TVALID,
    input wire tx_TREADY
    );

    reg [15:0] workload_selection;
    reg [512 + 88 + 16 + 16:0] rx_TDATA_combined; //{tx_selection, rx_TDATA}
    reg rx_TVALID_combined;
    reg [15:0] packet_size;
    reg [15:0] priority;
    assign rx_TREADY = 1;

    //dataline counter, recognize new configuration line
    always @(posedge clk) begin
        rx_TVALID_combined = rx_TVALID;
        //This line is configuration line,
        if (rx_TVALID == 1 && rx_TREADY == 1 && rx_TDATA[447:0] == 448'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) begin
             workload_selection = rx_TDATA[511: 496];
             packet_size =  rx_TDATA[480: 464];
             //priority = rx_TDATA[463: 448];
             //rx_TDATA_combined = {packet_size, priority, workload_selection, rx_TDATA};
             rx_TDATA_combined = {packet_size, workload_selection, rx_TDATA};
        end
        //This line is normal line
        else if (rx_TVALID == 1 && rx_TREADY == 1) begin
             //rx_TDATA_combined = {packet_size, priority, workload_selection, rx_TDATA};
             rx_TDATA_combined = {packet_size, workload_selection, rx_TDATA};
        end
    end

   //Send data to FIFO
    // nukv_fifogen #(
    //         .DATA_SIZE(512 + 88 + 1 + 16 + 16), //with TLAST encrypted in TDATA, clear signal
    //         //{packet_size, tx_selection, rx_TDATA}
    //         .ADDR_BITS(2)
    //     ) fifo_inst (
    //             .clk(clk),
    //             .s_axis_tvalid(rx_TVALID_combined && rx_TREADY),
    //             .s_axis_tready(),
    //             .s_axis_tdata(rx_TDATA_combined),
    //             .m_axis_tvalid(tx_TVALID),
    //             .m_axis_tready(tx_TREADY),
    //             .m_axis_tdata(tx_TDATA)
    //             );

axis_reg #(
    .DATA_WIDTH(633),
    .KEEP_ENABLE(0),
    .LAST_ENABLE(0),
    .USER_ENABLE(0),
    .REG_TYPE(2)
) disp_fifo_inst
(
    .clk(clk),
    .rst(0),
    .s_axis_tdata(rx_TDATA_combined),
    .s_axis_tkeep(),
    .s_axis_tvalid(rx_TVALID_combined && rx_TREADY),
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
    .m_axis_tuser()
);
//  axis_fifo #
// (
//      // 16384
//     .DEPTH(2),
//     .KEEP_ENABLE(0),
//     .DATA_WIDTH(633),
//     .USER_ENABLE(0),
//     .RAM_PIPELINE(5)
// )
// single_packet_fifo
// (
//     .clk(clk),
//     .rst(0),
//     .s_axis_tdata(rx_TDATA_combined),
//     .s_axis_tkeep(),
//     .s_axis_tvalid(rx_TVALID_combined && rx_TREADY),
//     .s_axis_tready(),
//     .s_axis_tlast(),
//     .s_axis_tid(),
//     .s_axis_tdest(),
//     .s_axis_tuser(),

//     /*
//      * AXI output
//      */
//     .m_axis_tdata(tx_TDATA),
//     .m_axis_tkeep(),
//     .m_axis_tvalid(tx_TVALID),
//     .m_axis_tready(tx_TREADY),
//     .m_axis_tlast(),
//     .m_axis_tid(),
//     .m_axis_tdest(),
//     .m_axis_tuser(),

//     /*
//      * Pause
//      */
//     .pause_req(),
//     .pause_ack(),

//     /*
//      * Status
//      */
//     .status_depth(),
//     .status_depth_commit(),
//     .status_overflow(),
//     .status_bad_frame(),
//     .status_good_frame()
// );


endmodule
