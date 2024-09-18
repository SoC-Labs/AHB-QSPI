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



p_flash_cache_f0 #(
    .AW(22),
    .CW(12),
    .CACHE_WAY(2),
    .RESET_ALL_REGS(0),
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
        .RAMPWRUPREQ(),
        .RAMPWRUPACK(),
        // TAG RAM way 0
        .RAMTAG0ADDR(),
        .RAMTAG0WE(),
        .RAMTAG0RD(),
        .RAMTAG0CS(),
        .RAMTAG0WDATA(),
        .RAMTAG0RDATA(),
        // Data RAM way 0
        .RAMCLD0ADDR(),
        .RAMCLD0WE(),
        .RAMCLD0RD(),
        .RAMCLD0CS(),
        .RAMCLD0WDATA(),
        .RAMCLD0RDATA(),
        // TAG RAM way 1
        .RAMTAG1ADDR(),
        .RAMTAG1WE(),
        .RAMTAG1RD(),
        .RAMTAG1CS(),
        .RAMTAG1WDATA(),
        .RAMTAG1RDATA(),
        // Data RAM Way 1
        .RAMCLD1ADDR(),
        .RAMCLD1WE(),
        .RAMCLD1RD(),
        .RAMCLD1CS(),
        .RAMCLD1WDATA(),
        .RAMCLD1RDATA(),
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


endmodule