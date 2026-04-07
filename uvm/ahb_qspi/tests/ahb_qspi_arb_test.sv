///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_arb_test.sv
///////////////////////////////////////////////////////////////////////////////
// Arbitration tests: XIP_ACTIVE toggling, mux contention scenarios.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_ARB_TEST_SV
`define GUARD_AHB_QSPI_ARB_TEST_SV

class ahb_qspi_arb_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_arb_test)

  function new(string name = "ahb_qspi_arb_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence init_seq;
    qspi_cmd_sequence  cmd;

    phase.raise_objection(this);
    wait_for_reset();

    init_seq = qspi_init_sequence::type_id::create("init");
    init_seq.clear_protect = 1;
    init_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("ARB_TEST", "=== XIP Toggle While Idle ===", UVM_LOW)
    // ---------------------------------------------------------------
    // Toggle XIP_ACTIVE on and off while QSPI is idle
    for (int i = 0; i < 10; i++) begin
      apb_write(QSPI_AHB_SETUP_ADDR, {16'h0, 4'h8, 4'h0, SPI_OP_FAST_READ});
      apb_write(QSPI_CTRL_ADDR, (1 << CTRL_XIP_ACTIVE_BIT));
      wait_clks(5);
      apb_write(QSPI_CTRL_ADDR, 32'h0);
      wait_clks(5);
    end
    `uvm_info("ARB_TEST", "XIP idle toggle complete", UVM_LOW)

    // ---------------------------------------------------------------
    `uvm_info("ARB_TEST", "=== APB Command After XIP Disable ===", UVM_LOW)
    // ---------------------------------------------------------------
    // Verify APB commands work correctly after XIP is disabled
    apb_write(QSPI_CTRL_ADDR, (1 << CTRL_XIP_ACTIVE_BIT));
    wait_clks(10);
    apb_write(QSPI_CTRL_ADDR, 32'h0);
    wait_clks(10);

    // Issue JEDEC ID via APB — should work
    cmd = qspi_cmd_sequence::type_id::create("jedec_after_xip");
    cmd.opcode     = SPI_OP_JEDEC_ID;
    cmd.do_read    = 1;
    cmd.n_rw_bytes = 3;
    cmd.start(env.apb_agt.sequencer);

    env.scoreboard.check_reg_value("JEDEC after XIP toggle", cmd.rdata[0],
      {24'h0, FLASH_MFG_ID}, 32'h000000FF);

    // ---------------------------------------------------------------
    `uvm_info("ARB_TEST", "=== Multiple APB Commands Between XIP Cycles ===", UVM_LOW)
    // ---------------------------------------------------------------
    for (int i = 0; i < 5; i++) begin
      // APB command
      cmd = qspi_cmd_sequence::type_id::create($sformatf("jedec_%0d", i));
      cmd.opcode     = SPI_OP_JEDEC_ID;
      cmd.do_read    = 1;
      cmd.n_rw_bytes = 3;
      cmd.start(env.apb_agt.sequencer);

      // Brief XIP enable/disable
      apb_write(QSPI_AHB_SETUP_ADDR, {16'h0, 4'h8, 4'h0, SPI_OP_FAST_READ});
      apb_write(QSPI_CTRL_ADDR, (1 << CTRL_XIP_ACTIVE_BIT));
      wait_clks(20);
      apb_write(QSPI_CTRL_ADDR, 32'h0);
      wait_clks(10);
    end

    `uvm_info("ARB_TEST", "Arbitration test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_ARB_TEST_SV
