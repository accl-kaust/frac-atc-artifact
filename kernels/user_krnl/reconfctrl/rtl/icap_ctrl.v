`resetall
`timescale 1ns / 1ps
`default_nettype none

module icap_ctrl #(
     parameter DATA_WIDTH = 32,
     parameter KEEP_WIDTH = DATA_WIDTH/8
)
(
    input wire                  clk,
    input wire                  rst,

    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire [KEEP_WIDTH-1:0] s_axis_tkeep,
    input wire                  s_axis_tlast,
    output wire                 s_axis_tready,
    input wire                  s_axis_tvalid,

    output wire                 pr_done,
    output wire                 pr_err,
    output wire                 avail
);

assign s_axis_tready = 1'b1;

`ifdef SIMULATION
reg pr_done_reg = 1'b0;

assign pr_done = pr_done_reg;
assign pr_err = 1'b0;
assign avail = 1'b1;

always @(posedge clk) begin
    if (rst) begin
        pr_done_reg <= 1'b0;
    end else begin
        pr_done_reg <= s_axis_tvalid && s_axis_tready && s_axis_tlast;
    end
end
`else

//TODO: record 73656
//TODO: Add STARTUPE3 check Configuration Start-Up Considerations in UG570
ICAPE3 #(
    .DEVICE_ID(32'h03628093),     // Specifies the pre-programmed Device ID value to be used for simulation purposes
    .ICAP_AUTO_SWITCH("DISABLE"), // Enable switch ICAP using sync word.
    .SIM_CFG_FILE_NAME("NONE")    // Specifies the Raw Bitstream (RBT) file to be parsed by the simulation mode
)
ICAPE3_inst(
    .AVAIL(avail),     // 1-bit output: Availability status of ICAP.
    .O(),             // 32-bit output: Configuration data output bus.
    .PRDONE(pr_done),   // 1-bit output: Indicates completion of Partial Reconfiguration.
    .PRERROR(pr_err), // 1-bit output: Indicates error during Partial Reconfiguration.
    .CLK(clk),         // 1-bit input: Clock input.
    .CSIB(~s_axis_tvalid),       // 1-bit input: Active-Low ICAP enable.
    .I(s_axis_tdata),             // 32-bit input: Configuration data input bus.
    .RDWRB(1'b0)        // 1-bit input: Read/Write Select input.
);
`endif

endmodule
`resetall
