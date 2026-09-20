`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/11/2024 05:41:48 PM
// Design Name: 
// Module Name: Logistic_workload
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
module CNN_workload
#(ECHO  = 16'b0000, TOP_K = 16'b0001, CNN = 16'b0010, LOG=16'b0011, ASSEMBLED_DATA_SIZE = 48, PRECISION = 16)
(
    input wire clk,
    input wire [512:0] rx_TDATA,
    input wire rx_TVALID,
    output wire rx_TREADY,
    input wire [31:0] meta_TDATA,
    input wire [15:0] workload_selection, 
    output wire [511+1:0] pkt_tx_TDATA_payload,
    output wire tx_data_TVALID,
    input  wire tx_data_TREADY,
    output wire [31:0] meta_TDATA_out, 
    output wire meta_TVALID_out
);
    

    
    reg rx_TVALID_int;
    // Selection logic
    always @* begin
       if(workload_selection == CNN) begin
           rx_TVALID_int = rx_TVALID;
       end else begin
           rx_TVALID_int = 0;
       end
    end
            
    
    wire FIFO_output_TVALID;
    wire FIFO_output_TREADY_int;
    wire [512+32:0] FIFO_output_TDATA;
    
     axis_data_fifo_3 fifo_inst (
      .s_axis_aresetn(1'b1),  // input wire s_axis_aresetn
      .s_axis_aclk(clk),        // input wire s_axis_aclk
      .s_axis_tvalid(rx_TVALID_int),    // input wire s_axis_tvalid
      .s_axis_tready(rx_TREADY),    // output wire s_axis_tready
      .s_axis_tdata({meta_TDATA, rx_TDATA}),      // input wire [551 : 0] s_axis_tdata
      .m_axis_tvalid(FIFO_output_TVALID),    // output wire m_axis_tvalid
      .m_axis_tready(FIFO_output_TREADY_int),    // input wire m_axis_tready
      .m_axis_tdata(FIFO_output_TDATA)      // output wire [551 : 0] m_axis_tdata
    );
   
    wire [ASSEMBLED_DATA_SIZE - 1 :0] parsed_pkt_tx_TDATA;
    wire pkt_tx_TVALID_int;
    wire [31:0] meta_tdata_input;
    wire metadata_tvalid;
    reg input_CNN_data_ready;
    
   packet_parser_CNN packet_parser_CNN_inst(
        .clk(clk),
        .rx_TDATA(FIFO_output_TDATA),
        .rx_TVALID(FIFO_output_TVALID),
        .rx_TREADY(FIFO_output_TREADY_int),
        .tx_TDATA(parsed_pkt_tx_TDATA),
        .tx_TVALID(pkt_tx_TVALID_int),
        .tx_TREADY(input_CNN_data_ready),
        .metadata(meta_tdata_input),
        .metadata_tvalid(metadata_tvalid)
    );
    
    
    reg [31:0] cycle_counter = 0;
    always @(posedge clk) begin
        if (CNN_input_tvalid && CNN_input_tready && ap_rst_n == 1'b1) begin
            cycle_counter = cycle_counter + 1;
        end
        if (ap_ready == 1'b1) begin
            cycle_counter = 0;
        end
    end
    
    
    wire out_r_TVALID;
    wire [PRECISION*10-1:0] out_r_TDATA;
    wire out_r_TLAST;
    reg ap_rst_n = 0;
    wire ap_done;
    wire ap_ready;
    wire ap_idle;
    reg CNN_input_tvalid;
    wire CNN_input_tready;
    reg [ASSEMBLED_DATA_SIZE-1:0] CNN_input_tdata;
    
    /**Counter for buffering inside IP**/
    reg [1:0] ready_count = 0;
    reg [1:0] waiting_state = 0; //state_0: input network data; state_1: buffering 0s; state_2: output result
    
    
    always @(posedge clk) begin
        if (rx_TVALID && rx_TREADY) begin
            ap_rst_n = 1'b1;
        end
        
        if (waiting_state == 2 && ap_done == 1) begin
            CNN_input_tvalid = pkt_tx_TVALID_int;
            input_CNN_data_ready = CNN_input_tready;
            CNN_input_tdata = parsed_pkt_tx_TDATA;
            waiting_state = 0;
        end
        else if (ap_rst_n == 1'b1 && waiting_state == 1) begin //buffer with 0
            CNN_input_tvalid = 1'b1;
            input_CNN_data_ready = 0;
            CNN_input_tdata = 0;
            if (ap_ready == 1 && ready_count == 1) begin //buffer inputs
                ready_count = 0;
                CNN_input_tvalid = 0;
                input_CNN_data_ready = 0;
                CNN_input_tdata = 0;
                waiting_state = 2;
            end
            else if (ap_ready == 1 && ready_count == 0) begin
                ready_count = ready_count + 1;
            end
        end
        else if (ap_rst_n == 1'b1 && waiting_state == 0) begin //input the request data
            CNN_input_tvalid = pkt_tx_TVALID_int;
            input_CNN_data_ready =  CNN_input_tready;
            CNN_input_tdata = parsed_pkt_tx_TDATA; 
            if (ap_ready == 1) begin //buffer inputs
                ready_count = ready_count+1;
                CNN_input_tvalid = 0;
                input_CNN_data_ready = 0;
                CNN_input_tdata = 0;
                waiting_state = 1;
            end    
            else if (CNN_input_tvalid == 1'b0 && cycle_counter > 64) begin
                CNN_input_tvalid = 0;
                input_CNN_data_ready = 0;
                CNN_input_tdata = 0;
                waiting_state = 1;
            end    
        end

    end
    
     
myproject_1 myproject_1_inst (
  .input_1_V_TVALID(CNN_input_tvalid),          // input wire input_1_V_TVALID
  .input_1_V_TREADY(CNN_input_tready),          // output wire input_1_V_TREADY
  .input_1_V_TDATA(CNN_input_tdata),            // input wire [47 : 0] input_1_V_TDATA
  .layer34_out_V_TVALID(out_r_TVALID),  // output wire layer34_out_V_TVALID
   .layer34_out_V_TREADY(1'b1),  // input wire layer34_out_V_TREADY
  .layer34_out_V_TDATA(out_r_TDATA),    // output wire [159 : 0] layer34_out_V_TDATA
  .ap_clk(clk),                              // input wire ap_clk
  .ap_rst_n(ap_rst_n),                          // input wire ap_rst_n
  .ap_start(1'b1),                          // input wire ap_start
  .ap_done(ap_done),                            // output wire ap_done
  .ap_ready(ap_ready),                          // output wire ap_ready
  .ap_idle(ap_idle)                            // output wire ap_idle
);
 
    nukv_fifogen #(
        .DATA_SIZE(32),
        .ADDR_BITS(10)
    ) metadata_inst(
        .clk(clk),
        .s_axis_tvalid(metadata_tvalid),
        .s_axis_tready(),
        //.s_axis_tdata({meta_TDATA_calculated, meta_TDATA[15:0]}),
        .s_axis_tdata(meta_tdata_input),
        .m_axis_tvalid(meta_TVALID_out),
        .m_axis_tready(tx_data_TVALID && pkt_tx_TDATA_payload[512]),
        .m_axis_tdata(meta_TDATA_out)
    ); 
    
   
//    wire [31:0] output_payload;
//    wire output_tvalid;
//    wire output_tready;
    
//    assign output_tready = (meta_TVALID_out == 1'b1)? 1: 0;
    assign tx_data_TVALID = (waiting_state == 2)? out_r_TVALID: 0;
    assign pkt_tx_TDATA_payload [511:0] = (waiting_state == 2)?{352'b0, out_r_TDATA}:0;
    assign pkt_tx_TDATA_payload[512] = 1'b1;
    
    
    
endmodule