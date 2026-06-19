/*
 *-----------------------------------------------------------------------------
 * ahb_qspi - QSPI controller register map (single source of truth)
 *
 * Register offsets and bitfield masks for the AHB QSPI controller's APB
 * register block, transcribed verbatim from src/rdl/apb_qspi_regs.rdl. This
 * header is the ONE place these constants live: firmware that pokes the
 * controller should include this instead of re-defining offsets locally (which
 * is how the FAST_READ-dummy / RDSR-lane drift crept into the scattered copies
 * across the SoC firmware tree).
 *
 * Portable / dependency-free: only <stdint.h>. The register base is
 * configurable via QSPI_APB_BASE (default 0x21000000) and the XiP read-window
 * via QSPI_XIP_BASE so a consuming SoC can override them on the compiler
 * command line (-DQSPI_APB_BASE=0x...) without editing this file.
 *
 * A joint work commissioned on behalf of SoC Labs, under Arm Academic
 * Access license.
 *
 * Copyright (C) 2026, SoC Labs (www.soclabs.org)
 *-----------------------------------------------------------------------------
 */
#ifndef AHB_QSPI_QSPI_REGS_H
#define AHB_QSPI_QSPI_REGS_H

#include <stdint.h>

/* -------------------------------------------------------------------------
 * Base addresses (override on the command line for a specific SoC map).
 * QSPI_APB_BASE  - the APB register block (this register map).
 * QSPI_XIP_BASE  - the read-only AHB execute-in-place window (cache-served
 *                  flash reads once CTRL.XIP_ACTIVE is set).
 * ------------------------------------------------------------------------- */
#ifndef QSPI_APB_BASE
#define QSPI_APB_BASE  0x21000000UL
#endif

#ifndef QSPI_XIP_BASE
#define QSPI_XIP_BASE  0x24000000UL
#endif

/* QSPI_CACHE_BASE - the CG092 flash-cache CONFIG/STATUS (CCR/SR) APB block.
 * It sits at offset +0x1000 within the QSPI APB aperture (the controller's own
 * registers occupy +0x000..0x0FF). Derived from QSPI_APB_BASE by default so a
 * consumer that overrides the APB base gets the cache block for free; can be
 * overridden independently (-DQSPI_CACHE_BASE=0x...) for a standalone block.
 *
 * In the nanoSoC SoC (QSPI_APB_BASE=0x21000000) this resolves to the system
 * addresses:
 *     CONFIG (CCR) -> 0x21001000
 *     STATUS (SR)  -> 0x21001004
 */
#ifndef QSPI_CACHE_BASE
#define QSPI_CACHE_BASE  (QSPI_APB_BASE + 0x1000UL)
#endif

/* Generic 32-bit MMIO accessor. A consumer that already has a register
 * accessor can predefine QSPI_REG32 before including this header. */
#ifndef QSPI_REG32
#define QSPI_REG32(a)  (*(volatile uint32_t *)(uintptr_t)(a))
#endif

/* -------------------------------------------------------------------------
 * Register offsets (from apb_qspi_regs.rdl). All 32-bit word-aligned.
 * ------------------------------------------------------------------------- */
#define QSPI_CTRL_OFFSET          0x0000u
#define QSPI_STATUS_OFFSET        0x0004u
#define QSPI_SPI_CMD_OFFSET       0x0008u
#define QSPI_SPI_ADDR_OFFSET      0x000Cu
#define QSPI_RDATA0_OFFSET        0x0010u
#define QSPI_RDATA1_OFFSET        0x0014u
#define QSPI_RDATA2_OFFSET        0x0018u
#define QSPI_RDATA3_OFFSET        0x001Cu
#define QSPI_WDATA0_OFFSET        0x0020u
#define QSPI_WDATA1_OFFSET        0x0024u
#define QSPI_WDATA2_OFFSET        0x0028u
#define QSPI_WDATA3_OFFSET        0x002Cu
#define QSPI_AHB_SPI_SETUP_OFFSET 0x0030u
#define QSPI_CLK_DIV_OFFSET       0x0034u

/* Peripheral / component ID (read-only, for presence checks). */
#define QSPI_PIDR0_OFFSET         0x0FE0u  /* part number [7:0]  = 0x59 */
#define QSPI_PIDR1_OFFSET         0x0FE4u  /* part [11:8], designer[3:0] = 0x16 */
#define QSPI_PIDR2_OFFSET         0x0FE8u  /* designer[6:4], rev[7:4]    = 0x15 */
#define QSPI_CIDR0_OFFSET         0x0FF0u  /* 0x0D preamble = 0x50 */

/* -------------------------------------------------------------------------
 * CTRL (0x00)
 * ------------------------------------------------------------------------- */
#define QSPI_CTRL_QIO_MODE        (1u << 0)   /* quad I/O framing                 */
#define QSPI_CTRL_XIP_ACTIVE      (1u << 8)   /* AHB owns the bus (XiP reads)     */
#define QSPI_CTRL_MODE_CODE_Pos   16          /* [23:16] continuous-read mode byte */
#define QSPI_CTRL_MODE_CODE_Msk   (0xFFu << QSPI_CTRL_MODE_CODE_Pos)
#define QSPI_CTRL_CONT_READ       (1u << 25)  /* send mode byte after address     */
#define QSPI_CTRL_NO_CMD          (1u << 26)  /* skip opcode phase (cont-read)    */

/* -------------------------------------------------------------------------
 * STATUS (0x04)
 *   BUSY is hw-write/sw-read; IRQ_CLR is write-1-to-clear.
 * ------------------------------------------------------------------------- */
#define QSPI_STATUS_BUSY          (1u << 0)
#define QSPI_STATUS_IRQ_CLR       (1u << 8)   /* W1C the QSPI-finished IRQ        */

/* -------------------------------------------------------------------------
 * SPI_CMD (0x08) - write to configure + trigger an APB-initiated transaction.
 *   CMD          [7:0]   opcode
 *   ENABLE       [8]     strobe (auto-clears in HW on QSPI_ENABLE_ACK)
 *   READ         [9]     include a data-in phase
 *   WRITE        [10]    include a data-out phase
 *   ADDR_EN      [11]    include the address phase
 *   DUMMY_CYCLES [15:12] dummy cycles, encoded as (count - 1); 0 = none
 *   N_RW_BYTES   [19:16] data bytes, encoded as (count - 1); range 1..16
 * ------------------------------------------------------------------------- */
#define QSPI_CMD_OPCODE_Pos       0
#define QSPI_CMD_OPCODE_Msk       (0xFFu << QSPI_CMD_OPCODE_Pos)
#define QSPI_CMD_ENABLE           (1u << 8)
#define QSPI_CMD_READ             (1u << 9)
#define QSPI_CMD_WRITE            (1u << 10)
#define QSPI_CMD_ADDR_EN          (1u << 11)
#define QSPI_CMD_DUMMY_Pos        12          /* value = (dummy_cycles - 1)       */
#define QSPI_CMD_DUMMY_Msk        (0xFu << QSPI_CMD_DUMMY_Pos)
#define QSPI_CMD_NRW_Pos          16          /* value = (n_bytes - 1)            */
#define QSPI_CMD_NRW_Msk          (0xFu << QSPI_CMD_NRW_Pos)

/* -------------------------------------------------------------------------
 * SPI_ADDR (0x0C) - 22-bit flash byte address (bits [21:0]).
 * ------------------------------------------------------------------------- */
#define QSPI_ADDR_Msk             0x003FFFFFu

/* -------------------------------------------------------------------------
 * AHB_SPI_SETUP (0x30) - opcode + dummy cycles used for AHB (XiP) cache fills.
 *   AHB_CMD          [7:0]   opcode (typically 0x0B FAST_READ or 0xEB SQI)
 *   AHB_DUMMY_CYCLES [15:12] dummy cycles encoded as (count - 1)
 * ------------------------------------------------------------------------- */
#define QSPI_AHB_CMD_Pos          0
#define QSPI_AHB_CMD_Msk          (0xFFu << QSPI_AHB_CMD_Pos)
#define QSPI_AHB_DUMMY_Pos        12          /* value = (dummy_cycles - 1)       */
#define QSPI_AHB_DUMMY_Msk        (0xFu << QSPI_AHB_DUMMY_Pos)

/* -------------------------------------------------------------------------
 * CLK_DIV (0x34) - QSPI_SCLK = HCLK / (2 * CLK_DIV); reset default 1 (HCLK/2).
 *   NOTE: CLK_DIV=1 garbles RDID on real silicon; use >= 2 for command mode.
 * ------------------------------------------------------------------------- */
#define QSPI_CLK_DIV_Msk          0x1Fu

/* =========================================================================
 * CG092 flash cache (CoreLink AHB Flash Cache) CONFIG/STATUS block.
 *
 * Register offsets + bit layout transcribed from the CG092 r2p0 RTL:
 *   $ARM_IP_LIBRARY_PATH/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/
 *     logical/p_flash_cache_f0/verilog/p_flash_cache_f0_gen_const_pkg.vh
 *       P_CCR_REG_OFFSET = 0x000, P_SR_REG_OFFSET = 0x004
 *       P_CCR_*_BIT_RESET (STATISTIC_EN resets 1; all others 0 -> CCR=0x40)
 *     .../p_flash_cache_f0_core.v (ip_rdata mux ~L1532 CCR, ~L1544 SR)
 *
 * Offsets are relative to QSPI_CACHE_BASE (QSPI_APB_BASE + 0x1000); see the
 * SoC system addresses 0x21001000 / 0x21001004 noted at QSPI_CACHE_BASE above.
 * The existing cocotb suite drives this exact block (verif/cocotb/
 * ahb_qspi_tests.py: CACHE_CONFIG_ADDR=0x1000, STATUS at +0x04, enable via
 * CONFIG=0x1 then poll until (STATUS & 0x3)==2).
 * ========================================================================= */
#define QSPI_CACHE_CONFIG_OFFSET  0x0000u   /* CCR - Cache Control Register */
#define QSPI_CACHE_STATUS_OFFSET  0x0004u   /* SR  - Status Register        */

/* -------------------------------------------------------------------------
 * CCR (CONFIG, +0x00). Reset value = 0x40 (only STATISTIC_EN resets set).
 *   Setting EN=1 with the CG092's auto-power (APOW) / auto-invalidate (AINV)
 *   defaults triggers the automatic power-up + invalidate; software then polls
 *   SR until CS==READY. Per CG092 RTL ip_rdata mux (p_flash_cache_f0_core.v).
 * ------------------------------------------------------------------------- */
#define QSPI_CACHE_CCR_EN         (1u << 0)   /* cache enable                     */
#define QSPI_CACHE_CCR_INV_REQ    (1u << 1)   /* manual invalidate in-progress/req */
#define QSPI_CACHE_CCR_POW_REQ    (1u << 2)   /* manual power request             */
#define QSPI_CACHE_CCR_MAN_POW    (1u << 3)   /* set manual-power mode            */
#define QSPI_CACHE_CCR_MAN_INV    (1u << 4)   /* set manual-invalidate mode       */
#define QSPI_CACHE_CCR_PREFETCH   (1u << 5)   /* set prefetch                     */
#define QSPI_CACHE_CCR_STAT_EN    (1u << 6)   /* statistics enable (resets to 1)  */
#define QSPI_CACHE_CCR_RESET      0x40u       /* reset value (STATISTIC_EN only)  */

/* -------------------------------------------------------------------------
 * SR (STATUS, +0x04). Read-only. CS[1:0] is the cache state machine; the cache
 * is usable once CS == READY. (CG092 RTL: ip_rdata[1:0]=sr_cs, [2]=inv_stat,
 * [4]=pow_stat; reset CS=0.)
 * ------------------------------------------------------------------------- */
#define QSPI_CACHE_SR_CS_Pos      0
#define QSPI_CACHE_SR_CS_Msk      (0x3u << QSPI_CACHE_SR_CS_Pos)
#define QSPI_CACHE_SR_INV_STAT    (1u << 2)   /* invalidate-status                */
#define QSPI_CACHE_SR_POW_STAT    (1u << 4)   /* power-status                     */
#define QSPI_CACHE_CS_DISABLED    0u          /* CS == 0: disabled / off          */
#define QSPI_CACHE_CS_READY       2u          /* CS == 2: enabled + ready         */

#endif /* AHB_QSPI_QSPI_REGS_H */
