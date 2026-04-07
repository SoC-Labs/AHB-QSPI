///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_qpi_cmd_test.sv
///////////////////////////////////////////////////////////////////////////////
// QPI mode command tests: enter/exit QPI, JEDEC ID, continuous read.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_QPI_CMD_TEST_SV
`define GUARD_AHB_QSPI_QPI_CMD_TEST_SV

class ahb_qspi_qpi_cmd_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_qpi_cmd_test)

  function new(string name = "ahb_qspi_qpi_cmd_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence init_seq;
    qspi_cmd_sequence  cmd;

    phase.raise_objection(this);
    wait_for_reset();

    // Initialise flash in QPI mode
    init_seq = qspi_init_sequence::type_id::create("init");
    init_seq.enter_qpi     = 1;
    init_seq.clear_protect = 1;
    init_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("QPI_TEST", "=== QPI JEDEC ID ===", UVM_LOW)
    // ---------------------------------------------------------------
    cmd = qspi_cmd_sequence::type_id::create("qjedec");
    cmd.opcode     = SPI_OP_QUAD_JEDEC_ID;
    cmd.do_read    = 1;
    cmd.n_rw_bytes = 3;
    cmd.start(env.apb_agt.sequencer);

    env.scoreboard.check_reg_value("QPI JEDEC MFG", cmd.rdata[0], {24'h0, FLASH_MFG_ID}, 32'h000000FF);
    `uvm_info("QPI_TEST", $sformatf("QPI JEDEC ID: 0x%08h", cmd.rdata[0]), UVM_LOW)

    // ---------------------------------------------------------------
    `uvm_info("QPI_TEST", "=== QPI Fast Read ===", UVM_LOW)
    // ---------------------------------------------------------------
    cmd = qspi_cmd_sequence::type_id::create("qread");
    cmd.opcode       = SPI_OP_FAST_READ;
    cmd.do_read      = 1;
    cmd.addr_en      = 1;
    cmd.flash_addr   = 22'h0;
    cmd.dummy_cycles = 4;
    cmd.n_rw_bytes   = 4;
    cmd.start(env.apb_agt.sequencer);

    `uvm_info("QPI_TEST", $sformatf("QPI fast read: 0x%08h", cmd.rdata[0]), UVM_LOW)

    // ---------------------------------------------------------------
    `uvm_info("QPI_TEST", "=== Exit QPI Mode ===", UVM_LOW)
    // ---------------------------------------------------------------
    cmd = qspi_cmd_sequence::type_id::create("rstqio");
    cmd.opcode = SPI_OP_RSTQIO;
    cmd.start(env.apb_agt.sequencer);

    // Clear QIO_MODE bit
    apb_write(QSPI_CTRL_ADDR, 32'h0);

    // Verify SPI JEDEC ID still works
    cmd = qspi_cmd_sequence::type_id::create("spi_jedec");
    cmd.opcode     = SPI_OP_JEDEC_ID;
    cmd.do_read    = 1;
    cmd.n_rw_bytes = 3;
    cmd.start(env.apb_agt.sequencer);

    env.scoreboard.check_reg_value("SPI JEDEC after QPI exit", cmd.rdata[0],
      {24'h0, FLASH_MFG_ID}, 32'h000000FF);

    `uvm_info("QPI_TEST", "QPI command test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_QPI_CMD_TEST_SV
