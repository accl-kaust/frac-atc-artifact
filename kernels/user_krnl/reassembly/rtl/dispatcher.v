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
#(ECHO  = 16'b0000, TOP_K = 16'b0001, MM = 16'b0010, LOG = 6'b0011, CRYPTO=16'b0100 , NORM=16'b0101)
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

    reg [15:0] workload_selection;
    reg [512 + 88 + 32 + 16:0] rx_tdata_combined; //{tx_selection, rx_tdata}
    reg rx_tvalid_combined;
    reg [31:0] packet_size;
    reg [31:0] meta_data;

    assign rx_tready=1;
    //dataline counter, recognize new configuration line
    always @(posedge clk) begin
        if (rst) begin
             workload_selection = 16'd0;
             packet_size = 32'd0;
             meta_data = 32'd0;
             rx_tdata_combined = 0;
             rx_tvalid_combined = 1'b0;
        end else begin
        rx_tvalid_combined = rx_tvalid;
        //This line is configuration line,
        if (rx_tvalid == 1 && rx_tready == 1 && rx_tdata[447:0] == {448{1'b1}}) begin
             workload_selection = rx_tdata[511: 496];
             packet_size =  rx_tdata[479: 448];   //32-bit
             rx_tdata_combined = {packet_size, workload_selection, rx_tdata[512+32: 0]};
             meta_data = rx_tdata[512+32: 513];
        end
        //This line is normal line
        else if (rx_tvalid == 1 && rx_tready == 1) begin
             rx_tdata_combined = {packet_size, workload_selection, rx_tdata[512+32: 0]};
             meta_data = rx_tdata[512+32: 513];
        end
        end
    end

wire [599:0] tx_tdata_reg;
axis_data_fifo_2 fifo_inst(
  .rst(rst),
  .clk(clk),        // input wire s_axis_aclk
  .s_axis_tvalid(rx_tvalid_combined && rx_tready),    // input wire s_axis_tvalid
  .s_axis_tready(),    // output wire s_axis_tready
  .s_axis_tdata({7'b0, rx_tdata_combined}),      // input wire [639 : 0] s_axis_tdata
  .m_axis_tvalid(tx_tvalid),    // output wire m_axis_tvalid
  .m_axis_tready(tx_tready),    // input wire m_axis_tready
  .m_axis_tdata(tx_tdata_reg)      // output wire [639 : 0] m_axis_tdata
);
assign tx_tdata = tx_tdata_reg[592:0];

endmodule
