///////////////////////////////////////////////////////////////////////////////
// ahb_qspi_pkg.sv
///////////////////////////////////////////////////////////////////////////////
// UVM package for AHB QSPI testbench.
// Contains register map constants, configuration, and all class includes.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_QSPI_PKG_SV
`define GUARD_AHB_QSPI_PKG_SV

package ahb_qspi_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ===========================================================================
  // APB Register Map — byte addresses (from apb_qspi_regs.v)
  // PADDR[11:2] used as word address internally; byte offsets shown here
  // ===========================================================================

  // Control and status
  parameter QSPI_CTRL_ADDR       = 16'h0000;  // reg0: QIO_MODE, XIP_ACTIVE, MODE_CODE, CONT_READ, NO_CMD
  parameter QSPI_STATUS_ADDR     = 16'h0004;  // reg1: BUSY[0], IRQ_CLR[8]
  parameter QSPI_SPI_CMD_ADDR    = 16'h0008;  // reg2: CMD[7:0], ENABLE[8], READ[9], WRITE[10], ADDR_EN[11], DUMMY[15:12], N_RW[19:16]
  parameter QSPI_ADDR_ADDR       = 16'h000C;  // reg3: ADDR[21:0]

  // Read data (RO, byte-swapped from QSPI controller)
  parameter QSPI_RDATA0_ADDR     = 16'h0010;  // reg4
  parameter QSPI_RDATA1_ADDR     = 16'h0014;  // reg5
  parameter QSPI_RDATA2_ADDR     = 16'h0018;  // reg6
  parameter QSPI_RDATA3_ADDR     = 16'h001C;  // reg7

  // Write data (RW, nibble-swapped before QSPI controller)
  parameter QSPI_WDATA0_ADDR     = 16'h0020;  // reg8
  parameter QSPI_WDATA1_ADDR     = 16'h0024;  // reg9
  parameter QSPI_WDATA2_ADDR     = 16'h0028;  // reg10
  parameter QSPI_WDATA3_ADDR     = 16'h002C;  // reg11

  // AHB interface config
  parameter QSPI_AHB_SETUP_ADDR  = 16'h0030;  // reg12: AHB_CMD[7:0], AHB_DUMMY[15:12]
  parameter QSPI_CLK_DIV_ADDR    = 16'h0034;  // reg13: CLK_DIV[4:0]

  // Peripheral ID registers (RO)
  parameter QSPI_PIDR4_ADDR      = 16'h0FD0;
  parameter QSPI_PIDR5_ADDR      = 16'h0FD4;
  parameter QSPI_PIDR6_ADDR      = 16'h0FD8;
  parameter QSPI_PIDR7_ADDR      = 16'h0FDC;
  parameter QSPI_PIDR0_ADDR      = 16'h0FE0;
  parameter QSPI_PIDR1_ADDR      = 16'h0FE4;
  parameter QSPI_PIDR2_ADDR      = 16'h0FE8;
  parameter QSPI_PIDR3_ADDR      = 16'h0FEC;

  // Component ID registers (RO)
  parameter QSPI_CIDR0_ADDR      = 16'h0FF0;
  parameter QSPI_CIDR1_ADDR      = 16'h0FF4;
  parameter QSPI_CIDR2_ADDR      = 16'h0FF8;
  parameter QSPI_CIDR3_ADDR      = 16'h0FFC;

  // ===========================================================================
  // Expected ID Values
  // ===========================================================================
  parameter EXP_PIDR0 = 8'h59;
  parameter EXP_PIDR1 = 8'h16;
  parameter EXP_PIDR2 = 8'h15;
  parameter EXP_PIDR3 = 8'h00;
  parameter EXP_PIDR4 = 8'h00;
  parameter EXP_CIDR0 = 8'h50;
  parameter EXP_CIDR1 = 8'h51;
  parameter EXP_CIDR2 = 8'h4C;
  parameter EXP_CIDR3 = 8'h53;

  // ===========================================================================
  // CTRL register field masks
  // ===========================================================================
  parameter CTRL_QIO_MODE_BIT    = 0;
  parameter CTRL_XIP_ACTIVE_BIT  = 8;
  parameter CTRL_MODE_CODE_LSB   = 16;
  parameter CTRL_MODE_CODE_MSB   = 23;
  parameter CTRL_CONT_READ_BIT   = 24;
  parameter CTRL_NO_CMD_BIT      = 25;

  // ===========================================================================
  // STATUS register field masks
  // ===========================================================================
  parameter STATUS_BUSY_BIT      = 0;
  parameter STATUS_IRQ_CLR_BIT   = 8;

  // ===========================================================================
  // SPI_CMD register field masks
  // ===========================================================================
  parameter SPI_CMD_CMD_MSB      = 7;
  parameter SPI_CMD_CMD_LSB      = 0;
  parameter SPI_CMD_ENABLE_BIT   = 8;
  parameter SPI_CMD_READ_BIT     = 9;
  parameter SPI_CMD_WRITE_BIT    = 10;
  parameter SPI_CMD_ADDR_EN_BIT  = 11;
  parameter SPI_CMD_DUMMY_LSB    = 12;
  parameter SPI_CMD_DUMMY_MSB    = 15;
  parameter SPI_CMD_N_RW_LSB     = 16;
  parameter SPI_CMD_N_RW_MSB     = 19;

  // ===========================================================================
  // Common SPI Flash Opcodes (SST26VF064B)
  // ===========================================================================
  parameter SPI_OP_READ          = 8'h03;
  parameter SPI_OP_FAST_READ     = 8'h0B;
  parameter SPI_OP_RSTEN         = 8'h66;
  parameter SPI_OP_RST           = 8'h99;
  parameter SPI_OP_EQIO          = 8'h38;
  parameter SPI_OP_RSTQIO        = 8'hFF;
  parameter SPI_OP_RDSR          = 8'h05;
  parameter SPI_OP_WRSR          = 8'h01;
  parameter SPI_OP_WREN          = 8'h06;
  parameter SPI_OP_WRDI          = 8'h04;
  parameter SPI_OP_JEDEC_ID      = 8'h9F;
  parameter SPI_OP_QUAD_JEDEC_ID = 8'hAF;
  parameter SPI_OP_PP            = 8'h02;
  parameter SPI_OP_SE            = 8'h20;
  parameter SPI_OP_BE            = 8'hD8;
  parameter SPI_OP_CE            = 8'hC7;
  parameter SPI_OP_ULBPR         = 8'h98;

  // ===========================================================================
  // SST26VF064B Expected JEDEC ID
  // After byte-swap in RDATA0: {capacity, type, mfg, 0x00}
  // ===========================================================================
  parameter FLASH_MFG_ID         = 8'hBF;   // Microchip/SST
  parameter FLASH_DEV_TYPE       = 8'h26;
  parameter FLASH_DEV_ID         = 8'h43;   // 64Mbit
  parameter FLASH_JEDEC_RDATA0   = 32'h4326BF00; // Expected RDATA0 value for 3-byte JEDEC read

  // ===========================================================================
  // Reset values
  // ===========================================================================
  parameter REG0_RESET  = 32'h0000_0000;
  parameter REG1_RESET  = 32'h0000_0000;
  parameter REG2_RESET  = 32'h0000_0000;
  parameter REG3_RESET  = 32'h0000_0000;
  parameter REG12_RESET = 32'h0000_0000;
  parameter REG13_RESET = 32'h0000_0001;

  // ===========================================================================
  // Class includes
  // ===========================================================================

  // APB master agent
  `include "apb_master_transaction.sv"
  `include "apb_master_driver.sv"
  `include "apb_master_monitor.sv"
  `include "apb_master_sequencer.sv"
  `include "apb_master_agent.sv"

  // QSPI monitor
  `include "qspi_transaction.sv"
  `include "qspi_monitor.sv"

  // Cache tag RAM observation counters, populated by the cache_tag_probe
  // module (CACHE_MODEL=asic builds only) and read by ahb_qspi_cache_tag_test.
  // These live here as package statics rather than as probe members because
  // SystemVerilog forbids hierarchical references from inside a package, so
  // the probe has to push to the test rather than the test pull from it.
  class cache_tag_stats;
    static int unsigned tag_reads   = 0;
    static int unsigned tag_x_reads = 0;
    static int unsigned hit_events  = 0;
    static int unsigned miss_events = 0;
  endclass

  // Environment
  `include "ahb_qspi_scoreboard.sv"
  `include "ahb_qspi_coverage.sv"
  `include "ahb_qspi_env.sv"

  // Sequences
  `include "apb_read_sequence.sv"
  `include "apb_write_sequence.sv"
  `include "qspi_cmd_sequence.sv"
  `include "qspi_init_sequence.sv"
  `include "qspi_xip_sequence.sv"
  `include "qspi_stress_sequence.sv"
  `include "qspi_data_integrity_sequence.sv"
  `include "qspi_corner_case_sequence.sv"

  // Tests
  `include "ahb_qspi_base_test.sv"
  `include "ahb_qspi_register_test.sv"
  `include "ahb_qspi_spi_cmd_test.sv"
  `include "ahb_qspi_qpi_cmd_test.sv"
  `include "ahb_qspi_xip_test.sv"
  `include "ahb_qspi_error_test.sv"
  `include "ahb_qspi_clkdiv_test.sv"
  `include "ahb_qspi_irq_test.sv"
  `include "ahb_qspi_arb_test.sv"
  `include "ahb_qspi_reset_test.sv"
  `include "ahb_qspi_stress_test.sv"
  `include "ahb_qspi_data_integrity_test.sv"
  `include "ahb_qspi_corner_case_test.sv"
  `include "ahb_qspi_rdata_readonly_test.sv"
  `include "ahb_qspi_xip_stress_test.sv"
  `include "ahb_qspi_reset_recovery_test.sv"
  `include "ahb_qspi_cache_tag_test.sv"
  `include "ahb_qspi_debug_test.sv"

endpackage

`endif // GUARD_AHB_QSPI_PKG_SV
