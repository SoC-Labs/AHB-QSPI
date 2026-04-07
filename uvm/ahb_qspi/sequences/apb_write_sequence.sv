///////////////////////////////////////////////////////////////////////////////
// apb_write_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Single APB write transaction.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_WRITE_SEQUENCE_SV
`define GUARD_APB_WRITE_SEQUENCE_SV

class apb_write_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(apb_write_sequence)

  bit [15:0] addr;
  bit [31:0] wdata;

  function new(string name = "apb_write_sequence");
    super.new(name);
  endfunction

  virtual task body();
    apb_master_transaction tr;
    tr = apb_master_transaction::type_id::create("tr");
    start_item(tr);
    tr.write = 1;
    tr.addr  = this.addr;
    tr.wdata = this.wdata;
    finish_item(tr);
  endtask

endclass

`endif // GUARD_APB_WRITE_SEQUENCE_SV
