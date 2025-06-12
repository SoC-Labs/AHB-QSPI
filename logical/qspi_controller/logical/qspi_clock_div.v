module qspi_clock_div(
    input  wire         HCLK,
    input  wire         HRESETn,
    input  wire [4:0]   QSPI_CLK_DIV,
    output wire         QSPI_SCLK_i
);

reg [4:0] QSPI_CLK_DIV_COUNTER;
reg     QSPI_SCLK_reg;
assign QSPI_SCLK_i = (QSPI_CLK_DIV==5'h00) ? HCLK : QSPI_SCLK_reg;

// Clock Divider for SCLK
always @(posedge HCLK or negedge HRESETn) begin
    if(~HRESETn) begin
        QSPI_CLK_DIV_COUNTER<=5'h00;
        QSPI_SCLK_reg <= 1'b0;
    end else begin
        if(QSPI_CLK_DIV==5'h01) begin
            QSPI_SCLK_reg <= ~QSPI_SCLK_reg;
        end else if(QSPI_CLK_DIV!=5'h00) begin
            if(QSPI_CLK_DIV_COUNTER==QSPI_CLK_DIV-1'b1) begin
                QSPI_CLK_DIV_COUNTER <= 5'h00;
                QSPI_SCLK_reg <= ~QSPI_SCLK_reg;
            end else begin
                QSPI_CLK_DIV_COUNTER <= QSPI_CLK_DIV_COUNTER + 1;
            end
        end else begin
            QSPI_SCLK_reg <= 1'b0;
        end
    end
end



endmodule
