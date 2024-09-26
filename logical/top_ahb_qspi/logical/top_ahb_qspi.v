

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


wire            qspi_psel;
wire     [31:0] qspi_prdata;
wire            qspi_pready;
wire            qspi_pslverr;

wire            cache_psel;
wire     [31:0] cache_prdata;
wire            cache_pready;
wire            cache_pslverr;


  // AHB Outputs 
wire            flash_HSELM;        // Device select
wire [21:0]     flash_HADDRM;       // Address
wire [2:0]      flash_HBURSTM;      // Burst Type - Not used (tied to 0)!
wire            flash_HMASTLOCKM;   // Master Lock - Not used (tied to 0)!
wire [1:0]      flash_HTRANSM;      // Transfer control
wire [2:0]      flash_HSIZEM;       // Transfer size
wire [3:0]      flash_HPROTM;       // Transfer Protection
wire            flash_HWRITEM;      // Write control
wire [127:0]    flash_HWDATAM;      // Write data
wire            flash_HREADYM;      // Transfer phase done
wire            flash_HREADYOUTM;   // Device ready
wire [127:0]    flash_HRDATAM;      // Read data output
wire            flash_HRESPM;       // Error response


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

    .HSELS(HSELx),
    .HADDRS(HADDR[21:0]),
    .HBURSTS(HBURST),
    .HMASTLOCKS(1'b1),
    .HTRANSS(HTRANS),
    .HSIZES(HSIZE),
    .HPROTS(HPROT),
    .HWRITES(HWRITE),
    .HWDATAS(HWDATA),
    .HREADYS(HREADY),
    .HMASTERS(1'b0),
    .HREADYOUTS(HREADYOUT),
    .HRDATAS(HRDATA),
    .HRESPS(HRESP),

    .HSELM(flash_HSELM),
    .HADDRM(flash_HADDRM),
    .HBURSTM(flash_HBURSTM),
    .HMASTLOCKM(flash_HMASTLOCKM),
    .HTRANSM(flash_HTRANSM),
    .HSIZEM(flash_HSIZEM),
    .HPROTM(flash_HPROTM),
    .HWRITEM(flash_HWRITEM),
    .HWDATAM(flash_HWDATAM),
    .HREADYM(flash_HREADYM),
    .HREADYOUTM(flash_HREADYOUTM),
    .HRDATAM(flash_HRDATAM),
    .HRESPM(flash_HRESPM),

    .IRQ(),
    .CACHEMISS(),
    .CACHEHIT()
);


wire [7:0]           QSPI_CMD;
wire                 QSPI_ENABLE;
wire                 QSPI_READ;
wire                 QSPI_WRITE;
wire                 QSPI_ADDR_EN;
wire [3:0]           QSPI_DUMMY_CYCLES;
wire [3:0]           QSPI_N_RW_BYTES;
wire [21:0]          QSPI_ADDR;
wire [127:0]         QSPI_WDATA;
wire                 QSPI_ENABLE_ACK;
wire                 QSPI_BUSY;
wire [127:0]         QSPI_RDATA;

wire [7:0]           AHB_QSPI_CMD;
wire                 AHB_QSPI_ENABLE;
wire                 AHB_QSPI_READ;
wire                 AHB_QSPI_WRITE;
wire                 AHB_QSPI_ADDR_EN;
wire [3:0]           AHB_QSPI_DUMMY_CYCLES;
wire [3:0]           AHB_QSPI_N_RW_BYTES;
wire [21:0]          AHB_QSPI_ADDR;
wire [127:0]         AHB_QSPI_WDATA;
wire                 AHB_QSPI_ENABLE_ACK;
wire                 AHB_QSPI_BUSY;
wire [127:0]         AHB_QSPI_RDATA;

wire [7:0]           APB_QSPI_CMD;
wire                 APB_QSPI_ENABLE;
wire                 APB_QSPI_READ;
wire                 APB_QSPI_WRITE;
wire                 APB_QSPI_ADDR_EN;
wire [3:0]           APB_QSPI_DUMMY_CYCLES;
wire [3:0]           APB_QSPI_N_RW_BYTES;
wire [21:0]          APB_QSPI_ADDR;
wire [127:0]         APB_QSPI_WDATA;
wire                 APB_QSPI_ENABLE_ACK;
wire                 APB_QSPI_BUSY;
wire [127:0]         APB_QSPI_RDATA;

// Config from APB
wire            QSPI_QIO_MODE;
wire            QSPI_CONT_READ;
wire [7:0]      QSPI_MODE_CODE;
wire            QSPI_NO_CMD;
wire            XIP_ACTIVE;


qspi_controller_mux u_qspi_controller_mux(
    .XIP_ACTIVE(XIP_ACTIVE),

    .AHB_QSPI_CMD(AHB_QSPI_CMD),
    .AHB_QSPI_ENABLE(AHB_QSPI_ENABLE),
    .AHB_QSPI_READ(AHB_QSPI_READ),
    .AHB_QSPI_WRITE(AHB_QSPI_WRITE),
    .AHB_QSPI_ADDR_EN(AHB_QSPI_ADDR_EN),
    .AHB_QSPI_DUMMY_CYCLES(AHB_QSPI_DUMMY_CYCLES),
    .AHB_QSPI_N_RW_BYTES(AHB_QSPI_N_RW_BYTES),
    .AHB_QSPI_ADDR(AHB_QSPI_ADDR),
    .AHB_QSPI_WDATA(AHB_QSPI_WDATA),
    .AHB_QSPI_ENABLE_ACK(AHB_QSPI_ENABLE_ACK),
    .AHB_QSPI_BUSY(AHB_QSPI_BUSY),
    .AHB_QSPI_RDATA(AHB_QSPI_RDATA),

    .APB_QSPI_CMD(APB_QSPI_CMD),
    .APB_QSPI_ENABLE(APB_QSPI_ENABLE),
    .APB_QSPI_READ(APB_QSPI_READ),
    .APB_QSPI_WRITE(APB_QSPI_WRITE),
    .APB_QSPI_ADDR_EN(APB_QSPI_ADDR_EN),
    .APB_QSPI_DUMMY_CYCLES(APB_QSPI_DUMMY_CYCLES),
    .APB_QSPI_N_RW_BYTES(APB_QSPI_N_RW_BYTES),
    .APB_QSPI_ADDR(APB_QSPI_ADDR),
    .APB_QSPI_WDATA(APB_QSPI_WDATA),
    .APB_QSPI_ENABLE_ACK(APB_QSPI_ENABLE_ACK),
    .APB_QSPI_BUSY(APB_QSPI_BUSY),
    .APB_QSPI_RDATA(APB_QSPI_RDATA),

    .QSPI_CMD(QSPI_CMD),
    .QSPI_ENABLE(QSPI_ENABLE),
    .QSPI_READ(QSPI_READ),
    .QSPI_WRITE(QSPI_WRITE),
    .QSPI_ADDR_EN(QSPI_ADDR_EN),
    .QSPI_DUMMY_CYCLES(QSPI_DUMMY_CYCLES),
    .QSPI_N_RW_BYTES(QSPI_N_RW_BYTES),
    .QSPI_ADDR(QSPI_ADDR),
    .QSPI_WDATA(QSPI_WDATA),
    .QSPI_ENABLE_ACK(QSPI_ENABLE_ACK),
    .QSPI_BUSY(~QSPI_nCS),
    .QSPI_RDATA(QSPI_RDATA)
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
    .PSLVERR(qspi_pslverr),

    .QSPI_CMD(APB_QSPI_CMD),
    .QSPI_ENABLE(APB_QSPI_ENABLE),
    .QSPI_ENABLE_ACK(APB_QSPI_ENABLE_ACK),
    .QSPI_READ(APB_QSPI_READ),
    .QSPI_WRITE(APB_QSPI_WRITE),
    .QSPI_ADDR_EN(APB_QSPI_ADDR_EN),
    .QSPI_DUMMY_CYCLES(APB_QSPI_DUMMY_CYCLES),
    .QSPI_N_RW_BYTES(APB_QSPI_N_RW_BYTES),
    .QSPI_ADDR(APB_QSPI_ADDR),
    .QSPI_BUSY(APB_QSPI_BUSY),
    .QSPI_QIO_MODE(QSPI_QIO_MODE),
    .QSPI_RDATA(APB_QSPI_RDATA),
    .QSPI_WDATA(APB_QSPI_WDATA),
    .XIP_ACTIVE(XIP_ACTIVE),
    .QSPI_CONT_READ(QSPI_CONT_READ),
    .QSPI_MODE_CODE(QSPI_MODE_CODE),
    .QSPI_NO_CMD(QSPI_NO_CMD)
);

ahb_qspi_interface #(
    .ADDR_W(22),
    .DATA_W(128)
    ) u_ahb_qspi_interface (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HADDR(flash_HADDRM),
        .HTRANS(flash_HTRANSM),
        .HWRITE(flash_HWRITEM),
        .HSIZE(flash_HSIZEM),
        .HBURST(flash_HBURSTM),
        .HPROT(flash_HPROTM),
        .HWDATA(flash_HWDATAM),
        .HSELx(flash_HSELM),
        .HRDATA(flash_HRDATAM),
        .HREADY(flash_HREADYM),
        .HREADYOUT(flash_HREADYOUTM),
        .HRESP(flash_HRESPM),
        .AHB_QSPI_CMD(AHB_QSPI_CMD),
        .AHB_QSPI_ENABLE(AHB_QSPI_ENABLE),
        .AHB_QSPI_READ(AHB_QSPI_READ),
        .AHB_QSPI_WRITE(AHB_QSPI_WRITE),
        .AHB_QSPI_ADDR_EN(AHB_QSPI_ADDR_EN),
        .AHB_QSPI_DUMMY_CYCLES(AHB_QSPI_DUMMY_CYCLES),
        .AHB_QSPI_N_RW_BYTES(AHB_QSPI_N_RW_BYTES),
        .AHB_QSPI_ADDR(AHB_QSPI_ADDR),
        .AHB_QSPI_WDATA(AHB_QSPI_WDATA),
        .AHB_QSPI_ENABLE_ACK(AHB_QSPI_ENABLE_ACK),
        .AHB_QSPI_BUSY(AHB_QSPI_BUSY),
        .AHB_QSPI_RDATA(AHB_QSPI_RDATA)
);

qspi_controller u_qspi_controller(
    .HCLK(HCLK),
    .HRESETn(HRESETn),
    .QSPI_CLK_DIV(8'h01),
    .QSPI_SPI_MODE(2'b00),
    .QSPI_CMD(QSPI_CMD),
    .QSPI_ENABLE(QSPI_ENABLE),
    .QSPI_ENABLE_ACK(QSPI_ENABLE_ACK),
    .QSPI_READ(QSPI_READ),
    .QSPI_WRITE(QSPI_WRITE),
    .QSPI_ADDR_EN(QSPI_ADDR_EN),
    .QSPI_DUMMY_CYCLES(QSPI_DUMMY_CYCLES),
    .QSPI_N_RW_BYTES(QSPI_N_RW_BYTES),
    .QSPI_ADDR(QSPI_ADDR),
    .QSPI_QIO_MODE(QSPI_QIO_MODE),
    .QSPI_WDATA(QSPI_WDATA),
    .QSPI_RDATA(QSPI_RDATA),
    .QSPI_CONT_READ(QSPI_CONT_READ),
    .QSPI_MODE_CODE(QSPI_MODE_CODE),
    .QSPI_NO_CMD(QSPI_NO_CMD),

    .QSPI_SCLK(QSPI_SCLK),
    .QSPI_nCS(QSPI_nCS),
    .QSPI_IO_o(QSPI_IO_o),
    .QSPI_IO_i(QSPI_IO_i),
    .QSPI_IO_e(QSPI_IO_e)
);
endmodule