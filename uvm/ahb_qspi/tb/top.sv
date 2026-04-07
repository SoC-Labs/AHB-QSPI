///////////////////////////////////////////////////////////////////////////////
// top.sv
///////////////////////////////////////////////////////////////////////////////
// Top-level UVM testbench for AHB QSPI verification.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "uvm_pkg.sv"

// Interfaces (must be outside module)
`include "apb_master_if.sv"
`include "ahb_data_if.sv"
`include "qspi_monitor_if.sv"

// Testbench package
`include "ahb_qspi_pkg.sv"

module test_top;

  // ---------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------
  parameter CLK_PERIOD = 10; // 100 MHz (matches cocotb TB, avoids flash timing violations)

  bit  hclk;
  logic hresetn;

  initial begin
    hclk = 1'b0;
    forever #(CLK_PERIOD/2) hclk = ~hclk;
  end

  initial begin
    hresetn = 1'b0;
    repeat (20) @(posedge hclk);
    hresetn = 1'b1;
  end

  // ---------------------------------------------------------------
  // Package imports
  // ---------------------------------------------------------------
  import uvm_pkg::*;
  import ahb_qspi_pkg::*;

  // ---------------------------------------------------------------
  // Interface instances
  // ---------------------------------------------------------------
  apb_master_if   apb_if(.clk(hclk), .rst_n(hresetn));
  ahb_data_if     ahb_if(.clk(hclk), .rst_n(hresetn));
  qspi_monitor_if qspi_if();

  // ---------------------------------------------------------------
  // DUT interrupt and QSPI bus signals
  // ---------------------------------------------------------------
  wire irq_qspi_finished;
  wire qspi_sclk;
  wire qspi_ncs;
  wire [3:0] qspi_io;

  // Connect IRQ to AHB interface for test observability
  assign ahb_if.irq_qspi_finished = irq_qspi_finished;

  // ---------------------------------------------------------------
  // DUT instantiation (pad-level wrapper with tri-state IO)
  // ---------------------------------------------------------------
  ahb_qspi_pads u_dut (
    .HCLK          (hclk),
    .HRESETn       (hresetn),
    .PCLK          (hclk),
    .PRESETn       (hresetn),

    // AHB slave port (data / XIP reads — driven via ahb_data_if)
    .HADDR         (ahb_if.haddr),
    .HTRANS        (ahb_if.htrans),
    .HWRITE        (ahb_if.hwrite),
    .HSIZE         (ahb_if.hsize),
    .HBURST        (ahb_if.hburst),
    .HPROT         (ahb_if.hprot),
    .HWDATA        (ahb_if.hwdata),
    .HSELx         (ahb_if.hsel),
    .HRDATA        (ahb_if.hrdata),
    .HREADY        (ahb_if.hready),
    .HREADYOUT     (ahb_if.hready),
    .HRESP         (ahb_if.hresp),

    // APB slave port (register config — driven by APB master agent)
    .PADDR         (apb_if.paddr),
    .PPROT         (3'b000),
    .PSEL          (apb_if.psel),
    .PENABLE       (apb_if.penable),
    .PWRITE        (apb_if.pwrite),
    .PWDATA        (apb_if.pwdata),
    .PSTRB         (4'b1111),
    .PRDATA        (apb_if.prdata),
    .PREADY        (apb_if.pready),
    .PSLVERR       (apb_if.pslverr),

    // QSPI pad signals
    .QSPI_SCLK    (qspi_sclk),
    .QSPI_nCS     (qspi_ncs),
    .QSPI_IO      (qspi_io),

    // Interrupt
    .IRQ_QSPI_FINISHED (irq_qspi_finished)
  );

  // ---------------------------------------------------------------
  // SST26VF064B Flash Memory Model
  // ---------------------------------------------------------------
  sst26vf064b u_flash (
    .SCK (qspi_sclk),
    .SIO (qspi_io),
    .CEb (qspi_ncs)
  );

  // Speed up flash model timing for simulation
  defparam u_flash.I0.Tbe  = 1_000;
  defparam u_flash.I0.Tse  = 1_000;
  defparam u_flash.I0.Tsce = 1_000;
  defparam u_flash.I0.Tpp  = 1_000;
  defparam u_flash.I0.Tws  = 1000;

  // ---------------------------------------------------------------
  // QSPI monitor interface connections
  // ---------------------------------------------------------------
  assign qspi_if.sclk = qspi_sclk;
  assign qspi_if.csn  = qspi_ncs;
  assign qspi_if.io   = qspi_io;

  // ---------------------------------------------------------------
  // Waveform dumping
  // ---------------------------------------------------------------
`ifdef WAVES_FSDB
  initial begin
    $fsdbDumpfile("test_top");
    $fsdbDumpvars;
  end
`elsif WAVES_VCD
  initial begin
    $dumpfile("test_top.vcd");
    $dumpvars(0, test_top);
  end
`elsif WAVES
  initial begin
    $vcdpluson;
  end
`endif

  // ---------------------------------------------------------------
  // UVM configuration and test launch
  // ---------------------------------------------------------------
  initial begin
    // APB master agent interfaces
    uvm_config_db#(virtual apb_master_if.driver)::set(uvm_root::get(),
      "uvm_test_top.env.apb_agt.driver", "vif", apb_if.driver);
    uvm_config_db#(virtual apb_master_if.monitor)::set(uvm_root::get(),
      "uvm_test_top.env.apb_agt.monitor", "vif", apb_if.monitor);

    // QSPI monitor interface
    uvm_config_db#(virtual qspi_monitor_if)::set(uvm_root::get(),
      "uvm_test_top.env.qspi_mon", "vif", qspi_if);

    // AHB data port interface (for XIP and error tests)
    uvm_config_db#(virtual ahb_data_if.master)::set(uvm_root::get(),
      "uvm_test_top", "ahb_vif", ahb_if.master);

    // APB interface for clock/reset access
    uvm_config_db#(virtual apb_master_if)::set(uvm_root::get(),
      "uvm_test_top", "vif", apb_if);

    run_test();
  end

endmodule
