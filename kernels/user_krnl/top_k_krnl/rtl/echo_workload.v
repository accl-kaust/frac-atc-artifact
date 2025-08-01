`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.07.2023 10:38:36
// Design Name: 
// Module Name: echo_workload
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


module echo_workload
#(parameter ECHO = 16'b00000)
(
    input wire clk,
    input wire [512:0] rx_TDATA,
    input wire rx_TVALID,
    output wire rx_TREADY,
    input wire [31:0] meta_TDATA,
    input wire [15:0] workload_selection, 
    output wire [512:0] pkt_tx_TDATA_payload, //add tlast
    output wire tx_data_TVALID,
    input  wire tx_data_TREADY,
    output wire [31:0] meta_TDATA_out, 
    output wire meta_TVALID_out
    );
    
    reg rx_TVALID_int;
    
    /**selection**/
    always @* begin
       if(workload_selection == ECHO) begin
           rx_TVALID_int = rx_TVALID;
       end 
       else begin
           rx_TVALID_int = 0;
       end
    end
    
    assign rx_TREADY = tx_data_TREADY;
    assign pkt_tx_TDATA_payload = rx_TDATA;
    //assign tx_data_TVALID = rx_TVALID_int & rx_TDATA[512];
    assign tx_data_TVALID = rx_TVALID_int;
    assign meta_TDATA_out = meta_TDATA;
    assign meta_TVALID_out = rx_TVALID & rx_TREADY & rx_TDATA[512]& rx_TVALID_int;
   
    
endmodule