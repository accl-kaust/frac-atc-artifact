`resetall
`timescale 1ns / 1ps
`default_nettype none

module reconfctrl #(
    parameter ADDR_WIDTH = 33,
    parameter AXI_DATA_WIDTH = 256,
    parameter AXIS_DATA_WIDTH = 512,
    parameter ICAP_DATA_WIDTH = 32
) (
    input  wire                         clk,
    input  wire                         rst,

    input  wire                         s_axis_tvalid,
    output reg                          s_axis_tready,
    input  wire [AXIS_DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire [AXIS_DATA_WIDTH/8-1:0] s_axis_tkeep,
    input  wire                         s_axis_tlast,

    output reg                          m_axis_tvalid,
    input  wire                         m_axis_tready,
    output reg  [AXIS_DATA_WIDTH-1:0]   m_axis_tdata,
    output reg  [AXIS_DATA_WIDTH/8-1:0] m_axis_tkeep,
    output reg                          m_axis_tlast,

    output reg                          m_axis_icap_tvalid,
    input  wire                         m_axis_icap_tready,
    output reg  [ICAP_DATA_WIDTH-1:0]   m_axis_icap_tdata,
    output reg                          m_axis_icap_tlast,

    output reg  [ADDR_WIDTH-1:0]        m_axi_awaddr,
    output wire [1:0]                   m_axi_awburst,
    output wire [5:0]                   m_axi_awid,
    output wire [7:0]                   m_axi_awlen,
    output wire [2:0]                   m_axi_awsize,
    output reg                          m_axi_awvalid,
    input  wire                         m_axi_awready,

    output reg  [AXI_DATA_WIDTH-1:0]    m_axi_wdata,
    output reg  [AXI_DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output wire [AXI_DATA_WIDTH/8-1:0]  m_axi_wdata_parity,
    output reg                          m_axi_wlast,
    output reg                          m_axi_wvalid,
    input  wire                         m_axi_wready,

    input  wire [5:0]                   m_axi_bid,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,
    output reg                          m_axi_bready,

    output reg  [ADDR_WIDTH-1:0]        m_axi_araddr,
    output wire [1:0]                   m_axi_arburst,
    output wire [5:0]                   m_axi_arid,
    output wire [7:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output reg                          m_axi_arvalid,
    input  wire                         m_axi_arready,

    input  wire [5:0]                   m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]  m_axi_rdata_parity,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    output reg                          m_axi_rready,

    output wire [3:0]                   state,
    output reg  [7:0]                   last_error
);

localparam [7:0]
    OP_WRITE_HBM   = 8'd1,
    OP_READ_HBM    = 8'd2,
    OP_RECONF_ICAP = 8'd3;

localparam [7:0]
    ERR_OK        = 8'd0,
    ERR_OPCODE    = 8'd1,
    ERR_ALIGN     = 8'd2,
    ERR_SIZE      = 8'd3,
    ERR_ADDR      = 8'd4,
    ERR_AXI_BRESP = 8'd5,
    ERR_AXI_RRESP = 8'd6,
    ERR_RLAST     = 8'd7;

localparam [3:0]
    STATE_IDLE            = 4'd0,
    STATE_WRITE_WAIT_DATA = 4'd1,
    STATE_WRITE_ADDR      = 4'd2,
    STATE_WRITE_DATA      = 4'd3,
    STATE_WRITE_RESP      = 4'd4,
    STATE_READ_ADDR_0     = 4'd5,
    STATE_READ_DATA_0     = 4'd6,
    STATE_READ_ADDR_1     = 4'd7,
    STATE_READ_DATA_1     = 4'd8,
    STATE_READ_SEND       = 4'd9,
    STATE_RECONF_ADDR     = 4'd10,
    STATE_RECONF_DATA     = 4'd11,
    STATE_RECONF_STREAM   = 4'd12,
    STATE_SEND_STATUS     = 4'd13;

localparam [ADDR_WIDTH-1:0] ADDR_INCR_32 = {{ADDR_WIDTH-6{1'b0}}, 6'd32};

reg [3:0] state_reg = STATE_IDLE;
reg [ADDR_WIDTH-1:0] current_addr_reg = {ADDR_WIDTH{1'b0}};
reg [63:0] remaining_bytes_reg = 64'd0;
reg [63:0] icap_words_remaining_reg = 64'd0;
reg [AXIS_DATA_WIDTH-1:0] data_line_reg = {AXIS_DATA_WIDTH{1'b0}};
reg [6:0] line_bytes_reg = 7'd0;
reg half_select_reg = 1'b0;
reg [AXIS_DATA_WIDTH-1:0] read_response_reg = {AXIS_DATA_WIDTH{1'b0}};
reg [AXI_DATA_WIDTH-1:0] read_data_reg = {AXI_DATA_WIDTH{1'b0}};
reg [2:0] icap_word_index_reg = 3'd0;
reg [7:0] status_reg = ERR_OK;

wire [7:0] cmd_opcode = s_axis_tdata[7:0];
wire [63:0] cmd_addr = s_axis_tdata[127:64];
wire [63:0] cmd_size = s_axis_tdata[191:128];
wire cmd_addr_fits = cmd_addr[63:ADDR_WIDTH] == {(64-ADDR_WIDTH){1'b0}};
wire cmd_addr_aligned = cmd_addr[4:0] == 5'd0;
wire cmd_size_nonzero = cmd_size != 64'd0;
wire cmd_read_size_ok = cmd_size <= 64'd64;
wire cmd_reconf_size_ok = cmd_size[1:0] == 2'd0;

assign state = state_reg;
assign m_axi_awid = 6'd0;
assign m_axi_awlen = 8'd0;
assign m_axi_awsize = 3'd5;
assign m_axi_awburst = 2'b01;
assign m_axi_wdata_parity = {(AXI_DATA_WIDTH/8){1'b0}};
assign m_axi_arid = 6'd0;
assign m_axi_arlen = 8'd0;
assign m_axi_arsize = 3'd5;
assign m_axi_arburst = 2'b01;

function [AXI_DATA_WIDTH/8-1:0] strobe_for_bytes;
    input [5:0] byte_count;
    integer i;
begin
    strobe_for_bytes = {(AXI_DATA_WIDTH/8){1'b0}};
    for (i = 0; i < AXI_DATA_WIDTH/8; i = i + 1) begin
        if (i < byte_count) begin
            strobe_for_bytes[i] = 1'b1;
        end
    end
end
endfunction

function [5:0] write_bytes_for_half;
    input [6:0] line_bytes;
    input half_select;
begin
    if (!half_select) begin
        if (line_bytes >= 7'd32) begin
            write_bytes_for_half = 6'd32;
        end else begin
            write_bytes_for_half = line_bytes[5:0];
        end
    end else if (line_bytes >= 7'd64) begin
        write_bytes_for_half = 6'd32;
    end else if (line_bytes > 7'd32) begin
        write_bytes_for_half = line_bytes[5:0] - 6'd32;
    end else begin
        write_bytes_for_half = 6'd0;
    end
end
endfunction

function [6:0] next_line_bytes;
    input [63:0] remaining_bytes;
begin
    if (remaining_bytes > 64'd64) begin
        next_line_bytes = 7'd64;
    end else begin
        next_line_bytes = remaining_bytes[6:0];
    end
end
endfunction

function [AXI_DATA_WIDTH-1:0] mask_data_256;
    input [AXI_DATA_WIDTH-1:0] data;
    input [5:0] byte_count;
    integer i;
begin
    mask_data_256 = {AXI_DATA_WIDTH{1'b0}};
    for (i = 0; i < AXI_DATA_WIDTH/8; i = i + 1) begin
        if (i < byte_count) begin
            mask_data_256[i*8 +: 8] = data[i*8 +: 8];
        end
    end
end
endfunction

function [5:0] read_first_byte_count;
    input [63:0] byte_count;
begin
    if (byte_count >= 64'd32) begin
        read_first_byte_count = 6'd32;
    end else begin
        read_first_byte_count = byte_count[5:0];
    end
end
endfunction

function [5:0] read_second_byte_count;
    input [63:0] byte_count;
    reg [63:0] tail_count;
begin
    tail_count = byte_count - 64'd32;
    if (tail_count >= 64'd32) begin
        read_second_byte_count = 6'd32;
    end else begin
        read_second_byte_count = tail_count[5:0];
    end
end
endfunction

function [31:0] select_icap_word;
    input [AXI_DATA_WIDTH-1:0] data;
    input [2:0] index;
begin
    case (index)
        3'd0: select_icap_word = data[31:0];
        3'd1: select_icap_word = data[63:32];
        3'd2: select_icap_word = data[95:64];
        3'd3: select_icap_word = data[127:96];
        3'd4: select_icap_word = data[159:128];
        3'd5: select_icap_word = data[191:160];
        3'd6: select_icap_word = data[223:192];
        default: select_icap_word = data[255:224];
    endcase
end
endfunction

task start_status;
    input [7:0] status;
begin
    status_reg <= status;
    last_error <= status;
    m_axis_tdata <= {AXIS_DATA_WIDTH{1'b0}};
    m_axis_tdata[7:0] <= status;
    m_axis_tkeep <= {(AXIS_DATA_WIDTH/8){1'b1}};
    m_axis_tlast <= 1'b1;
    m_axis_tvalid <= 1'b1;
    state_reg <= STATE_SEND_STATUS;
end
endtask

always @(posedge clk) begin
    if (rst) begin
        state_reg <= STATE_IDLE;
        s_axis_tready <= 1'b0;
        m_axis_tvalid <= 1'b0;
        m_axis_tdata <= {AXIS_DATA_WIDTH{1'b0}};
        m_axis_tkeep <= {(AXIS_DATA_WIDTH/8){1'b0}};
        m_axis_tlast <= 1'b0;
        m_axis_icap_tvalid <= 1'b0;
        m_axis_icap_tdata <= {ICAP_DATA_WIDTH{1'b0}};
        m_axis_icap_tlast <= 1'b0;
        m_axi_awaddr <= {ADDR_WIDTH{1'b0}};
        m_axi_awvalid <= 1'b0;
        m_axi_wdata <= {AXI_DATA_WIDTH{1'b0}};
        m_axi_wstrb <= {(AXI_DATA_WIDTH/8){1'b0}};
        m_axi_wlast <= 1'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
        m_axi_araddr <= {ADDR_WIDTH{1'b0}};
        m_axi_arvalid <= 1'b0;
        m_axi_rready <= 1'b0;
        current_addr_reg <= {ADDR_WIDTH{1'b0}};
        remaining_bytes_reg <= 64'd0;
        icap_words_remaining_reg <= 64'd0;
        data_line_reg <= {AXIS_DATA_WIDTH{1'b0}};
        line_bytes_reg <= 7'd0;
        half_select_reg <= 1'b0;
        read_response_reg <= {AXIS_DATA_WIDTH{1'b0}};
        read_data_reg <= {AXI_DATA_WIDTH{1'b0}};
        icap_word_index_reg <= 3'd0;
        status_reg <= ERR_OK;
        last_error <= ERR_OK;
    end else begin
        case (state_reg)
            STATE_IDLE: begin
                s_axis_tready <= 1'b1;
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
                m_axis_icap_tvalid <= 1'b0;
                m_axis_icap_tlast <= 1'b0;
                m_axi_awvalid <= 1'b0;
                m_axi_wvalid <= 1'b0;
                m_axi_wlast <= 1'b0;
                m_axi_bready <= 1'b0;
                m_axi_arvalid <= 1'b0;
                m_axi_rready <= 1'b0;

                if (s_axis_tvalid && s_axis_tready) begin
                    s_axis_tready <= 1'b0;

                    if (cmd_opcode != OP_WRITE_HBM && cmd_opcode != OP_READ_HBM && cmd_opcode != OP_RECONF_ICAP) begin
                        start_status(ERR_OPCODE);
                    end else if (!cmd_addr_fits) begin
                        start_status(ERR_ADDR);
                    end else if (!cmd_addr_aligned) begin
                        start_status(ERR_ALIGN);
                    end else if (!cmd_size_nonzero) begin
                        start_status(ERR_SIZE);
                    end else if (cmd_opcode == OP_READ_HBM && !cmd_read_size_ok) begin
                        start_status(ERR_SIZE);
                    end else if (cmd_opcode == OP_RECONF_ICAP && !cmd_reconf_size_ok) begin
                        start_status(ERR_SIZE);
                    end else if (cmd_opcode == OP_WRITE_HBM) begin
                        current_addr_reg <= cmd_addr[ADDR_WIDTH-1:0];
                        remaining_bytes_reg <= cmd_size;
                        state_reg <= STATE_WRITE_WAIT_DATA;
                    end else if (cmd_opcode == OP_READ_HBM) begin
                        current_addr_reg <= cmd_addr[ADDR_WIDTH-1:0];
                        remaining_bytes_reg <= cmd_size;
                        read_response_reg <= {AXIS_DATA_WIDTH{1'b0}};
                        state_reg <= STATE_READ_ADDR_0;
                    end else begin
                        current_addr_reg <= cmd_addr[ADDR_WIDTH-1:0];
                        icap_words_remaining_reg <= {2'd0, cmd_size[63:2]};
                        icap_word_index_reg <= 3'd0;
                        state_reg <= STATE_RECONF_ADDR;
                    end
                end
            end

            STATE_WRITE_WAIT_DATA: begin
                s_axis_tready <= 1'b1;

                if (s_axis_tvalid && s_axis_tready) begin
                    s_axis_tready <= 1'b0;
                    data_line_reg <= s_axis_tdata;
                    line_bytes_reg <= next_line_bytes(remaining_bytes_reg);
                    half_select_reg <= 1'b0;
                    state_reg <= STATE_WRITE_ADDR;
                end
            end

            STATE_WRITE_ADDR: begin
                m_axi_awaddr <= current_addr_reg + (half_select_reg ? ADDR_INCR_32 : {ADDR_WIDTH{1'b0}});
                m_axi_awvalid <= 1'b1;

                if (m_axi_awvalid && m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wdata <= half_select_reg ? data_line_reg[511:256] : data_line_reg[255:0];
                    m_axi_wstrb <= strobe_for_bytes(write_bytes_for_half(line_bytes_reg, half_select_reg));
                    m_axi_wlast <= 1'b1;
                    m_axi_wvalid <= 1'b1;
                    state_reg <= STATE_WRITE_DATA;
                end
            end

            STATE_WRITE_DATA: begin
                if (m_axi_wvalid && m_axi_wready) begin
                    m_axi_wvalid <= 1'b0;
                    m_axi_wlast <= 1'b0;
                    m_axi_bready <= 1'b1;
                    state_reg <= STATE_WRITE_RESP;
                end
            end

            STATE_WRITE_RESP: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    m_axi_bready <= 1'b0;

                    if (m_axi_bresp != 2'b00) begin
                        start_status(ERR_AXI_BRESP);
                    end else if (!half_select_reg && line_bytes_reg > 7'd32) begin
                        half_select_reg <= 1'b1;
                        state_reg <= STATE_WRITE_ADDR;
                    end else if (remaining_bytes_reg <= {57'd0, line_bytes_reg}) begin
                        remaining_bytes_reg <= 64'd0;
                        current_addr_reg <= current_addr_reg + {{ADDR_WIDTH-7{1'b0}}, line_bytes_reg};
                        start_status(ERR_OK);
                    end else begin
                        remaining_bytes_reg <= remaining_bytes_reg - {57'd0, line_bytes_reg};
                        current_addr_reg <= current_addr_reg + {{ADDR_WIDTH-7{1'b0}}, line_bytes_reg};
                        state_reg <= STATE_WRITE_WAIT_DATA;
                    end
                end
            end

            STATE_READ_ADDR_0: begin
                m_axi_araddr <= current_addr_reg;
                m_axi_arvalid <= 1'b1;

                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready <= 1'b1;
                    state_reg <= STATE_READ_DATA_0;
                end
            end

            STATE_READ_DATA_0: begin
                if (m_axi_rvalid && m_axi_rready) begin
                    m_axi_rready <= 1'b0;

                    if (m_axi_rresp != 2'b00) begin
                        start_status(ERR_AXI_RRESP);
                    end else if (!m_axi_rlast) begin
                        start_status(ERR_RLAST);
                    end else begin
                        read_response_reg[255:0] <= mask_data_256(m_axi_rdata, read_first_byte_count(remaining_bytes_reg));

                        if (remaining_bytes_reg > 64'd32) begin
                            state_reg <= STATE_READ_ADDR_1;
                        end else begin
                            m_axis_tdata <= {256'd0, mask_data_256(m_axi_rdata, read_first_byte_count(remaining_bytes_reg))};
                            m_axis_tkeep <= {(AXIS_DATA_WIDTH/8){1'b1}};
                            m_axis_tlast <= 1'b1;
                            m_axis_tvalid <= 1'b1;
                            state_reg <= STATE_READ_SEND;
                        end
                    end
                end
            end

            STATE_READ_ADDR_1: begin
                m_axi_araddr <= current_addr_reg + ADDR_INCR_32;
                m_axi_arvalid <= 1'b1;

                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready <= 1'b1;
                    state_reg <= STATE_READ_DATA_1;
                end
            end

            STATE_READ_DATA_1: begin
                if (m_axi_rvalid && m_axi_rready) begin
                    m_axi_rready <= 1'b0;

                    if (m_axi_rresp != 2'b00) begin
                        start_status(ERR_AXI_RRESP);
                    end else if (!m_axi_rlast) begin
                        start_status(ERR_RLAST);
                    end else begin
                        read_response_reg[511:256] <= mask_data_256(m_axi_rdata, read_second_byte_count(remaining_bytes_reg));
                        m_axis_tdata <= {mask_data_256(m_axi_rdata, read_second_byte_count(remaining_bytes_reg)), read_response_reg[255:0]};
                        m_axis_tkeep <= {(AXIS_DATA_WIDTH/8){1'b1}};
                        m_axis_tlast <= 1'b1;
                        m_axis_tvalid <= 1'b1;
                        state_reg <= STATE_READ_SEND;
                    end
                end
            end

            STATE_READ_SEND: begin
                if (m_axis_tvalid && m_axis_tready) begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                    state_reg <= STATE_IDLE;
                end
            end

            STATE_RECONF_ADDR: begin
                m_axi_araddr <= current_addr_reg;
                m_axi_arvalid <= 1'b1;

                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready <= 1'b1;
                    state_reg <= STATE_RECONF_DATA;
                end
            end

            STATE_RECONF_DATA: begin
                if (m_axi_rvalid && m_axi_rready) begin
                    m_axi_rready <= 1'b0;

                    if (m_axi_rresp != 2'b00) begin
                        start_status(ERR_AXI_RRESP);
                    end else if (!m_axi_rlast) begin
                        start_status(ERR_RLAST);
                    end else begin
                        read_data_reg <= m_axi_rdata;
                        icap_word_index_reg <= 3'd0;
                        m_axis_icap_tdata <= m_axi_rdata[31:0];
                        m_axis_icap_tlast <= icap_words_remaining_reg == 64'd1;
                        m_axis_icap_tvalid <= 1'b1;
                        state_reg <= STATE_RECONF_STREAM;
                    end
                end
            end

            STATE_RECONF_STREAM: begin
                if (m_axis_icap_tvalid && m_axis_icap_tready) begin
                    if (icap_words_remaining_reg == 64'd1) begin
                        icap_words_remaining_reg <= 64'd0;
                        m_axis_icap_tvalid <= 1'b0;
                        m_axis_icap_tlast <= 1'b0;
                        start_status(ERR_OK);
                    end else begin
                        icap_words_remaining_reg <= icap_words_remaining_reg - 64'd1;

                        if (icap_word_index_reg == 3'd7) begin
                            current_addr_reg <= current_addr_reg + ADDR_INCR_32;
                            icap_word_index_reg <= 3'd0;
                            m_axis_icap_tvalid <= 1'b0;
                            m_axis_icap_tlast <= 1'b0;
                            state_reg <= STATE_RECONF_ADDR;
                        end else begin
                            icap_word_index_reg <= icap_word_index_reg + 3'd1;
                            m_axis_icap_tdata <= select_icap_word(read_data_reg, icap_word_index_reg + 3'd1);
                            m_axis_icap_tlast <= icap_words_remaining_reg == 64'd2;
                        end
                    end
                end
            end

            STATE_SEND_STATUS: begin
                if (m_axis_tvalid && m_axis_tready) begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                    state_reg <= STATE_IDLE;
                end
            end

            default: begin
                state_reg <= STATE_IDLE;
            end
        endcase
    end
end

endmodule

`resetall
