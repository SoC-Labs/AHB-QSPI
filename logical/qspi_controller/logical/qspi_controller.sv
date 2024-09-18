
module qspi_controller (
    input  wire         HCLK,
    input  wire         HRESETn,

    input  wire [7:0]   QSPI_CLK_DIV,
    input  wire [1:0]   QSPI_SPI_MODE, // {CPOL, CPHA} 

    input  wire [7:0]   QSPI_CMD,
    input  wire [23:0]  QSPI_ADDR,
    input  wire [31:0]  QSPI_WDATA,
    output wire [31:0]  QSPI_RDATA,

    // QSPI Interface
    output wire         QSPI_SCLK
);

reg [7:0] QSPI_CLK_DIV_COUNTER;
wire QSPI_ACTIVE;
reg     QSPI_SCLK_reg;
assign QSPI_ACTIVE = 1'b1;

assign QSPI_SCLK = (QSPI_CLK_DIV==8'h00) ? HCLK : QSPI_SCLK_reg;
// Clock Divider for SCLK
always @(posedge HCLK or negedge HRESETn) begin
    if(~HRESETn) begin
        QSPI_CLK_DIV_COUNTER<=8'h00;
        QSPI_SCLK_reg <= 1'b0;
    end else begin 
        if(QSPI_ACTIVE) begin 
            if(QSPI_CLK_DIV!=8'h00) begin 
                if(QSPI_CLK_DIV_COUNTER==QSPI_CLK_DIV-1'b1) begin 
                    QSPI_CLK_DIV_COUNTER <= 8'h00;
                end else begin 
                    QSPI_SCLK_reg <= ~QSPI_SCLK_reg;
                    QSPI_CLK_DIV_COUNTER <= QSPI_CLK_DIV_COUNTER + 1'b1;
                end
            end else begin 
                QSPI_SCLK_reg <= QSPI_SPI_MODE[1];
            end
        end else begin 
            QSPI_SCLK_reg <= QSPI_SPI_MODE[1];
        end
    end
end
endmodule