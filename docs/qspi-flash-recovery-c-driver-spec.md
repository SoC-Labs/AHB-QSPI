# QSPI flash-recovery — C driver / boot spec (nanoSoC integration)

**Status:** specification + reference implementation. The AHB-QSPI block
is not yet instantiated in nanoSoC (see §6); this is what the software
side must do when it is. Derived from the proven, on-silicon
`cocotb_silicon`/`pynq` `hardware_preamble` (see
[`cocotb-silicon-findings.md`](cocotb-silicon-findings.md)).

---

## 1. Why this is needed

The SPI-NOR flash is an **independent chip with persistent mode state**
(Deep Power-Down, continuous-read, QPI, 4-byte-addr, erase/program
suspend). **A controller / SoC / FPGA / `fpga_manager` reset does NOT
reset the flash chip** — only a flash power-cycle or an explicit reset
sequence does. So after any **warm reset / watchdog / re-flash / second
boot without flash power-cycle**, the first XIP fetch or driver access
hits whatever mode the *previous* firmware left the flash in.

This was proven on hardware: `pynq_z2_01_pl`'s flash read `0xFFFFFF`
across five runs and looked "dead"; it was in **Deep Power-Down**. A
JEDEC-standard soft reset (`0x66`/`0x99`) **cannot** wake a flash from
DPD — only `0xAB` (Release from Deep Power-Down) does. After `0xAB`
the part returned a correct Micron ID + SFDP and full erase/program/
read-back worked.

**Applies to:** any warm-resettable system, and **especially XIP boot
from QSPI flash** (the bootrom must guarantee the flash is in a
readable SPI state before the first instruction fetch from
`0x70000000`).

**Not needed only if:** every boot is a guaranteed cold power-on of the
flash, *or* the flash `RESET#` pin is asserted by system reset. The
PmodSF3 / N25Q `RESET#` is muxed with `HOLD#`/`DQ3` and is generally
**not** a reliable hard reset in this design → assume it is needed.

## 2. BLOCKING prerequisite — register-map mismatch

The nanoSoC software currently models QSPI with a **placeholder** that
does not match the real controller. This must be corrected before the
recovery code (or any QSPI driver) can work.

| | nanoSoC placeholder (`CMSDK_CM0.h` `CMSDK_QSPI_TypeDef`, `nanosoc_qspi_ctrl.yaml`) | **Real controller** (`src/rdl/apb_qspi_regs.rdl`, `sys_desc/register_maps/apb_qspi_regs.yaml`) |
|---|---|---|
| 0x00 | `CTRL` | `CTRL` (bit0 `QIO_MODE`, bit8 `XIP_ACTIVE`, …) |
| 0x04 | `STATUS` | `STATUS` (bit0 `BUSY`; **write** bit8 = `IRQ_CLR`) |
| 0x08 | `CLK_DIV` ❌ | `SPI_CMD` (see §3) |
| 0x0C | `CMD` ❌ | `SPI_ADDR` |
| 0x10 | `ADDR` ❌ | `RDATA0` |
| 0x14 / 0x18 / 0x1C | `TX_DATA` / `RX_DATA` / `JEDEC_ID` ❌ | `RDATA1` / `RDATA2` / `RDATA3` |
| 0x20–0x2C | — | `WDATA0..3` |
| 0x30 | — | `AHB_SPI_SETUP` |
| 0x34 | — | `CLK_DIV` |

The existing `stage0_bootloader.c` `qspi_probe_jedec_id()` is written
against the placeholder (`->CMD`, `->JEDEC_ID`) and **will not function
against the real RTL**. Action: regenerate `CMSDK_QSPI_TypeDef` and
`nanosoc_qspi_ctrl.yaml` from `apb_qspi_regs.rdl` (single source of
truth), then port the bootloader QSPI path to it. The struct in §3 is
the correct target.

## 3. Correct register model (house style)

CMSIS volatile-struct overlay, matching the existing nanoSoC idiom
(`CMSDK_QSPI->FIELD`). Base = APB extension slot 12 = `0x4000C000`
(`CMSDK_QSPI_BASE`); read-only XIP window = `0x70000000`
(`NANOSOC_QSPI_MEM_BASE`).

```c
typedef struct {
    __IO uint32_t CTRL;          /* 0x00  bit0 QIO_MODE, bit8 XIP_ACTIVE   */
    __IO uint32_t STATUS;        /* 0x04  R: bit0 BUSY;  W: bit8 IRQ_CLR   */
    __IO uint32_t SPI_CMD;       /* 0x08  see SPI_CMD encoding below       */
    __IO uint32_t SPI_ADDR;      /* 0x0C  flash byte address               */
    __I  uint32_t RDATA[4];      /* 0x10..0x1C  received data words         */
    __O  uint32_t WDATA[4];      /* 0x20..0x2C  data to program             */
    __IO uint32_t AHB_SPI_SETUP; /* 0x30  XIP opcode|dummy                  */
    __IO uint32_t CLK_DIV;       /* 0x34  QSPI_SCLK = HCLK / (2*CLK_DIV)    */
} QSPI_TypeDef;

#define QSPI            ((QSPI_TypeDef *)0x4000C000UL)
#define QSPI_XIP_BASE   0x70000000UL

/* SPI_CMD (0x08) bit fields */
#define QSPI_CMD_OPCODE_Pos    0      /* [7:0]  flash opcode               */
#define QSPI_CMD_ENABLE_Pos    8      /* strobe: start the transaction     */
#define QSPI_CMD_READ_Pos      9
#define QSPI_CMD_WRITE_Pos     10
#define QSPI_CMD_ADDR_EN_Pos   11
#define QSPI_CMD_DUMMY_Pos     12     /* [15:12] dummy cycles              */
#define QSPI_CMD_NRW_Pos       16     /* [.. :16] = (data_bytes - 1)       */

#define QSPI_STATUS_BUSY_Msk   (1u << 0)
#define QSPI_STATUS_IRQ_CLR    (1u << 8)   /* write-1 to clear IRQ         */
#define QSPI_CTRL_QIO_MODE     (1u << 0)
```

A command is issued by the **two-write strobe**: write the descriptor,
then re-write it with `ENABLE` set; the controller raises `STATUS.BUSY`
until done, then the firmware clears the IRQ.

## 4. Recovery sequence (reference C)

Direct port of the proven `hardware_preamble` (order-independent and
idempotent — safe to call unconditionally at every boot/init). All
opcodes are JEDEC-standard and Micron N25Q-compatible.

```c
/* Bounded controller-BUSY wait. Returns 0 on success, -1 on timeout.
 * Bound chosen so it cannot hang the bootrom even if the block is
 * absent/wedged; tune POLLS to the platform clock. */
static int qspi_wait_idle(void)
{
    for (uint32_t i = 0; i < 2000000u; i++)
        if (!(QSPI->STATUS & QSPI_STATUS_BUSY_Msk))
            return 0;
    return -1;
}

/* Issue an opcode-only command (no address, no data). */
static void qspi_cmd_only(uint8_t op)
{
    uint32_t d = (uint32_t)op;                 /* opcode in [7:0]        */
    QSPI->SPI_CMD = d;                         /* descriptor            */
    QSPI->SPI_CMD = d | (1u << QSPI_CMD_ENABLE_Pos);   /* strobe        */
    (void)qspi_wait_idle();
    QSPI->STATUS  = QSPI_STATUS_IRQ_CLR;       /* W1C the IRQ           */
}

/* Crude busy-wait microsecond delay. Replace with the platform timer;
 * the absolute values matter (tRDP, tRST) — see §5. */
extern void delay_us(uint32_t us);

/* Bring the external SPI-NOR back to a known SPI/idle state regardless
 * of the mode a previous run/boot left it in. Call once, early, before
 * any JEDEC probe / XIP enable. */
void qspi_flash_recover(void)
{
    QSPI->CLK_DIV = 5;          /* HCLK/10 — safe. CLK_DIV=1 garbles    */
                                /* RDID on real silicon; keep >= 2.     */
    QSPI->CTRL    = 0;          /* SPI framing, XIP off                 */

    /* 1. Release from Deep Power-Down. A soft reset CANNOT wake DPD;
     *    only 0xAB does. Twice, with tRDP settle. */
    qspi_cmd_only(0xAB); delay_us(50);
    qspi_cmd_only(0xAB); delay_us(50);

    /* 2. QPI framing: absorb any continuous-read trap, decode RSTQIO,
     *    then RSTEN+RST while still in QPI. */
    QSPI->CTRL = QSPI_CTRL_QIO_MODE;
    qspi_cmd_only(0xFF); qspi_cmd_only(0xFF);   /* exit cont-read/RSTQIO */
    qspi_cmd_only(0x66); qspi_cmd_only(0x99);   /* RSTEN + RST (QPI)     */

    /* 3. SPI framing: definitive RSTEN+RST. */
    QSPI->CTRL = 0;
    qspi_cmd_only(0x66); qspi_cmd_only(0x99);   /* RSTEN + RST (SPI)     */
    delay_us(100);                              /* tRST settle           */

    QSPI->SPI_CMD = 0; QSPI->SPI_ADDR = 0;      /* quiesce               */
}

/* Optional: confirm the part answers (use as the boot go/no-go gate).
 * Returns the 24-bit JEDEC ID (mfg<<16 | type<<8 | density), or 0. */
uint32_t qspi_read_jedec(void)
{
    QSPI->SPI_ADDR = 0;
    uint32_t d = 0x9Fu
               | (1u << QSPI_CMD_READ_Pos)
               | (2u << QSPI_CMD_NRW_Pos);      /* 3 data bytes          */
    QSPI->SPI_CMD = d;
    QSPI->SPI_CMD = d | (1u << QSPI_CMD_ENABLE_Pos);
    if (qspi_wait_idle()) return 0;
    QSPI->STATUS = QSPI_STATUS_IRQ_CLR;
    /* Controller lane order: RDATA[0] holds the 3 ID bytes; extract
     * per the apb_qspi_regs RDATA packing (verify against silicon —
     * observed 0x..ba.. for Micron). */
    return QSPI->RDATA[0];
}
```

## 5. Timing constants

`delay_us()` values are **flash-datasheet-driven**, not arbitrary:

* `tRDP` (release-from-DPD to next command) — Micron N25Q256: ~30 µs;
  the spec uses 50 µs for margin.
* `tRST` (reset recovery) — Micron N25Q256: ~tens of µs; spec uses
  100 µs.

Take the exact figures from the **production flash's** datasheet (the
PmodSF3 is N25Q256A / MT25QL256). Over-delay is harmless at boot;
under-delay silently corrupts the first post-reset command.

## 6. Integration point

`nanosoc_m0_soc/firmware/bootloader/stage0/stage0_bootloader.c`:

* `qspi_boot()` is the orchestrator; `qspi_probe_jedec_id()` is the
  first flash access.
* **Call `qspi_flash_recover()` at the top of `qspi_boot()`, before
  `qspi_probe_jedec_id()`** — i.e. after the `BOOT_CFG` QSPI-present
  check, before any flash read or XIP enable.
* Use `qspi_read_jedec()` as the go/no-go gate: on the expected ID,
  proceed with QSPI boot; on `0` or wrong ID, fall through to the
  existing **ADP / external-load fallback** (`FlashLoader()`) — the
  recovery must never *block* boot, only improve QSPI reliability.
* Gate the whole path on the existing
  `CMSDK_SYSCON->BOOT_CFG & …_QSPI_PRESENT_Msk`.

A standalone driver is not required for boot; if a richer runtime QSPI
driver is later added, put it at
`nanosoc_arch_tech/firmware/software/drivers/qspi_flash_driver.{c,h}`
following the CMSIS volatile-struct idiom and the §3 model.

## 7. Prerequisites / sequencing

1. **Instantiate the block:** uncomment `u_ss_qspi` in
   `nanosoc_m0_soc.yaml`, set `QSPI_FLASH_PRESENT=1`, wire APB slot 12
   + the AHB read-only XIP port + pads.
2. **Fix the register model (§2):** regenerate `QSPI_TypeDef` /
   `nanosoc_qspi_ctrl.yaml` from `apb_qspi_regs.rdl`; port the
   bootloader QSPI path to it.
3. **Add `qspi_flash_recover()`** (§4) and call it per §6.
4. **Validate on silicon:** the cocotb-silicon `hardware_preamble`
   (`pynq/cocotb_silicon_adapter.py`) is the proven reference — the C
   path must reproduce the same opcode order and timing. Triage with
   `make -C fpga flash_diag BOARD=<b>` (its RESURRECT section is the
   same sequence).

## 8. Reference

* Proven sequence: `pynq/cocotb_silicon_adapter.py::hardware_preamble`
  and the cocotb-silicon engine hook `Adapter.hardware_preamble`.
* Evidence it was required (DPD on `01_pl`):
  [`cocotb-silicon-findings.md`](cocotb-silicon-findings.md).
* Register truth: `src/rdl/apb_qspi_regs.rdl`,
  `sys_desc/register_maps/apb_qspi_regs.yaml`.
