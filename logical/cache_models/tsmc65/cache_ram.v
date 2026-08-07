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

flash_cache_data data_ram_0_word_0_i (
    .Q(CLD_RDATA[31:0]),
    .CLK(CLK),
    .CEN(~cs_ram0_word0),
    .WEN(~CLD_WE),
    .A(CLD_ADDR),
    .D(CLD_WDATA[31:0]),
    .EMA(3'b010),
    .EMAW(2'b00),
    .RET1N(1'b1)

);

// ----------------------------------------------------------------------------
// RAM0 Instance for Word index 1
// ----------------------------------------------------------------------------
wire    cs_ram0_word1;
assign  cs_ram0_word1   = CLD_CS[1] & (CLD_WE | CLD_RD[1]);

flash_cache_data data_ram_0_word_1_i (
    .Q(CLD_RDATA[63:32]),
    .CLK(CLK),
    .CEN(~cs_ram0_word1),
    .WEN(~CLD_WE),
    .A(CLD_ADDR),
    .D(CLD_WDATA[63:32]),
    .EMA(3'b010),
    .EMAW(2'b00),
    .RET1N(1'b1)
);

// ----------------------------------------------------------------------------
// RAM0 Instance for Word index 2
// ----------------------------------------------------------------------------
wire    cs_ram0_word2;
assign  cs_ram0_word2   = CLD_CS[2] & (CLD_WE | CLD_RD[2]);

flash_cache_data data_ram_0_word_2_i (
    .Q(CLD_RDATA[95:64]),
    .CLK(CLK),
    .CEN(~cs_ram0_word2),
    .WEN(~CLD_WE),
    .A(CLD_ADDR),
    .D(CLD_WDATA[95:64]),
    .EMA(3'b010),
    .EMAW(2'b00),
    .RET1N(1'b1)
);

// ----------------------------------------------------------------------------
// RAM0 Instance for Word index 3
// ----------------------------------------------------------------------------
wire    cs_ram0_word3;
assign  cs_ram0_word3   = CLD_CS[3] & (CLD_WE | CLD_RD[3]);

flash_cache_data data_ram_0_word_3_i (
    .Q(CLD_RDATA[127:96]),
    .CLK(CLK),
    .CEN(~cs_ram0_word3),
    .WEN(~CLD_WE),
    .A(CLD_ADDR),
    .D(CLD_WDATA[127:96]),
    .EMA(3'b010),
    .EMAW(2'b00),
    .RET1N(1'b1)
);

// ----------------------------------------------------------------------------
// TAG RAM 0 Instance
// ----------------------------------------------------------------------------
wire    cs_tag0;
assign  cs_tag0         = TAG_CS & (TAG_WE | TAG_RD);

// flash_cache_tag is compiled with write_mask=on (see the "Write Mask: On"
// header in flash_cache_tag.v, and GroupWriteEnable in its .memlib), so WEN
// is an 11-bit per-bit write enable — replicate the active-low TAG_WE across
// every bit to write the whole word. Ganging every bit is correct here: the
// controller exposes a single RAMTAGnWE and only ever writes whole tag words
// (all-zero on invalidate, {tag,valid} on linefill), so there is no per-bit
// mask to honour.
//
// GWEN is the macro's global write enable and selects read vs write for the
// cycle: low = write, high = read. WEN only masks which bits of a write land,
// so GWEN must be driven too. Leaving it unconnected broke both flows:
//   - synthesis tied it low (TIEL), parking the macro permanently in write
//     mode, so the read path never ran and Q never presented tag data;
//   - in simulation an unconnected input is z, and the model's isBitX(GWEN)
//     check then forces writeEnable and D to X while still taking the write
//     branch -- actively corrupting the addressed row rather than merely
//     suppressing reads.
// flash_cache_data has no GWEN port (write_mask=off), which is why only the
// tag RAM needs this.
flash_cache_tag tag_ram_0_i (
    .Q(TAG_RDATA),
    .CLK(CLK),
    .CEN(~cs_tag0),
    .GWEN(~TAG_WE),
    .WEN({11{~TAG_WE}}),
    .A(TAG_ADDR),
    .D(TAG_WDATA),
    .EMA(3'b010),
    .EMAW(2'b00),
    .RET1N(1'b1)
);

endmodule
