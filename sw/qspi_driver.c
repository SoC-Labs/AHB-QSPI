/*
 *-----------------------------------------------------------------------------
 * ahb_qspi - portable C driver for the AHB QSPI controller (implementation)
 *
 * See qspi_driver.h for the API and the quirk catalogue. All hardware quirks
 * are documented inline at the point a consumer would otherwise be surprised.
 *
 * A joint work commissioned on behalf of SoC Labs, under Arm Academic
 * Access license.
 *
 * Copyright (C) 2026, SoC Labs (www.soclabs.org)
 *-----------------------------------------------------------------------------
 */

#include "qspi_driver.h"

/* Address helpers built on the configurable base (qspi_regs.h). */
#define QSPI_R(off)   QSPI_REG32(QSPI_APB_BASE + (off))

/* A data-synchronisation barrier where available. The cmsdk_ahb_to_apb bridge
 * can drop back-to-back writes on a fast in-order M0+ unless the prior write is
 * fenced; a register read-back + dsb makes the CMD land before we poll BUSY.
 * Fall back to a compiler barrier on non-ARM hosts (host-compile of tests). */
#if defined(__arm__) || defined(__thumb__) || defined(__ARM_ARCH)
#  define QSPI_DSB()  __asm volatile("dsb" ::: "memory")
#else
#  define QSPI_DSB()  __asm volatile("" ::: "memory")
#endif

/* ------------------------------------------------------------------------- */

int qspi_wait_idle(void)
{
    /* Fence the prior SPI_CMD write: read it back + barrier so the cmsdk APB
     * bridge has definitely accepted it before we sample BUSY. */
    (void)QSPI_R(QSPI_SPI_CMD_OFFSET);
    QSPI_DSB();

    /* QUIRK (BUSY 2-FF CDC race): BUSY is driven through ENABLE 3-FF into the
     * SCLK domain -> nCS -> BUSY 2-FF back into PCLK (~6-8 HCLK), so it is NOT
     * yet 1 in the cycles right after the CMD write. A bare `while(BUSY)` can
     * fall straight through and the caller then reads RDATA0 -- a comb view of
     * a reset-to-0 capture latch -- as 0x000000. So wait for BUSY to SET first,
     * THEN wait for it to clear. Both loops bounded so a wedged/absent
     * controller cannot hang the caller. */
    uint32_t g = 0;
    while (!(QSPI_R(QSPI_STATUS_OFFSET) & QSPI_STATUS_BUSY)
           && ++g < QSPI_BUSY_SET_POLLS) {
        /* spin: waiting for BUSY to assert */
    }

    uint32_t c = 0;
    while ((QSPI_R(QSPI_STATUS_OFFSET) & QSPI_STATUS_BUSY)
           && ++c < QSPI_BUSY_CLEAR_POLLS) {
        /* spin: waiting for BUSY to deassert */
    }

    /* W1C the QSPI-finished IRQ so the next command starts clean. */
    QSPI_R(QSPI_STATUS_OFFSET) = QSPI_STATUS_IRQ_CLR;

    return (c >= QSPI_BUSY_CLEAR_POLLS) ? -1 : 0;
}

void qspi_set_clk_div(uint32_t div)
{
    QSPI_R(QSPI_CLK_DIV_OFFSET) = div & QSPI_CLK_DIV_Msk;
}

void qspi_cmd_only(uint8_t opcode)
{
    /* Two-write strobe: descriptor, then descriptor|ENABLE. ENABLE auto-clears
     * in HW on QSPI_ENABLE_ACK. */
    uint32_t d = ((uint32_t)opcode << QSPI_CMD_OPCODE_Pos);
    QSPI_R(QSPI_SPI_CMD_OFFSET) = d;
    QSPI_R(QSPI_SPI_CMD_OFFSET) = d | QSPI_CMD_ENABLE;
    (void)qspi_wait_idle();
}

uint32_t qspi_cmd_read(uint8_t opcode, uint8_t n_bytes)
{
    if (n_bytes == 0u) { n_bytes = 1u; }
    if (n_bytes > 16u) { n_bytes = 16u; }

    uint32_t d = ((uint32_t)opcode << QSPI_CMD_OPCODE_Pos)
               | QSPI_CMD_READ
               | (((uint32_t)(n_bytes - 1u) << QSPI_CMD_NRW_Pos) & QSPI_CMD_NRW_Msk);
    QSPI_R(QSPI_SPI_CMD_OFFSET) = d;
    QSPI_R(QSPI_SPI_CMD_OFFSET) = d | QSPI_CMD_ENABLE;
    if (qspi_wait_idle()) { return 0u; }

    uint32_t raw = QSPI_R(QSPI_RDATA0_OFFSET);

    /* QUIRK (top-lane packing): for a sub-word read (N < 4) the controller
     * LEFT-justifies the captured bytes into the TOP of RDATA0 -- a 1-byte read
     * (RDSR/RDID byte) lands in bits[31:24], with the low bytes as zero
     * padding. Reading RDATA0 raw and masking bit 0 would always see 0 (WIP
     * reads "done" instantly, WEL reads "clear" forever -- masquerading as
     * "writes never take effect"). Shift the captured bytes down so callers can
     * mask from bit 0. A 4-byte read is already bit-0 aligned (no-op). */
    if (n_bytes < 4u) {
        raw >>= 8u * (4u - n_bytes);
    }
    return raw;
}

void qspi_cmd_read_addr(uint8_t opcode, uint32_t addr, uint8_t n_bytes,
                        uint8_t dummy, uint32_t out[4])
{
    if (n_bytes == 0u) { n_bytes = 1u; }
    if (n_bytes > 16u) { n_bytes = 16u; }

    QSPI_R(QSPI_SPI_ADDR_OFFSET) = addr & QSPI_ADDR_Msk;

    /* QUIRK (dummy = count - 1): DUMMY_CYCLES is an (N-1) field. dummy==0 means
     * "no dummy phase"; for any non-zero count we program (count - 1). FAST_READ
     * callers pass QSPI_FAST_READ_DUMMY (9, the +1-compensated value). */
    uint32_t dummy_field = 0u;
    if (dummy != 0u) {
        dummy_field = ((uint32_t)(dummy - 1u) << QSPI_CMD_DUMMY_Pos) & QSPI_CMD_DUMMY_Msk;
    }

    uint32_t d = ((uint32_t)opcode << QSPI_CMD_OPCODE_Pos)
               | QSPI_CMD_READ | QSPI_CMD_ADDR_EN
               | dummy_field
               | (((uint32_t)(n_bytes - 1u) << QSPI_CMD_NRW_Pos) & QSPI_CMD_NRW_Msk);
    QSPI_R(QSPI_SPI_CMD_OFFSET) = d;
    QSPI_R(QSPI_SPI_CMD_OFFSET) = d | QSPI_CMD_ENABLE;
    if (qspi_wait_idle()) {
        out[0] = out[1] = out[2] = out[3] = 0u;
        return;
    }

    out[0] = QSPI_R(QSPI_RDATA0_OFFSET);
    out[1] = QSPI_R(QSPI_RDATA1_OFFSET);
    out[2] = QSPI_R(QSPI_RDATA2_OFFSET);
    out[3] = QSPI_R(QSPI_RDATA3_OFFSET);
}

void qspi_cmd_write_addr(uint8_t opcode, uint32_t addr, uint8_t n_bytes,
                         const uint8_t *data)
{
    if (n_bytes == 0u) { return; }
    if (n_bytes > 16u) { n_bytes = 16u; }

    uint32_t w[4] = { 0u, 0u, 0u, 0u };
    for (uint8_t i = 0u; i < n_bytes; ++i) {
        w[i / 4u] |= ((uint32_t)data[i]) << ((i % 4u) * 8u);
    }
    QSPI_R(QSPI_WDATA0_OFFSET) = w[0];
    QSPI_R(QSPI_WDATA1_OFFSET) = w[1];
    QSPI_R(QSPI_WDATA2_OFFSET) = w[2];
    QSPI_R(QSPI_WDATA3_OFFSET) = w[3];
    QSPI_R(QSPI_SPI_ADDR_OFFSET) = addr & QSPI_ADDR_Msk;

    uint32_t d = ((uint32_t)opcode << QSPI_CMD_OPCODE_Pos)
               | QSPI_CMD_WRITE | QSPI_CMD_ADDR_EN
               | (((uint32_t)(n_bytes - 1u) << QSPI_CMD_NRW_Pos) & QSPI_CMD_NRW_Msk);
    QSPI_R(QSPI_SPI_CMD_OFFSET) = d;
    QSPI_R(QSPI_SPI_CMD_OFFSET) = d | QSPI_CMD_ENABLE;
    (void)qspi_wait_idle();
}

uint32_t qspi_read_jedec(void)
{
    /* RDID returns 3 bytes; qspi_cmd_read corrects the top-lane packing so the
     * result is mfr<<16 | type<<8 | density. */
    return qspi_cmd_read(QSPI_OP_RDID, 3u);
}

int qspi_wait_wip(uint32_t max_polls)
{
    if (max_polls == 0u) { max_polls = QSPI_BUSY_CLEAR_POLLS; }
    for (uint32_t i = 0u; i < max_polls; ++i) {
        uint32_t sr = qspi_cmd_read(QSPI_OP_RDSR, 1u);
        if ((sr & QSPI_SR_WIP) == 0u) {
            return 0;
        }
    }
    return -1;
}

void qspi_flash_recover(void (*delay_us)(uint32_t us))
{
    /* A SoC/FPGA/fpga_manager reset does NOT reset the flash chip; only a flash
     * power-cycle or an explicit reset sequence does. After any warm reset the
     * first access hits whatever mode the previous firmware left the flash in.
     * This sequence is order-independent and idempotent (a direct port of the
     * proven on-silicon hardware_preamble). All opcodes are JEDEC-standard. */

    qspi_set_clk_div(5u);            /* HCLK/10 -- safe; div=1 garbles RDID    */
    QSPI_R(QSPI_CTRL_OFFSET) = 0u;   /* SPI framing, XiP off                    */

    /* 1. Release from Deep Power-Down. A soft reset CANNOT wake DPD; only 0xAB
     *    does. Twice, with tRDP settle (~30 us on N25Q256; 50 us for margin). */
    qspi_cmd_only(QSPI_OP_RDPD);
    if (delay_us) { delay_us(50u); }
    qspi_cmd_only(QSPI_OP_RDPD);
    if (delay_us) { delay_us(50u); }

    /* 2. QPI framing: absorb any continuous-read trap / RSTQIO, then RSTEN+RST
     *    while still in QPI so a QPI-mode part decodes them. */
    QSPI_R(QSPI_CTRL_OFFSET) = QSPI_CTRL_QIO_MODE;
    qspi_cmd_only(QSPI_OP_RSTQIO);   /* 0xFF: exit cont-read / reset QPI        */
    qspi_cmd_only(QSPI_OP_RSTQIO);
    qspi_cmd_only(QSPI_OP_RSTEN);    /* 0x66 + 0x99: RSTEN + RST in QPI         */
    qspi_cmd_only(QSPI_OP_RST);

    /* 3. SPI framing: definitive RSTEN + RST. */
    QSPI_R(QSPI_CTRL_OFFSET) = 0u;
    qspi_cmd_only(QSPI_OP_RSTEN);
    qspi_cmd_only(QSPI_OP_RST);
    if (delay_us) { delay_us(100u); } /* tRST settle                            */

    /* Quiesce. */
    QSPI_R(QSPI_SPI_CMD_OFFSET)  = 0u;
    QSPI_R(QSPI_SPI_ADDR_OFFSET) = 0u;
}

void qspi_xip_enable(void)
{
    /* The controller resets with AHB_SPI_SETUP=0 / XIP_ACTIVE=0, so program
     * FAST_READ (0x0B) + dummy into AHB_SPI_SETUP, then set CTRL.XIP_ACTIVE.
     * AHB_DUMMY_CYCLES is an (N-1) field, same +1-compensation as the APB path
     * (true 9 -> programmed 8), so the encoded value is (QSPI_FAST_READ_DUMMY-1)
     * which yields the familiar 0x0000800B for the default. */
    uint32_t setup = ((uint32_t)QSPI_OP_FAST_READ << QSPI_AHB_CMD_Pos)
                   | (((uint32_t)(QSPI_FAST_READ_DUMMY - 1u) << QSPI_AHB_DUMMY_Pos)
                      & QSPI_AHB_DUMMY_Msk);
    QSPI_R(QSPI_AHB_SPI_SETUP_OFFSET) = setup;
    (void)QSPI_R(QSPI_AHB_SPI_SETUP_OFFSET);   /* read-back barrier (APB bridge) */

    QSPI_R(QSPI_CTRL_OFFSET) = QSPI_CTRL_XIP_ACTIVE;
    (void)QSPI_R(QSPI_CTRL_OFFSET);            /* drain */

    /* Prime the first cached read: the AHB wait-state self-synchronises until
     * the cache/controller serves data. */
    (void)QSPI_REG32(QSPI_XIP_BASE);

    /* CAVEAT (privileged CG092 cache CCR): the CG092 flash cache CCR registers
     * (APB 0x1000-0x1FFF) require a privileged APB master (PPROT[0]=1) to
     * write. In the current SoC map firmware CANNOT reach them, so the cache
     * runs with its reset config -- functional but not firmware-tunable. Do NOT
     * add CCR pokes here expecting them to take; they silently no-op. See
     * CG092_bus_logic_bug_report.md. */
}

void qspi_xip_disable(void)
{
    QSPI_R(QSPI_CTRL_OFFSET) &= ~QSPI_CTRL_XIP_ACTIVE;
    (void)QSPI_R(QSPI_CTRL_OFFSET);            /* drain */
}

void qspi_unlock_global(void)
{
    /* SST26 ships all blocks protected; ULBPR clears the WRITE-protection so
     * erase/program take effect. N25Q treats 0x98 as an unknown opcode (no-op),
     * so this is safe on both. Requires WEL -> issue WREN first. */
    qspi_cmd_only(QSPI_OP_WREN);
    qspi_cmd_only(QSPI_OP_ULBPR);
}

int qspi_sector_erase(uint32_t addr)
{
    qspi_cmd_only(QSPI_OP_WREN);

    QSPI_R(QSPI_SPI_ADDR_OFFSET) = addr & QSPI_ADDR_Msk;
    uint32_t d = ((uint32_t)QSPI_OP_SE_64K << QSPI_CMD_OPCODE_Pos)
               | QSPI_CMD_ADDR_EN;
    QSPI_R(QSPI_SPI_CMD_OFFSET) = d;
    QSPI_R(QSPI_SPI_CMD_OFFSET) = d | QSPI_CMD_ENABLE;
    (void)qspi_wait_idle();

    return qspi_wait_wip(0u);   /* typ ~700 ms per N25Q256A datasheet */
}

int qspi_page_program(uint32_t addr, const uint8_t *data, uint8_t n_bytes)
{
    qspi_cmd_only(QSPI_OP_WREN);
    qspi_cmd_write_addr(QSPI_OP_PP, addr, n_bytes, data);
    return qspi_wait_wip(0u);
}
