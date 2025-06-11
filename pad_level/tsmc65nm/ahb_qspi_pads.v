


module ahb_qspi_pads (
    input  wire                 HCLK,
    input  wire                 HRESETn,
    input  wire                 PCLK,
    input  wire                 PRESETn,
    // AHB Signals
    input  wire [32-1:0]        HADDR,
    input  wire [1:0]           HTRANS,
    input  wire                 HWRITE,
    input  wire [2:0]           HSIZE,
    input  wire [2:0]           HBURST,
    input  wire [3:0]           HPROT,
    input  wire [32-1:0]        HWDATA,
    input  wire                 HSELx,
    output wire [32-1:0]        HRDATA,
    input  wire                 HREADY,
    output wire                 HREADYOUT,
    output wire                 HRESP,

    // APB Signals
    input  wire [15:0]          PADDR,
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
    inout  wire [3:0]           QSPI_IO,

    output wire                 IRQ_QSPI_FINISHED
);

wire QSPI_SCLK_i;
wire QSPI_nCS_i;
wire [3:0] QSPI_IO_o;
wire [3:0] QSPI_IO_i;
wire [3:0] QSPI_IO_e;


PRDW0408SCDG uPAD_QSPI_SCLK_o(
    .IE(1'b0),
    .C(),
    .PE(1'b0),
    .DS(1'b0),
    .I(QSPI_SCLK_i),
    .OEN(1'b0),
    .PAD(QSPI_SCLK)
);

PRDW0408SCDG uPAD_QSPI_nCS_o(
    .IE(1'b0),
    .C(),
    .PE(1'b0),
    .DS(1'b0),
    .I(QSPI_nCS_i),
    .OEN(1'b0),
    .PAD(QSPI_nCS)
);


PRDW0408SCDG uPAD_QSPI_IO_0(
    .IE(~QSPI_IO_e[0]),
    .C(QSPI_IO_i[0]),
    .PE(1'b1),
    .DS(1'b0),
    .I(QSPI_IO_o[0]),
    .OEN(~QSPI_IO_e[0]),
    .PAD(QSPI_IO[0])
);

PRDW0408SCDG uPAD_QSPI_IO_1(
    .IE(~QSPI_IO_e[1]),
    .C(QSPI_IO_i[1]),
    .PE(1'b1),
    .DS(1'b0),
    .I(QSPI_IO_o[1]),
    .OEN(~QSPI_IO_e[1]),
    .PAD(QSPI_IO[1])
);

PRDW0408SCDG uPAD_QSPI_IO_2(
    .IE(~QSPI_IO_e[2]),
    .C(QSPI_IO_i[2]),
    .PE(1'b1),
    .DS(1'b0),
    .I(QSPI_IO_o[2]),
    .OEN(~QSPI_IO_e[2]),
    .PAD(QSPI_IO[2])
);

PRDW0408SCDG uPAD_QSPI_IO_3(
    .IE(~QSPI_IO_e[3]),
    .C(QSPI_IO_i[3]),
    .PE(1'b1),
    .DS(1'b0),
    .I(QSPI_IO_o[3]),
    .OEN(~QSPI_IO_e[3]),
    .PAD(QSPI_IO[3])
);


top_ahb_qspi u_top_ahb_qspi(
    .HCLK(HCLK),
    .HRESETn(HRESETn),
    .PCLK(HCLK),
    .PRESETn(HRESETn),

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
    .HRESP(HRESP),

    .PADDR(PADDR),
    .PPROT(PPROT),
    .PSEL(PSEL),
    .PENABLE(PENABLE),
    .PWRITE(PWRITE),
    .PWDATA(PWDATA),
    .PSTRB(PSTRB),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR),

    .QSPI_SCLK(QSPI_SCLK_i),
    .QSPI_nCS(QSPI_nCS_i),
    .QSPI_IO_o(QSPI_IO_o),
    .QSPI_IO_i(QSPI_IO_i),
    .QSPI_IO_e(QSPI_IO_e),

    .IRQ_QSPI_FINISHED(IRQ_QSPI_FINISHED)
);

endmodule
