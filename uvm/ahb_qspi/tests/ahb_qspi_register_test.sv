///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_register_test.sv
///////////////////////////////////////////////////////////////////////////////
// Register access tests: reset values, read/write, PID/CID, reserved addrs.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_REGISTER_TEST_SV
`define GUARD_AHB_QSPI_REGISTER_TEST_SV

class ahb_qspi_register_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_register_test)

  function new(string name = "ahb_qspi_register_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit [31:0] rdata;

    phase.raise_objection(this);
    wait_for_reset();

    `uvm_info("REG_TEST", "=== Register Reset Value Tests ===", UVM_LOW)

    // Check reset values
    apb_read(QSPI_CTRL_ADDR, rdata);
    env.scoreboard.check_reg_value("CTRL reset", rdata, REG0_RESET);

    apb_read(QSPI_STATUS_ADDR, rdata);
    env.scoreboard.check_reg_value("STATUS reset", rdata, REG1_RESET, 32'hFFFF_FFFE); // Mask BUSY bit

    apb_read(QSPI_SPI_CMD_ADDR, rdata);
    env.scoreboard.check_reg_value("SPI_CMD reset", rdata, REG2_RESET);

    apb_read(QSPI_ADDR_ADDR, rdata);
    env.scoreboard.check_reg_value("ADDR reset", rdata, REG3_RESET);

    apb_read(QSPI_AHB_SETUP_ADDR, rdata);
    env.scoreboard.check_reg_value("AHB_SETUP reset", rdata, REG12_RESET);

    apb_read(QSPI_CLK_DIV_ADDR, rdata);
    env.scoreboard.check_reg_value("CLK_DIV reset", rdata, REG13_RESET);

    // ---------------------------------------------------------------
    `uvm_info("REG_TEST", "=== PID/CID Tests ===", UVM_LOW)
    // ---------------------------------------------------------------

    apb_read(QSPI_PIDR0_ADDR, rdata);
    env.scoreboard.check_reg_value("PIDR0", rdata, {24'h0, EXP_PIDR0});

    apb_read(QSPI_PIDR1_ADDR, rdata);
    env.scoreboard.check_reg_value("PIDR1", rdata, {24'h0, EXP_PIDR1});

    apb_read(QSPI_PIDR2_ADDR, rdata);
    env.scoreboard.check_reg_value("PIDR2", rdata, {24'h0, EXP_PIDR2});

    apb_read(QSPI_PIDR3_ADDR, rdata);
    env.scoreboard.check_reg_value("PIDR3", rdata, {24'h0, EXP_PIDR3});

    apb_read(QSPI_PIDR4_ADDR, rdata);
    env.scoreboard.check_reg_value("PIDR4", rdata, {24'h0, EXP_PIDR4});

    apb_read(QSPI_CIDR0_ADDR, rdata);
    env.scoreboard.check_reg_value("CIDR0", rdata, {24'h0, EXP_CIDR0});

    apb_read(QSPI_CIDR1_ADDR, rdata);
    env.scoreboard.check_reg_value("CIDR1", rdata, {24'h0, EXP_CIDR1});

    apb_read(QSPI_CIDR2_ADDR, rdata);
    env.scoreboard.check_reg_value("CIDR2", rdata, {24'h0, EXP_CIDR2});

    apb_read(QSPI_CIDR3_ADDR, rdata);
    env.scoreboard.check_reg_value("CIDR3", rdata, {24'h0, EXP_CIDR3});

    // ---------------------------------------------------------------
    `uvm_info("REG_TEST", "=== Register Read/Write Tests ===", UVM_LOW)
    // ---------------------------------------------------------------

    // Write and readback CTRL register
    apb_write(QSPI_CTRL_ADDR, 32'h03A5_0101);
    apb_read(QSPI_CTRL_ADDR, rdata);
    env.scoreboard.check_reg_value("CTRL write", rdata, 32'h03A5_0101);

    // Restore CTRL
    apb_write(QSPI_CTRL_ADDR, 32'h0);

    // Write and readback CLK_DIV
    apb_write(QSPI_CLK_DIV_ADDR, 32'h0000_001F);
    apb_read(QSPI_CLK_DIV_ADDR, rdata);
    env.scoreboard.check_reg_value("CLK_DIV write max", rdata, 32'h0000_001F);

    // Restore CLK_DIV
    apb_write(QSPI_CLK_DIV_ADDR, REG13_RESET);

    // Write and readback ADDR register
    apb_write(QSPI_ADDR_ADDR, 32'h003F_FFFF);
    apb_read(QSPI_ADDR_ADDR, rdata);
    env.scoreboard.check_reg_value("ADDR write max", rdata, 32'h003F_FFFF);

    // Restore ADDR
    apb_write(QSPI_ADDR_ADDR, 32'h0);

    // Walking-1 test on WDATA0
    for (int i = 0; i < 32; i++) begin
      bit [31:0] pattern = (1 << i);
      apb_write(QSPI_WDATA0_ADDR, pattern);
      apb_read(QSPI_WDATA0_ADDR, rdata);
      env.scoreboard.check_reg_value($sformatf("WDATA0 walk1 bit%0d", i), rdata, pattern);
    end

    // Restore WDATA0
    apb_write(QSPI_WDATA0_ADDR, 32'h0);

    // ---------------------------------------------------------------
    `uvm_info("REG_TEST", "=== Reserved Address Test ===", UVM_LOW)
    // ---------------------------------------------------------------

    // Read unmapped address — should return 0xDEADCAFE
    apb_read(16'h0040, rdata);
    env.scoreboard.check_reg_value("Reserved addr 0x0040", rdata, 32'hDEADCAFE);

    apb_read(16'h0100, rdata);
    env.scoreboard.check_reg_value("Reserved addr 0x0100", rdata, 32'hDEADCAFE);

    `uvm_info("REG_TEST", "Register test complete", UVM_LOW)

    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_REGISTER_TEST_SV
