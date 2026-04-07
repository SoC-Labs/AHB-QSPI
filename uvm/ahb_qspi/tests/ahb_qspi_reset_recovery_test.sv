///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_reset_recovery_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests recovery from various controller states by restoring registers
// to defaults and verifying the controller returns to a functional state.
//
// NOTE: Direct hardware reset assertion requires a reset agent or
// module-scope code. This test verifies software-level recovery.
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
    `uvm_info("RST_REC", "=== Phase 1: Configure and operate ===", UVM_LOW)
    // ---------------------------------------------------------------
    init_seq = qspi_init_sequence::type_id::create("init1");
    init_seq.clear_protect = 1;
    init_seq.start(env.apb_agt.sequencer);

    // Do some work: program data
    cmd = qspi_cmd_sequence::type_id::create("wren");
    cmd.opcode = SPI_OP_WREN;
    cmd.start(env.apb_agt.sequencer);

    cmd = qspi_cmd_sequence::type_id::create("pp");
    cmd.opcode     = SPI_OP_PP;
    cmd.do_write   = 1;
    cmd.addr_en    = 1;
    cmd.flash_addr = 22'h0;
    cmd.n_rw_bytes = 4'hF;  // 16 bytes
    cmd.wdata[0]   = 32'hCAFE1234;
    cmd.wdata[1]   = 32'hDEAD5678;
    cmd.wdata[2]   = 32'hBEEF9ABC;
    cmd.wdata[3]   = 32'hF00DDEF0;
    cmd.start(env.apb_agt.sequencer);

    // Wait for flash programming
    begin
      bit flash_busy = 1;
      int timeout = 2000;
      while (flash_busy && timeout > 0) begin
        cmd = qspi_cmd_sequence::type_id::create("poll1");
        cmd.opcode     = SPI_OP_RDSR;
        cmd.do_read    = 1;
        cmd.n_rw_bytes = 4'h0;
        cmd.start(env.apb_agt.sequencer);
        flash_busy = cmd.rdata[0][0];
        timeout--;
      end
    end

    // Modify configuration
    apb_write(QSPI_CLK_DIV_ADDR, 32'h0F);
    apb_write(QSPI_AHB_SETUP_ADDR, 32'h0000_800B);

    // ---------------------------------------------------------------
    `uvm_info("RST_REC", "=== Phase 2: Restore registers to defaults ===", UVM_LOW)
    // ---------------------------------------------------------------
    apb_write(QSPI_CTRL_ADDR, REG0_RESET);
    apb_write(QSPI_SPI_CMD_ADDR, REG2_RESET);
    apb_write(QSPI_ADDR_ADDR, REG3_RESET);
    apb_write(QSPI_CLK_DIV_ADDR, REG13_RESET);
    apb_write(QSPI_AHB_SETUP_ADDR, REG12_RESET);

    // Verify
    apb_read(QSPI_CLK_DIV_ADDR, rdata);
    env.scoreboard.check_reg_value("CLK_DIV restored", rdata, REG13_RESET);

    apb_read(QSPI_AHB_SETUP_ADDR, rdata);
    env.scoreboard.check_reg_value("AHB_SETUP restored", rdata, REG12_RESET);

    // ---------------------------------------------------------------
    `uvm_info("RST_REC", "=== Phase 3: Verify operational post-restore ===", UVM_LOW)
    // ---------------------------------------------------------------
    init_seq = qspi_init_sequence::type_id::create("init2");
    init_seq.start(env.apb_agt.sequencer);

    cmd = qspi_cmd_sequence::type_id::create("jedec_post_rst");
    cmd.opcode     = SPI_OP_JEDEC_ID;
    cmd.do_read    = 1;
    cmd.n_rw_bytes = 4'h2;
    cmd.start(env.apb_agt.sequencer);

    env.scoreboard.check_reg_value("JEDEC post-restore", cmd.rdata[0], FLASH_JEDEC_RDATA0);

    // ---------------------------------------------------------------
    `uvm_info("RST_REC", "=== Phase 4: Multiple restore cycles ===", UVM_LOW)
    // ---------------------------------------------------------------
    for (int cycle = 0; cycle < 3; cycle++) begin
      // Configure non-default value
      apb_write(QSPI_CLK_DIV_ADDR, cycle + 2);

      // Restore
      apb_write(QSPI_CLK_DIV_ADDR, REG13_RESET);
      apb_write(QSPI_CTRL_ADDR, REG0_RESET);

      // Verify CLK_DIV at default
      apb_read(QSPI_CLK_DIV_ADDR, rdata);
      env.scoreboard.check_reg_value($sformatf("CLK_DIV cycle %0d", cycle), rdata, REG13_RESET);

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
