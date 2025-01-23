
module apb_qspi_regs(
    // APB Signals
    input  wire                 PCLK,
    input  wire                 PRESETn,
    input  wire [11:2]          PADDR,
    input  wire [2:0]           PPROT,
    input  wire                 PSEL,
    input  wire                 PENABLE,
    input  wire                 PWRITE,
    input  wire [31:0]          PWDATA,
    input  wire [3:0]           PSTRB,
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
    output wire                 QSPI_NO_CMD
);   
// Registers
// reg0 Control 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
//      QSPI_QIO_MODE[0]           |  |  |                    |                     |               |--> QSPI_QIO_MODE [0]
//     XIP_ACTIVE [8]              |  |  |                    |                     |------------------> XIP_ACTIVE [8]
//  QSPI_MODE_CODE[23:16]          |  |  |<------------------>|----------------------------------------> QSPI_MODE_CODE[23:16] 
//  QSPI_CONT_READ[24]             |  |----------------------------------------------------------------> QSPI_CONT_READ[24] 
//  QSPI_NO_CMD[25]                |-------------------------------------------------------------------> QSPI_NO_CMD[25]

// reg1 Status

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



reg [31:0] reg0;
reg [31:0] reg1;
reg [31:0] reg2;
reg [31:0] reg3;
// reg 4-7 not used as directly from SPI
reg [31:0] reg8;
reg [31:0] reg9;
reg [31:0] reg10;
reg [31:0] reg11;


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

assign QSPI_WDATA[31:0] =   {reg8[27:24],reg8[31:28],reg8[19:16],reg8[23:20],reg8[11:8],reg8[15:12],reg8[3:0],reg8[7:4]};
assign QSPI_WDATA[63:32] =  {reg9[27:24],reg9[31:28],reg9[19:16],reg9[23:20],reg9[11:8],reg9[15:12],reg9[3:0],reg9[7:4]};
assign QSPI_WDATA[95:64] =  {reg10[27:24],reg10[31:28],reg10[19:16],reg10[23:20],reg10[11:8],reg10[15:12],reg10[3:0],reg10[7:4]};
assign QSPI_WDATA[127:96] = {reg11[27:24],reg11[31:28],reg11[19:16],reg11[23:20],reg11[11:8],reg11[15:12],reg11[3:0],reg11[7:4]};

always @(posedge PCLK or negedge PRESETn) begin
    if(~PRESETn) begin
        reg0 = 32'd0;
        reg1 = 32'd0;
        reg2 = 32'd0;
        reg3 = 32'd0;
        reg8 = 32'd0;
        reg9 = 32'd0;
        reg10 = 32'd0;
        reg11 = 32'd0;
    end else begin
        if(PSEL & PENABLE & PWRITE) begin
            case(PADDR)
                10'h000: reg0 = PWDATA;
                10'h001: reg1 = PWDATA;
                10'h002: reg2 = PWDATA;
                10'h003: reg3 = PWDATA;
                10'h008: reg8 = PWDATA;
                10'h009: reg9 = PWDATA;
                10'h00A: reg10 = PWDATA;
                10'h00B: reg11 = PWDATA;
            endcase
        end 
        if(QSPI_ENABLE_ACK)
            reg2[8]=1'b0;
        reg1[0] = QSPI_BUSY;
    end
end

always @(PCLK, PADDR) begin
    if(PCLK) begin 
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
            default: PRDATA = 32'hDEADCAFE;
        endcase
    end
end

assign PREADY =  1'b1; //(PSEL & PENABLE & PWRITE) | (PSEL & ~PWRITE);
assign PSLVERR = 1'b0;

endmodule