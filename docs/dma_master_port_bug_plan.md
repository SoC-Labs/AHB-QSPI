# DMA-in-stage-0 hang — debug plan

_Original title was "XIP cache regression in nanoSoC — debug plan"
tracking a DMA-master-port-corrupts-IMEM hypothesis; that framing
has been refuted by probe evidence and by the `dma_xip_probe`
stage-1 experiment. This rewrite captures the actual open issue._

## Current state

`test_boot_flash_dma_copy_and_banner` in
`nanosoc-ethernet-flash-system/cocotb/soc_boot_flash/` **passes**
end-to-end (IMEM matches flash payload, stage-1 banner emitted) with
the current stage-0 that uses a CPU-driven XIP-aperture copy loop.
The current stage-0 source:

```c
for (uint32_t w = 0; w < n_words; ++w) {
    dst[w] = src[w];                   /* IMEM <= XIP */
}
```

The original plan sat on top of a DMA-copy version of stage-0 and a
symptom of "IMEM left at X after stage-0". **Post the §1.3 firmware
+ generator fixes** (register-map off-by-one + `dma230_req_w`
wiring, both landed 2026-04-24) the symptom has shifted: stage-0
PL230 no longer hangs on `CHNL_ENABLE_SET` — the channel now
enables, starts issuing master-port reads, copies part of the
payload, then stalls mid-burst. See the data points below under
"Phase 1 data collected". The CPU-copy version still ships working
stage-0 today; re-enabling DMA-copy is filed as a follow-up in
`nanosoc-ethernet-flash-system/docs/PROJECT_COMPLETION_TODO.md §1.3`.

## What's been ruled out

Documented with direct probe evidence from
`test_stage0_boot_path_probe` in
`nanosoc-ethernet-flash-system/cocotb/soc_boot_flash/test_soc_boot_flash.py`
(committed as `b05d2fc` on master — reusable diagnostic infra).

- **CACHE_CONFIG APB write works.** A probe at CG092's register-
  block APB input showed the complete write cycle reaching the
  cache with the right `PSEL/PENABLE/PWRITE/PADDR/PWDATA`, and the
  readback one cycle later returning `PRDATA=0x00000001`. The
  earlier "readback shows 0x0" reading was a misinterpretation of
  AHB pipeline delay (HRDATA-from-previous-beat vs HRDATA-for-
  current-HADDR). Probes A/B/C/D are clean end-to-end on the APB
  path.
- **Cache reaches READY normally.** `CACHE_STATUS[1:0]` transitions
  0 → 1 at +7 cycles, 1 → 2 (READY) at +267 cycles. Stage-0's
  1000-iteration spin budget is never exceeded; `qspi_enter_xip()`
  does not hang.
- **CPU-side XIP reads return correct data.** `dma_xip_probe`
  stage-1 app (separate test) drives both CPU and DMA through the
  XIP aperture and confirms they return byte-identical data. So
  the original "CG092 DMA-master-port returns X for DMA-initiated
  reads" hypothesis is refuted independently.
- **Back-to-back NSEQ cache handling.** `ahb_qspi`-level regression
  tests `test_xip_cache_pipelined_nseq_reads_regression` and
  `test_xip_cache_pipelined_rw_interleave_regression` pass with
  HPROT `4'b1000` and PL230's actual `4'b0001`. Cache handles
  zero-IDLE NSEQ streams correctly at the IP boundary.

## Open hypotheses — what changes when DMA runs in stage-0 context

The puzzle: the same PL230 programming + copy pattern runs from
stage-1 (post-REMAP, executing from IMEM) and works end-to-end —
but hangs the CPU on `CHNL_ENABLE_SET` poll when run from stage-0
(pre-REMAP, executing from BOOTROM at absolute `0x08000000`). Four
axes on which the two contexts differ:

**A — CPU instruction-fetch arbitration against DMA reads.**
  Stage-0 runs with PC in BOOTROM (0x08xxxxxx). The DMA reads XIP
  (0x60xxxxxx) and writes IMEM (0x10xxxxxx). All three live under
  the same busmatrix; the CPU's poll of the DMA APB register adds
  APB traffic. Maybe the busmatrix arbitrates the DMA and
  CPU-fetch-plus-poll combo into a starvation pattern where
  DMA-done never propagates back through PL230's `dma_done` ≤1
  cycle that the CPU can sample.

**B — REMAP state affects DMA's view of memory.** Stage-0 pre-REMAP
  has `sys_remap_ctrl=0` so BOOTROM aliases at `0x00000000`. DMA
  descriptor table lives at `0x18000200` (DMEM, absolute). Do any
  of: DMA master-port addresses, descriptor fetches, or cache line
  fills route through the REMAP-affected aperture? If DMA's first
  descriptor fetch lands at an address that differs between
  REMAP=0 and REMAP=1, stage-0 and stage-1 would diverge.

**C — Stage-0 runs before DMEM is initialised.** Stage-1 runs after
  IMEM has been populated AND after stage-0 has had a chance to
  touch DMEM (if crt0 does `.data` init into DMEM). The descriptor
  table at `0x18000200` may land in uninitialised DMEM on stage-0,
  whereas stage-1 runs after stage-0 has already touched it. If
  the SRAM model returns X for never-written addresses and the
  descriptor readback sees X for any field, PL230 halts internally
  without raising `dma_done`.

**D — PL230 PCLK domain.** If PL230's APB clock gating (`PCLKEN`)
  is tied to a signal that's in a different state in stage-0 vs
  stage-1, the CPU-written control registers won't get sampled.
  Probably not it — the CPU's APB writes to DMA230 at `0x50000000`
  must succeed for the poll to even be reading a register, not an
  endless 0.

## Debug plan

### Phase 1 — reproduce in isolation and capture PL230 state

**Gate:** a VCD window covering the PL230 hang in stage-0 context,
narrow enough to open in Verdi.

1. Temporarily flip stage-0 back to DMA-copy (revert the code block
   in `firmware/bootloader/stage0_bootrom/main.c` to its pre-
   "CPU copy" form — see `git log -p` for the exact block). Mark
   the revert local-only; don't commit.
2. Run `test_boot_flash_dma_copy_and_banner` with `$dumpon`/`$dumpoff`
   narrowed around the `CHNL_ENABLE_SET` poll (the window is ~50µs
   of sim time post-cache-ready; start the dump at the CPU's first
   APB write to `0x50000028`).
3. Capture:
   - PL230 master port (`dma_230_0_m_*`) — HADDR, HTRANS, HWRITE,
     HREADY, HRESP for the whole dump window
   - PL230 internal state (`u_pl230_udma.ctrl_state`,
     `u_pl230_udma.int_dma_done`) — whether it ever transitions
     out of the active state
   - Descriptor-table reads: any HADDR near `0x18000200` on the
     PL230 master port; compare HRDATA against what the CPU wrote
     into DMEM

#### Phase 1 data collected (2026-04-24)

Partial execution of Phase 1 step 1 (local main.c revert to
DMA-copy, then run `test_boot_flash_dma_copy_and_banner`) yielded
three data points before rolling back:

| Stage-0 PL230 config                        | IMEM result  |
|---------------------------------------------|--------------|
| `CYCLE_AUTO`, no SW_REQ                     | 0/241 words  |
| `CYCLE_BASIC`, `R_POWER_4`, 1× SW_REQ       | 4/241 words  |
| `CYCLE_BASIC`, `R_POWER_10`, 1× SW_REQ      | 177/241 words |

What each row tells us:

- **AUTO: 0 words.** Self-request still doesn't fire in stage-0
  context even post-§1.3. Confirms AUTO mode is not a viable path;
  the `dma230_req_w` tieoff fix didn't revive it. Likely needs a
  separate investigation into PL230's request-masking state at
  pre-REMAP / BOOTROM-executing time.
- **BASIC + R_POWER_4 + 1× SW_REQ: 4 words.** Exactly one
  arbitration unit (2²=4), then stalls waiting for the next
  request. **This is the positive control**: channel enable + APB
  register-map + `dma230_req_w` wiring + SW_REQ are all working
  end-to-end now. Matches PL230 TRM behaviour. Rules out the
  channel-never-starts hypotheses.
- **BASIC + R_POWER_10 + 1× SW_REQ: 177 words.** Real progress
  through the cache — then stalls at word 177 (dest
  `IMEM+0x2C4`). Since R_POWER_10 gives 1024 transfers per
  arbitration, one SW_REQ **should** cover all 241 words in a
  single arbitration unit. The mid-burst stall is the new open
  bug. 177 isn't cache-line-aligned (177 % 4 = 1), which rules
  out some obvious theories.

The revert is clean; the user's CPU-copy stage-0 still passes
end-to-end. Three most promising next probes for the 177-word
stall (all require Phase 1 step 3 instrumentation):

1. **AHB watchdog interaction.** `ahb_qspi` ships a 16-bit AHB
   watchdog (commit `e72d160`); long plain-SPI line-fills under
   DMA pressure might trip it. A watchdog ERR aborts the in-flight
   transaction; PL230 would see HRESP=ERROR and could halt the
   channel. Instrument the watchdog's ERR signal alongside PL230
   master-port HRESP.
2. **Cache line-fill backpressure during DMA burst.** DMA issues
   NSEQ reads faster than the cache can fill lines at `CLK_DIV=5`.
   If the cache's HREADY rises out of phase with DMA's pipelined
   address phase, data is sampled on the wrong cycle. Instrument
   HREADY relative to HTRANS transitions.
3. **Descriptor-table re-fetch / update.** PL230 writes the
   descriptor back to DMEM after each arbitration per the TRM. If
   the write races with anything reading DMEM, subsequent PL230
   state is corrupted. Instrument HADDR on the PL230 master port
   for accesses in the `0x18000200` region.

### Phase 2 — diff stage-0 vs stage-1 PL230 runs

**Gate:** a side-by-side of the same PL230 signals in two sims —
stage-0-DMA (hangs) and stage-1-DMA-via-dma_xip_probe (works).

4. Run `dma_xip_probe` to completion with the same dump discipline.
   This is the known-working reference.
5. Align waveforms by the first CPU write to `CHNL_ENABLE_SET=1`
   and diff:
   - First N PL230 HADDR/HTRANS transitions — same sequence? same
     timing relative to APB writes?
   - Descriptor fields: does PL230 see the same
     src_end_ptr / dst_end_ptr / channel_cfg on both runs?
   - `ctrl_state` trajectory — stage-0 gets stuck in which state?

### Phase 3 — narrow by flipping one axis at a time

**Gate:** a single RTL/firmware change that makes stage-0-DMA pass.

6. If Phase 2 shows stage-0 never reads the descriptor correctly,
   put the descriptor table in BOOTROM-mapped memory instead of
   DMEM as a test (firmware change only). If that unblocks,
   hypothesis C (DMEM uninitialised / X-returning) is confirmed
   and the fix is either a crt0 DMEM clear or moving the
   descriptor table.
7. If Phase 2 shows correct descriptor reads but PL230 gets stuck
   mid-transfer, suspect arbitration (A) — repro by manually
   triggering a single CPU HADDR to the APB-polled register on
   every cycle (heavy CPU traffic) and see if the busmatrix
   starves DMA.
8. If (B) REMAP is the axis, run stage-0 with REMAP asserted
   early (before DMA programming) and see if DMA then works. This
   tests whether REMAP state changes DMA's effective memory view.

## Parked — the already-refuted hypotheses

None of these are worth restarting unless Phase 2/3 turn up
evidence that points back at them.

- **H1 — interconnect arbitration handover corrupting DMA reads.**
  The `dma_xip_probe` experiment shows DMA-XIP reads are
  byte-identical to CPU-XIP reads. Interconnect routing is fine.
- **H2 — HSEL-toggle corner at the cache's slave input.** Same
  evidence rules this out.
- **H3 — PL230 HPROT/HMASTLOCK signal combos confusing the cache.**
  `ahb_qspi`-level pipelined NSEQ tests with `+HPROT_DATA=1`
  (PL230's actual default) pass; HPROT is not the differentiator.
- **H4 — cross-master APB-vs-data AHB concurrency.** No evidence
  for this; parked. The `test_xip_cache_pipelined_rw_interleave_regression`
  test covers the adjacent HWRITE-toggle sub-case.
- **H0 (from previous plan revision) — CACHE_CONFIG write lost in
  APB chain.** Refuted by direct probe at CG092's APB input.

The regression tests that anchor these parked hypotheses still ship:
`test_xip_cache_pipelined_nseq_reads_regression` and
`test_xip_cache_pipelined_rw_interleave_regression` in
`verif/cocotb/ahb_qspi_tests.py`. They keep the already-proven
cache behaviour from silently regressing.

## References

- Current working stage-0:
  `nanosoc-ethernet-flash-system/firmware/bootloader/stage0_bootrom/main.c`
  — CPU-copy loop at ~line 167.
- The passing end-to-end test:
  `nanosoc-ethernet-flash-system/cocotb/soc_boot_flash/test_soc_boot_flash.py`
  (test_boot_flash_dma_copy_and_banner).
- Uncommitted debug probe:
  `test_cache_config_write_probe` appended to the same file —
  walks the APB chain A/B/C/D on the `CACHE_CONFIG` write and
  follows the cache-ready / XIP / DMA-APB sequence post-ready.
  Reusable for Phase 1 PL230 probing with minor adaptation.
- Follow-up tracking:
  `nanosoc-ethernet-flash-system/docs/PROJECT_COMPLETION_TODO.md §1.3`
  (DMA-in-stage-0 re-enablement).
- `verif/cocotb/ahb_qspi_cocotb.v` — `+HPROT_DATA=N` plusarg
  (leftover from H3 investigation, worth keeping).
- PL230 source:
  `/research/AAA/ip_library/DMA-230/PL230-r0p0-02rel2-1/…/pl230_ahb_ctrl.v`
  — `hprot = {hprot3to1, 1'b1}`, `hmastlock = 1'b0`.
- `docs/CG092_bus_logic_bug_report.md` — separate, pre-existing
  CG092 bug filing; not related to the current hang.
