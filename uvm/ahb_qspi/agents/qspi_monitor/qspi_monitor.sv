///////////////////////////////////////////////////////////////////////////////
// qspi_monitor.sv
///////////////////////////////////////////////////////////////////////////////
// Passive UVM monitor for the QSPI pad bus.
// Decodes transactions by observing SCLK edges while nCS is asserted.
// Captures opcode, address, dummy, and data phases.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_QSPI_MONITOR_SV
`define GUARD_QSPI_MONITOR_SV

class qspi_monitor extends uvm_monitor;

  `uvm_component_utils(qspi_monitor)

  virtual qspi_monitor_if vif;

  uvm_analysis_port #(qspi_transaction) ap;

  function new(string name = "qspi_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual qspi_monitor_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for qspi_monitor")
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      qspi_transaction tr;
      capture_transaction(tr);
      if (tr != null)
        ap.write(tr);
    end
  endtask

  // Wait for nCS to assert (fall), capture all SCLK-edge data until nCS deasserts
  virtual task capture_transaction(output qspi_transaction tr);
    int cycle_count;
    bit [7:0] captured_bytes[$];
    bit [7:0] current_byte;
    int       bit_count;

    // Wait for nCS to go low (transaction start)
    @(negedge vif.csn);

    tr = qspi_transaction::type_id::create("qspi_mon_tr");
    cycle_count = 0;
    bit_count   = 0;
    current_byte = 8'h00;

    // Capture data on rising SCLK edges while nCS is low
    while (!vif.csn) begin
      @(posedge vif.sclk or posedge vif.csn);
      if (vif.csn) break;

      // Sample IO[0] (MOSI in SPI mode) for basic capture
      // Full quad-mode decoding would sample all 4 IO lines
      current_byte = {current_byte[6:0], vif.io[0]};
      bit_count++;
      cycle_count++;

      if (bit_count == 8) begin
        captured_bytes.push_back(current_byte);
        current_byte = 8'h00;
        bit_count = 0;
      end
    end

    tr.total_sclk_cycles = cycle_count;

    // Extract opcode from first captured byte (if any)
    if (captured_bytes.size() > 0) begin
      tr.opcode     = captured_bytes[0];
      tr.has_opcode = 1;
    end

    // Extract address from bytes 1-3 (if present)
    if (captured_bytes.size() >= 4) begin
      tr.address     = {captured_bytes[1], captured_bytes[2], captured_bytes[3]};
      tr.has_address = 1;
    end

    `uvm_info("QSPI_MON", $sformatf("Transaction: opcode=0x%02h cycles=%0d bytes=%0d",
      tr.opcode, cycle_count, captured_bytes.size()), UVM_MEDIUM)
  endtask

endclass

`endif // GUARD_QSPI_MONITOR_SV
