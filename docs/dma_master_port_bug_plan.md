# DMA-master-port XIP cache regression — debug plan

## Symptom

In `nanosoc-ethernet-flash-system` stage-0, the cocotb test
`test_boot_flash_dma_copy_and_banner` fails with "IMEM DMA check
failed: 241 X/Z words" after 200k HCLK cycles (2ms sim time). CPU
never enters WFI (`sleeping=0`), no UART banner emitted, IMEM is
100% X (not partial).

## Phase-0 finding (2026-04-24): stage-0 hangs before DMA runs

An earlier framing of this bug assumed PL230 ran to completion but
silently corrupted IMEM. That framing is **wrong**. Bus-trace
evidence from `TRACE_TXNS=500` run:

- CPU executes crt0 (bootrom .data copy to DMEM) — beats 0…~450.
- CPU reaches `qspi_enter_xip()` APB sequence — writes `CLK_DIV`
  (0x58000034), `AHB_SPI_SETUP` (0x58000030), `CTRL` (0x58000000).
- CPU writes `CACHE_CONFIG` (0x58001000) = 0x1 (enable), reads it
  back — **reads back 0x0, not 0x1**.
- Enters the cache-ready spin loop (`while (spin--) { if ((STATUS &
  0x3) == 0x2) return; }`); STATUS stays 0.
- **Zero reads observed at `0x6xxxxxxx` (XIP aperture)** — CPU
  never gets past `qspi_enter_xip()`. It runs out the spin counter
  and calls `halt()`.
- PL230 is never programmed. IMEM is X because DMA never ran.

**Compare against the passing ahb_qspi-level test** (`test_ahb_xip_read`
in `verif/cocotb/ahb_qspi_tests.py:326–330`):

```python
await tb.config_ahb_master.write(CACHE_CONFIG_ADDR, 0x1)
CACHE_CONFIG = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR, 4)
assert CACHE_CONFIG == 0x1              # passes at the IP boundary
```

Same register, same write, same readback — at the ahb_qspi IP
boundary it reads back 0x1 and the rest of the init succeeds. In the
nanoSoC path it reads back 0x0. The APB write isn't reaching the
cache (or is being silently dropped).

## Revised top hypothesis (H0)

The APB path from CPU to the cache's CONFIG register in the nanoSoC
integration is broken. The likely suspects, in priority order:

1. **Address decode in the QSPI APB slave mux.** Cache registers
   live at `QSPI_APB_BASE + 0x1000` via `top_ahb_qspi.u_cmsdk_apb_slave_mux`'s
   `PADDR[15:12]` decode. If the nanoSoC APB interconnect above it
   masks `PADDR[15:12]` (e.g. addresses the slave with only low bits),
   the `+0x1000` offset is lost and the write goes to a QSPI control
   register instead of the cache.
2. **Write strobe / PSEL qualification.** `nanosoc-ethernet-flash-system`
   may have an APB bridge between AHB and the QSPI APB aperture that
   drops PWRITE or PSEL during the cache handshake. The ahb_qspi TB
   drives APB directly from an AHB master through `cmsdk_ahb_to_apb`;
   nanoSoC goes through `eth_flash_ahb_interconnect` → `cmsdk_ahb_to_apb`
   → `cmsdk_apb_slave_mux` → cache. Extra layer, extra chances to
   drop the write.
3. **Clock domain / reset.** The cache has CDC synchronizers on its
   register interface. If HCLK / PCLK / PCLKEN isn't lined up in the
   nanoSoC build the same way as in the ahb_qspi TB, writes can miss.

H1–H4 from the previous version of this plan (DMA arbitration,
HSEL-toggle, PL230 signal combos, APB-vs-data concurrency) are
**parked until H0 is resolved**, because if the cache never enables,
none of those can trigger.

## Phase 1 — pinpoint where the CACHE_CONFIG write disappears (DO THIS NEXT)

1. **Instrument the APB path in the nanoSoC sim.** Add `$display`
   probes (or cocotb coroutines) on:
   - CPU's HADDR/HWDATA/HWRITE/HREADY at the first AHB master port
   - PADDR/PWDATA/PWRITE/PSEL/PENABLE at the AHB-to-APB bridge output
   - PADDR/PWDATA/PWRITE/PSEL/PENABLE at the APB slave mux output
     going to the cache subsystem
   - The cache's internal `ccr_wr_en` (from
     `p_flash_cache_f0_reg_block`)

   Run `test_boot_flash_dma_copy_and_banner` and compare the signal
   values at the expected CACHE_CONFIG write cycle. Whichever stage
   shows the write with correct address/data but the downstream
   stage doesn't is the boundary where the write is being lost.

2. **Diff the passing ahb_qspi-level hierarchy against the failing
   nanoSoC hierarchy.**
   - In ahb_qspi TB: `cpu_ahb → cmsdk_ahb_to_apb → cmsdk_apb_slave_mux
     → cache`.
   - In nanoSoC: `cpu_0 → eth_flash_ahb_interconnect (busmatrix +
     per-port IO stages) → cmsdk_ahb_to_apb → cmsdk_apb_slave_mux →
     cache`.
   - Extra interconnect is the suspect. Look specifically at
     `eth_flash_target_output_QSPI_FLASH_0.v` (the QSPI APB output
     stage) for any PADDR masking or PWRITE re-timing.

3. **Acceptance for Phase 1.** A named signal/module where the
   CACHE_CONFIG write is present on the upstream side but absent on
   the downstream side.

## Phase 2 — fix, add ahb_qspi-level regression, verify nanoSoC end-to-end

Once Phase 1 identifies the stage, the fix is likely a one-line RTL
change (un-masked PADDR bit, missed PWRITE qualification, etc.).
After the fix:

- Add a new cocotb test at the ahb_qspi level if feasible that
  covers the specific signal pattern Phase 1 found — e.g. a test
  that drives APB writes with the nanoSoC-pattern timing and asserts
  that CACHE_CONFIG readback matches. If the bug is purely in a
  nanoSoC-specific module (not in anything ahb_qspi ships), the test
  lives in `nanosoc-ethernet-flash-system/cocotb/` instead.
- Re-run `test_boot_flash_dma_copy_and_banner` to confirm stage-0
  reaches XIP, programs PL230, and IMEM gets populated. At that
  point we either see the original DMA-master-port hypothesis fire
  (H1–H4) or the test passes end-to-end.

## Resuming the DMA-master-port investigation (H1–H4)

Only relevant **if** H0 is fixed and the test still fails. The
previous plan's phases are preserved below — they are the right
phases to execute once the cache is actually enabled and DMA can
run.

## What's ruled out

Documented by the `test_xip_cache_pipelined_*_regression` tests in
`verif/cocotb/ahb_qspi_tests.py`. Negatives so far:

- **CG092 cache handles back-to-back NSEQ SINGLE reads.**
  `test_xip_cache_pipelined_nseq_reads_regression` drives the same
  AHB wire pattern as PL230 (HBURST=SINGLE, HTRANS=NSEQ every cycle,
  no IDLE between transactions) via `cocotbext.ahb`'s `pip=True`
  mode. Passes with 16 back-to-back reads, all data matches.
- **HPROT[3]=0 (non-cacheable) data path correct.** Re-ran the
  pipelined NSEQ test with `+HPROT_DATA=1` (exactly what PL230 emits
  on default APB config: `hprot = {hprot3to1, 1'b1}` per
  `pl230_ahb_ctrl.v:1035`). Cache pass-through path is ~2.3× slower
  (no caching, every read hits flash) but returns correct data.
- **HWRITE toggle mid-burst doesn't disturb the cache FSM.**
  `test_xip_cache_pipelined_rw_interleave_regression` drives
  alternating R/W NSEQ without IDLE gaps (HSEL=1 throughout).
  Caveat: doesn't probe the true HSEL-toggle corner that real
  multi-slave interconnect creates.
- **§1.1 fpga-infra red herring.** (Unrelated to the cache bug but
  rules out "maybe the board itself is misbehaving".) The nanoSoC
  stage-0 failing case is a sim-level symptom, not an on-host issue.

## Remaining hypotheses, in priority order

**H1 — Interconnect arbitration handover between DMA and CPU
masters.** The `eth_flash_ahb_interconnect` is CMSDK BusMatrix with
per-port input-stage and output-arbiter sub-modules (all of which
have `always` blocks — the top-level is pure connectivity, but the
sub-modules register signals). If the arbiter for `QSPI_FLASH_XIP`
loses a transaction during master handover (PL230 taking over from
CPU, or vice versa), cache sees a malformed NSEQ and returns X.

**H2 — HSEL-toggle corner at the cache's slave input.** In the
nanoSoC interconnect, DMA reads XIP then writes IMEM, so the cache's
HSEL drops to 0 between DMA transactions while HTRANS stays NSEQ.
Our existing `rw_interleave` test keeps HSEL=1 and only probes
HWRITE-toggle; it doesn't cover the HSEL=0 + HTRANS=NSEQ case.

**H3 — PL230 signal combos we haven't tested in isolation.** HMASTLOCK
is tied `1'b0` in PL230 (see `pl230_ahb_ctrl.v:1041`), so probably
not that. HMASTER and HPROT[3:1] are software-programmable via APB;
stage-0 might program something unusual. We tested only the defaults.

**H4 — Cross-master concurrent traffic on the APB side.** nanoSoC
has the CPU polling APB config regs while the DMA runs. The ahb_qspi
TB's `AHBLiteMaster` is quiet on APB while data reads flow. If the
cache's shared APB-control-vs-AHB-data FSM has a race, the CPU's
poll could corrupt a DMA read in flight. This is the weakest
hypothesis (no obvious shared state between APB and data-port AHB)
but easy to check once a minimal repro exists.

## Plan

### Phase 0 — Establish a failing waveform (the decision gate)

Nothing else is worth doing until we have a waveform of the bug
firing in simulation, because every other path requires knowing
*which* signal looks wrong.

1. **Reproduce in sim first.** Check whether
   `nanosoc-ethernet-flash-system/cocotb/` or `…/uvm/` has a stage-0
   test that fails in simulation. If it does, dump the cache's
   slave-port signals (HSEL, HADDR, HTRANS, HWRITE, HPROT, HSIZE,
   HBURST, HMASTER, HMASTLOCK, HREADY, HRESP, HRDATA, HWDATA) over
   the failing DMA window.
2. **If the bug only shows on hardware**, add an ILA on the cache's
   AHB slave port, trigger on DMA start, capture ≥ 64 cycles. This
   is slower to iterate on but may be unavoidable if sim doesn't
   repro.

**Acceptance.** A VCD / FSDB / ILA capture of the failing transaction
that we can share. Without this, every subsequent phase is
speculation.

### Phase 1 — Isolate the bad signal

From the Phase-0 capture, find *which* signal is wrong during the
failing transaction. Concretely, compare against a passing reference
(the same cache's slave-port signals during a working CPU-only copy
from the same aperture):

- Does HSEL drop mid-transaction? Is the handover clean?
- Does HADDR stay stable through HREADY rising?
- Are HTRANS transitions all NSEQ → NSEQ, or is there a spurious
  BUSY or IDLE?
- Does HREADY gap in an unusual way?
- Does HRESP go ERROR at any point?
- Is HMASTER or HPROT unexpected?

One of these will look different between the failing DMA capture and
a passing CPU capture. That signal points at the bug.

**Acceptance.** A written diff: "in the failing case, signal X
shows behaviour Y at cycle Z; in the passing case it shows Y'."

### Phase 2 — Trace the bad signal back to its source

Once Phase 1 names signal X, walk the interconnect backward:

- cache slave AHB port ← `eth_flash_target_output_QSPI_FLASH_XIP.v`
- ← `eth_flash_arbiter_QSPI_FLASH_XIP.v` (arbitration between CPU
  and DMA masters)
- ← `eth_flash_matrix_decode_DMA_230_0_M.v` (DMA master input stage)
- ← PL230 `pl230_ahb_ctrl.v`

Read each sub-module; find which one produces the bad signal. If the
problem is in the arbiter, it's likely a handover bug. If it's in
the input stage, it's a master-specific issue. If the bad signal
traces back to PL230, the bug is in how PL230 is being driven (most
likely an APB programming issue in the stage-0 firmware).

**Acceptance.** A specific line in a specific file identified as the
origin of signal X's bad value.

### Phase 3 — Build a minimal repro at `ahb_qspi` IP boundary

Independent of Phase 1/2, worth building because it makes every
future regression-test-and-fix cycle fast (sim ~few seconds vs the
full nanoSoC sim):

- Extend `verif/cocotb/ahb_qspi_cocotb.v` with a second AHB master
  slot + a dummy scratch slave (so HSEL can toggle between the cache
  and scratch the way it does in nanoSoC).
- Write a test that replicates the stage-0 pattern: read XIP,
  interleaved with writes to the scratch slave, at the timing PL230
  emits. Use `cocotbext.ahb.custom()` with pip=True driving two
  logical masters through the address decoder.
- **If that fails, H2 (HSEL-toggle corner) is confirmed** and the
  bug is reproducible without PL230 — Phase 1's "bad signal"
  diagnosis can be verified directly.
- **If it still passes**, the bug is either (a) PL230-master-
  specific — needs a real PL230 instance in the TB — or (b) in the
  nanoSoC interconnect routing, not in the cache.

**Acceptance.** Either a failing cocotb test at the `ahb_qspi`
level that repros the X/corruption, or confirmation that a
two-master HSEL-toggle testbench can't repro it (narrowing to the
interconnect or PL230).

### Phase 4 — Fix, verify, regress

Fix placement depends on Phase 2's diagnosis:

- **Bad signal originates in `eth_flash_arbiter_QSPI_FLASH_XIP.v`**
  — patch the arbiter (likely a missed `HREADY` qualification or
  handover state). File the patch against
  `nanosoc-ethernet-flash-system/build_soc/rtl/…`.
- **Bug in cache's slave-port wrapper** — patch
  `logical/ahb_qspi_interface/logical/ahb_qspi_interface.sv` or
  `logical/cache_subsytem/logical/cache_subsystem.v`.
- **Bug in CG092 itself** — unlikely (Arm IP), but if so file a
  `CG092_*_bug_report.md` alongside the existing one in this dir
  and work around in the wrapper.
- **Bug in nanoSoC PL230 programming** — patch the stage-0 firmware
  under `nanosoc-ethernet-flash-system/firmware/`.

For each fix: add a cocotb test at the `ahb_qspi` level that would
have caught it, run the nanoSoC stage-0 test end-to-end to confirm
the silent-fail is gone, and run the full `ahb_qspi` regression to
confirm no other tests regressed.

**Acceptance.** Stage-0 DMA copy succeeds on nanoSoC sim AND on
hardware; `ahb_qspi` TESTS=N PASS=N FAIL=0 in CI; a new cocotb test
pins the fix as a regression guard.

## Fallbacks and escape hatches

- **If Phase 0 can't produce a failing sim** within a day's work,
  pivot to hardware ILA capture.
- **If Phase 1 shows every signal matches** between failing and
  passing captures, the cache corruption is internal to CG092 and
  we're looking at a CG092 hazard. Escalate to the existing
  `docs/CG092_bus_logic_bug_report.md` material.
- **If Phase 3's two-master TB doesn't repro** and Phase 2's
  interconnect walk doesn't find a smoking gun, bring in a real
  PL230 instance. The CMSDK DMA-230 is in the ARM IP library at
  `/research/AAA/ip_library/DMA-230/`; the ahb_qspi TB has the APB
  infrastructure needed to program it.
- **Time-boxed hypotheses.** H1 + H2 are each worth a day. H3 + H4
  should each be cheap (~2 hours) once a minimal repro exists. If
  2 full days in and no progress, write up the negative results
  next to this plan and re-prioritise.

## References

- `verif/cocotb/ahb_qspi_tests.py` — see `test_xip_cache_pipelined_nseq_reads_regression` and `test_xip_cache_pipelined_rw_interleave_regression` for the ruled-out hypotheses, with per-test docstrings documenting what was probed.
- `verif/cocotb/ahb_qspi_cocotb.v` — `+HPROT_DATA=N` plusarg for HPROT sweeps on the data-port AHB master.
- `docs/CG092_bus_logic_bug_report.md` — prior CG092 bug we've filed against Arm.
- `/research/AAA/ip_library/DMA-230/PL230-r0p0-02rel2-1/…/pl230_ahb_ctrl.v` — PL230 master port source (`hprot = {hprot3to1, 1'b1}`, `hmastlock = 1'b0`).
- `/home/dam1n19/SoCLabs/nanosoc-ethernet-flash-system/build_soc/rtl/eth_flash_ahb_interconnect/` — generated CMSDK BusMatrix for the failing system.
