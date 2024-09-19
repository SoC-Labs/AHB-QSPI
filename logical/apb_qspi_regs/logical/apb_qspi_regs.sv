
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
    output wire [24:0]          QSPI_ADDR
);   
// Registers
// reg  Name    31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
// reg0 Control 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
//      QSPI_QIO_MODE[0]
//
//

// reg1 Status

// reg2 SPI Commands 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
//     QSPI_CMD [7:0]                                        |     |              |  | | | |----> QSPI_CMD [7:0]
//     QSPI_ENABLE [8]                                       |     |              |  | | |---> QSPI_ENABLE [8]   
//     QSPI_READ [9]                                         |     |              |  | |-------> QSPI_READ [9] 
//     QSPI_WRITE [10]                                       |     |              |  |--------> QSPI_WRITE [10]
//     QSPI_ADDR_EN[11]                                      |     |              |---------> QSPI_ADDR_EN [11]
//     QSPI_DUMMY_CYCLES[15:12]
//     QSPI_N_RW_BYTES [19:16]                               |<--->|---------------------> QSPI_N_RW_BYTES [18:16]


reg [31:0] reg0;
reg [31:0] reg1;
reg [31:0] reg2;
reg [31:0] reg3;


assign QSPI_QIO_MODE = reg0[0];

assign QSPI_CMD = reg2[7:0];
assign QSPI_ENABLE = reg2[8];
assign QSPI_READ = reg2[9];
assign QSPI_WRITE = reg2[10];
assign QSPI_ADDR_EN = reg2[11];
assign QSPI_DUMMY_CYCLES = reg2[15:12];
assign QSPI_N_RW_BYTES = reg2[19:16];

always @(posedge PCLK or negedge PRESETn) begin
    if(~PRESETn) begin
        reg0 = 32'd0;
        reg1 = 32'd0;
        reg2 = 32'd0;
    end else begin
        if(PSEL & PENABLE & PWRITE) begin
            case(PADDR)
                10'h000: reg0 = PWDATA;
                10'h001: reg1 = PWDATA;
                10'h002: reg2 = PWDATA;
                10'h003: reg3 = PWDATA;
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
        endcase
    end
end

assign PREADY =  1'b1; //(PSEL & PENABLE & PWRITE) | (PSEL & ~PWRITE);
assign PSLVERR = 1'b0;

endmodule