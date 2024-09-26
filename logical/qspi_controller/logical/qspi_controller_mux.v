module qspi_controller_mux(
    input  wire                 XIP_ACTIVE,

    input  wire [7:0]           AHB_QSPI_CMD,
    input  wire                 AHB_QSPI_ENABLE,
    input  wire                 AHB_QSPI_READ,
    input  wire                 AHB_QSPI_WRITE,
    input  wire                 AHB_QSPI_ADDR_EN,
    input  wire [3:0]           AHB_QSPI_DUMMY_CYCLES,
    input  wire [3:0]           AHB_QSPI_N_RW_BYTES,
    input  wire [21:0]          AHB_QSPI_ADDR,
    input  wire [127:0]         AHB_QSPI_WDATA,

    output wire                 AHB_QSPI_ENABLE_ACK,
    output wire                 AHB_QSPI_BUSY,
    output wire [127:0]         AHB_QSPI_RDATA,


    input  wire [7:0]           APB_QSPI_CMD,
    input  wire                 APB_QSPI_ENABLE,
    input  wire                 APB_QSPI_READ,
    input  wire                 APB_QSPI_WRITE,
    input  wire                 APB_QSPI_ADDR_EN,
    input  wire [3:0]           APB_QSPI_DUMMY_CYCLES,
    input  wire [3:0]           APB_QSPI_N_RW_BYTES,
    input  wire [21:0]          APB_QSPI_ADDR,
    input  wire [127:0]         APB_QSPI_WDATA,

    output wire                 APB_QSPI_ENABLE_ACK,
    output wire                 APB_QSPI_BUSY,
    output wire [127:0]         APB_QSPI_RDATA,

    output wire [7:0]           QSPI_CMD,
    output wire                 QSPI_ENABLE,
    output wire                 QSPI_READ,
    output wire                 QSPI_WRITE,
    output wire                 QSPI_ADDR_EN,
    output wire [3:0]           QSPI_DUMMY_CYCLES,
    output wire [3:0]           QSPI_N_RW_BYTES,
    output wire [21:0]          QSPI_ADDR,
    output wire [127:0]         QSPI_WDATA,

    input  wire                 QSPI_ENABLE_ACK,
    input  wire                 QSPI_BUSY,
    input  wire [127:0]         QSPI_RDATA

);


assign QSPI_CMD = (XIP_ACTIVE==1'b1)? AHB_QSPI_CMD : APB_QSPI_CMD;
assign QSPI_ENABLE = (XIP_ACTIVE==1'b1)? AHB_QSPI_ENABLE: APB_QSPI_ENABLE;
assign QSPI_READ = (XIP_ACTIVE==1'b1)? AHB_QSPI_READ : APB_QSPI_READ;
assign QSPI_WRITE = (XIP_ACTIVE==1'b1)? AHB_QSPI_WRITE : APB_QSPI_WRITE;
assign QSPI_ADDR_EN = (XIP_ACTIVE==1'b1)? AHB_QSPI_ADDR_EN : APB_QSPI_ADDR_EN;
assign QSPI_DUMMY_CYCLES = (XIP_ACTIVE==1'b1)? AHB_QSPI_DUMMY_CYCLES : APB_QSPI_DUMMY_CYCLES;
assign QSPI_N_RW_BYTES = (XIP_ACTIVE==1'b1)? AHB_QSPI_N_RW_BYTES : APB_QSPI_N_RW_BYTES;
assign QSPI_ADDR = (XIP_ACTIVE==1'b1)? AHB_QSPI_ADDR : APB_QSPI_ADDR;
assign QSPI_WDATA = (XIP_ACTIVE==1'b1)? AHB_QSPI_WDATA : APB_QSPI_WDATA;

assign AHB_QSPI_ENABLE_ACK = (XIP_ACTIVE==1'b1) ? QSPI_ENABLE_ACK : 1'b0;
assign AHB_QSPI_BUSY = (XIP_ACTIVE==1'b1) ? QSPI_BUSY : 1'b1;
assign AHB_QSPI_RDATA = (XIP_ACTIVE==1'b1) ?  QSPI_RDATA : 128'd0;

assign APB_QSPI_ENABLE_ACK = (XIP_ACTIVE==1'b0) ? QSPI_ENABLE_ACK : 1'b0;
assign APB_QSPI_BUSY = (XIP_ACTIVE==1'b0) ? QSPI_BUSY : 1'b1;
assign APB_QSPI_RDATA = (XIP_ACTIVE==1'b0) ?  QSPI_RDATA : 128'd0;

endmodule