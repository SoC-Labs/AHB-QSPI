# Flash-model bug report + XiP code-fetch coverage findings

Investigation of why a Cortex-M0+ hangs executing branching code in place (XiP)
from the QSPI aperture at the SoC level, while the ahb_qspi IP verifies fine.
**Reported, not fixed** (per request). Branch: `feature/xip-coverage-and-drivers`.

## Headline: the IP and the flash model are EXONERATED for the tested patterns

Five new CPU-instruction-fetch-pattern XiP tests were added to
`verif/cocotb/ahb_qspi_tests.py` and **all PASS** against the **Verilog**
`SST26VF064B.v` model (the same model the SoC uses — wired in as `u_sst26vf064b`
in `ahb_qspi_cocotb.v`; the `SST26VF064B.py` file is only a cocotb poll-helper):

- `test_xip_cpu_fetch_loop` — ascending prefetch run crossing a line boundary,
  then **backward NONSEQ branch to an earlier already-cached line**, forward
  branch, second backward branch. (the exact shape the SoC hangs on)
- `test_xip_evict_then_refetch` — evict line 0 (set-aliasing + 32-line capacity
  sweep), backward-jump to re-fill it.
- `test_xip_cpu_fetch_loop_soc_0x800b` — same pattern with the literal SoC
  `AHB_SPI_SETUP=0x800B` (Fast-Read 0x0B, NO_CMD=0, command-per-line).
- `test_xip_cpu_fetch_loop_qpi_nocmd_contread`, `..._cmd_per_line` — QPI
  continuous-read and per-line command modes.

So the CG092 cache + QSPI controller + Verilog flash model correctly service
backward branches, evict→refetch, and the SoC's `0x800B` mode at the IP boundary.
**This refutes the "XiP non-sequential fetch / flash-model artifact" theory** for
every access pattern expressible at the IP.

**Residual gap (why the SoC still differs):** cocotbext-ahb only ever emits
HTRANS=NONSEQ — never SEQ — and never drives HPROT (the TB hardwires
instruction-fetch HPROT). A real M0+ linear prefetch emits NONSEQ→SEQ and may
speculatively fetch past a branch / retry on bus-fault. So the SoC XiP hang most
likely lives in the **SoC integration / real-M0+ prefetch interaction with the
XiP wait-states** (cf. the stage-0 "dummy DMEM write" timing pad), NOT in the
QSPI IP, cache, or flash model. Confirming that needs a real-M0+ stimulus
(the hardware test `docs/imem_xip/HW_XIP_TEST.md`) or a core-level TB.

## A genuine (but separate) latent model bug found

While hunting, a real defect was found in `verif/VIP/SST26VF064B.v` —
**continuous-read (NO_CMD / Mode_Configuration[7:4]==0xA) re-entry is only
implemented for `QUAD_IO_READ` (0xEB) and `SDIOR` (0xBB), not for `SPI_READ`
(0x03) or `SPI_HS_READ` (0x0B)** (re-entry handler ~lines 745-750), plus the
re-entry address reload leaves the upper address bits (`addr[ADDR_MSB:20]`)
uninitialized (~lines 1796-1805). In continuous-read mode with 0x03/0x0B, a
back-to-back re-entry would misinterpret address nibbles as a new opcode and/or
read an X/aliased address.

**Why this is NOT the SoC root cause:** it only triggers in NO_CMD
continuous-read mode for 0x03/0x0B. The SoC XiP path uses `0x800B` with NO_CMD=0
(full command re-issued per line), and `test_xip_cpu_fetch_loop_soc_0x800b` +
`..._cmd_per_line` PASS. So this is a **model coverage gap worth fixing for
completeness** (it would matter if firmware ever enables 0x0B continuous-read
XiP), but it does not explain the SoC hang.

## Recommendation

1. Treat the SoC hang as an integration / M0+-prefetch question — run the
   hardware test (`HW_XIP_TEST.md`) on z2_01, or add a core-level TB; do NOT
   chase the QSPI IP further on the strength of the IP tests above.
2. Fix the model's 0x03/0x0B continuous-read re-entry (lines ~745-750 + the
   address reload) so the model can support a future 0x0B-continuous-read XiP
   mode — and add a directed `test_sst26_continuous_read_0x0b` to cover it. (Not
   done here per the "report, don't fix" scope.)
