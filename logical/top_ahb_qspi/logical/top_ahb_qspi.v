

module top_ahb_qspi #(
    parameter ADDR_W = 16,
    parameter DATA_W = 32
    )(
    input  wire                 HCLK,
    input  wire                 HRESETn,

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

    // QSPI Signals
    output wire                 QSPI_SCLK,
    output wire                 QSPI_nCS,
    output wire [3:0]           QSPI_IO_o,
    input  wire [3:0]           QSPI_IO_i,
    output wire [3:0]           QSPI_IO_e
);


endmodule