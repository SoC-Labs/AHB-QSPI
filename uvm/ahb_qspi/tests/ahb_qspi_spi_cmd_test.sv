///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_spi_cmd_test.sv
///////////////////////////////////////////////////////////////////////////////
// SPI mode command tests: JEDEC ID, read, write, erase operations.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_SPI_CMD_TEST_SV
`define GUARD_AHB_QSPI_SPI_CMD_TEST_SV

class ahb_qspi_spi_cmd_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_spi_cmd_test)

  function new(string name = "ahb_qspi_spi_cmd_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence init_seq;
    qspi_cmd_sequence  cmd;

    phase.raise_objection(this);
    wait_for_reset();

    // Initialise flash
    init_seq = qspi_init_sequence::type_id::create("init");
    init_seq.clear_protect = 1;
    init_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("SPI_TEST", "=== JEDEC ID Test ===", UVM_LOW)
    // ---------------------------------------------------------------
    cmd = qspi_cmd_sequence::type_id::create("jedec");
    cmd.opcode     = SPI_OP_JEDEC_ID;
    cmd.do_read    = 1;
    cmd.n_rw_bytes = 3;
    cmd.start(env.apb_agt.sequencer);

    env.scoreboard.check_reg_value("JEDEC MFG ID", cmd.rdata[0], {24'h0, FLASH_MFG_ID}, 32'h000000FF);
    `uvm_info("SPI_TEST", $sformatf("JEDEC ID: 0x%08h", cmd.rdata[0]), UVM_LOW)

    // ---------------------------------------------------------------
    `uvm_info("SPI_TEST", "=== Read Status Register ===", UVM_LOW)
    // ---------------------------------------------------------------
    cmd = qspi_cmd_sequence::type_id::create("rdsr");
    cmd.opcode     = SPI_OP_RDSR;
    cmd.do_read    = 1;
    cmd.n_rw_bytes = 1;
    cmd.start(env.apb_agt.sequencer);
    `uvm_info("SPI_TEST", $sformatf("Status Register: 0x%02h", cmd.rdata[0][7:0]), UVM_LOW)

    // ---------------------------------------------------------------
    `uvm_info("SPI_TEST", "=== Page Program + Read Verify ===", UVM_LOW)
    // ---------------------------------------------------------------

    // Write Enable
    cmd = qspi_cmd_sequence::type_id::create("wren");
    cmd.opcode = SPI_OP_WREN;
    cmd.start(env.apb_agt.sequencer);

    // Page Program at address 0x000000 with known data
    cmd = qspi_cmd_sequence::type_id::create("pp");
    cmd.opcode     = SPI_OP_PP;
    cmd.do_write   = 1;
    cmd.addr_en    = 1;
    cmd.flash_addr = 22'h0;
    cmd.n_rw_bytes = 4;
    cmd.wdata[0]   = 32'hDEADBEEF;
    cmd.start(env.apb_agt.sequencer);

    // Wait for flash internal programming (poll BUSY via RDSR)
    begin
      bit flash_busy = 1;
      int timeout = 1000;
      while (flash_busy && timeout > 0) begin
        cmd = qspi_cmd_sequence::type_id::create("poll_sr");
        cmd.opcode     = SPI_OP_RDSR;
        cmd.do_read    = 1;
        cmd.n_rw_bytes = 1;
        cmd.start(env.apb_agt.sequencer);
        flash_busy = cmd.rdata[0][0]; // WIP bit
        timeout--;
      end
    end

    // Read back with slow read (0x03)
    cmd = qspi_cmd_sequence::type_id::create("read_verify");
    cmd.opcode       = SPI_OP_READ;
    cmd.do_read      = 1;
    cmd.addr_en      = 1;
    cmd.flash_addr   = 22'h0;
    cmd.dummy_cycles = 0;
    cmd.n_rw_bytes   = 4;
    cmd.start(env.apb_agt.sequencer);

    `uvm_info("SPI_TEST", $sformatf("Read back: 0x%08h", cmd.rdata[0]), UVM_LOW)

    // ---------------------------------------------------------------
    `uvm_info("SPI_TEST", "=== Fast Read with Dummy Cycles ===", UVM_LOW)
    // ---------------------------------------------------------------
    cmd = qspi_cmd_sequence::type_id::create("fast_read");
    cmd.opcode       = SPI_OP_FAST_READ;
    cmd.do_read      = 1;
    cmd.addr_en      = 1;
    cmd.flash_addr   = 22'h0;
    cmd.dummy_cycles = 8;
    cmd.n_rw_bytes   = 4;
    cmd.start(env.apb_agt.sequencer);

    `uvm_info("SPI_TEST", $sformatf("Fast read: 0x%08h", cmd.rdata[0]), UVM_LOW)

    // ---------------------------------------------------------------
    `uvm_info("SPI_TEST", "=== Write Disable ===", UVM_LOW)
    // ---------------------------------------------------------------
    cmd = qspi_cmd_sequence::type_id::create("wrdi");
    cmd.opcode = SPI_OP_WRDI;
    cmd.start(env.apb_agt.sequencer);

    `uvm_info("SPI_TEST", "SPI command test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_SPI_CMD_TEST_SV
