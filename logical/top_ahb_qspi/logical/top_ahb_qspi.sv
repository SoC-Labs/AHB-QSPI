

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
    output wire [3:0]           QSPI_IO_o,
    input  wire [3:0]           QSPI_IO_i,
    output wire [3:0]           QSPI_IO_e
);


wire             qspi_psel;
wire     [31:0]  qspi_prdata;
wire             qspi_pready;
wire             qspi_pslverr;

wire             cache_psel;
wire     [31:0]  cache_prdata;
wire             cache_pready;
wire             cache_pslverr;


cmsdk_apb_slave_mux #(
    .PORT0_ENABLE  (1), // QSPI Control
    .PORT1_ENABLE  (1), // Cache Control
    .PORT2_ENABLE  (0), // not used
    .PORT3_ENABLE  (0), // not used
    .PORT4_ENABLE  (0), // not used
    .PORT5_ENABLE  (0), // not used
    .PORT6_ENABLE  (0), // not used
    .PORT7_ENABLE  (0), // not used
    .PORT8_ENABLE  (0), // not used
    .PORT9_ENABLE  (0), // not used
    .PORT10_ENABLE (0), // not used
    .PORT11_ENABLE (0), // not used
    .PORT12_ENABLE (0),
    .PORT13_ENABLE (0),
    .PORT14_ENABLE (0),
    .PORT15_ENABLE (0)
) u_cmsdk_apb_slave_mux (
    // Inputs
    .DECODE4BIT        (PADDR[15:12]),
    .PSEL              (PSEL),
    // PSEL (output) and return status & data (inputs) for each port
    .PSEL0             (qspi_psel),
    .PREADY0           (qspi_pready),
    .PRDATA0           (qspi_prdata),
    .PSLVERR0          (qspi_pslverr),

    .PSEL1             (cache_psel),
    .PREADY1           (cache_pready),
    .PRDATA1           (cache_prdata),
    .PSLVERR1          (cache_pslverr),

    // Output
    .PREADY            (PREADY),
    .PRDATA            (PRDATA),
    .PSLVERR           (PSLVERR)

);

cache_subsystem u_cache_subsystem(
    .HCLK(HCLK),
    .HRESETn(HRESETn),

    .PCLKG(PCLK),
    .PADDR(PADDR[11:0]),
    .PWDATA(PWDATA),
    .PWRITE(PWRITE),
    .PSEL(cache_psel),
    .PENABLE(PENABLE),
    .PSTRB(PSTRB),
    .PPROT(PPROT),
    .PRDATA(cache_prdata),
    .PSLVERR(cache_pslverr),
    .PREADY(cache_pready),

    .HSELS(),
    .HADDRS(),
    .HBURSTS(),
    .HMASTLOCKS(),
    .HTRANSS(),
    .HSIZES(),
    .HPROTS(),
    .HWRITES(),
    .HWDATAS(),
    .HREADYS(),
    .HMASTERS(),
    .HREADYOUTS(),
    .HRDATAS(),
    .HRESPS(),

    .HSELM(),
    .HADDRM(),
    .HBURSTM(),
    .HMASTLOCKM(),
    .HTRANSM(),
    .HSIZEM(),
    .HPROTM(),
    .HWRITEM(),
    .HWDATAM(),
    .HREADYM(),
    .HREADYOUTM(),
    .HRDATAM(),
    .HRESPM(),

    .IRQ(),
    .CACHEMISS(),
    .CACHEHIT()
);

apb_qspi_regs u_apb_qspi_regs(
    .PCLK(PCLK),
    .PRESETn(PRESETn),
    .PADDR(PADDR[11:2]),
    .PPROT(PPROT),
    .PSEL(qspi_psel),
    .PENABLE(PENABLE),
    .PWRITE(PWRITE),
    .PWDATA(PWDATA),
    .PSTRB(PSTRB),
    .PRDATA(qspi_prdata),
    .PREADY(qspi_pready),
    .PSLVERR(qspi_pslverr)
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