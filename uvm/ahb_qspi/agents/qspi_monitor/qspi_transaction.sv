///////////////////////////////////////////////////////////////////////////////
// qspi_transaction.sv
///////////////////////////////////////////////////////////////////////////////
// Transaction captured by the QSPI monitor.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_QSPI_TRANSACTION_SV
`define GUARD_QSPI_TRANSACTION_SV

class qspi_transaction extends uvm_sequence_item;

  bit [7:0]  opcode;
  bit        has_opcode;
  bit [23:0] address;
  bit        has_address;
  int        dummy_cycles;
  bit [7:0]  data[];       // Dynamic array for variable-length data
  bit        is_read;      // 1 = flash-to-host, 0 = host-to-flash
  bit        quad_mode;    // 1 = QPI/quad, 0 = standard SPI
  int        total_sclk_cycles;

  `uvm_object_utils_begin(qspi_transaction)
    `uvm_field_int(opcode,            UVM_ALL_ON)
    `uvm_field_int(has_opcode,        UVM_ALL_ON)
    `uvm_field_int(address,           UVM_ALL_ON)
    `uvm_field_int(has_address,       UVM_ALL_ON)
    `uvm_field_int(dummy_cycles,      UVM_ALL_ON)
    `uvm_field_array_int(data,        UVM_ALL_ON)
    `uvm_field_int(is_read,           UVM_ALL_ON)
    `uvm_field_int(quad_mode,         UVM_ALL_ON)
    `uvm_field_int(total_sclk_cycles, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "qspi_transaction");
    super.new(name);
  endfunction

endclass

`endif // GUARD_QSPI_TRANSACTION_SV
