///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_base_test.sv
///////////////////////////////////////////////////////////////////////////////
// Base test for all AHB QSPI tests.
// Creates the environment and provides helper tasks for common operations.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_BASE_TEST_SV
`define GUARD_AHB_QSPI_BASE_TEST_SV

class ahb_qspi_base_test extends uvm_test;

  `uvm_component_utils(ahb_qspi_base_test)

  ahb_qspi_env env;
  virtual apb_master_if vif;
  virtual ahb_data_if.master ahb_vif;

  function new(string name = "ahb_qspi_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = ahb_qspi_env::type_id::create("env", this);

    if (!uvm_config_db#(virtual apb_master_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for base test")
    if (!uvm_config_db#(virtual ahb_data_if.master)::get(this, "", "ahb_vif", ahb_vif))
      `uvm_fatal("NOVIF", "AHB data virtual interface not found for base test")
  endfunction

  // Wait for reset to deassert
  task wait_for_reset();
    @(posedge vif.rst_n);
    repeat (5) @(posedge vif.clk);
    `uvm_info("BASE_TEST", "Reset deasserted, starting test", UVM_LOW)
  endtask

  // Helper: APB read
  task apb_read(bit [15:0] addr, output bit [31:0] data);
    apb_read_sequence seq;
    seq = apb_read_sequence::type_id::create("rd");
    seq.addr = addr;
    seq.start(env.apb_agt.sequencer);
    data = seq.rdata;
  endtask

  // Helper: APB write
  task apb_write(bit [15:0] addr, bit [31:0] data);
    apb_write_sequence seq;
    seq = apb_write_sequence::type_id::create("wr");
    seq.addr  = addr;
    seq.wdata = data;
    seq.start(env.apb_agt.sequencer);
  endtask

  // Helper: Wait N clock cycles
  task wait_clks(int n);
    repeat (n) @(posedge vif.clk);
  endtask

  // Helper: Single AHB read via ahb_data_if
  task ahb_read(bit [31:0] addr, output bit [31:0] data);
    @(ahb_vif.drv_cb);
    ahb_vif.drv_cb.haddr  <= addr;
    ahb_vif.drv_cb.htrans <= 2'b10;  // NONSEQ
    ahb_vif.drv_cb.hwrite <= 1'b0;
    ahb_vif.drv_cb.hsel   <= 1'b1;
    ahb_vif.drv_cb.hsize  <= 3'b010; // Word

    // Wait for address phase acceptance
    do @(ahb_vif.drv_cb); while (!ahb_vif.drv_cb.hready);

    // Data phase: go idle
    ahb_vif.drv_cb.htrans <= 2'b00;
    ahb_vif.drv_cb.hsel   <= 1'b0;

    do @(ahb_vif.drv_cb); while (!ahb_vif.drv_cb.hready);

    data = ahb_vif.drv_cb.hrdata;
  endtask

  // Helper: Single AHB write via ahb_data_if
  task ahb_write_txn(bit [31:0] addr, bit [31:0] wdata);
    @(ahb_vif.drv_cb);
    ahb_vif.drv_cb.haddr  <= addr;
    ahb_vif.drv_cb.htrans <= 2'b10;  // NONSEQ
    ahb_vif.drv_cb.hwrite <= 1'b1;
    ahb_vif.drv_cb.hsel   <= 1'b1;
    ahb_vif.drv_cb.hsize  <= 3'b010;

    do @(ahb_vif.drv_cb); while (!ahb_vif.drv_cb.hready);

    // Data phase
    ahb_vif.drv_cb.hwdata <= wdata;
    ahb_vif.drv_cb.htrans <= 2'b00;
    ahb_vif.drv_cb.hsel   <= 1'b0;
    ahb_vif.drv_cb.hwrite <= 1'b0;

    do @(ahb_vif.drv_cb); while (!ahb_vif.drv_cb.hready);
  endtask

  virtual function void report_phase(uvm_phase phase);
    uvm_report_server svr = uvm_report_server::get_server();
    if (svr.get_severity_count(UVM_ERROR) == 0 &&
        svr.get_severity_count(UVM_FATAL) == 0)
      `uvm_info("TEST_RESULT", "*** TEST PASSED ***", UVM_NONE)
    else
      `uvm_info("TEST_RESULT", "*** TEST FAILED ***", UVM_NONE)
  endfunction

endclass

`endif // GUARD_AHB_QSPI_BASE_TEST_SV
