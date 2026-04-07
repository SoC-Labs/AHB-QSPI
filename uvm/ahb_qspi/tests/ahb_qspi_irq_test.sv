///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_irq_test.sv
///////////////////////////////////////////////////////////////////////////////
// Interrupt tests: IRQ assertion on command completion, IRQ clear.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_IRQ_TEST_SV
`define GUARD_AHB_QSPI_IRQ_TEST_SV

class ahb_qspi_irq_test extends ahb_qspi_base_test;

  `uvm_component_utils(ahb_qspi_irq_test)

  function new(string name = "ahb_qspi_irq_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qspi_init_sequence init_seq;
    qspi_cmd_sequence  cmd;

    phase.raise_objection(this);
    wait_for_reset();

    init_seq = qspi_init_sequence::type_id::create("init");
    init_seq.start(env.apb_agt.sequencer);

    // ---------------------------------------------------------------
    `uvm_info("IRQ_TEST", "=== IRQ on Command Complete ===", UVM_LOW)
    // ---------------------------------------------------------------

    // Verify IRQ is initially low
    @(ahb_vif.drv_cb);
    if (ahb_vif.drv_cb.irq_qspi_finished !== 1'b0)
      `uvm_error("IRQ_TEST", "IRQ should be low before any command")

    // Issue JEDEC ID command (don't auto-clear IRQ — do it manually)
    begin
      apb_write_sequence wr;
      apb_read_sequence  rd;

      // Issue command
      wr = apb_write_sequence::type_id::create("wr_cmd");
      wr.addr  = QSPI_SPI_CMD_ADDR;
      wr.wdata = {12'h0, 4'h3, 4'h0, 4'h0, 1'b0, 1'b0, 1'b1, 1'b1, SPI_OP_JEDEC_ID};
      wr.start(env.apb_agt.sequencer);

      // Poll for completion
      begin
        bit busy = 1;
        int timeout = 5000;
        while (busy && timeout > 0) begin
          rd = apb_read_sequence::type_id::create("rd_status");
          rd.addr = QSPI_STATUS_ADDR;
          rd.start(env.apb_agt.sequencer);
          busy = rd.rdata[STATUS_BUSY_BIT];
          timeout--;
        end
      end

      // Give time for IRQ to propagate
      wait_clks(10);

      // Check IRQ is asserted
      @(ahb_vif.drv_cb);
      if (ahb_vif.drv_cb.irq_qspi_finished === 1'b1)
        `uvm_info("IRQ_TEST", "PASS: IRQ asserted after command completion", UVM_LOW)
      else
        `uvm_error("IRQ_TEST", "FAIL: IRQ not asserted after command completion")
    end

    // ---------------------------------------------------------------
    `uvm_info("IRQ_TEST", "=== IRQ Clear ===", UVM_LOW)
    // ---------------------------------------------------------------

    // Write IRQ_CLR
    apb_write(QSPI_STATUS_ADDR, (1 << STATUS_IRQ_CLR_BIT));
    wait_clks(5);

    // Check IRQ is deasserted
    @(ahb_vif.drv_cb);
    if (ahb_vif.drv_cb.irq_qspi_finished === 1'b0)
      `uvm_info("IRQ_TEST", "PASS: IRQ deasserted after IRQ_CLR", UVM_LOW)
    else
      `uvm_error("IRQ_TEST", "FAIL: IRQ still asserted after IRQ_CLR")

    // ---------------------------------------------------------------
    `uvm_info("IRQ_TEST", "=== Multiple IRQ Cycles ===", UVM_LOW)
    // ---------------------------------------------------------------
    for (int i = 0; i < 5; i++) begin
      cmd = qspi_cmd_sequence::type_id::create($sformatf("cmd_%0d", i));
      cmd.opcode     = SPI_OP_JEDEC_ID;
      cmd.do_read    = 1;
      cmd.n_rw_bytes = 3;
      cmd.start(env.apb_agt.sequencer);  // auto-clears IRQ

      `uvm_info("IRQ_TEST", $sformatf("IRQ cycle %0d complete", i), UVM_MEDIUM)
    end

    `uvm_info("IRQ_TEST", "Interrupt test complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif // GUARD_AHB_QSPI_IRQ_TEST_SV
