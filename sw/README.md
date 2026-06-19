# ahb_qspi `sw/` — portable C driver

A small, dependency-free C driver for the AHB QSPI controller, living **inside
the `ahb_qspi` submodule** so SoC firmware stops duplicating ad-hoc register
pokes. It is the software companion to the RDL register spec
(`../src/rdl/apb_qspi_regs.rdl`) and the recovery spec
(`../docs/qspi-flash-recovery-c-driver-spec.md`).

## Files

| File | Purpose |
|---|---|
| `qspi_regs.h` | Register offsets + bitfield masks, transcribed verbatim from `apb_qspi_regs.rdl`. **Single source of truth.** Configurable base. |
| `qspi_driver.h` / `qspi_driver.c` | The driver: BUSY-poll discipline, command helpers, JEDEC, XiP enable, warm-boot flash recovery, erase/program. |

No SoC headers, no CMSIS, no RTOS — only `<stdint.h>`. All MMIO goes through a
`volatile uint32_t *` accessor, so it drops into a bootrom or an app unchanged.

## Configuration (override on the compiler command line)

```
-DQSPI_APB_BASE=0x21000000     # APB register block base (default 0x21000000)
-DQSPI_XIP_BASE=0x24000000     # read-only XiP window base (default 0x24000000)
-DQSPI_CACHE_BASE=0x21001000   # CG092 cache CCR/SR block (default APB base + 0x1000)
-DQSPI_REG32(a)=...            # supply your own MMIO accessor (optional)
-DQSPI_FAST_READ_DUMMY=9       # FAST_READ true dummy-cycle count (default 9)
-DQSPI_BUSY_CLEAR_POLLS=...    # BUSY-clear timeout bound
```

If `QSPI_REG32` is left at the default it is `*(volatile uint32_t*)(addr)`.

## API at a glance

```c
#include "qspi_driver.h"

/* --- warm-boot bring-up (call once, early) --- */
qspi_flash_recover(delay_us);     /* DPD/QPI/cont-read -> SPI idle; delay_us may be NULL */
uint32_t id = qspi_read_jedec();  /* go/no-go gate: 0 / 0xFFFFFF == not responding */

/* --- XiP read path (cache-served fetches from QSPI_XIP_BASE) --- */
qspi_xip_enable();                /* = the old xip_bringup(): AHB_SPI_SETUP=0x800B + XIP_ACTIVE + prime */
/* ... reads from QSPI_XIP_BASE now hit the CG092 cache ... */
qspi_xip_disable();               /* back to APB-command mode before erase/program */

/* --- CG092 flash cache enable (CCR/SR @ +0x1000) --- */
if (qspi_cache_enable() == 0) {   /* CCR.EN=1 -> auto power-up + invalidate -> CS==READY */
    /* cache is live; XiP reads from QSPI_XIP_BASE are now cache-served */
}
int rdy = qspi_cache_is_ready();  /* non-zero once SR.CS == READY (==2) */
qspi_cache_disable();             /* clear CCR.EN (does not block on wind-down) */

/* --- program / erase --- */
qspi_unlock_global();             /* SST26 ULBPR (no-op on N25Q) */
qspi_sector_erase(0x000000);      /* WREN + 64K erase + WIP poll */
qspi_page_program(off, buf, 16);  /* WREN + PP + WIP poll, <=16 B/CS */

/* --- raw commands --- */
qspi_cmd_only(QSPI_OP_WREN);
uint32_t sr  = qspi_cmd_read(QSPI_OP_RDSR, 1);             /* bit0 = WIP, bit-0 aligned */
uint32_t out[4];
qspi_cmd_read_addr(QSPI_OP_FAST_READ, addr, 16,
                   QSPI_FAST_READ_DUMMY, out);             /* up to 16 B */
```

## Encoded hardware quirks (do not re-derive these in firmware)

1. **STATUS.BUSY 2-FF CDC race.** `BUSY` crosses ENABLE→SCLK→nCS→BUSY (2-FF back
   to PCLK), so it is *not* 1 in the cycles right after the `SPI_CMD` write. A
   bare `while(BUSY)` on a fast in-order M0+ falls straight through and reads
   `RDATA0` (a comb view of a reset-to-0 latch) as `0x000000`.
   `qspi_wait_idle()` waits for BUSY to **set, then clear**, both bounded, with
   a read-back + `dsb` fence on the prior CMD write (the cmsdk APB bridge drops
   back-to-back writes otherwise).

2. **Sub-word reads are top-lane justified.** A 1–3 byte read lands in the
   **top** byte lanes of `RDATA0` (an RDSR/RDID byte is in `[31:24]`, not
   `[7:0]`). `qspi_cmd_read()` shifts it down so callers mask from bit 0. This is
   the bug that made WIP read "done" instantly and WEL "clear" forever.

3. **DUMMY / N_RW are `(count-1)` fields, and FAST_READ needs +1.** The helpers
   take the *true* count and subtract 1 internally. `FAST_READ` (0x0B)
   nominally wants 8 dummy cycles but the controller is one short on the read
   phase (bench-characterised on z2_01), so the true count is **9**
   (`QSPI_FAST_READ_DUMMY`) → programmed as field value 8 →
   `AHB_SPI_SETUP = 0x0000800B`.

4. **Flash mode survives a SoC reset.** A SoC/FPGA reset does *not* reset the
   external flash. `qspi_flash_recover()` is the idempotent DPD/QPI/cont-read →
   SPI-idle sequence (0xAB release-from-DPD — a soft reset cannot wake DPD —
   then RSTQIO/RSTEN/RST in both QPI and SPI framing). Run it before the first
   probe on any warm-resettable board.

5. **CG092 cache CCR/SR enable + the +0x1000 reachability caveat.** The cache
   resets **disabled** (`CCR.EN=0`). To use it, `qspi_cache_enable()` sets
   `CCR.EN=1` (read-modify-write, preserving `STATISTIC_EN`) — which, with the
   CG092's auto-power (`APOW`) / auto-invalidate (`AINV`) defaults, triggers the
   automatic power-up + invalidate — then polls `SR.CS` until `READY` (`==2`),
   bounded by `QSPI_CACHE_READY_POLLS`. This is the exact sequence the cocotb
   suite uses (`verif/cocotb/ahb_qspi_tests.py`: write `CONFIG=0x1`, poll until
   `(STATUS & 0x3)==2`).

   **CAVEAT (re-verify on hardware):** the SoC's `stage0_bootrom` historically
   carried a comment that the `+0x1000` cache window is **NOT decoded** (a read
   AHB-faulted), and earlier driver notes assumed it needed a privileged APB
   master. RTL analysis now shows the block **IS decoded** at `0x21001000`
   (`PADDR[15:12]` decode, `ADDRWIDTH=16` bridge), so the API targets it
   directly. Before relying on the cache from firmware, **re-verify reachability
   on silicon**: if a read of `0x21001004` (STATUS) AHB-faults, a `sys_desc`
   decode change is required (the API itself is bounded, so a fault/wedge shows
   up as `qspi_cache_enable()` returning `-1`, not a hang).

## How SoC firmware should consume it

Replace the duplicated pokes with `#include "qspi_driver.h"` and the calls
above:

- **`firmware/include/xip_bringup.h`** → `qspi_xip_enable()`.
- **`stage0_bootrom` / `smoke_remap`** XiP bring-up copies → `qspi_xip_enable()`;
  add `qspi_flash_recover()` + `qspi_read_jedec()` go/no-go before the boot-table
  read.
- **`qspi_flasher` / `qspi_selftest`** local register maps → delete; use
  `qspi_regs.h` + the `qspi_cmd_*` / `qspi_sector_erase` / `qspi_page_program`
  helpers. The BUSY-race wait, the top-lane shift and the FAST_READ +1 are now
  encoded once here, removing the per-app drift.

Point the consuming build's include path at this directory and set
`-DQSPI_APB_BASE` / `-DQSPI_XIP_BASE` to the SoC's actual addresses (e.g. the
nanoSoC values from `nanosoc_multicore_addrmap.h`).

## Build / verify

```
arm-none-eabi-gcc -c -mcpu=cortex-m0plus -mthumb -Wall -Wextra -Isw \
    sw/qspi_driver.c -o /tmp/qspi_driver.o      # clean
gcc -c -std=c99 -Wall -Wextra -pedantic -Isw \
    sw/qspi_driver.c -o /tmp/qspi_driver_host.o # portable (host)
```
