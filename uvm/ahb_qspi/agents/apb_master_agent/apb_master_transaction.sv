///////////////////////////////////////////////////////////////////////////////
// apb_master_transaction.sv
///////////////////////////////////////////////////////////////////////////////
// UVM sequence item for APB master transactions.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_MASTER_TRANSACTION_SV
`define GUARD_APB_MASTER_TRANSACTION_SV

class apb_master_transaction extends uvm_sequence_item;

  // Request fields (set by sequence)
  rand bit [15:0] addr;
  rand bit [31:0] wdata;
  rand bit        write;

  // Response fields (filled by driver after transfer)
  bit [31:0] rdata;
  bit        slverr;

  constraint c_word_aligned { addr[1:0] == 2'b00; }

  `uvm_object_utils_begin(apb_master_transaction)
    `uvm_field_int(addr,   UVM_ALL_ON)
    `uvm_field_int(wdata,  UVM_ALL_ON)
    `uvm_field_int(write,  UVM_ALL_ON)
    `uvm_field_int(rdata,  UVM_ALL_ON)
    `uvm_field_int(slverr, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "apb_master_transaction");
    super.new(name);
  endfunction

endclass

`endif // GUARD_APB_MASTER_TRANSACTION_SV
