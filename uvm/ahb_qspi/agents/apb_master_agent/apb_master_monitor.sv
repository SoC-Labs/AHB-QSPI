///////////////////////////////////////////////////////////////////////////////
// apb_master_monitor.sv
///////////////////////////////////////////////////////////////////////////////
// Passive UVM monitor for the APB master bus.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_MASTER_MONITOR_SV
`define GUARD_APB_MASTER_MONITOR_SV

class apb_master_monitor extends uvm_monitor;

  `uvm_component_utils(apb_master_monitor)

  virtual apb_master_if.monitor vif;

  uvm_analysis_port #(apb_master_transaction) ap;

  function new(string name = "apb_master_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual apb_master_if.monitor)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for apb_master_monitor")
  endfunction

  virtual task run_phase(uvm_phase phase);
    @(posedge vif.rst_n);
    forever begin
      apb_master_transaction tr;
      collect_transaction(tr);
      ap.write(tr);
    end
  endtask

  virtual task collect_transaction(output apb_master_transaction tr);
    @(vif.mon_cb);
    while (!(vif.mon_cb.psel && vif.mon_cb.penable && vif.mon_cb.pready)) begin
      @(vif.mon_cb);
    end

    tr = apb_master_transaction::type_id::create("apb_mon_tr");
    tr.addr   = vif.mon_cb.paddr;
    tr.write  = vif.mon_cb.pwrite;
    tr.slverr = vif.mon_cb.pslverr;

    if (vif.mon_cb.pwrite)
      tr.wdata = vif.mon_cb.pwdata;
    else
      tr.rdata = vif.mon_cb.prdata;

    `uvm_info("APB_MON", $sformatf("Captured %s addr=0x%04h%s",
      tr.write ? "WRITE" : "READ", tr.addr,
      tr.slverr ? " [SLVERR]" : ""), UVM_MEDIUM)
  endtask

endclass

`endif // GUARD_APB_MASTER_MONITOR_SV
