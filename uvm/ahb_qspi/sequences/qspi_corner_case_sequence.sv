///////////////////////////////////////////////////////////////////////////////
// qspi_corner_case_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Sequences targeting corner cases and boundary conditions.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_QSPI_CORNER_CASE_SEQUENCE_SV
`define GUARD_QSPI_CORNER_CASE_SEQUENCE_SV

// ---------------------------------------------------------------------------
// N_RW_BYTES sweep: exercise all 16 data-size values (0-15 → 1-16 bytes)
// ---------------------------------------------------------------------------
class n_rw_bytes_sweep_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(n_rw_bytes_sweep_sequence)

  function new(string name = "n_rw_bytes_sweep_sequence");
    super.new(name);
  endfunction

  virtual task body();
    qspi_cmd_sequence cmd;

    `uvm_info("NRW_SWEEP", "Sweeping N_RW_BYTES 0-15 with fast reads", UVM_LOW)

    for (int n = 0; n < 16; n++) begin
      cmd = qspi_cmd_sequence::type_id::create($sformatf("cmd_n%0d", n));
      cmd.opcode       = SPI_OP_FAST_READ;
      cmd.do_read      = 1;
      cmd.addr_en      = 1;
      cmd.flash_addr   = 22'h0;
      cmd.dummy_cycles = 8;
      cmd.n_rw_bytes   = n;
      cmd.start(m_sequencer);
      `uvm_info("NRW_SWEEP", $sformatf("N_RW=%0d (%0d bytes): rdata[0]=0x%08h", n, n+1, cmd.rdata[0]), UVM_MEDIUM)
    end
  endtask

endclass

// ---------------------------------------------------------------------------
// Simultaneous R+W bits: set both READ and WRITE, verify no hang
// ---------------------------------------------------------------------------
class simultaneous_rw_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(simultaneous_rw_sequence)

  function new(string name = "simultaneous_rw_sequence");
    super.new(name);
  endfunction

  virtual task body();
    apb_write_sequence wr;
    apb_read_sequence  rd;
    bit [31:0] cmd_val;

    `uvm_info("SIM_RW", "Setting both READ and WRITE bits simultaneously", UVM_LOW)

    // Set address
    wr = apb_write_sequence::type_id::create("wr_addr");
    wr.addr  = QSPI_ADDR_ADDR;
    wr.wdata = 32'h0;
    wr.start(m_sequencer);

    // Build command with both READ and WRITE
    cmd_val = SPI_OP_READ;              // [7:0]  opcode
    cmd_val |= (1 << SPI_CMD_READ_BIT);  // [9]    read=1
    cmd_val |= (1 << SPI_CMD_WRITE_BIT); // [10]   write=1
    cmd_val |= (1 << SPI_CMD_ADDR_EN_BIT); // [11] addr_en=1
    cmd_val |= (3 << SPI_CMD_N_RW_LSB);  // [19:16] n_rw=3

    // Setup phase
    wr = apb_write_sequence::type_id::create("wr_cmd_setup");
    wr.addr  = QSPI_SPI_CMD_ADDR;
    wr.wdata = cmd_val;
    wr.start(m_sequencer);

    // Trigger
    wr = apb_write_sequence::type_id::create("wr_cmd_trig");
    wr.addr  = QSPI_SPI_CMD_ADDR;
    wr.wdata = cmd_val | (1 << SPI_CMD_ENABLE_BIT);
    wr.start(m_sequencer);

    // Poll for completion (should not hang)
    begin
      bit busy = 1;
      int timeout = 50000;
      while (busy && timeout > 0) begin
        rd = apb_read_sequence::type_id::create("rd_status");
        rd.addr = QSPI_STATUS_ADDR;
        rd.start(m_sequencer);
        busy = rd.rdata[STATUS_BUSY_BIT];
        timeout--;
      end
      if (timeout == 0)
        `uvm_error("SIM_RW", "Controller hung with both R+W bits set")
      else
        `uvm_info("SIM_RW", "Controller completed without hang", UVM_LOW)
    end

    // Clear IRQ
    wr = apb_write_sequence::type_id::create("wr_irq_clr");
    wr.addr  = QSPI_STATUS_ADDR;
    wr.wdata = (1 << STATUS_IRQ_CLR_BIT);
    wr.start(m_sequencer);
  endtask

endclass

// ---------------------------------------------------------------------------
// Back-to-back commands: issue many reads without extra delay
// ---------------------------------------------------------------------------
class back_to_back_cmd_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(back_to_back_cmd_sequence)

  rand int num_commands;
  constraint c_count { num_commands inside {[20:100]}; }

  function new(string name = "back_to_back_cmd_sequence");
    super.new(name);
  endfunction

  virtual task body();
    qspi_cmd_sequence cmd;

    `uvm_info("B2B", $sformatf("Issuing %0d back-to-back JEDEC ID reads", num_commands), UVM_LOW)

    for (int i = 0; i < num_commands; i++) begin
      cmd = qspi_cmd_sequence::type_id::create($sformatf("jedec_%0d", i));
      cmd.opcode     = SPI_OP_JEDEC_ID;
      cmd.do_read    = 1;
      cmd.n_rw_bytes = 4'h2;
      cmd.start(m_sequencer);

      if (cmd.rdata[0] != FLASH_JEDEC_RDATA0)
        `uvm_error("B2B", $sformatf("JEDEC ID mismatch on iteration %0d: 0x%08h", i, cmd.rdata[0]))
    end

    `uvm_info("B2B", $sformatf("All %0d back-to-back reads passed", num_commands), UVM_LOW)
  endtask

endclass

// ---------------------------------------------------------------------------
// Address boundary: test reads at address 0 and near max (22-bit)
// ---------------------------------------------------------------------------
class addr_boundary_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(addr_boundary_sequence)

  function new(string name = "addr_boundary_sequence");
    super.new(name);
  endfunction

  virtual task body();
    qspi_cmd_sequence cmd;

    `uvm_info("ADDR_BND", "Testing address boundaries: 0x000000 and 0x3FFF00", UVM_LOW)

    // Read from address 0
    cmd = qspi_cmd_sequence::type_id::create("read_zero");
    cmd.opcode       = SPI_OP_FAST_READ;
    cmd.do_read      = 1;
    cmd.addr_en      = 1;
    cmd.flash_addr   = 22'h000000;
    cmd.dummy_cycles = 8;
    cmd.n_rw_bytes   = 3;
    cmd.start(m_sequencer);
    `uvm_info("ADDR_BND", $sformatf("Addr 0x000000: 0x%08h", cmd.rdata[0]), UVM_LOW)

    // Read from near-max address
    cmd = qspi_cmd_sequence::type_id::create("read_max");
    cmd.opcode       = SPI_OP_FAST_READ;
    cmd.do_read      = 1;
    cmd.addr_en      = 1;
    cmd.flash_addr   = 22'h3FFF00;
    cmd.dummy_cycles = 8;
    cmd.n_rw_bytes   = 3;
    cmd.start(m_sequencer);
    `uvm_info("ADDR_BND", $sformatf("Addr 0x3FFF00: 0x%08h", cmd.rdata[0]), UVM_LOW)

    `uvm_info("ADDR_BND", "Address boundary reads completed without error", UVM_LOW)
  endtask

endclass

// ---------------------------------------------------------------------------
// Continuous read mode: enable cont_read + NO_CMD, verify NO_FETCH path
// ---------------------------------------------------------------------------
class continuous_read_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(continuous_read_sequence)

  function new(string name = "continuous_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    qspi_cmd_sequence cmd;
    apb_write_sequence wr;
    apb_read_sequence  rd;

    `uvm_info("CONT_RD", "Testing continuous read with NO_CMD", UVM_LOW)

    // First, enter QPI mode
    cmd = qspi_cmd_sequence::type_id::create("eqio");
    cmd.opcode = SPI_OP_EQIO;
    cmd.start(m_sequencer);

    // Set QIO_MODE + CONT_READ + MODE_CODE=0xA0
    wr = apb_write_sequence::type_id::create("wr_ctrl_cont");
    wr.addr  = QSPI_CTRL_ADDR;
    wr.wdata = (1 << CTRL_QIO_MODE_BIT) | (1 << CTRL_CONT_READ_BIT) | (32'hA0 << CTRL_MODE_CODE_LSB);
    wr.start(m_sequencer);

    // Normal read to establish last_QSPI_ADDR
    cmd = qspi_cmd_sequence::type_id::create("initial_read");
    cmd.opcode       = SPI_OP_FAST_READ;
    cmd.do_read      = 1;
    cmd.addr_en      = 1;
    cmd.flash_addr   = 22'h0;
    cmd.dummy_cycles = 4;
    cmd.n_rw_bytes   = 15;
    cmd.start(m_sequencer);

    // Enable NO_CMD
    rd = apb_read_sequence::type_id::create("rd_ctrl");
    rd.addr = QSPI_CTRL_ADDR;
    rd.start(m_sequencer);

    wr = apb_write_sequence::type_id::create("wr_no_cmd");
    wr.addr  = QSPI_CTRL_ADDR;
    wr.wdata = rd.rdata | (1 << CTRL_NO_CMD_BIT);
    wr.start(m_sequencer);

    // Read same address (should hit NO_FETCH path)
    cmd = qspi_cmd_sequence::type_id::create("no_fetch_read");
    cmd.opcode       = SPI_OP_FAST_READ;
    cmd.do_read      = 1;
    cmd.addr_en      = 1;
    cmd.flash_addr   = 22'h0;
    cmd.dummy_cycles = 4;
    cmd.n_rw_bytes   = 15;
    cmd.start(m_sequencer);
    `uvm_info("CONT_RD", $sformatf("NO_FETCH read: 0x%08h", cmd.rdata[0]), UVM_LOW)

    // Read different address (should use ADDR path)
    cmd = qspi_cmd_sequence::type_id::create("addr_path_read");
    cmd.opcode       = SPI_OP_FAST_READ;
    cmd.do_read      = 1;
    cmd.addr_en      = 1;
    cmd.flash_addr   = 22'h100;
    cmd.dummy_cycles = 4;
    cmd.n_rw_bytes   = 15;
    cmd.start(m_sequencer);
    `uvm_info("CONT_RD", $sformatf("ADDR path read: 0x%08h", cmd.rdata[0]), UVM_LOW)

    // Disable NO_CMD and continuous read, exit QPI
    wr = apb_write_sequence::type_id::create("wr_ctrl_clear");
    wr.addr  = QSPI_CTRL_ADDR;
    wr.wdata = (1 << CTRL_QIO_MODE_BIT);  // keep QPI on for rstqio
    wr.start(m_sequencer);

    cmd = qspi_cmd_sequence::type_id::create("rstqio");
    cmd.opcode = SPI_OP_RSTQIO;
    cmd.start(m_sequencer);

    wr = apb_write_sequence::type_id::create("wr_ctrl_off");
    wr.addr  = QSPI_CTRL_ADDR;
    wr.wdata = 0;
    wr.start(m_sequencer);

    `uvm_info("CONT_RD", "Continuous read and NO_CMD path verified", UVM_LOW)
  endtask

endclass

`endif // GUARD_QSPI_CORNER_CASE_SEQUENCE_SV
