///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_corner_case_test.sv
///////////////////////////////////////////////////////////////////////////////
// Corner case tests: N_RW_BYTES sweep, simultaneous R+W, back-to-back
// commands, address boundaries, continuous read mode.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_CORNER_CASE_TEST_SV
`define GUARD_AHB_QSPI_CORNER_CASE_TEST_SV

class ahb_qspi_corner_case_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_corner_case_test)

  function new(string name = "ahb_qspi_corner_case_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence         init_seq;
    n_rw_bytes_sweep_sequence  nrw_seq;
    simultaneous_rw_sequence   sim_rw_seq;
    back_to_back_cmd_sequence  b2b_seq;
    addr_boundary_sequence     addr_seq;
    continuous_read_sequence   cont_seq;

    phase.raise_objection(this);
    wait_for_reset();

    // ---------------------------------------------------------------
    `uvm_info("CORNER", "=== Phase 1: Flash Init ===", UVM_LOW)
    // ---------------------------------------------------------------
    init_seq = qspi_init_sequence::type_id::create("init");
    init_seq.clear_protect = 1;
    init_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("CORNER", "=== Phase 2: N_RW_BYTES Sweep ===", UVM_LOW)
    // ---------------------------------------------------------------
    nrw_seq = n_rw_bytes_sweep_sequence::type_id::create("nrw_sweep");
    nrw_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("CORNER", "=== Phase 3: Simultaneous R+W Bits ===", UVM_LOW)
    // ---------------------------------------------------------------
    sim_rw_seq = simultaneous_rw_sequence::type_id::create("sim_rw");
    sim_rw_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("CORNER", "=== Phase 4: Back-to-back Commands ===", UVM_LOW)
    // ---------------------------------------------------------------
    b2b_seq = back_to_back_cmd_sequence::type_id::create("b2b");
    b2b_seq.num_commands = 50;
    b2b_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("CORNER", "=== Phase 5: Address Boundaries ===", UVM_LOW)
    // ---------------------------------------------------------------
    addr_seq = addr_boundary_sequence::type_id::create("addr_bnd");
    addr_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("CORNER", "=== Phase 6: Continuous Read + NO_CMD ===", UVM_LOW)
    // ---------------------------------------------------------------
    cont_seq = continuous_read_sequence::type_id::create("cont_rd");
    cont_seq.start(env.apb_agt.sequencer);

    `uvm_info("CORNER", "Corner case test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_CORNER_CASE_TEST_SV
