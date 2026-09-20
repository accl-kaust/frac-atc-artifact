`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/15/2024 03:53:59 PM
// Design Name: 
// Module Name: packet_parser_logistic
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


module packet_parser_CNN
#(INPUT_DATA_SIZE = 16, ASSEMBLED_DATA_SIZE=48)
(
    input wire clk,
    input wire rst,
    input wire [512 + 32:0] rx_TDATA,
    input wire rx_TVALID,
    output wire rx_TREADY,
    output wire [ASSEMBLED_DATA_SIZE - 1: 0] tx_TDATA,
    output wire tx_TVALID,
    input wire tx_TREADY,
    output wire [31:0] metadata,
    output wire metadata_tvalid
    );
    
    reg [511+1:0] rx_TDATA_parsing = 0;
    reg [INPUT_DATA_SIZE - 1 + 1:0]current_data_TDATA; //tlast + data
    reg current_data_TVALID;
    reg rx_TREADY_reg = 1;
    
    reg [ASSEMBLED_DATA_SIZE-1:0] assembled_data = 0;  // Buffer for assembling three 16-bit values into 48-bit
    reg [1:0] data_count = 0;       // Counter for 3 data pieces
    reg assembled_data_valid = 0;   // Valid signal for assembled 48-bit data
    
    assign rx_TREADY = rx_TREADY_reg;
    assign metadata = {16'd64, rx_TDATA[512+16: 513]};
    assign metadata_tvalid = rx_TDATA[512] && rx_TVALID && rx_TREADY;
 
   //0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    //Parse the new dataline and put each data in FIFO
    always @(posedge clk) begin
        if (assembled_data_valid == 1'b1) begin
            assembled_data_valid = 1'b0;
        end
    
    
        if(rx_TDATA_parsing != 0) begin      //parsing the current        
            if((rx_TDATA_parsing[511 + 1: INPUT_DATA_SIZE +1] == 0) && (rx_TDATA_parsing[INPUT_DATA_SIZE] == 1'b1)) begin    //is the last
                current_data_TDATA = {1'b1, rx_TDATA_parsing[INPUT_DATA_SIZE - 1:0]};   
                rx_TDATA_parsing = 0; //shift
                current_data_TVALID = 1'b1; 
                rx_TREADY_reg = 0;
            end
            else begin      //not the last of this dataline
                current_data_TDATA = {1'b0, rx_TDATA_parsing[INPUT_DATA_SIZE - 1:0]};  //not the last
                rx_TDATA_parsing = {16'b0, rx_TDATA_parsing[511 + 1: INPUT_DATA_SIZE]}; //shift
                current_data_TVALID = 1'b1; 
                rx_TREADY_reg = 0;
            end    
           
            // Assemble three 16-bit words into 48-bit
            assembled_data = {current_data_TDATA[INPUT_DATA_SIZE-1:0], assembled_data[ASSEMBLED_DATA_SIZE-1:INPUT_DATA_SIZE]};  
            data_count = data_count + 1;
            if (data_count == 3) begin  // Once 3 x 16-bit received
                assembled_data_valid = 1'b1;
                data_count = 0;
            end
        end

        else begin
            current_data_TVALID = 1'b0;
            if (rx_TDATA[447:0]!= 448'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) begin //not the configuration line
                if(rx_TVALID == 1 && rx_TREADY_reg == 1) begin  
                    rx_TDATA_parsing = rx_TDATA[512:0];
                    rx_TREADY_reg = 0;
                end
                else begin
                    rx_TREADY_reg = 1;
                end
            end
            else begin
                rx_TREADY_reg = 1;
            end
        end
    end
    
    reg [31:0] input_dataline_counter = 0;
    reg [31:0] input_numbers = 0;
    always@(posedge clk) begin
        if (rx_TVALID && rx_TREADY) begin
            input_dataline_counter = input_dataline_counter + 1;
        end
        if (assembled_data_valid) begin
            input_numbers = input_numbers + 1;
        end
    end
    
    
    
    
    axis_data_fifo_32_long fifo_inst (
      .s_axis_aresetn(1'b1),  // input wire s_axis_aresetn
      .s_axis_aclk(clk),        // input wire s_axis_aclk
      .s_axis_tvalid(assembled_data_valid),    // input wire s_axis_tvalid
      .s_axis_tready(),    // output wire s_axis_tready
      .s_axis_tdata(assembled_data),      // input wire [63 : 0] s_axis_tdata
      .m_axis_tvalid(tx_TVALID),    // output wire m_axis_tvalid
      .m_axis_tready(tx_TREADY),    // input wire m_axis_tready
      .m_axis_tdata(tx_TDATA)      // output wire [63 : 0] m_axis_tdata
    );
    
   
                
endmodule
