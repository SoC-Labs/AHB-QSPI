
module apb_qspi_regs(
    // APB Signals
    input  wire                 PCLK,
    input  wire                 PRESETn,
    input  wire [11:2]          PADDR,
    input  wire                 PSEL,
    input  wire                 PENABLE,
    input  wire                 PWRITE,
    input  wire [31:0]          PWDATA,
    output reg [31:0]           PRDATA,
    output wire                 PREADY,
    output wire                 PSLVERR,

    output wire [7:0]           QSPI_CMD,
    output wire                 QSPI_ENABLE,
    input  wire                 QSPI_ENABLE_ACK,
    output wire                 QSPI_READ,
    output wire                 QSPI_WRITE,
    output wire                 QSPI_ADDR_EN,
    output wire [3:0]           QSPI_DUMMY_CYCLES,
    output wire [3:0]           QSPI_N_RW_BYTES,
    input  wire                 QSPI_BUSY,
    output wire                 QSPI_QIO_MODE,
    output wire [21:0]          QSPI_ADDR,
    input  wire [127:0]         QSPI_RDATA,
    output wire [127:0]         QSPI_WDATA,
    output wire                 XIP_ACTIVE,
    output wire                 QSPI_CONT_READ,
    output wire [7:0]           QSPI_MODE_CODE,
    output wire                 QSPI_NO_CMD,

    output wire [4:0]           QSPI_CLK_DIV,

    output wire                 IRQ_QSPI_FINISHED,

    // AHB Control Signals
    output wire [7:0]           AHB_QSPI_CMD,
    output wire [3:0]           AHB_QSPI_DUMMY_CYCLES
);
// Registers
// reg0 Control 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
//      QSPI_QIO_MODE[0]           |  |  |                    |                     |               |--> QSPI_QIO_MODE [0]
//     XIP_ACTIVE [8]              |  |  |                    |                     |------------------> XIP_ACTIVE [8]
//  QSPI_MODE_CODE[23:16]          |  |  |<------------------>|----------------------------------------> QSPI_MODE_CODE[23:16]
//  QSPI_CONT_READ[24]             |  |----------------------------------------------------------------> QSPI_CONT_READ[24]
//  QSPI_NO_CMD[25]                |-------------------------------------------------------------------> QSPI_NO_CMD[25]

// reg1 Status 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
// QSPI_BUSY                                                                       |               |--> QSPI_BUSY
// IRQ_CLR                                                                         |------------------> IRQ_CLR

// reg2 SPI Commands 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
//     QSPI_CMD [7:0]                                  |  |        |  |        |  |  | | | |----> QSPI_CMD [7:0]
//     QSPI_ENABLE [8]                                 |  |        |  |        |  |  | | |---> QSPI_ENABLE [8]
//     QSPI_READ [9]                                   |  |        |  |        |  |  | |-------> QSPI_READ [9]
//     QSPI_WRITE [10]                                 |  |        |  |        |  |  |--------> QSPI_WRITE [10]
//     QSPI_ADDR_EN[11]                                |  |        |  |        |  |---------> QSPI_ADDR_EN [11]
//     QSPI_DUMMY_CYCLES[15:12]                        |  |        |  |<------>|-------> QSPI_DUMMY_CYCLES [15:12]
//     QSPI_N_RW_BYTES [19:16]                         |  |<------>|---------------------> QSPI_N_RW_BYTES [19:16]

// reg3 SPI Commands 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
//     QSPI_ADDR [21:0]                             |<-------------------------------------------------->|-> QSPI_ADDR [21:0]


// reg12 AHB SPI setup 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
// reg12 SPI Commands 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
//     AHB_QSPI_CMD [7:0]                              |  |        |  |        |  |  | | | |----> QSPI_CMD [7:0]
//     AHB_QSPI_DUMMY_CYCLES[15:12]                    |  |        |  |<------>|-------> QSPI_DUMMY_CYCLES [15:12]

// reg13 QSPI_clk_div [4:0]

reg qspi_finished;
reg qspi_busy_last;
assign IRQ_QSPI_FINISHED = qspi_finished;

// 2-FF CDC synchronizers for signals from QSPI_SCLK_i domain into PCLK domain
reg qspi_enable_ack_meta, qspi_enable_ack_sync;
reg qspi_busy_meta,       qspi_busy_sync;

always @(posedge PCLK or negedge PRESETn) begin
    if(~PRESETn) begin
        qspi_enable_ack_meta <= 1'b0;
        qspi_enable_ack_sync <= 1'b0;
        qspi_busy_meta       <= 1'b0;
        qspi_busy_sync       <= 1'b0;
    end else begin
        qspi_enable_ack_meta <= QSPI_ENABLE_ACK;
        qspi_enable_ack_sync <= qspi_enable_ack_meta;
        qspi_busy_meta       <= QSPI_BUSY;
        qspi_busy_sync       <= qspi_busy_meta;
    end
end


localparam [7:0] PIDR0 = 8'h59; //0xFE0
localparam [7:0] PIDR1 = 8'h16; //0xFE4
localparam [7:0] PIDR2 = 8'h15; //0xFE8
localparam [7:0] PIDR3 = 8'h00; //0xFEC
localparam [7:0] PIDR4 = 8'h00; //0xFD0
localparam [7:0] PIDR5 = 8'h00; //0xFD4
localparam [7:0] PIDR6 = 8'h00; //0xFD8
localparam [7:0] PIDR7 = 8'h00; //0xFDC
localparam [7:0] CIDR0 = 8'h50;
localparam [7:0] CIDR1 = 8'h51;
localparam [7:0] CIDR2 = 8'h4C;
localparam [7:0] CIDR3 = 8'h53;

reg [31:0] reg0;
reg [31:0] reg1;
reg [31:0] reg2;
reg [31:0] reg3;
// reg 4-7 not used as directly from SPI
reg [31:0] reg8;
reg [31:0] reg9;
reg [31:0] reg10;
reg [31:0] reg11;
reg [31:0] reg12;
reg [4:0]  reg13;


assign QSPI_QIO_MODE = reg0[0];
assign XIP_ACTIVE = reg0[8];
assign QSPI_MODE_CODE = reg0[23:16];
assign QSPI_CONT_READ = reg0[24];
assign QSPI_NO_CMD = reg0[25];

assign QSPI_CMD = reg2[7:0];
assign QSPI_ENABLE = reg2[8];
assign QSPI_READ = reg2[9];
assign QSPI_WRITE = reg2[10];
assign QSPI_ADDR_EN = reg2[11];
assign QSPI_DUMMY_CYCLES = reg2[15:12];
assign QSPI_N_RW_BYTES = reg2[19:16];

assign QSPI_ADDR = reg3[21:0];

// WDATA byte transformation:
//   QPI mode  — nibble-swap per byte (compensates for nibble-serial, lower-nibble-first output)
//   SPI mode  — bit-reversal per byte (compensates for bit-serial, LSB-first output)
assign QSPI_WDATA[31:0]   = QSPI_QIO_MODE ?
    {reg8[27:24],reg8[31:28],reg8[19:16],reg8[23:20],reg8[11:8],reg8[15:12],reg8[3:0],reg8[7:4]} :
    {reg8[24],reg8[25],reg8[26],reg8[27],reg8[28],reg8[29],reg8[30],reg8[31],
     reg8[16],reg8[17],reg8[18],reg8[19],reg8[20],reg8[21],reg8[22],reg8[23],
     reg8[8],reg8[9],reg8[10],reg8[11],reg8[12],reg8[13],reg8[14],reg8[15],
     reg8[0],reg8[1],reg8[2],reg8[3],reg8[4],reg8[5],reg8[6],reg8[7]};
assign QSPI_WDATA[63:32]  = QSPI_QIO_MODE ?
    {reg9[27:24],reg9[31:28],reg9[19:16],reg9[23:20],reg9[11:8],reg9[15:12],reg9[3:0],reg9[7:4]} :
    {reg9[24],reg9[25],reg9[26],reg9[27],reg9[28],reg9[29],reg9[30],reg9[31],
     reg9[16],reg9[17],reg9[18],reg9[19],reg9[20],reg9[21],reg9[22],reg9[23],
     reg9[8],reg9[9],reg9[10],reg9[11],reg9[12],reg9[13],reg9[14],reg9[15],
     reg9[0],reg9[1],reg9[2],reg9[3],reg9[4],reg9[5],reg9[6],reg9[7]};
assign QSPI_WDATA[95:64]  = QSPI_QIO_MODE ?
    {reg10[27:24],reg10[31:28],reg10[19:16],reg10[23:20],reg10[11:8],reg10[15:12],reg10[3:0],reg10[7:4]} :
    {reg10[24],reg10[25],reg10[26],reg10[27],reg10[28],reg10[29],reg10[30],reg10[31],
     reg10[16],reg10[17],reg10[18],reg10[19],reg10[20],reg10[21],reg10[22],reg10[23],
     reg10[8],reg10[9],reg10[10],reg10[11],reg10[12],reg10[13],reg10[14],reg10[15],
     reg10[0],reg10[1],reg10[2],reg10[3],reg10[4],reg10[5],reg10[6],reg10[7]};
assign QSPI_WDATA[127:96] = QSPI_QIO_MODE ?
    {reg11[27:24],reg11[31:28],reg11[19:16],reg11[23:20],reg11[11:8],reg11[15:12],reg11[3:0],reg11[7:4]} :
    {reg11[24],reg11[25],reg11[26],reg11[27],reg11[28],reg11[29],reg11[30],reg11[31],
     reg11[16],reg11[17],reg11[18],reg11[19],reg11[20],reg11[21],reg11[22],reg11[23],
     reg11[8],reg11[9],reg11[10],reg11[11],reg11[12],reg11[13],reg11[14],reg11[15],
     reg11[0],reg11[1],reg11[2],reg11[3],reg11[4],reg11[5],reg11[6],reg11[7]};

assign AHB_QSPI_CMD = reg12[7:0];
assign AHB_QSPI_DUMMY_CYCLES = reg12[15:12];

assign QSPI_CLK_DIV = reg13;

always @(posedge PCLK or negedge PRESETn) begin
    if(~PRESETn) begin
        reg0 <= 32'd0;
        reg1 <= 32'd0;
        reg2 <= 32'd0;
        reg3 <= 32'd0;
        reg8 <= 32'd0;
        reg9 <= 32'd0;
        reg10 <= 32'd0;
        reg11 <= 32'd0;
        reg12 <= 32'd0;
        reg13 <= 5'h01;
    end else begin
        if(PSEL & PENABLE & PWRITE) begin
            case(PADDR)
                10'h000: reg0 <= PWDATA;
                10'h001: reg1[31:1] <= PWDATA[31:1];
                10'h002: reg2 <= PWDATA;
                10'h003: reg3 <= PWDATA;
                10'h008: reg8 <= PWDATA;
                10'h009: reg9 <= PWDATA;
                10'h00A: reg10 <= PWDATA;
                10'h00B: reg11 <= PWDATA;
                10'h00C: reg12 <= PWDATA;
                10'h00D: reg13 <= PWDATA[4:0];
            endcase
        end
        if(qspi_enable_ack_sync)
            reg2[8] <= 1'b0;
        if(reg1[8] & (~qspi_finished))
            reg1[8] <= 1'b0;
        reg1[0] <= qspi_busy_sync;
    end
end

always @(*) begin
    case(PADDR)
            10'h000: PRDATA = reg0;
            10'h001: PRDATA = reg1;
            10'h002: PRDATA = reg2;
            10'h003: PRDATA = reg3;
            10'h004: PRDATA = {QSPI_RDATA[7:0],QSPI_RDATA[15:8],QSPI_RDATA[23:16],QSPI_RDATA[31:24]};
            10'h005: PRDATA = {QSPI_RDATA[39:32], QSPI_RDATA[47:40], QSPI_RDATA[55:48], QSPI_RDATA[63:56]};
            10'h006: PRDATA = {QSPI_RDATA[71:64], QSPI_RDATA[79:72], QSPI_RDATA[87:80], QSPI_RDATA[95:88]};
            10'h007: PRDATA = {QSPI_RDATA[103:96], QSPI_RDATA[111:104], QSPI_RDATA[119:112], QSPI_RDATA[127:120]};
            10'h008: PRDATA = reg8;
            10'h009: PRDATA = reg9;
            10'h00A: PRDATA = reg10;
            10'h00B: PRDATA = reg11;
            10'h00C: PRDATA = reg12;
            10'h00D: PRDATA = {27'd0, reg13};
            10'h3F4: PRDATA = {24'd0, PIDR4};
            10'h3F5: PRDATA = {24'd0, PIDR5};
            10'h3F6: PRDATA = {24'd0, PIDR6};
            10'h3F7: PRDATA = {24'd0, PIDR7};
            10'h3F8: PRDATA = {24'd0, PIDR0};
            10'h3F9: PRDATA = {24'd0, PIDR1};
            10'h3FA: PRDATA = {24'd0, PIDR2};
            10'h3FB: PRDATA = {24'd0, PIDR3};
            10'h3FC: PRDATA = {24'd0, CIDR0};
            10'h3FD: PRDATA = {24'd0, CIDR1};
            10'h3FE: PRDATA = {24'd0, CIDR2};
            10'h3FF: PRDATA = {24'd0, CIDR3};
            default: PRDATA = 32'hDEADCAFE;
    endcase
end

assign PREADY =  1'b1; //(PSEL & PENABLE & PWRITE) | (PSEL & ~PWRITE);
assign PSLVERR = 1'b0;

//Interrupt generation
always @(posedge PCLK or negedge PRESETn) begin
    if(~PRESETn) begin
        qspi_finished <= 1'b0;
        qspi_busy_last <= 1'b0;
    end else begin
        qspi_busy_last <= qspi_busy_sync;

        if(qspi_busy_last&(~qspi_busy_sync)) begin
            qspi_finished <= 1'b1;
        end else if((reg1[8])) begin
            qspi_finished <= 1'b0;
        end
    end
end

endmodule
