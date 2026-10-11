module qspi_controller_mux(
    input  wire                 HRESETn,
    input  wire                 QSPI_SCLK,
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

reg AHB_QSPI_BUSY_del;
reg AHB_QSPI_BUSY_del1;
reg AHB_QSPI_BUSY_del2;

assign QSPI_CMD = (XIP_ACTIVE==1'b1)? AHB_QSPI_CMD : APB_QSPI_CMD;
assign QSPI_ENABLE = (XIP_ACTIVE==1'b1)? AHB_QSPI_ENABLE: APB_QSPI_ENABLE;
assign QSPI_READ = (XIP_ACTIVE==1'b1)? AHB_QSPI_READ : APB_QSPI_READ;
assign QSPI_WRITE = (XIP_ACTIVE==1'b1)? AHB_QSPI_WRITE : APB_QSPI_WRITE;
assign QSPI_ADDR_EN = (XIP_ACTIVE==1'b1)? AHB_QSPI_ADDR_EN : APB_QSPI_ADDR_EN;
assign QSPI_DUMMY_CYCLES = (XIP_ACTIVE==1'b1)? AHB_QSPI_DUMMY_CYCLES : APB_QSPI_DUMMY_CYCLES;
assign QSPI_N_RW_BYTES = (XIP_ACTIVE==1'b1)? AHB_QSPI_N_RW_BYTES : APB_QSPI_N_RW_BYTES;
assign QSPI_ADDR = (XIP_ACTIVE==1'b1)? AHB_QSPI_ADDR : APB_QSPI_ADDR;
assign QSPI_WDATA = (XIP_ACTIVE==1'b1)? AHB_QSPI_WDATA : APB_QSPI_WDATA;

// AHB_QSPI_ENABLE_ACK: registered below (CDC). QSPI_ENABLE_ACK is already a
// flop (qspi_controller.sv), but the XIP_ACTIVE gate is a PCLK-domain register,
// so the gated value had sources in two domains in its fan-in (SpyGlass
// Ac_glitch03 on ahb_qspi_enable_ack_meta). The APB acknowledge's gate is in
// its own sink's domain (PCLK), so it stays a gate.
wire AHB_QSPI_ENABLE_ACK_in = (XIP_ACTIVE==1'b1) ? QSPI_ENABLE_ACK : 1'b0;
assign AHB_QSPI_RDATA = (XIP_ACTIVE==1'b1) ?  QSPI_RDATA : 128'd0;

assign APB_QSPI_ENABLE_ACK = (XIP_ACTIVE==1'b0) ? QSPI_ENABLE_ACK : 1'b0;
// APB_QSPI_BUSY: registered below (CDC), from this select.
wire APB_QSPI_BUSY_in = (XIP_ACTIVE==1'b0) ? QSPI_BUSY : 1'b1;
assign APB_QSPI_RDATA = (XIP_ACTIVE==1'b0) ?  QSPI_RDATA : 128'd0;

wire AHB_QSPI_BUSY_in = (XIP_ACTIVE==1'b1) ? QSPI_BUSY : 1'b1;
// AHB_QSPI_BUSY must be delayed to introduce a delay between qspi transaction
// otherwise timing violations occur on the chip select (nCS)
always @(posedge QSPI_SCLK or negedge HRESETn) begin
    if(~HRESETn) begin
        AHB_QSPI_BUSY_del  <= 1'b1;
        AHB_QSPI_BUSY_del1 <= 1'b1;
        AHB_QSPI_BUSY_del2 <= 1'b1;
    end else begin
        AHB_QSPI_BUSY_del  <= AHB_QSPI_BUSY_in;
        AHB_QSPI_BUSY_del1 <= AHB_QSPI_BUSY_del;
        AHB_QSPI_BUSY_del2 <= AHB_QSPI_BUSY_del1;
    end
end

// Both BUSY outputs cross into another clock domain, where a 2-FF synchroniser
// samples them (ahb_qspi_interface: HCLK; apb_qspi_regs: PCLK). They used to be
// combinational -- an OR of the combinational BUSY_in with the three delay
// flops, and a mux of ~nCS (itself a decode) -- so a glitch on an SCLK edge
// could be captured as a false BUSY (HAL CBPAHI on the synchronisers' first
// flops; ticket T-L3-QSPI-CDC). Each is now a single flop in the QSPI_SCLK
// domain: glitch-free, one SCLK cycle later in both directions. Reset values
// are the old outputs' values in reset (AHB: the delay flops reset to 1;
// APB: no transaction, XIP off).
reg AHB_QSPI_BUSY_q;
reg APB_QSPI_BUSY_q;
reg AHB_QSPI_ENABLE_ACK_q;
always @(posedge QSPI_SCLK or negedge HRESETn) begin
    if(~HRESETn) begin
        AHB_QSPI_BUSY_q       <= 1'b1;
        APB_QSPI_BUSY_q       <= 1'b0;
        AHB_QSPI_ENABLE_ACK_q <= 1'b0;
    end else begin
        AHB_QSPI_BUSY_q       <= AHB_QSPI_BUSY_in | AHB_QSPI_BUSY_del | AHB_QSPI_BUSY_del1 | AHB_QSPI_BUSY_del2;
        APB_QSPI_BUSY_q       <= APB_QSPI_BUSY_in;
        AHB_QSPI_ENABLE_ACK_q <= AHB_QSPI_ENABLE_ACK_in;
    end
end
// AHB side: the acknowledge is now two SCLK cycles after the FSM decode, BUSY
// (three delay flops, then this one) still falls well after it.
assign AHB_QSPI_ENABLE_ACK = AHB_QSPI_ENABLE_ACK_q;
assign AHB_QSPI_BUSY = AHB_QSPI_BUSY_q;
assign APB_QSPI_BUSY = APB_QSPI_BUSY_q;
endmodule
