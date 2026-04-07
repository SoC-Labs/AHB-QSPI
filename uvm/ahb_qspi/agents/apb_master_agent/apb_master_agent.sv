///////////////////////////////////////////////////////////////////////////////
// apb_master_agent.sv
///////////////////////////////////////////////////////////////////////////////
// UVM agent for the APB master interface.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_MASTER_AGENT_SV
`define GUARD_APB_MASTER_AGENT_SV

class apb_master_agent extends uvm_agent;

  `uvm_component_utils(apb_master_agent)

  apb_master_driver    driver;
  apb_master_monitor   monitor;
  apb_master_sequencer sequencer;

  uvm_analysis_port #(apb_master_transaction) ap;

  function new(string name = "apb_master_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    monitor = apb_master_monitor::type_id::create("monitor", this);
    ap = new("ap", this);

    if (get_is_active() == UVM_ACTIVE) begin
      driver    = apb_master_driver::type_id::create("driver", this);
      sequencer = apb_master_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    monitor.ap.connect(ap);
    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass

`endif // GUARD_APB_MASTER_AGENT_SV
