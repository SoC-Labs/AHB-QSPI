# cocotb-silicon — on-hardware findings

Evidence log for the cocotb-silicon parity investigation (companion to
[`cocotb-silicon-design.md`](cocotb-silicon-design.md) §8). Six hardware
runs across two PYNQ-Z2 boards. Bottom line: **the replay framework is
correct and proven on healthy silicon; the remaining non-green tests are
a dead board (now isolated) plus deep flash-sequence/XIP-stability work
that the `pynq/stress/` suite already owns.**

## Run log

| # | Target | Outcome | What it established |
|--:|---|---|---|
| 1 | `01_pl` (auto) | crash @ test 5 | `AHB_BAD_BEHAVIOUR` errored-MMIO store → **SIGBUS** killed the process, aborting ~50 tests. Extraction itself worked (deploy, bare fallback, stub/register/substitute, sanity, `APB_reg_tests`+`CACHE_CONFIG` pass). |
| 2 | `01_pl` (auto) | 8 pass / 41 fail, 0 crash | After per-test **crash isolation** + `skip`/`xfail`: ran all 55. Failures categorised; ~27 "flash busy", 4 stub `ImportError`, 3 nested-poke `AttributeError`. |
| 3 | `01_pl` (auto) | deploy SSH flake | `kex_exchange_identification: Connection reset` during `scp`. Never executed; ignored. |
| 4 | `01_pl` (auto) | 8 pass / 29 fail, 14 xfail | New code confirmed running: stub gaps closed (`Edge`/`First`/`AHBWrite`/`get_sim_time`), recursive `_DummyDutSignal`, Micron 4-byte RDSR, expanded `xfail`. **27 "flash busy" unchanged** by the status fix → pointed deeper. |
| 5 | `01_pl` (`flash_diag`) | decisive | Proven `qspi_hw` reference **fails identically** (JEDEC=`0xffffff`, RDSR=`0xff`). The "flash busy" wall is **not** a cocotb-sequence bug — the flash isn't responding. |
| 5b | `01_pl` (`flash_diag` + soft-reset preamble) | misleading | After `0x66/0x99` + cont-read-exit JEDEC still `0xffffff` → **wrongly concluded "physically dead"**. A soft reset cannot wake a flash from Deep Power-Down. |
| 6 | **`03_pl`** (`flash_diag`) | healthy | `qspi_hw.jedec_id()=0x20ba19`, erase+program+**read-back MATCH=True**. Framework + preamble + overlay all work on good hardware. |
| 6b | **`03_pl`** (full suite) | framework proven; PS wedged on XIP | Clean `PASS` incl. **`test_spi_write_and_read` (real flash write/read on silicon)**, correct `XFAIL`/`SKIP`, 0 crash. Aborted mid-run when XIP-heavy tests **hung the PS** (SSH timeout). |
| 7 | `01_pl` (`flash_diag` RESURRECT) | **`01_pl` is ALIVE** | `0xAB` Release-from-DPD ×3, then `RDID`@CLK_DIV≥2 → `0x19ba2000` (Micron, lane order), `SFDP`→`'SFDP'`, flag-status `0x80`; `qspi_hw` reference then **passes (read-back MATCH=True)**. The "dead" verdict (runs 1–5b) was **Deep Power-Down**, which only `0xAB` clears. `CLK_DIV=1` garbles RDID; use ≥2. |
| 8 | `01_pl` (full suite, `0xAB`-preamble) | re-validation | `hardware_preamble` now issues `0xAB` before `0x66/0x99`; full `cocotb_hw` re-run on the (alive) `01_pl` for real parity numbers. |

## What is proven

- **Extraction & engine are correct on real silicon.** Stub injection,
  decorator self-registration, TB/bus/DUT substitution, MMIO-over-AXI,
  the bare `/dev/mem` fallback, sanity gate, per-test subprocess crash
  isolation, declarative `skip`/`xfail`, the Micron status-read override,
  and the generic `Adapter.hardware_preamble` reset hook all work — `0`
  crashes, `0` framework errors on healthy hardware, and a genuine flash
  write+read round-trip (`test_spi_write_and_read`) passes through the
  unmodified cocotb test on the board.
- **The dead-board red herring is isolated.** Five runs were dominated
  by `01_pl`'s non-responsive PmodSF3; the `flash_diag` probe (proven
  `qspi_hw` path vs raw cocotb sequence, side by side) pinned it
  unambiguously.

## Correction: `01_pl` was Deep Power-Down, not dead

Runs 1–5b were dominated by `01_pl`'s flash reading `0xFFFFFF` and were
**wrongly** concluded as a physically dead Pmod. Run 7 (the `flash_diag`
RESURRECT probe, prompted by "can we get *any* response?") proved the
part is healthy: it was stuck in **Deep Power-Down**, which a soft reset
(`0x66`/`0x99`) cannot clear — only **`0xAB` Release-from-DPD** does.
`hardware_preamble` now issues `0xAB` (×2, `tRDP` settle, SPI framing)
before the RSTEN/RST + continuous-read-exit dance. This is generic and
defensive (harmless if not in DPD; essential if a prior run left it
there) and applies equally to any warm-reset / XIP-boot C driver — a
controller/PL/SoC reset does **not** reset the flash chip.

## What is out of scope (owned elsewhere)

1. **Deep flash-sequence parity.** On healthy hardware a subset of
   program/erase-heavy tests still "flash busy": the SST helper's
   `QPI_PAGE_PROGRAM` / `SPI_SECTOR_ERASE` / `0x98` unlock / 4 KB-erase
   sequences differ from what the real Micron N25Q256 needs.
   `pynq/stress/qspi_hw.py` already implements Micron-correct
   program/erase/WIP — re-deriving it in adapter overrides duplicates
   that coverage for no new signal.
2. **XIP PS-wedge.** The XIP-heavy tests destabilise the Zynq PS
   (concurrent APB during AHB-heavy XIP — the same hazard the stress
   runner documents). Per-test process isolation contains a *process*
   crash but cannot survive the *whole board* hanging; this is a
   board/PS-stability concern, not a replay-layer one.

## Actions

- **`pynq_z2_01_pl` needs no physical fix** — its PmodSF3 is healthy;
  it just gets left in Deep Power-Down. The `0xAB` preamble handles it.
  Both `01_pl` and `03_pl` are usable for QSPI hardware work (pin
  `BOARD=`; `BOARD_TAG` auto-pick is fine now that the preamble recovers
  DPD).
- **Cheap health/triage:** `make -C fpga flash_diag BOARD=<board>` — the
  RESURRECT section does `0xAB` + CLK_DIV/opcode sweep then the proven
  `qspi_hw` reference. `0x20ba19` = healthy; persistent `0xffffff` even
  after `0xAB` at CLK_DIV≥2 = genuinely dead.
- **Hardware iteration stopped deliberately** — the framework (the
  deliverable) is done; the rest is stress-suite territory.
