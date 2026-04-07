///////////////////////////////////////////////////////////////////////////////
// qspi_data_integrity_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Sequences for verifying data integrity: pattern programming, multi-word
// read/write, and cross-mode consistency (SPI vs QPI).
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_QSPI_DATA_INTEGRITY_SEQUENCE_SV
`define GUARD_QSPI_DATA_INTEGRITY_SEQUENCE_SV

// ---------------------------------------------------------------------------
// Program and verify a page of data at a given address
// ---------------------------------------------------------------------------
class page_program_verify_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(page_program_verify_sequence)

  bit [21:0] flash_addr;
  bit [31:0] wdata [4];
  int        n_words;       // 1-4
  bit        use_qpi;       // 1 = QPI mode active, 0 = SPI mode

  function new(string name = "page_program_verify_sequence");
    super.new(name);
    flash_addr = 0;
    n_words    = 4;
    use_qpi    = 0;
    foreach (wdata[i]) wdata[i] = 0;
  endfunction

  virtual task body();
    qspi_cmd_sequence cmd;
    int n_rw = n_words * 4 - 1;  // N_RW_BYTES encoding

    // WREN
    cmd = qspi_cmd_sequence::type_id::create("wren");
    cmd.opcode = SPI_OP_WREN;
    cmd.start(m_sequencer);

    // Page Program
    cmd = qspi_cmd_sequence::type_id::create("pp");
    cmd.opcode     = SPI_OP_PP;
    cmd.do_write   = 1;
    cmd.addr_en    = 1;
    cmd.flash_addr = flash_addr;
    cmd.n_rw_bytes = n_rw;
    for (int i = 0; i < 4; i++)
      cmd.wdata[i] = wdata[i];
    cmd.start(m_sequencer);

    // Poll flash BUSY (RDSR bit 0)
    begin
      bit flash_busy = 1;
      int timeout = 2000;
      while (flash_busy && timeout > 0) begin
        cmd = qspi_cmd_sequence::type_id::create("poll_sr");
        cmd.opcode     = SPI_OP_RDSR;
        cmd.do_read    = 1;
        cmd.n_rw_bytes = 0;
        cmd.start(m_sequencer);
        flash_busy = cmd.rdata[0][0];
        timeout--;
      end
      if (timeout == 0)
        `uvm_error("PP_VERIFY", "Timeout waiting for flash program completion")
    end

    // Read back
    cmd = qspi_cmd_sequence::type_id::create("read_verify");
    cmd.opcode       = SPI_OP_FAST_READ;
    cmd.do_read      = 1;
    cmd.addr_en      = 1;
    cmd.flash_addr   = flash_addr;
    cmd.dummy_cycles = use_qpi ? 6 : 8;
    cmd.n_rw_bytes   = n_rw;
    cmd.start(m_sequencer);

    // Verify
    for (int i = 0; i < n_words; i++) begin
      if (cmd.rdata[i] !== wdata[i])
        `uvm_error("PP_VERIFY", $sformatf("Data mismatch at addr 0x%06h word %0d: got 0x%08h, expected 0x%08h",
          flash_addr, i, cmd.rdata[i], wdata[i]))
      else
        `uvm_info("PP_VERIFY", $sformatf("Word %0d OK: 0x%08h", i, cmd.rdata[i]), UVM_MEDIUM)
    end

    // WRDI
    cmd = qspi_cmd_sequence::type_id::create("wrdi");
    cmd.opcode = SPI_OP_WRDI;
    cmd.start(m_sequencer);
  endtask

endclass

// ---------------------------------------------------------------------------
// Data pattern sweep: program and verify various bit patterns
// ---------------------------------------------------------------------------
class data_pattern_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(data_pattern_sequence)

  bit use_qpi;

  function new(string name = "data_pattern_sequence");
    super.new(name);
    use_qpi = 0;
  endfunction

  virtual task body();
    page_program_verify_sequence pp;

    // Pattern 1: All zeros
    pp = page_program_verify_sequence::type_id::create("pp_zeros");
    pp.flash_addr = 22'h010000;
    pp.n_words    = 4;
    pp.use_qpi    = use_qpi;
    pp.wdata      = '{32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000};
    pp.start(m_sequencer);

    // Pattern 2: All ones
    pp = page_program_verify_sequence::type_id::create("pp_ones");
    pp.flash_addr = 22'h010100;
    pp.n_words    = 4;
    pp.use_qpi    = use_qpi;
    pp.wdata      = '{32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF};
    pp.start(m_sequencer);

    // Pattern 3: Alternating 0xAA
    pp = page_program_verify_sequence::type_id::create("pp_aa");
    pp.flash_addr = 22'h010200;
    pp.n_words    = 4;
    pp.use_qpi    = use_qpi;
    pp.wdata      = '{32'hAAAAAAAA, 32'hAAAAAAAA, 32'hAAAAAAAA, 32'hAAAAAAAA};
    pp.start(m_sequencer);

    // Pattern 4: Alternating 0x55
    pp = page_program_verify_sequence::type_id::create("pp_55");
    pp.flash_addr = 22'h010300;
    pp.n_words    = 4;
    pp.use_qpi    = use_qpi;
    pp.wdata      = '{32'h55555555, 32'h55555555, 32'h55555555, 32'h55555555};
    pp.start(m_sequencer);

    // Pattern 5: Walking 1
    pp = page_program_verify_sequence::type_id::create("pp_walk1");
    pp.flash_addr = 22'h010400;
    pp.n_words    = 4;
    pp.use_qpi    = use_qpi;
    pp.wdata      = '{32'h00000001, 32'h00000002, 32'h00000004, 32'h00000008};
    pp.start(m_sequencer);

    // Pattern 6: Walking 0
    pp = page_program_verify_sequence::type_id::create("pp_walk0");
    pp.flash_addr = 22'h010500;
    pp.n_words    = 4;
    pp.use_qpi    = use_qpi;
    pp.wdata      = '{32'hFFFFFFFE, 32'hFFFFFFFD, 32'hFFFFFFFB, 32'hFFFFFFF7};
    pp.start(m_sequencer);

    // Pattern 7: Byte ramp
    pp = page_program_verify_sequence::type_id::create("pp_ramp");
    pp.flash_addr = 22'h010600;
    pp.n_words    = 4;
    pp.use_qpi    = use_qpi;
    pp.wdata      = '{32'h00010203, 32'h04050607, 32'h08090A0B, 32'h0C0D0E0F};
    pp.start(m_sequencer);

    // Pattern 8: Nibble-swap
    pp = page_program_verify_sequence::type_id::create("pp_nibble");
    pp.flash_addr = 22'h010700;
    pp.n_words    = 4;
    pp.use_qpi    = use_qpi;
    pp.wdata      = '{32'hF0F0F0F0, 32'h0F0F0F0F, 32'hF0F0F0F0, 32'h0F0F0F0F};
    pp.start(m_sequencer);

    `uvm_info("DATA_PAT", "All 8 data patterns verified", UVM_LOW)
  endtask

endclass

// ---------------------------------------------------------------------------
// Multi-word program sweep: test 1, 2, 3, 4 word programs independently
// ---------------------------------------------------------------------------
class multiword_program_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(multiword_program_sequence)

  bit use_qpi;

  function new(string name = "multiword_program_sequence");
    super.new(name);
    use_qpi = 0;
  endfunction

  virtual task body();
    page_program_verify_sequence pp;

    for (int nw = 1; nw <= 4; nw++) begin
      pp = page_program_verify_sequence::type_id::create($sformatf("pp_%0dw", nw));
      pp.flash_addr = 22'h020000 + nw * 22'h100;
      pp.n_words    = nw;
      pp.use_qpi    = use_qpi;
      for (int i = 0; i < 4; i++)
        pp.wdata[i] = (nw << 28) | (i + 1);
      pp.start(m_sequencer);
    end

    `uvm_info("MULTIWORD", "All program sizes (1-4 words) verified", UVM_LOW)
  endtask

endclass

// ---------------------------------------------------------------------------
// Cross-mode consistency: program in one mode, read in both, compare
// ---------------------------------------------------------------------------
class cross_mode_verify_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(cross_mode_verify_sequence)

  function new(string name = "cross_mode_verify_sequence");
    super.new(name);
  endfunction

  virtual task body();
    qspi_cmd_sequence cmd;
    apb_write_sequence wr;
    bit [31:0] rdata_spi [4];
    bit [31:0] rdata_qpi [4];
    bit [31:0] expected [4] = '{32'hCAFEBABE, 32'hDEADF00D, 32'hBAADF00D, 32'h0BADC0DE};
    bit [21:0] addr = 22'h030000;

    // Program in SPI mode (assuming SPI mode is currently active)
    // WREN
    cmd = qspi_cmd_sequence::type_id::create("wren");
    cmd.opcode = SPI_OP_WREN;
    cmd.start(m_sequencer);

    // PP
    cmd = qspi_cmd_sequence::type_id::create("pp");
    cmd.opcode     = SPI_OP_PP;
    cmd.do_write   = 1;
    cmd.addr_en    = 1;
    cmd.flash_addr = addr;
    cmd.n_rw_bytes = 15;
    cmd.wdata      = expected;
    cmd.start(m_sequencer);

    // Poll flash BUSY
    begin
      bit flash_busy = 1;
      int timeout = 2000;
      while (flash_busy && timeout > 0) begin
        cmd = qspi_cmd_sequence::type_id::create("poll");
        cmd.opcode     = SPI_OP_RDSR;
        cmd.do_read    = 1;
        cmd.n_rw_bytes = 0;
        cmd.start(m_sequencer);
        flash_busy = cmd.rdata[0][0];
        timeout--;
      end
    end

    // WRDI
    cmd = qspi_cmd_sequence::type_id::create("wrdi");
    cmd.opcode = SPI_OP_WRDI;
    cmd.start(m_sequencer);

    // Read in SPI mode
    cmd = qspi_cmd_sequence::type_id::create("spi_read");
    cmd.opcode       = SPI_OP_FAST_READ;
    cmd.do_read      = 1;
    cmd.addr_en      = 1;
    cmd.flash_addr   = addr;
    cmd.dummy_cycles = 8;
    cmd.n_rw_bytes   = 15;
    cmd.start(m_sequencer);
    rdata_spi = cmd.rdata;

    // Enter QPI mode
    cmd = qspi_cmd_sequence::type_id::create("eqio");
    cmd.opcode = SPI_OP_EQIO;
    cmd.start(m_sequencer);

    wr = apb_write_sequence::type_id::create("set_qpi");
    wr.addr  = QSPI_CTRL_ADDR;
    wr.wdata = (1 << CTRL_QIO_MODE_BIT);
    wr.start(m_sequencer);

    // Read in QPI mode
    cmd = qspi_cmd_sequence::type_id::create("qpi_read");
    cmd.opcode       = SPI_OP_FAST_READ;
    cmd.do_read      = 1;
    cmd.addr_en      = 1;
    cmd.flash_addr   = addr;
    cmd.dummy_cycles = 6;
    cmd.n_rw_bytes   = 15;
    cmd.start(m_sequencer);
    rdata_qpi = cmd.rdata;

    // Exit QPI
    cmd = qspi_cmd_sequence::type_id::create("rstqio");
    cmd.opcode = SPI_OP_RSTQIO;
    cmd.start(m_sequencer);

    wr = apb_write_sequence::type_id::create("clr_qpi");
    wr.addr  = QSPI_CTRL_ADDR;
    wr.wdata = 0;
    wr.start(m_sequencer);

    // Compare
    for (int i = 0; i < 4; i++) begin
      if (rdata_spi[i] !== expected[i])
        `uvm_error("XMODE", $sformatf("SPI read word %0d mismatch: 0x%08h vs 0x%08h", i, rdata_spi[i], expected[i]))
      if (rdata_qpi[i] !== expected[i])
        `uvm_error("XMODE", $sformatf("QPI read word %0d mismatch: 0x%08h vs 0x%08h", i, rdata_qpi[i], expected[i]))
      if (rdata_spi[i] !== rdata_qpi[i])
        `uvm_error("XMODE", $sformatf("SPI vs QPI word %0d mismatch: 0x%08h vs 0x%08h", i, rdata_spi[i], rdata_qpi[i]))
    end

    `uvm_info("XMODE", "Cross-mode data consistency verified", UVM_LOW)
  endtask

endclass

`endif // GUARD_QSPI_DATA_INTEGRITY_SEQUENCE_SV
