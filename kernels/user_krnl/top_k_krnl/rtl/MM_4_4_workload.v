`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2023 10:59:36
// Design Name: 
// Module Name: MM_4_4_workload
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


module MM_4_4_workload
#(ECHO  = 16'b0000, TOP_K = 16'b0001, MM = 16'b0010)
(
    input wire clk,
    input wire [512:0] rx_TDATA,
    input wire rx_TVALID,
    output wire rx_TREADY,
    input wire [31:0] meta_TDATA,
    input wire [15:0] workload_selection, 
    output wire [511 + 1:0] pkt_tx_TDATA_payload,
    output wire tx_data_TVALID,
    input  wire tx_data_TREADY,
    output wire [31:0] meta_TDATA_out, 
    output wire meta_TVALID_out
    );
    
    wire [511 + 1:0] pkt_tx_TDATA_1_int, pkt_tx_TDATA_2_int;
    wire pkt_tx_TVALID_int;
    reg rx_TVALID_int;
    
    /**selection**/
    always @* begin
       if(workload_selection == MM) begin
           rx_TVALID_int = rx_TVALID;
       end 
       else begin
           rx_TVALID_int = 0;
       end
    end
    
   wire FIFO_output_TVALID;
   wire FIFO_output_TREADY;
   wire [512+32:0] FIFO_output_TDATA;
    
   nukv_fifogen #(
        .DATA_SIZE(513+32), //tlast + tdata
        .ADDR_BITS(12)
    ) fifo_inst(
        .clk(clk),
        .rst(0),
        .s_axis_tvalid(rx_TVALID_int),
        .s_axis_tready(rx_TREADY),
        .s_axis_tdata({meta_TDATA, rx_TDATA}),
        .m_axis_tvalid(FIFO_output_TVALID),
        .m_axis_tready(FIFO_output_TREADY),
        .m_axis_tdata(FIFO_output_TDATA)
    );
    
    
    
    
    
    packet_parser_MM_44 packet_paser_MM_44_isnt(
    .clk(clk),
    .pkt_rx_TDATA(FIFO_output_TDATA[511:0]),
    .pkt_rx_TVALID(FIFO_output_TVALID),
    .pkt_rx_TLAST(FIFO_output_TDATA[512] && FIFO_output_TVALID),
    .pkt_rx_TREADY(FIFO_output_TREADY),
    .pkt_tx_TDATA_1(pkt_tx_TDATA_1_int),
    .pkt_tx_TDATA_2 (pkt_tx_TDATA_2_int),
    .pkt_tx_TVALID(pkt_tx_TVALID_int),
    .pkt_tx_TREADY(tx_data_TREADY)
    );
    
    reg [31:0] counter = 0;
    reg meta_TVALID_inFIFO = 0;
    reg [31:0] meta_FIFO_output_TDATA_reg;
    reg [15:0] meta_MM_datasize;
    reg [15:0] right_part;
    reg [15:0] divided_value;
    
    always @(posedge clk) begin
        meta_FIFO_output_TDATA_reg <= {meta_MM_datasize,FIFO_output_TDATA[512 + 16: 512 + 1]};
        if(FIFO_output_TVALID == 1'b1 && FIFO_output_TREADY == 1'b1 && FIFO_output_TDATA[447:0]!= 448'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) begin
            counter = counter + 1;
            meta_TVALID_inFIFO = 0;
            if(counter == 2) begin
               counter = 0;
               meta_TVALID_inFIFO = 1;
            end
        end
        else begin
            meta_TVALID_inFIFO = 0;
        end
    end

    always @* begin
        right_part = FIFO_output_TDATA[512 + 32: 512 + 17];
        divided_value = right_part >> 7;    //divide by 64
        meta_MM_datasize = divided_value << 6;     // Multiplying by 64 using left shift
    end
    
    reg tready_output_payload_meta;
    
    wire meta_TVALID_out_reg;
     nukv_fifogen #(
        .DATA_SIZE(32),
        .ADDR_BITS(9)
     ) metadata_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(meta_TVALID_inFIFO),
        .s_axis_tready(),
        .s_axis_tdata(meta_FIFO_output_TDATA_reg),
        .m_axis_tvalid(meta_TVALID_out_reg),
        .m_axis_tready(tready_output_payload_meta),
        .m_axis_tdata(meta_TDATA_out)
    ); 
    
    wire [511:0] pkt_tx_TDATA_payload_reg;
    
    top_mul top_mul_inst(
    .ap_clk(clk),
    .ap_rst_n(1'b0),
    .ap_start(1'b1),
    .ap_done(),
    .ap_idle(),
    .ap_ready(),
    .inStream1_TDATA(pkt_tx_TDATA_1_int[511:0]),
    .inStream1_TVALID(pkt_tx_TVALID_int),
    .inStream1_TREADY(),
    .inStream1_TKEEP(64'hFFFFFFFFFFFFFFFF),
    .inStream1_TSTRB(64'hFFFFFFFFFFFFFFFF),
    .inStream1_TLAST(pkt_tx_TVALID_int),
    .inStream2_TDATA(pkt_tx_TDATA_2_int),
    .inStream2_TVALID(pkt_tx_TVALID_int),
    .inStream2_TREADY(),
    .inStream2_TKEEP(64'hFFFFFFFFFFFFFFFF),
    .inStream2_TSTRB(64'hFFFFFFFFFFFFFFFF),
    .inStream2_TLAST(pkt_tx_TVALID_int),
    .outStream_TDATA(pkt_tx_TDATA_payload_reg),
    .outStream_TVALID(),
    .outStream_TREADY(1'b1),
    .outStream_TKEEP(),
    .outStream_TSTRB(),
    .outStream_TLAST()
     );
    
    
    reg pkt_tx_TVALID_int_1;
    reg pkt_tx_TLAST_int_1;
    reg tx_data_TVALID_reg;
    reg tx_data_TLAST_reg;

    /******/
    always @(posedge clk) begin
       pkt_tx_TVALID_int_1 <= pkt_tx_TVALID_int;
       pkt_tx_TLAST_int_1 <= pkt_tx_TDATA_1_int[512];
       tx_data_TVALID_reg <= pkt_tx_TVALID_int_1;
       tx_data_TLAST_reg <= pkt_tx_TLAST_int_1;      
    end

    
    wire payload_data_valid;
    
      nukv_fifogen #(
        .DATA_SIZE(512 + 1),
        .ADDR_BITS(12)
     ) payloaddata_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(tx_data_TVALID_reg),
        .s_axis_tready(),
        .s_axis_tdata({tx_data_TLAST_reg, pkt_tx_TDATA_payload_reg}),
        .m_axis_tvalid(payload_data_valid),
        .m_axis_tready(tready_output_payload_meta),
        .m_axis_tdata(pkt_tx_TDATA_payload)
    ); 
    
    always @(*) begin
        if(payload_data_valid == 1 && meta_TVALID_out_reg == 1) begin
            tready_output_payload_meta = 1'b1;
        end
        else begin
            tready_output_payload_meta = 1'b0;
        end
    end
    
    assign tx_data_TVALID = tready_output_payload_meta && payload_data_valid && meta_TVALID_out_reg;
    assign meta_TVALID_out = tx_data_TVALID;
   
endmodule