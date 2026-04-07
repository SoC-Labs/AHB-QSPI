///////////////////////////////////////////////////////////////////////////////
// qspi_xip_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// XIP (execute-in-place) configuration sequence via APB registers.
// Enables XIP mode and configures AHB opcode/dummy cycles.
// AHB reads are performed by the test using the ahb_data_if helper tasks.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_QSPI_XIP_SEQUENCE_SV
`define GUARD_QSPI_XIP_SEQUENCE_SV

class qspi_xip_enable_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(qspi_xip_enable_sequence)

  bit [7:0]  ahb_cmd;         // Opcode for AHB reads (e.g. 0x0B = Fast Read)
  bit [3:0]  ahb_dummy;       // Dummy cycles for AHB reads

  function new(string name = "qspi_xip_enable_sequence");
    super.new(name);
    ahb_cmd    = SPI_OP_FAST_READ;
    ahb_dummy  = 4'h8;
  endfunction

  virtual task body();
    apb_write_sequence wr;

    // Configure AHB interface opcode and dummy cycles
    wr = apb_write_sequence::type_id::create("wr_ahb_setup");
    wr.addr  = QSPI_AHB_SETUP_ADDR;
    wr.wdata = {16'h0, ahb_dummy, 4'h0, ahb_cmd};
    wr.start(m_sequencer);

    // Enable XIP mode
    wr = apb_write_sequence::type_id::create("wr_xip_enable");
    wr.addr  = QSPI_CTRL_ADDR;
    wr.wdata = (1 << CTRL_XIP_ACTIVE_BIT);
    wr.start(m_sequencer);

    `uvm_info("XIP_SEQ", $sformatf("XIP enabled: cmd=0x%02h dummy=%0d",
      ahb_cmd, ahb_dummy), UVM_LOW)
  endtask

endclass

class qspi_xip_disable_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(qspi_xip_disable_sequence)

  function new(string name = "qspi_xip_disable_sequence");
    super.new(name);
  endfunction

  virtual task body();
    apb_write_sequence wr;
    wr = apb_write_sequence::type_id::create("wr_xip_disable");
    wr.addr  = QSPI_CTRL_ADDR;
    wr.wdata = 32'h0;
    wr.start(m_sequencer);
    `uvm_info("XIP_SEQ", "XIP disabled", UVM_LOW)
  endtask

endclass

`endif // GUARD_QSPI_XIP_SEQUENCE_SV
