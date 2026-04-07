///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_reset_recovery_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests reset recovery from various controller states:
// - Reset after configuration changes
// - Reset after successful operations
// - Verify post-reset register defaults and operational readiness
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_RESET_RECOVERY_TEST_SV
`define GUARD_AHB_QSPI_RESET_RECOVERY_TEST_SV

class ahb_qspi_reset_recovery_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_reset_recovery_test)

  function new(string name = "ahb_qspi_reset_recovery_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence init_seq;
    qspi_cmd_sequence  cmd;
    bit [31:0] rdata;

    phase.raise_objection(this);
    wait_for_reset();

    // ---------------------------------------------------------------
    `uvm_info("RST_REC", "=== Phase 1: Configure and operate, then verify ===", UVM_LOW)
    // ---------------------------------------------------------------
    init_seq = qspi_init_sequence::type_id::create("init1");
    init_seq.clear_protect = 1;
    init_seq.enter_qpi     = 1;
    init_seq.start(env.apb_agt.sequencer);

    // Do some work: program and read
    cmd = qspi_cmd_sequence::type_id::create("wren");
    cmd.opcode = SPI_OP_WREN;
    cmd.start(env.apb_agt.sequencer);

    cmd = qspi_cmd_sequence::type_id::create("pp");
    cmd.opcode     = SPI_OP_PP;
    cmd.do_write   = 1;
    cmd.addr_en    = 1;
    cmd.flash_addr = 22'h0;
    cmd.n_rw_bytes = 15;
    cmd.wdata[0]   = 32'hCAFE1234;
    cmd.wdata[1]   = 32'hDEAD5678;
    cmd.wdata[2]   = 32'hBEEF9ABC;
    cmd.wdata[3]   = 32'hF00DDEF0;
    cmd.start(env.apb_agt.sequencer);

    // Wait for flash
    begin
      bit flash_busy = 1;
      int timeout = 2000;
      while (flash_busy && timeout > 0) begin
        cmd = qspi_cmd_sequence::type_id::create("poll1");
        cmd.opcode     = SPI_OP_RDSR;
        cmd.do_read    = 1;
        cmd.n_rw_bytes = 0;
        cmd.start(env.apb_agt.sequencer);
        flash_busy = cmd.rdata[0][0];
        timeout--;
      end
    end

    // Modify configuration: change CLK_DIV, enable XIP, etc.
    apb_write(QSPI_CLK_DIV_ADDR, 32'h0F);
    apb_write(QSPI_AHB_SETUP_ADDR, 32'h0000_800B);
    apb_write(QSPI_CTRL_ADDR, (1 << CTRL_XIP_ACTIVE_BIT) | (1 << CTRL_QIO_MODE_BIT));

    // ---------------------------------------------------------------
    `uvm_info("RST_REC", "=== Phase 2: Assert reset ===", UVM_LOW)
    // ---------------------------------------------------------------
    // Drive reset
    vif.rst_n = 0;
    repeat (20) @(posedge vif.clk);
    vif.rst_n = 1;
    repeat (10) @(posedge vif.clk);

    // ---------------------------------------------------------------
    `uvm_info("RST_REC", "=== Phase 3: Verify all registers at defaults ===", UVM_LOW)
    // ---------------------------------------------------------------
    apb_read(QSPI_CTRL_ADDR, rdata);
    if (rdata !== REG0_RESET)
      `uvm_error("RST_REC", $sformatf("CTRL not at reset: 0x%08h", rdata))

    apb_read(QSPI_STATUS_ADDR, rdata);
    if (rdata[STATUS_BUSY_BIT])
      `uvm_error("RST_REC", "BUSY should be 0 after reset")

    apb_read(QSPI_SPI_CMD_ADDR, rdata);
    if (rdata !== REG2_RESET)
      `uvm_error("RST_REC", $sformatf("SPI_CMD not at reset: 0x%08h", rdata))

    apb_read(QSPI_CLK_DIV_ADDR, rdata);
    if (rdata !== REG13_RESET)
      `uvm_error("RST_REC", $sformatf("CLK_DIV not at reset (0x%08h vs 0x%08h)", rdata, REG13_RESET))

    apb_read(QSPI_AHB_SETUP_ADDR, rdata);
    if (rdata !== REG12_RESET)
      `uvm_error("RST_REC", $sformatf("AHB_SETUP not at reset: 0x%08h", rdata))

    `uvm_info("RST_REC", "All registers at expected reset values", UVM_LOW)

    // ---------------------------------------------------------------
    `uvm_info("RST_REC", "=== Phase 4: Verify operational post-reset ===", UVM_LOW)
    // ---------------------------------------------------------------
    init_seq = qspi_init_sequence::type_id::create("init2");
    init_seq.start(env.apb_agt.sequencer);

    cmd = qspi_cmd_sequence::type_id::create("jedec_post_rst");
    cmd.opcode     = SPI_OP_JEDEC_ID;
    cmd.do_read    = 1;
    cmd.n_rw_bytes = 4'h2;
    cmd.start(env.apb_agt.sequencer);

    env.scoreboard.check_reg_value("JEDEC post-reset", cmd.rdata[0], FLASH_JEDEC_RDATA0);

    // ---------------------------------------------------------------
    `uvm_info("RST_REC", "=== Phase 5: Multiple reset cycles ===", UVM_LOW)
    // ---------------------------------------------------------------
    for (int cycle = 0; cycle < 3; cycle++) begin
      // Configure something
      apb_write(QSPI_CLK_DIV_ADDR, cycle + 2);

      // Reset
      vif.rst_n = 0;
      repeat (10) @(posedge vif.clk);
      vif.rst_n = 1;
      repeat (10) @(posedge vif.clk);

      // Verify CLK_DIV at default
      apb_read(QSPI_CLK_DIV_ADDR, rdata);
      if (rdata !== REG13_RESET)
        `uvm_error("RST_REC", $sformatf("Cycle %0d: CLK_DIV not reset (0x%08h)", cycle, rdata))

      // Verify operational
      init_seq = qspi_init_sequence::type_id::create($sformatf("init_c%0d", cycle));
      init_seq.start(env.apb_agt.sequencer);

      cmd = qspi_cmd_sequence::type_id::create($sformatf("jedec_c%0d", cycle));
      cmd.opcode     = SPI_OP_JEDEC_ID;
      cmd.do_read    = 1;
      cmd.n_rw_bytes = 4'h2;
      cmd.start(env.apb_agt.sequencer);

      env.scoreboard.check_reg_value($sformatf("JEDEC cycle %0d", cycle), cmd.rdata[0], FLASH_JEDEC_RDATA0);
    end

    `uvm_info("RST_REC", "Reset recovery test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_RESET_RECOVERY_TEST_SV
