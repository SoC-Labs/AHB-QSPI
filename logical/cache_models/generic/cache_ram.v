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

p_flash_cache_f0_sp_ram #(.DATA_WIDTH(32),
    .MEMORY_DEPTH(2**(ADDR_W)),
    .ADDR_WIDTH(ADDR_W)) data_ram_0_word_0_i (
    .CLK    (CLK),
    .A      (CLD_ADDR),
    .CEN    (~cs_ram0_word0),
    .WEN    (~CLD_WE),
    .Q      (CLD_RDATA[31:0]),
    .D      (CLD_WDATA[31:0])
);

// ----------------------------------------------------------------------------
// RAM0 Instance for Word index 1
// ----------------------------------------------------------------------------
wire    cs_ram0_word1;
assign  cs_ram0_word1   = CLD_CS[1] & (CLD_WE | CLD_RD[1]);

p_flash_cache_f0_sp_ram #(.DATA_WIDTH(32),
    .MEMORY_DEPTH(2**(ADDR_W)),
    .ADDR_WIDTH(ADDR_W)) data_ram_0_word_1_i (
    .CLK    (CLK),
    .A      (CLD_ADDR),
    .CEN    (~cs_ram0_word1),
    .WEN    (~CLD_WE),
    .Q      (CLD_RDATA[63:32]),
    .D      (CLD_WDATA[63:32])
);

// ----------------------------------------------------------------------------
// RAM0 Instance for Word index 2
// ----------------------------------------------------------------------------
wire    cs_ram0_word2;
assign  cs_ram0_word2   = CLD_CS[2] & (CLD_WE | CLD_RD[2]);

p_flash_cache_f0_sp_ram #(.DATA_WIDTH(32),
    .MEMORY_DEPTH(2**(ADDR_W)),
    .ADDR_WIDTH(ADDR_W)) data_ram_0_word_2_i (
    .CLK    (CLK),
    .A      (CLD_ADDR),
    .CEN    (~cs_ram0_word2),
    .WEN    (~CLD_WE),
    .Q      (CLD_RDATA[95:64]),
    .D      (CLD_WDATA[95:64])
);

// ----------------------------------------------------------------------------
// RAM0 Instance for Word index 3
// ----------------------------------------------------------------------------
wire    cs_ram0_word3;
assign  cs_ram0_word3   = CLD_CS[3] & (CLD_WE | CLD_RD[3]);

p_flash_cache_f0_sp_ram #(.DATA_WIDTH(32),
    .MEMORY_DEPTH(2**(ADDR_W)),
    .ADDR_WIDTH(ADDR_W)) data_ram_0_word_3_i (
    .CLK    (CLK),
    .A      (CLD_ADDR),
    .CEN    (~cs_ram0_word3),
    .WEN    (~CLD_WE),
    .Q      (CLD_RDATA[127:96]),
    .D      (CLD_WDATA[127:96])
);

// ----------------------------------------------------------------------------
// TAG RAM 0 Instance
// ----------------------------------------------------------------------------
wire    cs_tag0;
assign  cs_tag0         = TAG_CS & (TAG_WE | TAG_RD);

p_flash_cache_f0_sp_ram #(.DATA_WIDTH(11),
    .MEMORY_DEPTH(2**(ADDR_W)),
    .ADDR_WIDTH(ADDR_W)) tag_ram_0_i (
    .CLK    (CLK),
    .A      (TAG_ADDR),
    .CEN    (~cs_tag0),
    .WEN    (~TAG_WE),
    .Q      (TAG_RDATA),
    .D      (TAG_WDATA)
);



endmodule
