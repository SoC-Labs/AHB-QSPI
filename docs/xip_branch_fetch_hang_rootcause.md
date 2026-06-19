# XiP branch-fetch hang — reconciled root cause + fix (ahb_qspi wrapper)

> **STATUS 2026-06-18: RECONCILED / ROOT-CAUSED.** This rewrite SUPERSEDES the
> earlier `last_HADDR` "address-latch" theory (kept, refuted, at the bottom).
> The corrected root cause below is backed by SoC-sim observation with a **real
> Cortex-M0+**, RTL + TRM analysis, and the subrepo regression.

## Symptom (hardware-confirmed, sim-reproduced)

A real Cortex-M0+ executing cold code **in place** from the QSPI XiP aperture:

- runs **straight-line** code fine, but
- **LIVELOCKS on a backward branch / loop / call-return** (first non-sequential
  fetch). HW-confirmed on z2_01 silicon (Micron N25Q256A) and reproduced in SoC
  cocotb (`cocotb/soc_xip_smoke` in the nanosoc-multicore-system repo).

It is a **wrong-data livelock, not a bus deadlock**: the wrapper watchdog never
fires, `cpu_0_lockup` stays `0`, CSn keeps toggling (the controller *is*
fetching — just the wrong data is consumed for the branch target). The CPU
receives stale instruction bytes for the branch target and spins.

## What it is NOT (corrections to the old doc)

All three of these were previously blamed and are now **refuted**:

1. **NOT the `ahb_qspi_interface.sv` combinational-`HADDR`-vs-`last_HADDR`
   address latch (old "≈line 255" theory).**
   Refuted by SoC-sim measurement: at every miss, `last_HADDR == HADDR`, and
   `AHB_QSPI_ADDR` (`ahb_qspi_interface.sv:255`,
   `{HADDR[ADDR_W-1:4],4'b0000}`) always latches the correct cache line.
   Swapping the source to `last_HADDR` is a **no-op** — the address was never
   the dropped quantity.

2. **NOT the `qspi_controller` `NO_CMD` / `NO_FETCH` stale-address
   optimisation.**
   The `NO_FETCH` skip (`qspi_controller.sv:252-254`,
   `if(QSPI_enable_sync && qspi_no_cmd_latched) if(last_QSPI_ADDR==QSPI_ADDR)
   next_state = NO_FETCH;`) is gated by `qspi_no_cmd_latched`, which derives
   from the `QSPI_NO_CMD` input. In the SoC XiP config `NO_CMD == 0`
   (`AHB_SETUP = 0x800B`, command re-issued per access), so this path is
   **inactive** and cannot be the cause.

3. **NOT inside the vendor CG092 cache-core hit logic.**
   The CG092 (`p_flash_cache_f0`) is **DISABLED** in this SoC: `CCR.EN` resets
   to `0` (CCR reset value `0x40`, `STATISTIC_EN=1`, `EN=0`) and **nothing ever
   enables it**. It therefore runs in combinational **BYPASS** through the thin
   `cache_subsystem.v` passthrough (`logical/cache_subsytem/logical/
   cache_subsystem.v`) and cannot produce a cache hit at all.

## The actual root cause — AHB back-to-back-NONSEQ handshake bug in OUR wrapper

Because the cache is disabled (bypass), **every** M0+ fetch reaches
`ahb_qspi_interface.sv` directly — there is no cache line to shield the wrapper
from the CPU's pipelined AHB timing.

The wrapper FSM is `IDLE → WAIT_READ → IDLE` (`ahb_qspi_interface.sv:159-185`).
A read is "done" when `qspi_ready` asserts in `WAIT_READ`
(`ahb_qspi_interface.sv:245-249`), at which point:

```
// ahb_qspi_interface.sv:136
assign HREADYOUT = ((current_state==IDLE && last_HTRANS[1]==1'b0)
                    || (current_state==ERR2)) ? 1'b1 : qspi_ready;
```

On a **back-to-back NONSEQ** transfer — a taken branch presents a new
(non-sequential) address in the **same cycle** the previous transfer completes
— the wrapper **re-serves the previous transfer's `qspi_ready` / `HRDATA`** for
the newly-accepted transfer instead of forcing a fresh fetch. `HREADYOUT`
(line 136) asserts `1` using the **stale** `qspi_ready`, and the data path
(`ahb_qspi_interface.sv:228-259`) hands back the prior line's `HRDATA`. The CPU
samples that stale word as its branch-target instruction and livelocks.

Straight-line code never presents a new NONSEQ address in the same cycle a
transfer completes (its fetches are SEQ / spaced), so it is immune — exactly
the observed straight-line-OK / branch-hangs split.

In short: it is an **AHB back-to-back-NONSEQ handshake bug in our wrapper RTL
(`ahb_qspi_interface.sv`)**, exposed only because the CG092 cache is in bypass
and the wrapper sees the raw M0+ fetch stream.

## Why the subrepo tests pass / the coverage gap

Every existing subrepo XiP cocotb test **enables the cache first** (which
shields the wrapper behind the CG092 line buffer) and **none drives a
back-to-back NONSEQ transfer in bypass mode**. So the suite is green while
silicon hangs. The AHB BFM also issues one transaction at a time and cannot
emit the M0+ pipelined NONSEQ/prefetch timing. A new **bypass-mode
back-to-back-NONSEQ** test is being added separately to close this gap.

## Fix directions (both pursued from the submodule, not in this docs-only pass)

1. **RTL fix in `ahb_qspi_interface.sv`** so a newly-accepted transfer can't
   reuse the prior transfer's `qspi_ready` / `HRDATA`. Force a fresh
   `WAIT_READ` (clear `qspi_ready`/`qspi_started` for any new
   address-phase-accepted transfer before re-asserting `HREADYOUT`), so the
   branch-target fetch always returns its own data.

2. **Enable + configure the CG092 cache** (write `CCR.EN`, poll `STATUS` for
   READY) so it shields the wrapper *and* adds the XiP read performance the
   feature wants. Reachable at **`0x21001000`** (the bootrom's "not
   decoded / hardfault" note appears stale — **re-verify on HW**). This is the
   preferred long-term path: it both fixes the symptom and is the intended
   operating mode; the bypass-mode wrapper fix (1) is the defence-in-depth for
   any access that bypasses the cache.

## Verify (in simulation, no hardware per iteration)

- SoC env `cocotb/soc_xip_smoke` (nanosoc-multicore-system repo) runs a real
  M0+ from the XiP aperture and reproduces the hang when the cold firmware
  contains a loop — use it to confirm the branch-target fetch returns stale
  data before the fix and fresh data after.
- Re-run this repo's XiP cocotb suite
  (`make run_cocotb TESTCASE=test_xip_* SIMULATOR=vcs`) plus the new
  bypass-mode back-to-back-NONSEQ test for regressions.

## Related known issue (SEPARATE bug — do not conflate with the branch hang)

The subrepo regression found a **distinct** defect:
`test_xip_cpu_fetch_loop` **FAILS in `0x03` / 0-dummy read mode** — the first
cache-line returns **corrupted data** (a consistent wrong word, **not a hang**).
This is a data-corruption bug in the 0-dummy read path, unrelated to the
bypass-mode back-to-back-NONSEQ branch livelock above. Tracked as a separate
known issue.

---

## SUPERSEDED (kept for the record) — the original `last_HADDR` address-latch theory

> The text below is the **refuted** earlier explanation. It is retained so the
> reasoning trail is visible; do **not** act on it. See "What it is NOT" above
> for why each claim fails.

The old theory held that `ahb_qspi_interface.sv` captured the QSPI byte address
from combinational `HADDR` (≈line 255) rather than the address-phase-latched
`last_HADDR` (≈line 150), so a branch target presented mid-`WAIT_READ` was
dropped and `qspi_controller`'s `NO_CMD`/`last_QSPI_ADDR` skip re-fetched the
stale address. **Refuted:** (a) `last_HADDR == HADDR` at every miss in sim, so
the latch source is irrelevant (the swap is a no-op); (b) `NO_CMD == 0` in the
SoC XiP config, so the `NO_FETCH` skip never fires; (c) the dropped quantity is
the *handshake/data* (`qspi_ready`/`HRDATA`) on a back-to-back NONSEQ, not the
*address*.
