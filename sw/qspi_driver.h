/*
 *-----------------------------------------------------------------------------
 * ahb_qspi - portable C driver for the AHB QSPI controller
 *
 * A dependency-free driver (only <stdint.h> + qspi_regs.h) that unifies the
 * ad-hoc QSPI register pokes previously duplicated across SoC firmware
 * (xip_bringup.h, qspi_flasher, qspi_selftest, stage0 bootroms). It encodes
 * the documented hardware quirks ONCE so consumers can't re-introduce drift:
 *
 *   - The STATUS.BUSY 2-FF CDC poll race: BUSY is NOT yet 1 in the cycles
 *     immediately after the SPI_CMD write (it crosses ENABLE 3-FF into SCLK,
 *     then nCS, then BUSY 2-FF back into PCLK). A bare `while(BUSY)` on a fast
 *     in-order M0+ core can fall straight through and read RDATA0 (a comb view
 *     of a reset-to-0 capture latch) as 0x000000. qspi_wait_idle() waits for
 *     BUSY to SET, then to CLEAR, both bounded.  See qspi_driver.c.
 *
 *   - Sub-word reads (N < 4) land LEFT-justified in the TOP byte lanes of
 *     RDATA0: an RDSR/RDID byte is in bits[31:24], not [7:0]. qspi_cmd_read()
 *     shifts it down so callers mask from bit 0.
 *
 *   - DUMMY_CYCLES / N_RW_BYTES are (count - 1) fields. FAST_READ (0x0B)
 *     nominally needs 8 dummy cycles but the controller is one cycle short on
 *     the read-data phase (bench-characterised on z2_01): use 9. The helpers
 *     take the *true* cycle count and subtract 1 internally.
 *
 *   - XiP enable + the privileged-CCR caveat: see qspi_xip_enable().
 *
 *   - Warm-boot recovery (DPD / QPI / continuous-read -> SPI idle): a flash
 *     chip keeps its mode across a SoC/FPGA reset. qspi_flash_recover().
 *
 * A joint work commissioned on behalf of SoC Labs, under Arm Academic
 * Access license.
 *
 * Copyright (C) 2026, SoC Labs (www.soclabs.org)
 *-----------------------------------------------------------------------------
 */
#ifndef AHB_QSPI_QSPI_DRIVER_H
#define AHB_QSPI_QSPI_DRIVER_H

#include <stdint.h>
#include "qspi_regs.h"

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------------
 * Tunables (override on the command line for a specific platform).
 * ------------------------------------------------------------------------- */

/* Bound for the "wait for BUSY to clear" loop. Chosen large enough for the
 * slowest command (sector erase polls WIP separately, not here) yet small
 * enough that an absent/wedged controller cannot hang a bootrom. */
#ifndef QSPI_BUSY_CLEAR_POLLS
#define QSPI_BUSY_CLEAR_POLLS   1000000u
#endif

/* Bound for the "wait for BUSY to set" loop. If BUSY's pulse is too short to
 * observe we simply fall through after this many polls -- by which point the
 * transaction has completed and RDATA is valid (no worse than the old code). */
#ifndef QSPI_BUSY_SET_POLLS
#define QSPI_BUSY_SET_POLLS     100000u
#endif

/* FAST_READ (0x0B) true dummy-cycle count. Controller is one short, so 9.
 * (Field encoding subtracts 1 -> programmed as 8.) */
#ifndef QSPI_FAST_READ_DUMMY
#define QSPI_FAST_READ_DUMMY    9u
#endif

/* Standard JEDEC SPI-NOR opcodes (Micron N25Q / SST26VF064B compatible). */
#define QSPI_OP_WREN      0x06u   /* write enable                              */
#define QSPI_OP_RDSR      0x05u   /* read status reg (bit0 = WIP)              */
#define QSPI_OP_RDID      0x9Fu   /* read JEDEC ID (3 bytes)                   */
#define QSPI_OP_PP        0x02u   /* page program (24-bit addr, <=256 B/CS)    */
#define QSPI_OP_READ      0x03u   /* slow read (24-bit addr)                   */
#define QSPI_OP_FAST_READ 0x0Bu   /* fast read (24-bit addr + dummy)           */
#define QSPI_OP_SE_64K    0xD8u   /* 64 KB sector/block erase                  */
#define QSPI_OP_SE_4K     0x20u   /* 4 KB sub-sector erase                     */
#define QSPI_OP_CE        0xC7u   /* chip erase                                */
#define QSPI_OP_ULBPR     0x98u   /* SST26 global block-protection unlock      */
#define QSPI_OP_RDPD      0xABu   /* release from deep power-down              */
#define QSPI_OP_RSTEN     0x66u   /* reset enable                              */
#define QSPI_OP_RST       0x99u   /* reset memory (exits XiP/cont-read/QPI)    */
#define QSPI_OP_RSTQIO    0xFFu   /* exit continuous-read / reset QPI          */

/* RDSR.WIP (write-in-progress) bit. */
#define QSPI_SR_WIP       (1u << 0)

/* -------------------------------------------------------------------------
 * Core controller operations.
 * ------------------------------------------------------------------------- */

/* Wait for the just-issued SPI command to complete. Fences the prior CMD
 * write, then waits BUSY set->clear (see CDC-race note above).
 * Returns 0 on success, -1 if the clear loop hit its bound (wedged/absent). */
int      qspi_wait_idle(void);

/* Set the serial clock divider (QSPI_SCLK = HCLK / (2*div)). Use >= 2 for
 * command mode (div=1 garbles RDID on silicon). */
void     qspi_set_clk_div(uint32_t div);

/* Issue an opcode-only command (no address, no data), e.g. WREN/RSTEN/RST.
 * Auto-clears ENABLE in HW; W1C the IRQ on completion. */
void     qspi_cmd_only(uint8_t opcode);

/* Issue a read of n_bytes (1..16) with NO address phase, e.g. RDSR (n=1) or
 * RDID (n=3). Returns the captured bytes right-justified from bit 0 (the
 * top-lane quirk is corrected here). */
uint32_t qspi_cmd_read(uint8_t opcode, uint8_t n_bytes);

/* Issue a read with an address phase and `dummy` *true* dummy cycles (0 to
 * skip). Loads RDATA0..3 (up to 16 bytes) into out[4] verbatim (caller treats
 * out as a byte stream). For FAST_READ pass QSPI_FAST_READ_DUMMY. */
void     qspi_cmd_read_addr(uint8_t opcode, uint32_t addr, uint8_t n_bytes,
                            uint8_t dummy, uint32_t out[4]);

/* Issue a write (page-program style) with an address phase. Loads WDATA0..3
 * from the n_bytes (1..16) byte stream. Caller must WREN first and poll WIP
 * after (qspi_wait_wip). */
void     qspi_cmd_write_addr(uint8_t opcode, uint32_t addr, uint8_t n_bytes,
                             const uint8_t *data);

/* Read the 24-bit JEDEC ID (mfr<<16 | type<<8 | density), or 0 on timeout.
 * Use as a boot go/no-go gate (0x000000 / 0xFFFFFF = flash not responding). */
uint32_t qspi_read_jedec(void);

/* Poll the flash's internal WIP bit until the program/erase finishes.
 * Bounded by `max_polls` (each poll is a full RDSR transaction); pass 0 for
 * the default. Returns 0 on WIP clear, -1 on timeout. */
int      qspi_wait_wip(uint32_t max_polls);

/* -------------------------------------------------------------------------
 * Higher-level flows.
 * ------------------------------------------------------------------------- */

/* Bring the external SPI-NOR back to a known SPI/idle state regardless of the
 * mode a previous run/boot left it in (DPD / continuous-read / QPI). A SoC or
 * FPGA reset does NOT reset the flash chip, so call this once, early, before
 * any JEDEC probe or XiP enable on a warm-resettable system. Idempotent.
 *
 * delay_us may be NULL (recovery still works in sim/most HW); supply a real
 * microsecond delay on silicon to honour tRDP/tRST settling. */
void     qspi_flash_recover(void (*delay_us)(uint32_t us));

/* Enable the CG092-cached AHB XiP read path: program FAST_READ into
 * AHB_SPI_SETUP, set CTRL.XIP_ACTIVE, with read-back barriers (the cmsdk APB
 * bridge needs them) and a priming read. After this, reads from QSPI_XIP_BASE
 * are served by the cache. NOTE the privileged-CCR caveat in qspi_driver.c. */
void     qspi_xip_enable(void);

/* Take the controller out of XiP back to APB-command mode (clears XIP_ACTIVE).
 * Required before issuing any qspi_cmd_* (program/erase) again. */
void     qspi_xip_disable(void);

/* SST26-family ships all blocks protected; clear global block protection so
 * erase/program take effect. Safe no-op on Micron N25Q (unknown opcode).
 * Issues WREN then ULBPR. */
void     qspi_unlock_global(void);

/* Erase one 64 KB sector at `addr`. Does WREN + SE + WIP-poll. Returns 0 on
 * success, -1 if the WIP poll timed out. */
int      qspi_sector_erase(uint32_t addr);

/* Program up to 16 bytes within one 256-byte page. Does WREN + PP + WIP-poll.
 * Returns 0 on success, -1 on WIP timeout. */
int      qspi_page_program(uint32_t addr, const uint8_t *data, uint8_t n_bytes);

#ifdef __cplusplus
}
#endif

#endif /* AHB_QSPI_QSPI_DRIVER_H */
