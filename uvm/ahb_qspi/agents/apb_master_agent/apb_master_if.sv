///////////////////////////////////////////////////////////////////////////////
// apb_master_if.sv
///////////////////////////////////////////////////////////////////////////////
// SystemVerilog interface for APB master bus signals.
// Adapted from ptp-hardware-clock-ahb UVM testbench.
///////////////////////////////////////////////////////////////////////////////

interface apb_master_if (
  input logic clk,
  input logic rst_n
);

  // APB signals (agent drives psel/penable/pwrite/paddr/pwdata)
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [15:0] paddr;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr;

  // Driver clocking block (master drives psel, penable, pwrite, paddr, pwdata)
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    output psel, penable, pwrite, paddr, pwdata;
    input  prdata, pready, pslverr;
  endclocking

  // Monitor clocking block
  clocking mon_cb @(posedge clk);
    default input #1step;
    input psel, penable, pwrite, paddr, pwdata, prdata, pready, pslverr;
  endclocking

  // Modports
  modport driver  (clocking drv_cb, input clk, input rst_n);
  modport monitor (clocking mon_cb, input clk, input rst_n);

endinterface
