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
  // Initialised to idle/deselected defaults to prevent xprop X propagation
  // through the AHB HREADY feedback path after reset deassertion.
  logic [31:0] haddr  = 32'h0;
  logic [1:0]  htrans = 2'b00;
  logic        hwrite = 1'b0;
  logic [2:0]  hsize  = 3'b000;
  logic [2:0]  hburst = 3'b000;
  logic [3:0]  hprot  = 4'b0000;
  logic [31:0] hwdata = 32'h0;
  logic        hsel   = 1'b0;
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
