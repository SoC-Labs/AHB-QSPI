///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_stress_test.sv
///////////////////////////////////////////////////////////////////////////////
// Stress test: register storm, clock divider sweep, mode switching frenzy,
// dummy cycle boundary walk.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_STRESS_TEST_SV
`define GUARD_AHB_QSPI_STRESS_TEST_SV

class ahb_qspi_stress_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_stress_test)

  function new(string name = "ahb_qspi_stress_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence    init_seq;
    reg_storm_sequence    storm_seq;
    clkdiv_sweep_sequence clk_seq;
    dummy_sweep_sequence  dummy_seq;
    mode_switch_sequence  mode_seq;

    phase.raise_objection(this);
    wait_for_reset();

    // ---------------------------------------------------------------
    `uvm_info("STRESS", "=== Phase 1: Flash Init ===", UVM_LOW)
    // ---------------------------------------------------------------
    init_seq = qspi_init_sequence::type_id::create("init");
    init_seq.clear_protect = 1;
    init_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("STRESS", "=== Phase 2: Register Storm ===", UVM_LOW)
    // ---------------------------------------------------------------
    storm_seq = reg_storm_sequence::type_id::create("storm");
    storm_seq.num_transactions = 200;
    storm_seq.start(env.apb_agt.sequencer);

    // Re-init after storm (registers are now random)
    apb_write(QSPI_CTRL_ADDR, 32'h0);
    apb_write(QSPI_CLK_DIV_ADDR, 32'h2);

    // Verify controller still works after storm
    begin
      qspi_cmd_sequence cmd;

      // Reset flash
      cmd = qspi_cmd_sequence::type_id::create("rsten");
      cmd.opcode = SPI_OP_RSTEN;
      cmd.start(env.apb_agt.sequencer);

      cmd = qspi_cmd_sequence::type_id::create("rst");
      cmd.opcode = SPI_OP_RST;
      cmd.start(env.apb_agt.sequencer);

      cmd = qspi_cmd_sequence::type_id::create("jedec_post_storm");
      cmd.opcode     = SPI_OP_JEDEC_ID;
      cmd.do_read    = 1;
      cmd.n_rw_bytes = 3;
      cmd.start(env.apb_agt.sequencer);

      env.scoreboard.check_reg_value("JEDEC post-storm", cmd.rdata[0],
        {24'h0, FLASH_MFG_ID}, 32'h000000FF);
    end

    // ---------------------------------------------------------------
    `uvm_info("STRESS", "=== Phase 3: Clock Divider Sweep ===", UVM_LOW)
    // ---------------------------------------------------------------
    clk_seq = clkdiv_sweep_sequence::type_id::create("clk_sweep");
    clk_seq.start(env.apb_agt.sequencer);

    // Restore safe divider
    apb_write(QSPI_CLK_DIV_ADDR, 32'h2);

    // ---------------------------------------------------------------
    `uvm_info("STRESS", "=== Phase 4: Dummy Cycle Boundary Walk ===", UVM_LOW)
    // ---------------------------------------------------------------
    dummy_seq = dummy_sweep_sequence::type_id::create("dummy_sweep");
    dummy_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("STRESS", "=== Phase 5: Mode Switching Frenzy ===", UVM_LOW)
    // ---------------------------------------------------------------
    mode_seq = mode_switch_sequence::type_id::create("mode_frenzy");
    mode_seq.num_switches = 20;
    mode_seq.start(env.apb_agt.sequencer);

    `uvm_info("STRESS", "Stress test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_STRESS_TEST_SV
