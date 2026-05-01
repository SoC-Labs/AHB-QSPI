///////////////////////////////////////////////////////////////////////////////
// apb_read_sequence.sv
///////////////////////////////////////////////////////////////////////////////
// Single APB read transaction.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_READ_SEQUENCE_SV
`define GUARD_APB_READ_SEQUENCE_SV

class apb_read_sequence extends uvm_sequence #(apb_master_transaction);

  `uvm_object_utils(apb_read_sequence)

  bit [15:0] addr;
  bit [31:0] rdata;   // Populated after body()

  function new(string name = "apb_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    apb_master_transaction tr;
    tr = apb_master_transaction::type_id::create("tr");
    start_item(tr);
    tr.write = 0;
    tr.addr  = this.addr;
    tr.wdata = 32'h0;
    finish_item(tr);
    this.rdata = tr.rdata;
  endtask

endclass

`endif // GUARD_APB_READ_SEQUENCE_SV
