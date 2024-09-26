module cache_subsystem(
    input  wire             HCLK,
    input  wire             HRESETn,

    // APB 
    input  wire             PCLKG,       
    input  wire [11:0]      PADDR,
    input  wire [31:0]      PWDATA,
    input  wire             PWRITE,
    input  wire             PSEL,
    input  wire             PENABLE,
    input  wire [3:0]       PSTRB,
    input  wire [2:0]       PPROT,
    output wire [31:0]      PRDATA,
    output wire             PSLVERR,
    output wire             PREADY,

    // AHB Subordinate
    input  wire             HSELS,        // Device select
    input  wire [21:0]      HADDRS,       // Address
    input  wire [2:0]       HBURSTS,      // Burst Type - Not used!
    input  wire             HMASTLOCKS,   // Master Lock - Not used!
    input  wire [1:0]       HTRANSS,      // Transfer control
    input  wire [2:0]       HSIZES,       // Transfer size
    input  wire [3:0]       HPROTS,       // Transfer Protection
    input  wire             HWRITES,      // Write control
    input  wire [31:0]      HWDATAS,      // Write data
    input  wire             HREADYS,      // Transfer phase done
    input  wire             HMASTERS,     // When 1 indicate a debug access
    output wire             HREADYOUTS,   // Device ready
    output wire [31:0]      HRDATAS,      // Read data output
    output wire             HRESPS,  
  
    // AHB Manager 
    output wire             HSELM,        // Device select
    output wire [21:0]      HADDRM,       // Address
    output wire [2:0]       HBURSTM,      // Burst Type - Not used (tied to 0)!
    output wire             HMASTLOCKM,   // Master Lock - Not used (tied to 0)!
    output wire [1:0]       HTRANSM,      // Transfer control
    output wire [2:0]       HSIZEM,       // Transfer size
    output wire [3:0]       HPROTM,       // Transfer Protection
    output wire             HWRITEM,      // Write control
    output wire [127:0]     HWDATAM,      // Write data
    output wire             HREADYM,      // Transfer phase done
    input  wire             HREADYOUTM,   // Device ready
    input  wire [127:0]     HRDATAM,      // Read data output
    input  wire             HRESPM,       // Error response

    output wire             IRQ,
    output wire             CACHEMISS,
    output wire             CACHEHIT
);

// Data RAM way 0 wires
wire [7:0]      RAMCLD0ADDR;
wire            RAMCLD0WE;
wire [3:0]      RAMCLD0RD;
wire [3:0]      RAMCLD0CS;
wire [127:0]    RAMCLD0WDATA;
wire [127:0]    RAMCLD0RDATA;
// TAG RAM way 0 wires
wire [7:0]      RAMTAG0ADDR;
wire            RAMTAG0WE;
wire            RAMTAG0RD;
wire            RAMTAG0CS;
wire [10:0]     RAMTAG0WDATA;
wire [10:0]     RAMTAG0RDATA;
// Data RAM way 1 wires
wire [7:0]      RAMCLD1ADDR;
wire            RAMCLD1WE;
wire [3:0]      RAMCLD1RD;
wire [3:0]      RAMCLD1CS;
wire [127:0]    RAMCLD1WDATA;
wire [127:0]    RAMCLD1RDATA;
// TAG RAM way 1 wires
wire [7:0]      RAMTAG1ADDR;
wire            RAMTAG1WE;
wire            RAMTAG1RD;
wire            RAMTAG1CS;
wire [10:0]     RAMTAG1WDATA;
wire [10:0]     RAMTAG1RDATA;

wire            RAMPWRUPACK;
wire            RAMPWRUPREQ;
reg             PWR_DELAY;

p_flash_cache_f0 #(
    .AW(22),
    .CW(12),
    .CACHE_WAY(2),
    .RESET_ALL_REGS(1),
    .GEN_STAT_LOGIC(1),
    .LINEW(4)
    ) u_cache_controller(
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        // APB Interface
        .PCLKG(PCLKG),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PWRITE(PWRITE),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PSTRB(PSTRB),
        .PPROT(PPROT),
        .PRDATA(PRDATA),
        .PSLVERR(PSLVERR),
        .PREADY(PREADY),
        // AHB Subordinate
        .HSELS(HSELS),
        .HADDRS(HADDRS),
        .HBURSTS(HBURSTS),
        .HMASTLOCKS(HMASTLOCKS),
        .HTRANSS(HTRANSS),
        .HSIZES(HSIZES),
        .HPROTS(HPROTS),
        .HWRITES(HWRITES),
        .HWDATAS(HWDATAS),
        .HREADYS(HREADYS),
        .HMASTERS(HMASTERS),
        .HREADYOUTS(HREADYOUTS),
        .HRDATAS(HRDATAS),
        .HRESPS(HRESPS),
        // CACHE RAM POWER UP
        .RAMPWRUPREQ(RAMPWRUPREQ),
        .RAMPWRUPACK(RAMPWRUPACK),
        // TAG RAM way 0
        .RAMTAG0ADDR(RAMTAG0ADDR),
        .RAMTAG0WE(RAMTAG0WE),
        .RAMTAG0RD(RAMTAG0RD),
        .RAMTAG0CS(RAMTAG0CS),
        .RAMTAG0WDATA(RAMTAG0WDATA),
        .RAMTAG0RDATA(RAMTAG0RDATA),
        // Data RAM way 0
        .RAMCLD0ADDR(RAMCLD0ADDR),
        .RAMCLD0WE(RAMCLD0WE),
        .RAMCLD0RD(RAMCLD0RD),
        .RAMCLD0CS(RAMCLD0CS),
        .RAMCLD0WDATA(RAMCLD0WDATA),
        .RAMCLD0RDATA(RAMCLD0RDATA),
        // TAG RAM way 1
        .RAMTAG1ADDR(RAMTAG1ADDR),
        .RAMTAG1WE(RAMTAG1WE),
        .RAMTAG1RD(RAMTAG1RD),
        .RAMTAG1CS(RAMTAG1CS),
        .RAMTAG1WDATA(RAMTAG1WDATA),
        .RAMTAG1RDATA(RAMTAG1RDATA),
        // Data RAM Way 1
        .RAMCLD1ADDR(RAMCLD1ADDR),
        .RAMCLD1WE(RAMCLD1WE),
        .RAMCLD1RD(RAMCLD1RD),
        .RAMCLD1CS(RAMCLD1CS),
        .RAMCLD1WDATA(RAMCLD1WDATA),
        .RAMCLD1RDATA(RAMCLD1RDATA),
        // AHB Manager
        .HSELM(HSELM),
        .HADDRM(HADDRM),
        .HBURSTM(HBURSTM),
        .HMASTLOCKM(HMASTLOCKM),
        .HTRANSM(HTRANSM),
        .HSIZEM(HSIZEM),
        .HPROTM(HPROTM),
        .HWRITEM(HWRITEM),
        .HWDATAM(HWDATAM),
        .HREADYM(HREADYM),
        .HREADYOUTM(HREADYOUTM),
        .HRDATAM(HRDATAM),
        .HRESPM(HRESPM),

        .IRQ(IRQ),

        .CACHEMISS(CACHEMISS),
        .CACHEHIT(CACHEHIT)
);

always @(posedge HCLK or negedge HRESETn) begin 
    if(~HRESETn)
        PWR_DELAY <= 1'b0;
    else 
        PWR_DELAY <= RAMPWRUPREQ;
end
assign RAMPWRUPACK = PWR_DELAY;

cache_ram #(
    .ADDR_W(8)
) u_way0_cache_ram (
    .CLK(HCLK),
    .TAG_ADDR(RAMTAG0ADDR),
    .TAG_WE(RAMTAG0WE),
    .TAG_RD(RAMTAG0RD),
    .TAG_CS(RAMTAG0CS),
    .TAG_WDATA(RAMTAG0WDATA),
    .TAG_RDATA(RAMTAG0RDATA),

    .CLD_ADDR(RAMCLD0ADDR),
    .CLD_WE(RAMCLD0WE),
    .CLD_RD(RAMCLD0RD),
    .CLD_CS(RAMCLD0CS),
    .CLD_WDATA(RAMCLD0WDATA),
    .CLD_RDATA(RAMCLD0RDATA)
);

cache_ram #(
    .ADDR_W(8)
) u_way1_cache_ram (
    .CLK(HCLK),
    .TAG_ADDR(RAMTAG1ADDR),
    .TAG_WE(RAMTAG1WE),
    .TAG_RD(RAMTAG1RD),
    .TAG_CS(RAMTAG1CS),
    .TAG_WDATA(RAMTAG1WDATA),
    .TAG_RDATA(RAMTAG1RDATA),

    .CLD_ADDR(RAMCLD1ADDR),
    .CLD_WE(RAMCLD1WE),
    .CLD_RD(RAMCLD1RD),
    .CLD_CS(RAMCLD1CS),
    .CLD_WDATA(RAMCLD1WDATA),
    .CLD_RDATA(RAMCLD1RDATA)
);


endmodule