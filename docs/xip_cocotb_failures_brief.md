# Brief: 5 failing XIP cocotb tests — investigation hand-off

**Status:** open. 5 of 55 cocotb tests fail. **Pre-existing on
`feat-nanosoc_int` — not caused by the QSPI_RDATA read-mux change in
the same working tree** (proven: the 3 fast-failing tests fail
identically with that change `git stash`-ed away; the change is
provably equivalent for all reachable `N_RW_BYTES` values).

## How to reproduce

```bash
cd /home/dam1n19/SoCLabs/ahb_qspi
export SOCLABS_AHB_QSPI_DIR="$(pwd)"
export SOCLABS_SOCTOOLS_FLOW_DIR="$(pwd)/soctools_flow"
export ARM_IP_LIBRARY_PATH=/research/AAA/ip_library
# All 5 (slowest is ~10 Mns sim, ~95 s wall each):
make run_cocotb SIMULATOR=vcs \
  TESTCASE=test_xip_qpi_no_cont_read_no_nocmd,test_xip_qpi_no_cont_read_warmup,test_xip_plain_spi_no_flash_write,test_xip_plain_spi_fast_read_line_fill,test_xip_plain_spi_slow_read_line_fill
```

Tests live in [verif/cocotb/ahb_qspi_tests.py](../verif/cocotb/ahb_qspi_tests.py);
helpers `_xip_baseline_minus` (line ~1249) and `_xip_plain_spi_fill_body`
(line ~1497). SPI/flash helpers in
[verif/cocotb/SST26VF064B.py](../verif/cocotb/SST26VF064B.py).

## The 5 failures and their exact signatures

| Test | Scenario | Failure |
|---|---|---|
| `test_xip_qpi_no_cont_read_no_nocmd` | QPI, **no** cont_read warmup, NO_CMD=0 | `ValueError: Can't convert LogicArray to int: it contains non-0/1 values` (X/Z on an AHB read beat) |
| `test_xip_qpi_no_cont_read_warmup` | QPI, NO_CMD=1, **no** cont_read warmup | `Exception: Timeout 5000 clk — AHB.SLAVE signals are not resolvable!` (X on AHB slave → hang) |
| `test_xip_plain_spi_no_flash_write` | plain SPI, **un-programmed** flash (all 0xFF) | `AssertionError: Cache did not reach READY (STATUS & 0x3 stuck at 0x1)` |
| `test_xip_plain_spi_fast_read_line_fill` | plain SPI fast-read, multi-line fill | `AssertionError: Cache did not become ready` |
| `test_xip_plain_spi_slow_read_line_fill` | plain SPI slow-read, multi-line fill | `AssertionError: Cache did not become ready` |

Two distinct failure modes:
1. **X / non-0/1 propagation on the QPI line-fill AHB path** (2 tests) —
   AHB read data / slave handshake goes metastable-X, cocotb can't
   convert it / times out.
2. **CG092 cache never reaches READY** (3 tests) — `CACHE_STATUS[1:0]`
   stuck at `0x1`, never advances to `0x2` (READY).

## The decisive diagnostic contrasts (start here)

The pass/fail split across the *full* XIP family isolates the trigger —
these PASS, so the bug is in what differs:

| PASSES | FAILS | What differs |
|---|---|---|
| `test_xip_qpi_no_nocmd` (QPI + cont_read warmup + NO_CMD=0) | `test_xip_qpi_no_cont_read_no_nocmd`, `test_xip_qpi_no_cont_read_warmup` | **the cont_read APB warmup**. With it: pass. Without it: X on the QPI line-fill path. |
| `test_xip_plain_spi_fast_read`, `test_xip_plain_spi_minimum`, `test_xip_plain_spi_line_fill_clkdiv_sweep` | `test_xip_plain_spi_fast_read_line_fill`, `test_xip_plain_spi_slow_read_line_fill`, `test_xip_plain_spi_no_flash_write` | the specific `_xip_plain_spi_fill_body` multi-line-fill sequence and the un-programmed-flash (0xFF) path; single fast-read and the clkdiv-sweep line-fill are fine. |
| `test_xip_baseline_sanity`, `test_ahb_xip_read`, `test_xip_multiple_addresses`, `test_xip_hang_on_stuck_busy`, `test_xip_timeout_recovery`, `test_xip_cache_pipelined_*` | — | the happy-path / regression-anchored XIP flows all pass. |

**Hypothesis (from the test docstrings themselves):** the cont_read APB
"warmup" is *load-bearing* for the QPI XIP line-fill path — without it
the cache line-fill sequencer drives X onto the AHB slave. The plain-SPI
line-fill + un-programmed-flash failures look like a separate
"cache never reaches READY" bug in the CG092 enable/ready path for
those specific setups.

## Strongly related existing material — read before starting

- [docs/dma_master_port_bug_plan.md](dma_master_port_bug_plan.md) —
  stage-0 DMA + XIP cache readiness; the "cache reaches READY at +267
  cycles" / `qspi_enter_xip()` analysis is directly relevant to the
  "cache did not become ready" failures.
- [docs/CG092_bus_logic_bug_report.md](CG092_bus_logic_bug_report.md) —
  CG092 cache-config (`PPROT[0]`) silent-drop; the `top_ahb_qspi.v:224`
  workaround is already in RTL, but the cache-config/ready path is the
  same area as failure mode 2.
- README "Project status": "AHB XiP on FPGA has known issues" — these
  cocotb failures are the *simulation* manifestation; this is an
  ASIC-readiness verification gap, not just FPGA.

## Suggested investigation order

1. **Mode 2 first (cache-not-READY, 3 tests)** — simplest signal:
   instrument `CACHE_STATUS[1:0]` and the CG092 enable handshake in
   `test_xip_plain_spi_no_flash_write` (shortest of the three). Compare
   the cache-enable → READY sequence against the passing
   `test_xip_plain_spi_fast_read`. Likely a missing/extra APB setup step
   in the `_xip_plain_spi_fill_body` path or an un-programmed-flash
   (0xFF opcode echo) interaction.
2. **Mode 1 (X-propagation, 2 tests)** — dump a VCD around the first
   failing line fill in `test_xip_qpi_no_cont_read_no_nocmd`; trace
   which AHB slave signal (`HRDATA`/`HREADYOUT`/`HRESP`) goes X and back
   to which RTL node. Confirm/deny the "cont_read warmup is load-bearing"
   hypothesis by diffing against passing `test_xip_qpi_no_nocmd`.
3. Decide per finding: real RTL/cache bug (must fix before tape-out) vs.
   test-harness setup gap (the test omits a required warmup the silicon
   use-case would always do). The docstrings frame this explicitly —
   "if it fails, the warmup is load-bearing and stage-0 needs to
   synthesise one" — so the outcome may be a firmware/integration
   requirement rather than an RTL fix. Record the verdict either way.

## Out of scope / already ruled out

- The QSPI_RDATA read-mux width-match + safe-default change in the
  current tree (`logical/qspi_controller/logical/qspi_controller.sv`) is
  **not** the cause — verified by a pristine-RTL baseline run.
- The newly-added `test_qspi_partial_byte_read_ordering` xfail is a
  *separate* tracked bug (non-word-aligned QSPI byte reads scramble) —
  not part of these 5; don't conflate.
