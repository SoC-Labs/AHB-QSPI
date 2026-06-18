# XiP branch-fetch hang — root cause + fix (ahb_qspi wrapper)

Hardware-confirmed bug: a Cortex-M0+ executing code in place from the QSPI XiP
aperture runs **straight-line** code fine but **HANGS on the first non-sequential
instruction fetch** (a taken branch / loop / call-return). Confirmed
deterministically on z2_01 silicon (Micron N25Q256A) and reproduced in the SoC
cocotb sim. XiP code execution is a standard technique and straight-line XiP
already works here, so this is a fixable wrapper bug — not a fundamental limit.

## Root cause (high-confidence, static RTL analysis)

`logical/ahb_qspi_interface/logical/ahb_qspi_interface.sv`: the QSPI byte address
sent to the controller is captured from the **combinational `HADDR`** (≈ line 255),
guarded only by "not in `WAIT_READ`" — *not* from the address-phase-latched
`last_HADDR` (already registered ≈ line 150 every HCLK).

On a taken branch the M0+ presents a **new non-sequential address** while the
previous fetch is still in `WAIT_READ`. Because capture is gated on "not
WAIT_READ" and uses combinational `HADDR`, the branch-target address is not
latched at the correct cycle. Downstream, `logical/qspi_controller/logical/
qspi_controller.sv` (the `NO_CMD` optimisation ≈ L252-256 + `last_QSPI_ADDR`
update ≈ L610) then sees the address unchanged and re-fetches the **stale**
address — returning wrong instruction bytes. The M0+ never advances past the
branch and spins. (Silicon/sim probe matches: CSn keeps toggling — the controller
*is* fetching, just the wrong address — and `cpu_0_lockup` never asserts.)

Straight-line code never presents a new address mid-`WAIT_READ`, so it's immune.
The IP's own cocotb tests pass because the AHB BFM issues one transaction at a
time and can't emit the M0+ pipelined NONSEQ/prefetch timing.

NOT the cause (checked): the CDC sync (correct 3-FF/2-FF), the CG092 cache (it
amplifies a stalled `HREADYOUT` but doesn't originate it), the SoC interconnect
(treats XiP like IMEM).

## Fix (this RTL)

Primary (≈1 line): capture the address from the latched `last_HADDR` instead of
combinational `HADDR` (or latch on every valid address phase `HREADY & HTRANS[1]`),
so a non-sequential branch target is captured before the next controller command.

Belt-and-braces: in `qspi_controller.sv`, re-latch `addr_code`/`last_QSPI_ADDR`
on every `QSPI_enable` rise so the `NO_CMD` skip can't fire on a stale compare.

## Verify (in simulation, no hardware per iteration)

The SoC cocotb env `cocotb/soc_xip_smoke` (in the nanosoc-multicore-system repo)
runs a **real M0+** from the XiP aperture and reproduces this hang when the cold
firmware contains a loop. Use it (plus its `test_xip_probe.py`) to confirm the
address is dropped before the fix and tracks correctly after. Re-run this repo's
XiP cocotb suite (`make run_cocotb TESTCASE=test_xip_* COCOTB_SIMULATOR=vcs`) to
check for regressions. Full plan: `docs/imem_xip/HW_SOLUTION_PLAN.md` in the SoC repo.
