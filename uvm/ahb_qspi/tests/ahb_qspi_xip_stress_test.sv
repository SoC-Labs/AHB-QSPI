///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_xip_stress_test.sv
///////////////////////////////////////////////////////////////////////////////
// XIP stress test: multiple addresses, cache thrashing, XIP/APB interleave
// with data verification.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_XIP_STRESS_TEST_SV
`define GUARD_AHB_QSPI_XIP_STRESS_TEST_SV

class ahb_qspi_xip_stress_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_xip_stress_test)

  function new(string name = "ahb_qspi_xip_stress_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence init_seq;
    qspi_cmd_sequence  cmd;
    bit [31:0] read_data;
    bit [31:0] expected [16];  // 4 pages x 4 words

    phase.raise_objection(this);
    wait_for_reset();

    // ---------------------------------------------------------------
    `uvm_info("XIP_STR", "=== Phase 1: Flash Init & Program ===", UVM_LOW)
    // ---------------------------------------------------------------
    init_seq = qspi_init_sequence::type_id::create("init");
    init_seq.clear_protect = 1;
    init_seq.start(env.apb_agt.sequencer);

    // Program 4 pages at scattered addresses
    for (int pg = 0; pg < 4; pg++) begin
      bit [21:0] addr = pg * 22'h100;

      cmd = qspi_cmd_sequence::type_id::create($sformatf("wren_%0d", pg));
      cmd.opcode = SPI_OP_WREN;
      cmd.start(env.apb_agt.sequencer);

      cmd = qspi_cmd_sequence::type_id::create($sformatf("pp_%0d", pg));
      cmd.opcode     = SPI_OP_PP;
      cmd.do_write   = 1;
      cmd.addr_en    = 1;
      cmd.flash_addr = addr;
      cmd.n_rw_bytes = 15;
      for (int w = 0; w < 4; w++) begin
        cmd.wdata[w]       = (pg << 28) | (w << 16) | (pg * 4 + w);
        expected[pg*4 + w] = cmd.wdata[w];
      end
      cmd.start(env.apb_agt.sequencer);

      // Poll flash BUSY
      begin
        bit flash_busy = 1;
        int timeout = 2000;
        while (flash_busy && timeout > 0) begin
          cmd = qspi_cmd_sequence::type_id::create($sformatf("poll_%0d", pg));
          cmd.opcode     = SPI_OP_RDSR;
          cmd.do_read    = 1;
          cmd.n_rw_bytes = 0;
          cmd.start(env.apb_agt.sequencer);
          flash_busy = cmd.rdata[0][0];
          timeout--;
        end
      end
    end

    // ---------------------------------------------------------------
    `uvm_info("XIP_STR", "=== Phase 2: XIP Multi-address Reads ===", UVM_LOW)
    // ---------------------------------------------------------------
    // Enable XIP
    apb_write(QSPI_AHB_SETUP_ADDR, {16'h0, 4'h8, 4'h0, SPI_OP_FAST_READ});
    apb_write(QSPI_CTRL_ADDR, (1 << CTRL_XIP_ACTIVE_BIT));
    wait_clks(5);

    // Read all 16 words across 4 pages
    for (int pg = 0; pg < 4; pg++) begin
      for (int w = 0; w < 4; w++) begin
        bit [31:0] addr = pg * 32'h100 + w * 4;
        ahb_read(addr, read_data);
        `uvm_info("XIP_STR", $sformatf("AHB [0x%06h] = 0x%08h (exp 0x%08h)",
          addr, read_data, expected[pg*4+w]), UVM_MEDIUM)
        if (read_data !== expected[pg*4+w])
          `uvm_error("XIP_STR", $sformatf("XIP data mismatch at 0x%06h", addr))
      end
    end

    // ---------------------------------------------------------------
    `uvm_info("XIP_STR", "=== Phase 3: Reverse-order Re-read ===", UVM_LOW)
    // ---------------------------------------------------------------
    for (int pg = 3; pg >= 0; pg--) begin
      bit [31:0] addr = pg * 32'h100;
      ahb_read(addr, read_data);
      if (read_data !== expected[pg*4])
        `uvm_error("XIP_STR", $sformatf("Reverse re-read mismatch at 0x%06h", addr))
    end

    // ---------------------------------------------------------------
    `uvm_info("XIP_STR", "=== Phase 4: AHB Write Rejection ===", UVM_LOW)
    // ---------------------------------------------------------------
    ahb_write_txn(32'h0, 32'hDEAD_DEAD);
    if (ahb_vif.drv_cb.hresp === 1'b1)
      `uvm_info("XIP_STR", "AHB write correctly rejected in XIP mode", UVM_LOW)
    else
      `uvm_error("XIP_STR", "AHB write should be rejected in XIP mode")

    // Disable XIP
    apb_write(QSPI_CTRL_ADDR, 32'h0);

    // ---------------------------------------------------------------
    `uvm_info("XIP_STR", "=== Phase 5: Verify APB works after XIP disable ===", UVM_LOW)
    // ---------------------------------------------------------------
    begin
      bit [31:0] rdata;
      cmd = qspi_cmd_sequence::type_id::create("jedec_post_xip");
      cmd.opcode     = SPI_OP_JEDEC_ID;
      cmd.do_read    = 1;
      cmd.n_rw_bytes = 4'h2;
      cmd.start(env.apb_agt.sequencer);

      env.scoreboard.check_reg_value("JEDEC post-XIP", cmd.rdata[0], FLASH_JEDEC_RDATA0);
    end

    `uvm_info("XIP_STR", "XIP stress test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_XIP_STRESS_TEST_SV
