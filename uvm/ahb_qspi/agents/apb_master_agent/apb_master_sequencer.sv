///////////////////////////////////////////////////////////////////////////////
// apb_master_sequencer.sv
///////////////////////////////////////////////////////////////////////////////
// UVM sequencer for APB master transactions.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_MASTER_SEQUENCER_SV
`define GUARD_APB_MASTER_SEQUENCER_SV

class apb_master_sequencer extends uvm_sequencer #(apb_master_transaction);

  `uvm_component_utils(apb_master_sequencer)

  function new(string name = "apb_master_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass

`endif // GUARD_APB_MASTER_SEQUENCER_SV
