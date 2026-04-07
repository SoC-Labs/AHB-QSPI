///////////////////////////////////////////////////////////////////////////////
// qspi_cmd_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Generic QSPI command sequence via APB register interface.
// Uses the two-phase command protocol: write fields with ENABLE=0 (setup),
// then write again with ENABLE=1 (trigger).
// Waits for completion by polling STATUS.BUSY.
//
// N_RW_BYTES encoding: value N means (N+1) bytes transferred.
//   0 → 1 byte, 1 → 2 bytes, 2 → 3 bytes, ..., 15 → 16 bytes
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_QSPI_CMD_SEQUENCE_SV
`define GUARD_QSPI_CMD_SEQUENCE_SV

class qspi_cmd_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(qspi_cmd_sequence)

  // Command parameters
  bit [7:0]  opcode;
  bit        do_read;
  bit        do_write;
  bit        addr_en;
  bit [3:0]  dummy_cycles;
  bit [3:0]  n_rw_bytes;    // Encoding: value N → (N+1) bytes
  bit [21:0] flash_addr;

  // Write data (up to 16 bytes, packed into 4 x 32-bit registers)
  bit [31:0] wdata [4];

  // Read data (populated after body())
  bit [31:0] rdata [4];

  function new(string name = "qspi_cmd_sequence");
    super.new(name);
    opcode       = 8'h00;
    do_read      = 0;
    do_write     = 0;
    addr_en      = 0;
    dummy_cycles = 0;
    n_rw_bytes   = 0;
    flash_addr   = 0;
    foreach (wdata[i]) wdata[i] = 0;
  endfunction

  virtual task body();
    apb_write_sequence wr_seq;
    apb_read_sequence  rd_seq;

    // 1. Set flash address (if needed)
    if (addr_en) begin
      wr_seq = apb_write_sequence::type_id::create("wr_addr");
      wr_seq.addr  = QSPI_ADDR_ADDR;
      wr_seq.wdata = {10'h0, flash_addr};
      wr_seq.start(m_sequencer);
    end

    // 2. Load write data (if writing)
    if (do_write) begin
      for (int i = 0; i < 4; i++) begin
        wr_seq = apb_write_sequence::type_id::create($sformatf("wr_wdata%0d", i));
        wr_seq.addr  = QSPI_WDATA0_ADDR + (i * 4);
        wr_seq.wdata = wdata[i];
        wr_seq.start(m_sequencer);
      end
    end

    // 3. Two-phase command: first write with ENABLE=0 (setup), then ENABLE=1 (trigger)
    begin
      bit [31:0] cmd_base;
      cmd_base = {12'h0,
                  n_rw_bytes,                     // [19:16]
                  dummy_cycles,                   // [15:12]
                  addr_en,                        // [11]
                  do_write,                       // [10]
                  do_read,                        // [9]
                  1'b0,                           // [8] ENABLE=0 (setup phase)
                  opcode};                        // [7:0]

      // Phase 1: setup (ENABLE=0)
      wr_seq = apb_write_sequence::type_id::create("wr_cmd_setup");
      wr_seq.addr  = QSPI_SPI_CMD_ADDR;
      wr_seq.wdata = cmd_base;
      wr_seq.start(m_sequencer);

      // Phase 2: trigger (ENABLE=1)
      wr_seq = apb_write_sequence::type_id::create("wr_cmd_enable");
      wr_seq.addr  = QSPI_SPI_CMD_ADDR;
      wr_seq.wdata = cmd_base | (1 << SPI_CMD_ENABLE_BIT);
      wr_seq.start(m_sequencer);
    end

    // 4. Wait for completion (poll STATUS.BUSY)
    begin
      bit busy = 1;
      int timeout = 50000;
      while (busy && timeout > 0) begin
        rd_seq = apb_read_sequence::type_id::create("rd_status");
        rd_seq.addr = QSPI_STATUS_ADDR;
        rd_seq.start(m_sequencer);
        busy = rd_seq.rdata[STATUS_BUSY_BIT];
        timeout--;
      end
      if (timeout == 0)
        `uvm_error("QSPI_CMD", "Timeout waiting for QSPI command completion")
    end

    // 5. Read back data (if reading)
    if (do_read) begin
      for (int i = 0; i < 4; i++) begin
        rd_seq = apb_read_sequence::type_id::create($sformatf("rd_rdata%0d", i));
        rd_seq.addr = QSPI_RDATA0_ADDR + (i * 4);
        rd_seq.start(m_sequencer);
        rdata[i] = rd_seq.rdata;
      end
    end

    // 6. Clear IRQ
    wr_seq = apb_write_sequence::type_id::create("wr_irq_clr");
    wr_seq.addr  = QSPI_STATUS_ADDR;
    wr_seq.wdata = (1 << STATUS_IRQ_CLR_BIT);
    wr_seq.start(m_sequencer);
  endtask

endclass

`endif // GUARD_QSPI_CMD_SEQUENCE_SV
