///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_env.sv
///////////////////////////////////////////////////////////////////////////////
// UVM environment for AHB QSPI verification.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_ENV_SV
`define GUARD_AHB_QSPI_ENV_SV

class ahb_qspi_env extends uvm_env;

  `uvm_component_utils(ahb_qspi_env)

  // Agents
  apb_master_agent   apb_agt;
  qspi_monitor       qspi_mon;

  // Checking and coverage
  ahb_qspi_scoreboard scoreboard;
  ahb_qspi_coverage   coverage;

  function new(string name = "ahb_qspi_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    apb_agt    = apb_master_agent::type_id::create("apb_agt", this);
    qspi_mon   = qspi_monitor::type_id::create("qspi_mon", this);
    scoreboard = ahb_qspi_scoreboard::type_id::create("scoreboard", this);
    coverage   = ahb_qspi_coverage::type_id::create("coverage", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // APB monitor -> scoreboard + coverage
    apb_agt.ap.connect(scoreboard.apb_export);
    apb_agt.ap.connect(coverage.analysis_export);

    // QSPI monitor -> scoreboard
    qspi_mon.ap.connect(scoreboard.qspi_export);
  endfunction

endclass

`endif // GUARD_AHB_QSPI_ENV_SV
