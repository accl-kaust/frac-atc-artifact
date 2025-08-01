module reset_gen #
(
    parameter COUNT_WIDTH = 7,         // log2(100) = 7
    parameter RESET_CYCLES = 25
)
(
    input  wire clk,
    output reg  rst_out,               // active-high synchronous reset output
    output reg  rstn_out               // active-low synchronous reset output
);

    reg [COUNT_WIDTH-1:0] count = 0;
    reg counting = 1'b1;

    always @(posedge clk) begin
        if (counting) begin
            if (count < RESET_CYCLES - 1) begin
                count <= count + 1;
            end else begin
                counting <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        rst_out  <= counting;
        rstn_out <= ~counting;
    end

endmodule
