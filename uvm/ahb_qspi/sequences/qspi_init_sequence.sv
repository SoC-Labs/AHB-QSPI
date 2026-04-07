///////////////////////////////////////////////////////////////////////////////
// qspi_init_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Flash initialisation sequence.
// Performs RSTEN + RST, then optionally enters QPI mode and clears protection.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_QSPI_INIT_SEQUENCE_SV
`define GUARD_QSPI_INIT_SEQUENCE_SV

class qspi_init_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(qspi_init_sequence)

  bit enter_qpi;      // If set, enters QPI mode after reset
  bit clear_protect;  // If set, clears block protection

  function new(string name = "qspi_init_sequence");
    super.new(name);
    enter_qpi     = 0;
    clear_protect = 0;
  endfunction

  virtual task body();
    qspi_cmd_sequence cmd;
    apb_write_sequence wr;

    // Set clock divider to a safe value
    wr = apb_write_sequence::type_id::create("wr_clkdiv");
    wr.addr  = QSPI_CLK_DIV_ADDR;
    wr.wdata = 32'h0000_0005;  // HCLK / 10 (10 MHz SCLK at 100 MHz HCLK)
    wr.start(m_sequencer);

    // RSTEN (0x66) — enable software reset (no data, no address)
    cmd = qspi_cmd_sequence::type_id::create("cmd_rsten");
    cmd.opcode = SPI_OP_RSTEN;
    cmd.start(m_sequencer);

    // RST (0x99) — execute software reset
    cmd = qspi_cmd_sequence::type_id::create("cmd_rst");
    cmd.opcode = SPI_OP_RST;
    cmd.start(m_sequencer);

    // Optionally clear block protection
    if (clear_protect) begin
      // WREN
      cmd = qspi_cmd_sequence::type_id::create("cmd_wren_prot");
      cmd.opcode = SPI_OP_WREN;
      cmd.start(m_sequencer);

      // ULBPR (0x98) — unlock all block protection
      cmd = qspi_cmd_sequence::type_id::create("cmd_ulbpr");
      cmd.opcode = SPI_OP_ULBPR;
      cmd.start(m_sequencer);
    end

    // Optionally enter QPI mode
    if (enter_qpi) begin
      // EQIO (0x38)
      cmd = qspi_cmd_sequence::type_id::create("cmd_eqio");
      cmd.opcode = SPI_OP_EQIO;
      cmd.start(m_sequencer);

      // Set QIO_MODE bit in CTRL register
      wr = apb_write_sequence::type_id::create("wr_qio_mode");
      wr.addr  = QSPI_CTRL_ADDR;
      wr.wdata = (1 << CTRL_QIO_MODE_BIT);
      wr.start(m_sequencer);
    end

    `uvm_info("QSPI_INIT", $sformatf("Flash initialised (QPI=%0b, unprotect=%0b)",
      enter_qpi, clear_protect), UVM_LOW)
  endtask

endclass

`endif // GUARD_QSPI_INIT_SEQUENCE_SV
