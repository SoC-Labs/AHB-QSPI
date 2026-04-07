///////////////////////////////////////////////////////////////////////////////
// ahb_data_if.sv
///////////////////////////////////////////////////////////////////////////////
// Interface for AHB data port (XIP reads) and DUT sideband signals.
// Tests drive AHB transactions and observe IRQ through this interface.
///////////////////////////////////////////////////////////////////////////////

interface ahb_data_if (
  input logic clk,
  input logic rst_n
);

  // AHB signals (test drives these for XIP reads)
  logic [31:0] haddr;
  logic [1:0]  htrans;
  logic        hwrite;
  logic [2:0]  hsize;
  logic [2:0]  hburst;
  logic [3:0]  hprot;
  logic [31:0] hwdata;
  logic        hsel;
  logic [31:0] hrdata;
  logic        hready;
  logic        hresp;

  // DUT sideband
  logic        irq_qspi_finished;

  // Clocking block for test access
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    output haddr, htrans, hwrite, hsize, hburst, hprot, hwdata, hsel;
    input  hrdata, hready, hresp, irq_qspi_finished;
  endclocking

  modport master (clocking drv_cb, input clk, input rst_n);

endinterface
