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
    output wire                 avail,

    // The ICAPE3 pins themselves, brought out so a static ILA can see what the
    // primitive is actually driven with and what it answers. Nothing consumes
    // them in logic; they exist to be probed.
    output wire                 icap_csib,
    output wire                 icap_rdwrb,
    output wire [DATA_WIDTH-1:0] icap_o
);

assign s_axis_tready = 1'b1;

// The tie-offs the primitive is instantiated with. Repeated here rather than
// tapped from the instance, because a Verilog input pin is not a readable net.
assign icap_csib  = ~s_axis_tvalid;
assign icap_rdwrb = 1'b0;

`ifdef SIMULATION
reg pr_done_reg = 1'b0;

assign pr_done = pr_done_reg;
assign pr_err = 1'b0;
assign avail = 1'b1;
assign icap_o = {DATA_WIDTH{1'b0}};

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
    .O(icap_o),       // 32-bit output: Configuration data output bus.
    .PRDONE(pr_done),   // 1-bit output: Indicates completion of Partial Reconfiguration.
    .PRERROR(pr_err), // 1-bit output: Indicates error during Partial Reconfiguration.
    .CLK(clk),         // 1-bit input: Clock input.
    .CSIB(icap_csib),            // 1-bit input: Active-Low ICAP enable.
    .I(s_axis_tdata),             // 32-bit input: Configuration data input bus.
    .RDWRB(icap_rdwrb)  // 1-bit input: Read/Write Select input.
);
`endif

endmodule
`resetall
