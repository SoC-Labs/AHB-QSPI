///////////////////////////////////////////////////////////////////////////////
// apb_master_driver.sv
///////////////////////////////////////////////////////////////////////////////
// UVM driver for the APB master side.
// Drives APB transfers (setup + access phases) to the DUT's APB slave.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_MASTER_DRIVER_SV
`define GUARD_APB_MASTER_DRIVER_SV

class apb_master_driver extends uvm_driver #(apb_master_transaction);

  `uvm_component_utils(apb_master_driver)

  virtual apb_master_if.driver vif;

  function new(string name = "apb_master_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_master_if.driver)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for apb_master_driver")
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Initialize bus to idle
    vif.drv_cb.psel    <= 1'b0;
    vif.drv_cb.penable <= 1'b0;
    vif.drv_cb.pwrite  <= 1'b0;
    vif.drv_cb.paddr   <= 16'h0;
    vif.drv_cb.pwdata  <= 32'h0;

    forever begin
      apb_master_transaction tr;
      seq_item_port.get_next_item(tr);
      drive_transfer(tr);
      seq_item_port.item_done();
    end
  endtask

  virtual task drive_transfer(apb_master_transaction tr);
    // Setup phase
    @(vif.drv_cb);
    vif.drv_cb.psel    <= 1'b1;
    vif.drv_cb.penable <= 1'b0;
    vif.drv_cb.pwrite  <= tr.write;
    vif.drv_cb.paddr   <= tr.addr;
    if (tr.write)
      vif.drv_cb.pwdata <= tr.wdata;

    // Access phase
    @(vif.drv_cb);
    vif.drv_cb.penable <= 1'b1;

    // Wait for pready
    do begin
      @(vif.drv_cb);
    end while (!vif.drv_cb.pready);

    // Capture response
    if (!tr.write)
      tr.rdata = vif.drv_cb.prdata;
    tr.slverr = vif.drv_cb.pslverr;

    `uvm_info("APB_DRV", $sformatf("%s addr=0x%04h %s",
      tr.write ? "WRITE" : "READ", tr.addr,
      tr.write ? $sformatf("data=0x%08h", tr.wdata)
               : $sformatf("data=0x%08h", tr.rdata)), UVM_HIGH)

    // Return to idle
    vif.drv_cb.psel    <= 1'b0;
    vif.drv_cb.penable <= 1'b0;
  endtask

endclass

`endif // GUARD_APB_MASTER_DRIVER_SV
