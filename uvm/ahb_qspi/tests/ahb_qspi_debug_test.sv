// Quick debug: raw JEDEC read matching cocotb exactly
`ifndef GUARD_AHB_QSPI_DEBUG_TEST_SV
`define GUARD_AHB_QSPI_DEBUG_TEST_SV
class ahb_qspi_debug_test extends ahb_qspi_base_test;
  `uvm_component_utils(ahb_qspi_debug_test)
  function new(string name="ahb_qspi_debug_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction
  virtual task run_phase(uvm_phase phase);
    bit [31:0] rd;
    phase.raise_objection(this);
    wait_for_reset();

    // Set clock divider = 5
    apb_write(16'h0034, 32'h5);
    apb_read(16'h0034, rd);
    `uvm_info("DBG", $sformatf("CLK_DIV = 0x%08h", rd), UVM_NONE)

    // RSTEN: cocotb writes 0x66 then 0x166
    `uvm_info("DBG", "RSTEN...", UVM_NONE)
    apb_write(16'h0008, 32'h00000066);
    apb_write(16'h0008, 32'h00000166);
    // Poll busy
    rd = 1;
    while (rd & 1) begin apb_read(16'h0004, rd); end
    `uvm_info("DBG", $sformatf("STATUS after RSTEN = 0x%08h", rd), UVM_NONE)

    // Clear IRQ
    apb_write(16'h0004, 32'h100);
    wait_clks(5);

    // RST: cocotb writes 0x99 then 0x199
    `uvm_info("DBG", "RST...", UVM_NONE)
    apb_write(16'h0008, 32'h00000099);
    apb_write(16'h0008, 32'h00000199);
    rd = 1;
    while (rd & 1) begin apb_read(16'h0004, rd); end
    apb_write(16'h0004, 32'h100);
    wait_clks(5);

    // JEDEC: cocotb writes 0x0002009F then 0x0002039F
    `uvm_info("DBG", "JEDEC ID...", UVM_NONE)
    apb_write(16'h0008, 32'h0002009F);
    apb_write(16'h0008, 32'h0002039F);

    // Poll busy
    rd = 1;
    while (rd & 1) begin apb_read(16'h0004, rd); end
    `uvm_info("DBG", $sformatf("STATUS after JEDEC = 0x%08h", rd), UVM_NONE)

    // Read reg2 (command register) to see state
    apb_read(16'h0008, rd);
    `uvm_info("DBG", $sformatf("SPI_CMD reg = 0x%08h", rd), UVM_NONE)

    // Read ALL 4 RDATA registers
    apb_read(16'h0010, rd);
    `uvm_info("DBG", $sformatf("RDATA0 (0x10) = 0x%08h", rd), UVM_NONE)
    apb_read(16'h0014, rd);
    `uvm_info("DBG", $sformatf("RDATA1 (0x14) = 0x%08h", rd), UVM_NONE)
    apb_read(16'h0018, rd);
    `uvm_info("DBG", $sformatf("RDATA2 (0x18) = 0x%08h", rd), UVM_NONE)
    apb_read(16'h001C, rd);
    `uvm_info("DBG", $sformatf("RDATA3 (0x1C) = 0x%08h", rd), UVM_NONE)

    `uvm_info("DBG", "Done", UVM_NONE)
    phase.drop_objection(this);
  endtask
endclass
`endif
