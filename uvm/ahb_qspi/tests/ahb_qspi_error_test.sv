///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_error_test.sv
///////////////////////////////////////////////////////////////////////////////
// Error path tests: AHB write rejection, read without XIP, APB during XIP.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_ERROR_TEST_SV
`define GUARD_AHB_QSPI_ERROR_TEST_SV

class ahb_qspi_error_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_error_test)

  function new(string name = "ahb_qspi_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence init_seq;
    bit [31:0] rdata;
    bit [31:0] dummy;

    phase.raise_objection(this);
    wait_for_reset();

    init_seq = qspi_init_sequence::type_id::create("init");
    init_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("ERR_TEST", "=== AHB Write Rejection ===", UVM_LOW)
    // ---------------------------------------------------------------
    // Enable XIP first
    apb_write(QSPI_AHB_SETUP_ADDR, {16'h0, 4'h8, 4'h0, SPI_OP_FAST_READ});
    apb_write(QSPI_CTRL_ADDR, (1 << CTRL_XIP_ACTIVE_BIT));
    wait_clks(5);

    // Attempt AHB write — should get HRESP=1
    ahb_write_txn(32'h0000_0000, 32'hBAD0_BA5E);

    if (ahb_vif.drv_cb.hresp === 1'b1)
      `uvm_info("ERR_TEST", "PASS: AHB write correctly rejected with HRESP=1", UVM_LOW)
    else
      `uvm_error("ERR_TEST", "FAIL: AHB write did NOT generate HRESP=1 error")

    // Disable XIP
    apb_write(QSPI_CTRL_ADDR, 32'h0);
    wait_clks(10);

    // ---------------------------------------------------------------
    `uvm_info("ERR_TEST", "=== AHB Read Without XIP ===", UVM_LOW)
    // ---------------------------------------------------------------
    // Attempt AHB read with XIP_ACTIVE=0
    ahb_read(32'h0000_0000, dummy);

    if (ahb_vif.drv_cb.hresp === 1'b1)
      `uvm_info("ERR_TEST", "PASS: AHB read without XIP correctly rejected", UVM_LOW)
    else
      `uvm_error("ERR_TEST", "FAIL: AHB read without XIP did NOT generate error")

    // ---------------------------------------------------------------
    `uvm_info("ERR_TEST", "=== APB Busy During XIP ===", UVM_LOW)
    // ---------------------------------------------------------------
    apb_write(QSPI_AHB_SETUP_ADDR, {16'h0, 4'h8, 4'h0, SPI_OP_FAST_READ});
    apb_write(QSPI_CTRL_ADDR, (1 << CTRL_XIP_ACTIVE_BIT));
    wait_clks(5);

    // Read STATUS — APB_QSPI_BUSY should be forced high during XIP
    apb_read(QSPI_STATUS_ADDR, rdata);
    `uvm_info("ERR_TEST", $sformatf("STATUS during XIP: 0x%08h (BUSY=%0b)", rdata, rdata[0]), UVM_LOW)

    // Disable XIP
    apb_write(QSPI_CTRL_ADDR, 32'h0);

    `uvm_info("ERR_TEST", "Error test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_ERROR_TEST_SV
