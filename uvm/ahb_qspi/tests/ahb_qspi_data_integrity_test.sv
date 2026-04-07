///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_data_integrity_test.sv
///////////////////////////////////////////////////////////////////////////////
// Data integrity tests: pattern sweep, multi-word program, cross-mode verify.
// Aims to detect bit-stuck, nibble-swap, and byte-ordering bugs.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_DATA_INTEGRITY_TEST_SV
`define GUARD_AHB_QSPI_DATA_INTEGRITY_TEST_SV

class ahb_qspi_data_integrity_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_data_integrity_test)

  function new(string name = "ahb_qspi_data_integrity_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence          init_seq;
    data_pattern_sequence       pat_seq;
    multiword_program_sequence  mw_seq;
    cross_mode_verify_sequence  xmode_seq;

    phase.raise_objection(this);
    wait_for_reset();

    // ---------------------------------------------------------------
    `uvm_info("DATA_INT", "=== Phase 1: Flash Init ===", UVM_LOW)
    // ---------------------------------------------------------------
    init_seq = qspi_init_sequence::type_id::create("init");
    init_seq.clear_protect = 1;
    init_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("DATA_INT", "=== Phase 2: Data Pattern Sweep (SPI) ===", UVM_LOW)
    // ---------------------------------------------------------------
    pat_seq = data_pattern_sequence::type_id::create("pat_spi");
    pat_seq.use_qpi = 0;
    pat_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("DATA_INT", "=== Phase 3: Multi-word Program (SPI) ===", UVM_LOW)
    // ---------------------------------------------------------------
    mw_seq = multiword_program_sequence::type_id::create("mw_spi");
    mw_seq.use_qpi = 0;
    mw_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("DATA_INT", "=== Phase 4: Cross-mode Consistency ===", UVM_LOW)
    // ---------------------------------------------------------------
    xmode_seq = cross_mode_verify_sequence::type_id::create("xmode");
    xmode_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("DATA_INT", "=== Phase 5: Data Pattern Sweep (QPI) ===", UVM_LOW)
    // ---------------------------------------------------------------
    begin
      qspi_cmd_sequence cmd;
      apb_write_sequence wr;

      // Enter QPI
      cmd = qspi_cmd_sequence::type_id::create("eqio");
      cmd.opcode = SPI_OP_EQIO;
      cmd.start(env.apb_agt.sequencer);

      wr = apb_write_sequence::type_id::create("set_qpi");
      wr.addr  = QSPI_CTRL_ADDR;
      wr.wdata = (1 << CTRL_QIO_MODE_BIT);
      wr.start(env.apb_agt.sequencer);

      pat_seq = data_pattern_sequence::type_id::create("pat_qpi");
      pat_seq.use_qpi = 1;
      pat_seq.start(env.apb_agt.sequencer);

      // Exit QPI
      cmd = qspi_cmd_sequence::type_id::create("rstqio");
      cmd.opcode = SPI_OP_RSTQIO;
      cmd.start(env.apb_agt.sequencer);

      wr = apb_write_sequence::type_id::create("clr_qpi");
      wr.addr  = QSPI_CTRL_ADDR;
      wr.wdata = 0;
      wr.start(env.apb_agt.sequencer);
    end

    `uvm_info("DATA_INT", "Data integrity test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_DATA_INTEGRITY_TEST_SV
