///////////////////////////////////////////////////////////////////////////////
// qspi_stress_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Randomised stress sequences for hammering the QSPI controller.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_QSPI_STRESS_SEQUENCE_SV
`define GUARD_QSPI_STRESS_SEQUENCE_SV

// ---------------------------------------------------------------------------
// Random register storm: write random values to random RW registers
// ---------------------------------------------------------------------------
class reg_storm_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(reg_storm_sequence)

  rand int num_transactions;

  constraint c_count { num_transactions inside {[50:500]}; }

  function new(string name = "reg_storm_sequence");
    super.new(name);
  endfunction

  virtual task body();
    bit [15:0] rw_addrs[] = '{
      QSPI_CTRL_ADDR, QSPI_SPI_CMD_ADDR, QSPI_ADDR_ADDR,
      QSPI_WDATA0_ADDR, QSPI_WDATA1_ADDR, QSPI_WDATA2_ADDR, QSPI_WDATA3_ADDR,
      QSPI_AHB_SETUP_ADDR, QSPI_CLK_DIV_ADDR
    };

    `uvm_info("REG_STORM", $sformatf("Starting register storm: %0d transactions", num_transactions), UVM_LOW)

    for (int i = 0; i < num_transactions; i++) begin
      apb_master_transaction tr;
      tr = apb_master_transaction::type_id::create($sformatf("storm_%0d", i));
      start_item(tr);
      assert(tr.randomize() with {
        addr inside {rw_addrs};
      });
      finish_item(tr);
    end

    `uvm_info("REG_STORM", "Register storm complete", UVM_LOW)
  endtask

endclass

// ---------------------------------------------------------------------------
// Clock divider sweep: change CLK_DIV while issuing commands
// ---------------------------------------------------------------------------
class clkdiv_sweep_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(clkdiv_sweep_sequence)

  function new(string name = "clkdiv_sweep_sequence");
    super.new(name);
  endfunction

  virtual task body();
    apb_write_sequence wr;
    qspi_cmd_sequence  cmd;

    `uvm_info("CLKDIV_SWEEP", "Sweeping CLK_DIV 0-31 with JEDEC ID reads", UVM_LOW)

    for (int div = 0; div < 32; div++) begin
      // Set clock divider
      wr = apb_write_sequence::type_id::create($sformatf("wr_div_%0d", div));
      wr.addr  = QSPI_CLK_DIV_ADDR;
      wr.wdata = div;
      wr.start(m_sequencer);

      // Issue JEDEC ID read and verify
      cmd = qspi_cmd_sequence::type_id::create($sformatf("cmd_jedec_%0d", div));
      cmd.opcode    = SPI_OP_JEDEC_ID;
      cmd.do_read   = 1;
      cmd.n_rw_bytes = 3;
      cmd.start(m_sequencer);

      // Check manufacturer ID
      if (cmd.rdata[0][7:0] != FLASH_MFG_ID)
        `uvm_error("CLKDIV_SWEEP", $sformatf("JEDEC ID mismatch at CLK_DIV=%0d: got 0x%02h, expected 0x%02h",
          div, cmd.rdata[0][7:0], FLASH_MFG_ID))
      else
        `uvm_info("CLKDIV_SWEEP", $sformatf("CLK_DIV=%0d: JEDEC ID OK (0x%02h)", div, cmd.rdata[0][7:0]), UVM_MEDIUM)
    end
  endtask

endclass

// ---------------------------------------------------------------------------
// Dummy cycle boundary walk: sweep dummy cycles 0-15 with fast reads
// ---------------------------------------------------------------------------
class dummy_sweep_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(dummy_sweep_sequence)

  function new(string name = "dummy_sweep_sequence");
    super.new(name);
  endfunction

  virtual task body();
    qspi_cmd_sequence cmd;

    `uvm_info("DUMMY_SWEEP", "Sweeping DUMMY_CYCLES 0-15 with fast reads", UVM_LOW)

    for (int d = 0; d < 16; d++) begin
      cmd = qspi_cmd_sequence::type_id::create($sformatf("cmd_fread_d%0d", d));
      cmd.opcode       = SPI_OP_FAST_READ;
      cmd.do_read      = 1;
      cmd.addr_en      = 1;
      cmd.flash_addr   = 22'h0;
      cmd.dummy_cycles = d;
      cmd.n_rw_bytes   = 4;
      cmd.start(m_sequencer);

      `uvm_info("DUMMY_SWEEP", $sformatf("DUMMY=%0d: rdata[0]=0x%08h", d, cmd.rdata[0]), UVM_MEDIUM)
    end
  endtask

endclass

// ---------------------------------------------------------------------------
// Mode switching frenzy: rapidly alternate SPI/QPI modes
// ---------------------------------------------------------------------------
class mode_switch_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(mode_switch_sequence)

  rand int num_switches;
  constraint c_count { num_switches inside {[10:50]}; }

  function new(string name = "mode_switch_sequence");
    super.new(name);
  endfunction

  virtual task body();
    qspi_cmd_sequence cmd;
    apb_write_sequence wr;

    `uvm_info("MODE_SW", $sformatf("Mode switching frenzy: %0d SPI<->QPI switches", num_switches), UVM_LOW)

    for (int i = 0; i < num_switches; i++) begin
      // Enter QPI
      cmd = qspi_cmd_sequence::type_id::create($sformatf("eqio_%0d", i));
      cmd.opcode = SPI_OP_EQIO;
      cmd.start(m_sequencer);

      wr = apb_write_sequence::type_id::create($sformatf("qio_on_%0d", i));
      wr.addr = QSPI_CTRL_ADDR;
      wr.wdata = (1 << CTRL_QIO_MODE_BIT);
      wr.start(m_sequencer);

      // JEDEC ID in QPI mode
      cmd = qspi_cmd_sequence::type_id::create($sformatf("qjedec_%0d", i));
      cmd.opcode     = SPI_OP_QUAD_JEDEC_ID;
      cmd.do_read    = 1;
      cmd.n_rw_bytes = 3;
      cmd.start(m_sequencer);

      // Exit QPI
      cmd = qspi_cmd_sequence::type_id::create($sformatf("rstqio_%0d", i));
      cmd.opcode = SPI_OP_RSTQIO;
      cmd.start(m_sequencer);

      wr = apb_write_sequence::type_id::create($sformatf("qio_off_%0d", i));
      wr.addr = QSPI_CTRL_ADDR;
      wr.wdata = 0;
      wr.start(m_sequencer);

      // JEDEC ID in SPI mode
      cmd = qspi_cmd_sequence::type_id::create($sformatf("sjedec_%0d", i));
      cmd.opcode     = SPI_OP_JEDEC_ID;
      cmd.do_read    = 1;
      cmd.n_rw_bytes = 3;
      cmd.start(m_sequencer);
    end
  endtask

endclass

`endif // GUARD_QSPI_STRESS_SEQUENCE_SV
