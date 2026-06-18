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

#endif /* AHB_QSPI_QSPI_REGS_H */
