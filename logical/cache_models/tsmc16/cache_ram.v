module cache_ram #(
    parameter ADDR_W=8
    )(
    input  wire                 CLK,
    input  wire [ADDR_W-1:0]    TAG_ADDR,
    input  wire                 TAG_WE,
    input  wire                 TAG_RD,
    input  wire                 TAG_CS,
    input  wire [10:0]          TAG_WDATA,
    output wire [10:0]          TAG_RDATA,

    input  wire [ADDR_W-1:0]    CLD_ADDR,
    input  wire                 CLD_WE,
    input  wire [3:0]           CLD_RD,
    input  wire [3:0]           CLD_CS,
    input  wire [127:0]         CLD_WDATA,
    output wire [127:0]         CLD_RDATA
);

// ----------------------------------------------------------------------------
// RAM0 Instance for Word index 0
// ----------------------------------------------------------------------------
wire    cs_ram0_word0;
assign  cs_ram0_word0   = CLD_CS[0] & (CLD_WE | CLD_RD[0]);

TS5N16FFCLLULVTA256X32M2SSHO data_ram_0_word_0_i (
    .Q(CLD_RDATA[31:0]),
    .CLK(CLK),
    .CEB(~cs_ram0_word0),
    .WEB(~CLD_WE),
    .A(CLD_ADDR),
    .D(CLD_WDATA[31:0]),
    .SLP        (1'b0),
    .DSLP       (1'b0),
    .SD         (1'b0),
    .PUDELAY    (),      // Propogation of SD
    .RTSEL      (2'b01),
    .WTSEL      (2'b01)
);

// ----------------------------------------------------------------------------
// RAM0 Instance for Word index 1
// ----------------------------------------------------------------------------
wire    cs_ram0_word1;
assign  cs_ram0_word1   = CLD_CS[1] & (CLD_WE | CLD_RD[1]);

TS5N16FFCLLULVTA256X32M2SSHO data_ram_0_word_1_i (
    .Q(CLD_RDATA[63:32]),
    .CLK(CLK),
    .CEB(~cs_ram0_word1),
    .WEB(~CLD_WE),
    .A(CLD_ADDR),
    .D(CLD_WDATA[63:32]),
    .SLP        (1'b0),
    .DSLP       (1'b0),
    .SD         (1'b0),
    .PUDELAY    (),      // Propogation of SD
    .RTSEL      (2'b01),
    .WTSEL      (2'b01)

);

// ----------------------------------------------------------------------------
// RAM0 Instance for Word index 2
// ----------------------------------------------------------------------------
wire    cs_ram0_word2;
assign  cs_ram0_word2   = CLD_CS[2] & (CLD_WE | CLD_RD[2]);

TS5N16FFCLLULVTA256X32M2SSHO data_ram_0_word_2_i (
    .Q(CLD_RDATA[95:64]),
    .CLK(CLK),
    .CEB(~cs_ram0_word2),
    .WEB(~CLD_WE),
    .A(CLD_ADDR),
    .D(CLD_WDATA[95:64]),
    .SLP        (1'b0),
    .DSLP       (1'b0),
    .SD         (1'b0),
    .PUDELAY    (),      // Propogation of SD
    .RTSEL      (2'b01),
    .WTSEL      (2'b01)

);

// ----------------------------------------------------------------------------
// RAM0 Instance for Word index 3
// ----------------------------------------------------------------------------
wire    cs_ram0_word3;
assign  cs_ram0_word3   = CLD_CS[3] & (CLD_WE | CLD_RD[3]);

TS5N16FFCLLULVTA256X32M2SSHO data_ram_0_word_3_i (
    .Q(CLD_RDATA[127:96]),
    .CLK(CLK),
    .CEB(~cs_ram0_word3),
    .WEB(~CLD_WE),
    .A(CLD_ADDR),
    .D(CLD_WDATA[127:96]),
    .SLP        (1'b0),
    .DSLP       (1'b0),
    .SD         (1'b0),
    .PUDELAY    (),      // Propogation of SD
    .RTSEL      (2'b01),
    .WTSEL      (2'b01)
);

// ----------------------------------------------------------------------------
// TAG RAM 0 Instance
// ----------------------------------------------------------------------------
wire    cs_tag0;
assign  cs_tag0         = TAG_CS & (TAG_WE | TAG_RD);

TS5N16FFCLLULVTA256X11M2SSHO tag_ram_0_i (
    .Q(TAG_RDATA),
    .CLK(CLK),
    .CEB(~cs_tag0),
    .WEB(~TAG_WE),
    .A(TAG_ADDR),
    .D(TAG_WDATA),
    .SLP        (1'b0),
    .DSLP       (1'b0),
    .SD         (1'b0),
    .PUDELAY    (),      // Propogation of SD
    .RTSEL      (2'b01),
    .WTSEL      (2'b01)
);



endmodule
