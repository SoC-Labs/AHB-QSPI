///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_rdata_readonly_test.sv
///////////////////////////////////////////////////////////////////////////////
// Verify RDATA registers (REG4-7) are read-only and cannot be corrupted
// by software writes. Also verifies RDATA is zero after reset.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_RDATA_READONLY_TEST_SV
`define GUARD_AHB_QSPI_RDATA_READONLY_TEST_SV

class ahb_qspi_rdata_readonly_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_rdata_readonly_test)

  function new(string name = "ahb_qspi_rdata_readonly_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit [31:0] rdata;
    bit [15:0] rdata_addrs [4] = '{QSPI_RDATA0_ADDR, QSPI_RDATA1_ADDR,
                                    QSPI_RDATA2_ADDR, QSPI_RDATA3_ADDR};

    phase.raise_objection(this);
    wait_for_reset();

    // ---------------------------------------------------------------
    `uvm_info("RDATA_RO", "=== Phase 1: Verify RDATA=0 after reset ===", UVM_LOW)
    // ---------------------------------------------------------------
    for (int i = 0; i < 4; i++) begin
      apb_read(rdata_addrs[i], rdata);
      if (rdata !== 32'h0)
        `uvm_error("RDATA_RO", $sformatf("RDATA%0d should be 0 after reset, got 0x%08h", i, rdata))
      else
        `uvm_info("RDATA_RO", $sformatf("RDATA%0d = 0x%08h (correct)", i, rdata), UVM_LOW)
    end

    // ---------------------------------------------------------------
    `uvm_info("RDATA_RO", "=== Phase 2: Attempt writes to RDATA regs ===", UVM_LOW)
    // ---------------------------------------------------------------
    for (int i = 0; i < 4; i++) begin
      apb_write(rdata_addrs[i], 32'hDEADBEEF);
    end

    // ---------------------------------------------------------------
    `uvm_info("RDATA_RO", "=== Phase 3: Verify RDATA unchanged ===", UVM_LOW)
    // ---------------------------------------------------------------
    for (int i = 0; i < 4; i++) begin
      apb_read(rdata_addrs[i], rdata);
      if (rdata !== 32'h0)
        `uvm_error("RDATA_RO", $sformatf("RDATA%0d is writable! Got 0x%08h after write attempt", i, rdata))
      else
        `uvm_info("RDATA_RO", $sformatf("RDATA%0d still 0x%08h after write attempt (correct)", i, rdata), UVM_LOW)
    end

    // ---------------------------------------------------------------
    `uvm_info("RDATA_RO", "=== Phase 4: Verify RDATA updates after real read ===", UVM_LOW)
    // ---------------------------------------------------------------
    begin
      qspi_init_sequence init_seq;
      qspi_cmd_sequence  cmd;

      init_seq = qspi_init_sequence::type_id::create("init");
      init_seq.start(env.apb_agt.sequencer);

      // JEDEC ID read
      cmd = qspi_cmd_sequence::type_id::create("jedec");
      cmd.opcode     = SPI_OP_JEDEC_ID;
      cmd.do_read    = 1;
      cmd.n_rw_bytes = 4'h2;
      cmd.start(env.apb_agt.sequencer);

      // Now RDATA0 should have JEDEC data
      apb_read(QSPI_RDATA0_ADDR, rdata);
      if (rdata === 32'h0)
        `uvm_error("RDATA_RO", "RDATA0 is still 0 after JEDEC read — not updating from QSPI")
      else
        `uvm_info("RDATA_RO", $sformatf("RDATA0 = 0x%08h after JEDEC read (non-zero, correct)", rdata), UVM_LOW)

      // Try to overwrite again
      apb_write(QSPI_RDATA0_ADDR, 32'hFFFFFFFF);
      apb_read(QSPI_RDATA0_ADDR, rdata);
      if (rdata === 32'hFFFFFFFF)
        `uvm_error("RDATA_RO", "RDATA0 was overwritten — not read-only!")
      else
        `uvm_info("RDATA_RO", $sformatf("RDATA0 = 0x%08h after overwrite attempt (read-only, correct)", rdata), UVM_LOW)
    end

    `uvm_info("RDATA_RO", "RDATA read-only test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_RDATA_READONLY_TEST_SV
