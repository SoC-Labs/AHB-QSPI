`timescale 1ns/1ps
// A1 assessment harness (independent assessor A1, 13 Oct 2026).
//
// Standalone "core" of top_ahb_qspi WITHOUT the CG092 cache: the AHB-Lite
// port of ahb_qspi_interface (ADDR_W=22, DATA_W=128, exactly as top_ahb_qspi
// instantiates it) is driven directly by a cycle-accurate cocotb master, so
// any legal AHB-Lite stimulus can be applied (back-to-back NONSEQ, IDLE/BUSY,
// transfers to another slave, waited HREADY from another slave).
//
// apb_qspi_regs is driven directly by a cocotb APB master. The SST26VF064B
// model is the flash. A second, zero-or-N-wait "default slave" (dflt_*) sits
// on the same AHB bus: transfers with HSEL=0 go to it, and HREADY is the
// standard data-phase mux of the two HREADYOUTs.
module tb_a1_core #(parameter WATCHDOG_WIDTH = 16) (
    input  wire          HCLK,
    input  wire          HRESETn,
    // AHB-Lite master side
    input  wire [21:0]   HADDR,
    input  wire [1:0]    HTRANS,
    input  wire          HWRITE,
    input  wire [2:0]    HSIZE,
    input  wire [2:0]    HBURST,
    input  wire [127:0]  HWDATA,
    input  wire          HSEL,          // select for the QSPI slave
    output wire [127:0]  HRDATA,        // muxed
    output wire          HREADY,        // muxed (bus HREADY)
    output wire          HRESP,         // muxed
    // QSPI slave raw outputs (for the protocol checker)
    output wire          S_HREADYOUT,
    output wire          S_HRESP,
    output wire [127:0]  S_HRDATA,
    // default slave control: wait states it inserts per transfer
    input  wire [9:0]    DFLT_WAIT,
    // APB
    input  wire [11:0]   PADDR,
    input  wire          PSEL,
    input  wire          PENABLE,
    input  wire          PWRITE,
    input  wire [31:0]   PWDATA,
    output wire [31:0]   PRDATA,
    output wire          PREADY,
    // flash backdoor load request (rising edge -> $readmemh)
    input  wire          FLASH_LOAD,
    output wire          QSPI_nCS_o,
    output wire          QSPI_SCLK_o
);

// ---------------- default slave + HREADY mux ----------------
reg        dp_sel_qspi;     // data phase belongs to the QSPI slave
reg        dp_dflt;         // data phase belongs to the default slave (valid xfer)
reg  [9:0] dflt_cnt;
wire       dflt_hreadyout = !dp_dflt || (dflt_cnt == 10'd0);
always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
        dp_sel_qspi <= 1'b0; dp_dflt <= 1'b0; dflt_cnt <= 10'd0;
    end else begin
        if (dp_dflt && dflt_cnt != 0) dflt_cnt <= dflt_cnt - 10'd1;
        if (HREADY) begin
            dp_sel_qspi <= HSEL;
            dp_dflt     <= !HSEL && HTRANS[1];
            dflt_cnt    <= (!HSEL && HTRANS[1]) ? DFLT_WAIT : 10'd0;
        end
    end
end
assign HREADY = dp_sel_qspi ? S_HREADYOUT : dflt_hreadyout;
assign HRESP  = dp_sel_qspi ? S_HRESP     : 1'b0;
assign HRDATA = dp_sel_qspi ? S_HRDATA    : 128'hD0D0_D0D0_D0D0_D0D0_D0D0_D0D0_D0D0_D0D0;

// ---------------- QSPI core (top_ahb_qspi minus cache) ----------------
wire [7:0]   QSPI_CMD;            wire QSPI_ENABLE;  wire QSPI_READ; wire QSPI_WRITE;
wire         QSPI_ADDR_EN;        wire [3:0] QSPI_DUMMY_CYCLES; wire [3:0] QSPI_N_RW_BYTES;
wire [21:0]  QSPI_ADDR;           wire [127:0] QSPI_WDATA; wire QSPI_ENABLE_ACK;
wire [127:0] QSPI_RDATA;
wire [7:0]   AHB_QSPI_CMD;        wire AHB_QSPI_ENABLE; wire AHB_QSPI_READ; wire AHB_QSPI_WRITE;
wire         AHB_QSPI_ADDR_EN;    wire [3:0] AHB_QSPI_DUMMY_CYCLES; wire [3:0] AHB_QSPI_N_RW_BYTES;
wire [21:0]  AHB_QSPI_ADDR;       wire [127:0] AHB_QSPI_WDATA; wire AHB_QSPI_ENABLE_ACK;
wire         AHB_QSPI_BUSY;       wire [127:0] AHB_QSPI_RDATA;
wire [7:0]   APB_QSPI_CMD;        wire APB_QSPI_ENABLE; wire APB_QSPI_READ; wire APB_QSPI_WRITE;
wire         APB_QSPI_ADDR_EN;    wire [3:0] APB_QSPI_DUMMY_CYCLES; wire [3:0] APB_QSPI_N_RW_BYTES;
wire [21:0]  APB_QSPI_ADDR;       wire [127:0] APB_QSPI_WDATA; wire APB_QSPI_ENABLE_ACK;
wire         APB_QSPI_BUSY;       wire [127:0] APB_QSPI_RDATA;
wire QSPI_QIO_MODE, QSPI_CONT_READ, QSPI_NO_CMD, XIP_ACTIVE;
wire [7:0] QSPI_MODE_CODE; wire [4:0] QSPI_CLK_DIV;
wire QSPI_SCLK_i, QSPI_SCLK, QSPI_nCS, qspi_soft_reset;
wire [3:0] QSPI_IO_o, QSPI_IO_i, QSPI_IO_e;
wire PSLVERR, IRQ_QSPI_FINISHED;

qspi_controller_mux u_qspi_controller_mux(
    .HRESETn(HRESETn), .QSPI_SCLK(QSPI_SCLK_i), .XIP_ACTIVE(XIP_ACTIVE),
    .AHB_QSPI_CMD(AHB_QSPI_CMD), .AHB_QSPI_ENABLE(AHB_QSPI_ENABLE), .AHB_QSPI_READ(AHB_QSPI_READ),
    .AHB_QSPI_WRITE(AHB_QSPI_WRITE), .AHB_QSPI_ADDR_EN(AHB_QSPI_ADDR_EN),
    .AHB_QSPI_DUMMY_CYCLES(AHB_QSPI_DUMMY_CYCLES), .AHB_QSPI_N_RW_BYTES(AHB_QSPI_N_RW_BYTES),
    .AHB_QSPI_ADDR(AHB_QSPI_ADDR), .AHB_QSPI_WDATA(AHB_QSPI_WDATA),
    .AHB_QSPI_ENABLE_ACK(AHB_QSPI_ENABLE_ACK), .AHB_QSPI_BUSY(AHB_QSPI_BUSY), .AHB_QSPI_RDATA(AHB_QSPI_RDATA),
    .APB_QSPI_CMD(APB_QSPI_CMD), .APB_QSPI_ENABLE(APB_QSPI_ENABLE), .APB_QSPI_READ(APB_QSPI_READ),
    .APB_QSPI_WRITE(APB_QSPI_WRITE), .APB_QSPI_ADDR_EN(APB_QSPI_ADDR_EN),
    .APB_QSPI_DUMMY_CYCLES(APB_QSPI_DUMMY_CYCLES), .APB_QSPI_N_RW_BYTES(APB_QSPI_N_RW_BYTES),
    .APB_QSPI_ADDR(APB_QSPI_ADDR), .APB_QSPI_WDATA(APB_QSPI_WDATA),
    .APB_QSPI_ENABLE_ACK(APB_QSPI_ENABLE_ACK), .APB_QSPI_BUSY(APB_QSPI_BUSY), .APB_QSPI_RDATA(APB_QSPI_RDATA),
    .QSPI_CMD(QSPI_CMD), .QSPI_ENABLE(QSPI_ENABLE), .QSPI_READ(QSPI_READ), .QSPI_WRITE(QSPI_WRITE),
    .QSPI_ADDR_EN(QSPI_ADDR_EN), .QSPI_DUMMY_CYCLES(QSPI_DUMMY_CYCLES), .QSPI_N_RW_BYTES(QSPI_N_RW_BYTES),
    .QSPI_ADDR(QSPI_ADDR), .QSPI_WDATA(QSPI_WDATA), .QSPI_ENABLE_ACK(QSPI_ENABLE_ACK),
    .QSPI_BUSY(~QSPI_nCS), .QSPI_RDATA(QSPI_RDATA)
);

apb_qspi_regs u_apb_qspi_regs(
    .PCLK(HCLK), .PRESETn(HRESETn), .PADDR(PADDR[11:2]), .PSEL(PSEL), .PENABLE(PENABLE),
    .PWRITE(PWRITE), .PWDATA(PWDATA), .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR),
    .QSPI_CMD(APB_QSPI_CMD), .QSPI_ENABLE(APB_QSPI_ENABLE), .QSPI_ENABLE_ACK(APB_QSPI_ENABLE_ACK),
    .QSPI_READ(APB_QSPI_READ), .QSPI_WRITE(APB_QSPI_WRITE), .QSPI_ADDR_EN(APB_QSPI_ADDR_EN),
    .QSPI_DUMMY_CYCLES(APB_QSPI_DUMMY_CYCLES), .QSPI_N_RW_BYTES(APB_QSPI_N_RW_BYTES),
    .QSPI_ADDR(APB_QSPI_ADDR), .QSPI_BUSY(APB_QSPI_BUSY), .QSPI_QIO_MODE(QSPI_QIO_MODE),
    .QSPI_RDATA(APB_QSPI_RDATA), .QSPI_WDATA(APB_QSPI_WDATA), .XIP_ACTIVE(XIP_ACTIVE),
    .QSPI_CONT_READ(QSPI_CONT_READ), .QSPI_MODE_CODE(QSPI_MODE_CODE), .QSPI_NO_CMD(QSPI_NO_CMD),
    .IRQ_QSPI_FINISHED(IRQ_QSPI_FINISHED), .QSPI_CLK_DIV(QSPI_CLK_DIV),
    .AHB_QSPI_CMD(AHB_QSPI_CMD), .AHB_QSPI_DUMMY_CYCLES(AHB_QSPI_DUMMY_CYCLES)
);

ahb_qspi_interface #(.ADDR_W(22), .DATA_W(128), .WATCHDOG_WIDTH(WATCHDOG_WIDTH)) u_ahb_qspi_interface (
    .HCLK(HCLK), .HRESETn(HRESETn), .HADDR(HADDR), .HTRANS(HTRANS), .HWRITE(HWRITE),
    .HSIZE(HSIZE), .HBURST(HBURST), .HPROT(4'b0010), .HWDATA(HWDATA), .HSELx(HSEL),
    .HRDATA(S_HRDATA), .HREADY(HREADY), .HREADYOUT(S_HREADYOUT), .HRESP(S_HRESP),
    .XIP_ACTIVE(XIP_ACTIVE), .AHB_QSPI_ENABLE(AHB_QSPI_ENABLE), .AHB_QSPI_READ(AHB_QSPI_READ),
    .AHB_QSPI_WRITE(AHB_QSPI_WRITE), .AHB_QSPI_ADDR_EN(AHB_QSPI_ADDR_EN),
    .AHB_QSPI_N_RW_BYTES(AHB_QSPI_N_RW_BYTES), .AHB_QSPI_ADDR(AHB_QSPI_ADDR),
    .AHB_QSPI_WDATA(AHB_QSPI_WDATA), .AHB_QSPI_ENABLE_ACK(AHB_QSPI_ENABLE_ACK),
    .AHB_QSPI_BUSY(AHB_QSPI_BUSY), .AHB_QSPI_RDATA(AHB_QSPI_RDATA), .SOFT_RESET(qspi_soft_reset)
);

qspi_clock_div u_qspi_clock_div(.HCLK(HCLK), .HRESETn(HRESETn), .QSPI_CLK_DIV(QSPI_CLK_DIV), .QSPI_SCLK_i(QSPI_SCLK_i));

qspi_controller u_qspi_controller(
    .HCLK(HCLK), .HRESETn(HRESETn), .SOFT_RESET(qspi_soft_reset), .QSPI_SCLK_i(QSPI_SCLK_i),
    .QSPI_SPI_MODE(2'b00), .QSPI_CMD(QSPI_CMD), .QSPI_ENABLE(QSPI_ENABLE), .QSPI_ENABLE_ACK(QSPI_ENABLE_ACK),
    .QSPI_READ(QSPI_READ), .QSPI_WRITE(QSPI_WRITE), .QSPI_ADDR_EN(QSPI_ADDR_EN),
    .QSPI_DUMMY_CYCLES(QSPI_DUMMY_CYCLES), .QSPI_N_RW_BYTES({1'b0,QSPI_N_RW_BYTES}), .QSPI_ADDR(QSPI_ADDR),
    .QSPI_QIO_MODE(QSPI_QIO_MODE), .QSPI_WDATA(QSPI_WDATA), .QSPI_RDATA(QSPI_RDATA),
    .QSPI_CONT_READ(QSPI_CONT_READ), .QSPI_MODE_CODE(QSPI_MODE_CODE), .QSPI_NO_CMD(QSPI_NO_CMD),
    .QSPI_SCLK(QSPI_SCLK), .QSPI_nCS(QSPI_nCS), .QSPI_IO_o(QSPI_IO_o), .QSPI_IO_i(QSPI_IO_i), .QSPI_IO_e(QSPI_IO_e)
);

// pads + flash
wire [3:0] QSPI_IO;
assign QSPI_IO[0] = QSPI_IO_e[0] ? QSPI_IO_o[0] : 1'bz;
assign QSPI_IO[1] = QSPI_IO_e[1] ? QSPI_IO_o[1] : 1'bz;
assign QSPI_IO[2] = QSPI_IO_e[2] ? QSPI_IO_o[2] : 1'bz;
assign QSPI_IO[3] = QSPI_IO_e[3] ? QSPI_IO_o[3] : 1'bz;
assign QSPI_IO_i  = QSPI_IO;
assign QSPI_nCS_o  = QSPI_nCS;
assign QSPI_SCLK_o = QSPI_SCLK;

sst26vf064b u_flash(.SCK(QSPI_SCLK), .SIO(QSPI_IO), .CEb(QSPI_nCS));
defparam u_flash.I0.Tbe = 1_000;
defparam u_flash.I0.Tse = 1_000;
defparam u_flash.I0.Tsce = 1_000;
defparam u_flash.I0.Tpp = 1_000;
defparam u_flash.I0.Tws = 1000;

// Backdoor preload: cocotb writes a1_flash.hex (addr 0..), then pulses FLASH_LOAD.
always @(posedge FLASH_LOAD) $readmemh("a1_flash.hex", u_flash.I0.memory);

endmodule
