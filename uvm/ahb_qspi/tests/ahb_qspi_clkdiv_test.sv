///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_clkdiv_test.sv
///////////////////////////////////////////////////////////////////////////////
// Clock divider tests: sweep all divider values, verify correct operation.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_CLKDIV_TEST_SV
`define GUARD_AHB_QSPI_CLKDIV_TEST_SV

class ahb_qspi_clkdiv_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_clkdiv_test)

  function new(string name = "ahb_qspi_clkdiv_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence   init_seq;
    clkdiv_sweep_sequence sweep_seq;

    phase.raise_objection(this);
    wait_for_reset();

    init_seq = qspi_init_sequence::type_id::create("init");
    init_seq.start(env.apb_agt.sequencer);

    sweep_seq = clkdiv_sweep_sequence::type_id::create("sweep");
    sweep_seq.start(env.apb_agt.sequencer);

    // Restore default divider
    apb_write(QSPI_CLK_DIV_ADDR, REG13_RESET);

    `uvm_info("CLKDIV_TEST", "Clock divider test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_CLKDIV_TEST_SV
