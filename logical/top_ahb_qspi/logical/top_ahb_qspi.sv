

module top_ahb_qspi #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32
    )(
    input  wire                 HCLK,
    input  wire                 HRESETn,
    input  wire                 PCLK,
    input  wire                 PRESETn,
    // AHB Signals
    input  wire [ADDR_W-1:0]    HADDR,
    input  wire [1:0]           HTRANS,
    input  wire                 HWRITE,
    input  wire [2:0]           HSIZE,
    input  wire [2:0]           HBURST,
    input  wire [3:0]           HPROT,
    input  wire [DATA_W-1:0]    HWDATA,
    input  wire                 HSELx,
    output wire [DATA_W-1:0]    HRDATA,
    input  wire                 HREADY,
    output wire                 HREADYOUT,
    output wire                 HRESP,

    // APB Signals
    input  wire [11:2]          PADDR,
    input  wire [2:0]           PPROT,
    input  wire                 PSEL,
    input  wire                 PENABLE,
    input  wire                 PWRITE,
    input  wire [31:0]          PWDATA,
    input  wire [3:0]           PSTRB,
    output wire [31:0]          PRDATA,
    output wire                 PREADY,
    output wire                 PSLVERR,   

    // QSPI Signals
    output wire                 QSPI_SCLK,
    output wire                 QSPI_nCS,
    output wire [3:0]           QSPI_IO_o,
    input  wire [3:0]           QSPI_IO_i,
    output wire [3:0]           QSPI_IO_e
);

cache_subsystem u_cache_subsystem(

);

apb_qspi_regs u_apb_qspi_regs(
    .PCLK(PCLK),
    .PRESETn(PRESETn),
    .PADDR(PADDR),
    .PPROT(PPROT),
    .PSEL(PSEL),
    .PENABLE(PENABLE),
    .PWRITE(PWRITE),
    .PWDATA(PWDATA),
    .PSTRB(PSTRB),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR)
);

ahb_qspi_interface #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
    ) u_ahb_qspi_interface (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HADDR(HADDR),
        .HTRANS(HTRANS),
        .HWRITE(HWRITE),
        .HSIZE(HSIZE),
        .HBURST(HBURST),
        .HPROT(HPROT),
        .HWDATA(HWDATA),
        .HSELx(HSELx),
        .HRDATA(HRDATA),
        .HREADY(HREADY),
        .HREADYOUT(HREADYOUT),
        .HRESP(HRESP)
);

qspi_controller u_qspi_controller(
    .HCLK(HCLK),
    .HRESETn(HRESETn),
    .QSPI_CLK_DIV(8'h02),
    .QSPI_SPI_MODE(2'b11),
    .QSPI_CMD(),
    .QSPI_ADDR(),
    .QSPI_WDATA(),
    .QSPI_RDATA(),

    .QSPI_SCLK(QSPI_SCLK)
);
endmodule