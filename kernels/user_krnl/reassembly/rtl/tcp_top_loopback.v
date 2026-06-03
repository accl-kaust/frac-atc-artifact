//---------------------------------------------------------------------------
//--  Copyright 2015 - 2017 Systems Group, ETH Zurich
//--
//--  This hardware module is free software: you can redistribute it and/or
//--  modify it under the terms of the GNU General Public License as published
//--  by the Free Software Foundation, either version 3 of the License, or
//--  (at your option) any later version.
//--
//--  This program is distributed in the hope that it will be useful,
//--  but WITHOUT ANY WARRANTY; without even the implied warranty of
//--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//--  GNU General Public License for more details.
//--
//--  You should have received a copy of the GNU General Public License
//--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//---------------------------------------------------------------------------


module tcp_top_loopback #(parameter IS_SIM = 0)
    (input wire clk,
     input wire rst,
     output wire	 m_axis_open_connection_tvalid,
     input wire 	 m_axis_open_connection_tready,
     output wire[47:0] m_axis_open_connection_tdata,
     input wire 	 s_axis_open_status_tvalid,
     output wire s_axis_open_status_tready,
     input wire[23:0] 	 s_axis_open_status_tdata,
     output wire 	 m_axis_close_connection_tvalid,
     input wire m_axis_close_connection_tready,
     output wire [15:0] m_axis_close_connection_tdata,
     output wire 	 m_axis_listen_port_tvalid,
     input wire m_axis_listen_port_tready,
     output wire [15:0] m_axis_listen_port_tdata,
     input wire 	 s_axis_listen_port_status_tvalid,
     output wire s_axis_listen_port_status_tready,
     input wire [7:0] 	 s_axis_listen_port_status_tdata,
     input wire 	 s_axis_notifications_tvalid,
     output wire s_axis_notifications_tready,
     input wire [87:0] 	 s_axis_notifications_tdata,
     output wire m_axis_read_package_tvalid,
     input wire m_axis_read_package_tready,
     output wire [31:0] m_axis_read_package_tdata,
     output wire m_axis_tx_data_tvalid,
     input wire m_axis_tx_data_tready,
     output wire [511:0] m_axis_tx_data_tdata,
      output wire [63:0] 	 m_axis_tx_data_tkeep,
     output wire m_axis_tx_data_tlast,
     output wire m_axis_tx_metadata_tvalid,              //for handshake logic
     input wire m_axis_tx_metadata_tready,
     output wire [31:0] m_axis_tx_metadata_tdata,         //for handshake logic
     input wire s_axis_tx_status_tvalid,
     output wire s_axis_tx_status_tready,
     input wire [63:0] 	 s_axis_tx_status_tdata,
     input wire 	 s_axis_rx_data_tvalid,
     output wire s_axis_rx_data_tready,
     input wire [511:0] 	 s_axis_rx_data_tdata,
     input wire [63:0] 	 s_axis_rx_data_tkeep,
     input wire [0:0] 	 s_axis_rx_data_tlast,
     input wire 	 s_axis_rx_metadata_tvalid,
     output wire 	 s_axis_rx_metadata_tready,
     input wire [15:0] 	 s_axis_rx_metadata_tdata);

    assign m_axis_close_connection_tvalid   = 0;
    assign s_axis_listen_port_status_tready = 1;
    assign s_axis_rx_metadata_tready        = 1;

    assign m_axis_open_connection_tvalid = 0;
    assign s_axis_open_status_tready     = 1;


    (* mark_debug = "true" *) reg 					    port_opened;
    (* mark_debug = "true" *) reg 					    axis_listen_port_valid;
    (* mark_debug = "true" *) reg [15:0] 				    axis_listen_port_data;
    //(* mark_debug = "true" *) wire[511:0] maxis_tx_data;
    //(* mark_debug = "true" *) wire maxis_tx_last;
    //(* mark_debug = "true" *) wire maxis_tx_ready;c
    //(* mark_debug = "true" *) wire maxis_tx_valid;

    //(* mark_debug = "true" *) wire[15:0] maxis_meta_data;
    //(* mark_debug = "true" *) wire maxis_meta_ready;
    //(* mark_debug = "true" *) wire maxis_meta_valid;


    reg [15:0] myClock;

    assign m_axis_listen_port_tdata  = axis_listen_port_data;
    assign m_axis_listen_port_tvalid = axis_listen_port_valid;


    //open up server port (2888)
    always @(posedge clk)
    begin
        if (rst) begin
            port_opened            <= 1'b0;
            axis_listen_port_valid <= 1'b0;
            axis_listen_port_data  <= 0;
            myClock                <= 0;
        end
        else begin
            axis_listen_port_valid <= 1'b0;

            //try every half millisecond
            if (myClock[15] == 1'b1 && port_opened == 0 && m_axis_listen_port_tready == 1) begin
                axis_listen_port_valid <= 1'b1;
                axis_listen_port_data <= 16'h0B48; //port = 2888
                port_opened <= 1;
            end


            myClock <= myClock+1;
        end
    end

    wire [512+88-1 + 1 : 0] pkt_tdata; //+tlast
    //wire [512+32-1 : 0] pkt_new_tdata;
    wire pkt_tvalid;
    wire pkt_tready;

    pkt_receiver pkt_receiver_inst(
        .clk(clk),
        .rst(rst),
        .s_axis_notifications_tdata(s_axis_notifications_tdata),
        .s_axis_notifications_tvalid(s_axis_notifications_tvalid),
        .s_axis_notifications_tready(s_axis_notifications_tready),
        .s_axis_rx_data_tdata({s_axis_rx_data_tlast, s_axis_rx_data_tdata}),
        .s_axis_rx_data_tvalid(s_axis_rx_data_tvalid),
        .s_axis_rx_data_tready(s_axis_rx_data_tready),
        .m_axis_read_package_tdata(m_axis_read_package_tdata),
        .m_axis_read_package_tvalid(m_axis_read_package_tvalid),
        .m_axis_read_package_tready(m_axis_read_package_tready),
        .pkt_tx_tdata(pkt_tdata), //meta_data + payload 88 + 512
        .pkt_tx_tvalid(pkt_tvalid),
        .pkt_tx_tready(pkt_tready)
    );


    wire [512+32-1 + 1: 0] pkt_tdata_int;
    wire pkt_tvalid_int;
    wire pkt_tready_int;


    pkt_logic pkt_logic_inst(
        .clk(clk),
        .rst(rst),
        .pkt_rx_tdata(pkt_tdata),
        .pkt_rx_tvalid(pkt_tvalid),
        .pkt_rx_tready(pkt_tready),
        .pkt_tx_tdata(pkt_tdata_int),
        .pkt_tx_tvalid(pkt_tvalid_int),
        .pkt_tx_tready(pkt_tready_int)
    );


    pkt_sender pkt_sender_inst(
        .clk(clk),
        .rst(rst),
        .pkt_rx_tdata(pkt_tdata_int), //metadata + tlast + tdata
        .pkt_rx_tvalid(pkt_tvalid_int),
        .pkt_rx_tready(pkt_tready_int),
        .s_axis_tx_status_tdata(s_axis_tx_status_tdata),
        .s_axis_tx_status_tvalid(s_axis_tx_status_tvalid),
        .s_axis_tx_status_tready(s_axis_tx_status_tready),
        .m_axis_tx_metadata_tdata(m_axis_tx_metadata_tdata),
        .m_axis_tx_metadata_tvalid(m_axis_tx_metadata_tvalid),
        .m_axis_tx_metadata_tready(m_axis_tx_metadata_tready),
        .m_axis_tx_data_tdata(m_axis_tx_data_tdata),
        .m_axis_tx_data_tvalid(m_axis_tx_data_tvalid),
        .m_axis_tx_data_tkeep(m_axis_tx_data_tkeep),
        .m_axis_tx_data_tlast(m_axis_tx_data_tlast),
        .m_axis_tx_data_tready(m_axis_tx_data_tready)
    );

endmodule
