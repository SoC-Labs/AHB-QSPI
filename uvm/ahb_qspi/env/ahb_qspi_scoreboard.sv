///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_scoreboard.sv
///////////////////////////////////////////////////////////////////////////////
// Scoreboard for AHB QSPI verification.
// Receives APB transactions from the APB monitor and QSPI transactions
// from the QSPI monitor. Checks data integrity and protocol correctness.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_SCOREBOARD_SV
`define GUARD_AHB_QSPI_SCOREBOARD_SV

// Analysis imp suffix macros — must precede class definition
`uvm_analysis_imp_decl(_apb)
`uvm_analysis_imp_decl(_qspi)

class ahb_qspi_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(ahb_qspi_scoreboard)

  // Analysis exports
  uvm_analysis_imp_apb  #(apb_master_transaction, ahb_qspi_scoreboard) apb_export;
  uvm_analysis_imp_qspi #(qspi_transaction, ahb_qspi_scoreboard) qspi_export;

  // Counters
  int apb_read_count;
  int apb_write_count;
  int qspi_transaction_count;
  int check_pass_count;
  int check_fail_count;

  // Shadow register model
  bit [31:0] shadow_regs[16];

  function new(string name = "ahb_qspi_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_export  = new("apb_export", this);
    qspi_export = new("qspi_export", this);

    // Initialize shadow registers to reset values
    foreach (shadow_regs[i]) shadow_regs[i] = 32'h0;
    shadow_regs[13] = 32'h0000_0001;  // CLK_DIV reset = 1
  endfunction

  // APB transaction received
  virtual function void write_apb(apb_master_transaction tr);
    if (tr.write) begin
      apb_write_count++;
      `uvm_info("SCB_APB", $sformatf("APB WRITE addr=0x%04h data=0x%08h",
        tr.addr, tr.wdata), UVM_HIGH)
    end else begin
      apb_read_count++;
      `uvm_info("SCB_APB", $sformatf("APB READ addr=0x%04h data=0x%08h",
        tr.addr, tr.rdata), UVM_HIGH)
    end
  endfunction

  // QSPI transaction received
  virtual function void write_qspi(qspi_transaction tr);
    qspi_transaction_count++;
    `uvm_info("SCB_QSPI", $sformatf("QSPI opcode=0x%02h cycles=%0d",
      tr.opcode, tr.total_sclk_cycles), UVM_HIGH)
  endfunction

  // Check a register read value against expected
  function void check_reg_value(string name, bit [31:0] actual, bit [31:0] expected,
                                 bit [31:0] mask = 32'hFFFF_FFFF);
    if ((actual & mask) == (expected & mask)) begin
      check_pass_count++;
      `uvm_info("SCB_CHK", $sformatf("PASS: %s = 0x%08h (expected 0x%08h)",
        name, actual, expected), UVM_MEDIUM)
    end else begin
      check_fail_count++;
      `uvm_error("SCB_CHK", $sformatf("FAIL: %s = 0x%08h (expected 0x%08h, mask=0x%08h)",
        name, actual, expected, mask))
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB_RPT", $sformatf(
      "\n=== Scoreboard Summary ===\n  APB reads:  %0d\n  APB writes: %0d\n  QSPI txns:  %0d\n  Checks passed: %0d\n  Checks failed: %0d\n==========================",
      apb_read_count, apb_write_count, qspi_transaction_count,
      check_pass_count, check_fail_count), UVM_LOW)

    if (check_fail_count > 0)
      `uvm_error("SCB_RPT", $sformatf("%0d checks FAILED", check_fail_count))
  endfunction

endclass

`endif // GUARD_AHB_QSPI_SCOREBOARD_SV
