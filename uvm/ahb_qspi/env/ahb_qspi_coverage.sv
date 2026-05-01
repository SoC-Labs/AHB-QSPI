///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_coverage.sv
///////////////////////////////////////////////////////////////////////////////
// Functional coverage collector for AHB QSPI verification.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_COVERAGE_SV
`define GUARD_AHB_QSPI_COVERAGE_SV

class ahb_qspi_coverage extends uvm_subscriber #(apb_master_transaction);

  `uvm_component_utils(ahb_qspi_coverage)

  // Sampled fields
  bit [15:0] apb_addr;
  bit        apb_write;
  bit [7:0]  spi_opcode;
  bit [4:0]  clk_div;
  bit        qio_mode;
  bit        xip_active;
  bit [3:0]  dummy_cycles;
  bit [3:0]  n_rw_bytes;

  // -----------------------------------------------------------------------
  // Register access coverage
  // -----------------------------------------------------------------------
  covergroup cg_apb_access;
    cp_addr: coverpoint apb_addr {
      bins ctrl       = {QSPI_CTRL_ADDR};
      bins status     = {QSPI_STATUS_ADDR};
      bins spi_cmd    = {QSPI_SPI_CMD_ADDR};
      bins addr_reg   = {QSPI_ADDR_ADDR};
      bins rdata[4]   = {QSPI_RDATA0_ADDR, QSPI_RDATA1_ADDR, QSPI_RDATA2_ADDR, QSPI_RDATA3_ADDR};
      bins wdata[4]   = {QSPI_WDATA0_ADDR, QSPI_WDATA1_ADDR, QSPI_WDATA2_ADDR, QSPI_WDATA3_ADDR};
      bins ahb_setup  = {QSPI_AHB_SETUP_ADDR};
      bins clk_div    = {QSPI_CLK_DIV_ADDR};
      bins pid[8]     = {[QSPI_PIDR4_ADDR:QSPI_PIDR3_ADDR]};
      bins cid[4]     = {[QSPI_CIDR0_ADDR:QSPI_CIDR3_ADDR]};
    }
    cp_rw: coverpoint apb_write {
      bins read  = {0};
      bins write = {1};
    }
    cx_addr_rw: cross cp_addr, cp_rw;
  endgroup

  // -----------------------------------------------------------------------
  // SPI command coverage
  // -----------------------------------------------------------------------
  covergroup cg_spi_command;
    cp_opcode: coverpoint spi_opcode {
      bins read         = {SPI_OP_READ};
      bins fast_read    = {SPI_OP_FAST_READ};
      bins rsten        = {SPI_OP_RSTEN};
      bins rst          = {SPI_OP_RST};
      bins eqio         = {SPI_OP_EQIO};
      bins rstqio       = {SPI_OP_RSTQIO};
      bins rdsr         = {SPI_OP_RDSR};
      bins wren         = {SPI_OP_WREN};
      bins wrdi         = {SPI_OP_WRDI};
      bins jedec_id     = {SPI_OP_JEDEC_ID};
      bins pp           = {SPI_OP_PP};
      bins se           = {SPI_OP_SE};
      bins be           = {SPI_OP_BE};
      bins ce           = {SPI_OP_CE};
      bins ulbpr        = {SPI_OP_ULBPR};
      bins other        = default;
    }
    cp_qio: coverpoint qio_mode {
      bins spi_mode  = {0};
      bins quad_mode = {1};
    }
    cp_dummy: coverpoint dummy_cycles {
      bins zero     = {0};
      bins low      = {[1:3]};
      bins mid      = {[4:7]};
      bins high     = {[8:15]};
    }
    cp_n_rw: coverpoint n_rw_bytes {
      bins zero     = {0};
      bins one      = {1};
      bins mid      = {[2:8]};
      bins max      = {[9:15]};
    }
    cx_opcode_mode: cross cp_opcode, cp_qio;
    cx_opcode_dummy: cross cp_opcode, cp_dummy;
  endgroup

  // -----------------------------------------------------------------------
  // Clock divider coverage
  // -----------------------------------------------------------------------
  covergroup cg_clk_div;
    cp_div: coverpoint clk_div {
      bins bypass   = {0};
      bins div_1    = {1};
      bins div_low  = {[2:7]};
      bins div_mid  = {[8:15]};
      bins div_high = {[16:31]};
    }
  endgroup

  // -----------------------------------------------------------------------
  // XIP mode coverage
  // -----------------------------------------------------------------------
  covergroup cg_xip;
    cp_xip: coverpoint xip_active;
  endgroup

  function new(string name = "ahb_qspi_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_apb_access = new();
    cg_spi_command = new();
    cg_clk_div = new();
    cg_xip = new();
  endfunction

  virtual function void write(apb_master_transaction t);
    apb_addr  = t.addr;
    apb_write = t.write;
    cg_apb_access.sample();

    // Sample command fields on SPI_CMD writes
    if (t.write && t.addr == QSPI_SPI_CMD_ADDR) begin
      spi_opcode   = t.wdata[SPI_CMD_CMD_MSB:SPI_CMD_CMD_LSB];
      dummy_cycles = t.wdata[SPI_CMD_DUMMY_MSB:SPI_CMD_DUMMY_LSB];
      n_rw_bytes   = t.wdata[SPI_CMD_N_RW_MSB:SPI_CMD_N_RW_LSB];
      cg_spi_command.sample();
    end

    // Sample CTRL writes
    if (t.write && t.addr == QSPI_CTRL_ADDR) begin
      qio_mode   = t.wdata[CTRL_QIO_MODE_BIT];
      xip_active = t.wdata[CTRL_XIP_ACTIVE_BIT];
      cg_xip.sample();
    end

    // Sample CLK_DIV writes
    if (t.write && t.addr == QSPI_CLK_DIV_ADDR) begin
      clk_div = t.wdata[4:0];
      cg_clk_div.sample();
    end
  endfunction

endclass

`endif // GUARD_AHB_QSPI_COVERAGE_SV
