`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/21/2023 11:37:16 AM
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


module packet_parser_MM_44(
    input wire clk,
    input wire [511:0] pkt_rx_TDATA,
    input wire pkt_rx_TVALID,
    input wire pkt_rx_TLAST,
    output wire pkt_rx_TREADY,
    output reg [511 + 1:0] pkt_tx_TDATA_1, //add one for tlast
    output reg [511 + 1:0] pkt_tx_TDATA_2, //add one for tlast
    output reg pkt_tx_TVALID,
    input wire pkt_tx_TREADY
    );
    
    reg [1:0] counter = 0;
    reg [511: 0] pkt_tx_TDATA_1_reg;
    
    
    always @(posedge clk) begin
        pkt_tx_TVALID = 0;
        pkt_tx_TDATA_1 = 0;
        pkt_tx_TDATA_2 = 0;
        if(pkt_rx_TVALID == 1 && pkt_tx_TREADY == 1 && pkt_rx_TDATA[447:0] != 448'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) begin
           counter  = counter + 1;
           if(counter == 2 && pkt_rx_TLAST == 1) begin
              pkt_tx_TDATA_1 = {1'b1,pkt_tx_TDATA_1_reg};
              pkt_tx_TDATA_2 = {1'b1, pkt_rx_TDATA};
              pkt_tx_TVALID = 1;
              counter = 0;
           end    
           else if (counter == 2 && pkt_rx_TLAST == 0) begin
              pkt_tx_TDATA_1 = {1'b0, pkt_tx_TDATA_1_reg};
              pkt_tx_TDATA_2 = {1'b0, pkt_rx_TDATA};
              pkt_tx_TVALID = 1;
              counter = 0;
           end
           else if (counter  == 1) begin       
              pkt_tx_TDATA_1_reg = pkt_rx_TDATA;
           end
        end
    end
    
    assign pkt_rx_TREADY = pkt_tx_TREADY;
    
    
    
endmodule