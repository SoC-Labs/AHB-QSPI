# CDC sign-off status & the `make cdc` hang fix

## The gap (why no CDC summary ever existed)

`make cdc` used the SpyGlass goal `cdc/cdc_verify`, which additionally
runs the **advanced formal `Ac_cdc` metastability rules**. On this
design that run **does not terminate in batch** — `spyglass.out` stops
at *"Checking Rule Ac_cdc01a (Rule 429 of total 533)"* and never rolls
up a summary. That is precisely why `top_ahb_qspi_cdc_summary.rpt` never
existed, the CI `spyglass-cdc` job is `allow_failure: true`, and
`consolidated_reports/` was empty — the structural CDC (rules 1–428)
*did* run, but the hang aborted the roll-up.

## The fix (committed in cdc/Makefile)

`make cdc` now defaults to `SG_GOAL=cdc/cdc_verify_struct` — the
**structural CDC sign-off goal** (no advanced formal engine). It
completes in minutes and produces `moresimple.rpt` →
`top_ahb_qspi_cdc_summary.rpt`. The full goal is still available, opt-in,
clearly marked as long/non-terminating:

```
make cdc                          # structural — completes, writes summary
make cdc SG_GOAL=cdc/cdc_verify   # full incl. advanced formal (hangs; manual)
```

`make cdc-report` re-extracts the summary (totals, per-rule tally, and
every unsynchronised crossing) without re-running.

## Actual structural CDC result (validated 2026-05-18)

`cdc/cdc_verify_struct`, sgdc + waiver.swl applied: **141 messages,
21 waived, 0 fatal**. Per-rule: 22 Ac_conv03, 14 Ac_sync01 (properly
synced — good), 10 Ac_glitch03, **6 Ac_unsync02**, 5 Clock_sync06,
5 Ac_conv04, 3 misc.

### The 6 unsynchronised crossings — sign-off review items

All six correspond to **documented design decisions in
`cdc/top_ahb_qspi.sgdc`**, not new surprises. The SGDC explicitly states
"SpyGlass will still flag these paths as unsynchronised" because the
author deliberately used `cdc_false_path` (so the report shows where the
protection lives) rather than `quasi_static` blanket waivers:

| # | Crossing | SGDC-documented protection |
|---|---|---|
| 1 | `apb_qspi_regs.reg0[8]` (PCLK) → `ahb_qspi_interface.current_state[1:0]` (HCLK). "Qualifier not found" | ENABLE/ACK handshake path — review the qualifier |
| 2 | `qspi_controller.qspi_n_rw_bytes_latched` (SCLK) → `ahb_qspi_interface.HRDATA[127:0]` (HCLK) | RDATA "safe-by-protocol, BUSY-qualified" (SGDC §Safe-by-Protocol) |
| 3 | `apb_qspi_regs.reg3[21:0]` (PCLK) → `qspi_controller.current_state[1]` (SCLK) | control bus latched at IDLE→OP (SGDC §Control Bus) |
| 4 | `ahb_qspi_interface.AHB_QSPI_ADDR` (HCLK) → `qspi_controller.addr_code[21:4]` (SCLK) | addr loaded at OP-entry (SGDC §Control Bus TODO: explicit latch) |
| 5 | `HWDATA[31:0]` (HCLK, primary input) → `qspi_controller.QSPI_WDATA_reg[127:0]` (SCLK) | WDATA loaded at OP-entry (SGDC §Control Bus) |
| 6 | `apb_qspi_regs.reg3[21:0]` (PCLK) → `qspi_controller.last_QSPI_ADDR[21:0]` (SCLK) | addr-compare path, same OP-entry latch family |

**These are real CDC crossings protected by protocol / single-flop
latching + a software two-write-hold convention, NOT by true 2-FF
synchronisers.** That is an intentional area/cost tradeoff the SGDC
argues for (a full 2-FF sync on 22-bit addr + 128-bit WDATA + flags ≈
165 flops). For tape-out, a CDC owner must **explicitly sign each off**
as accepted-by-protocol, or convert the highest-risk ones (esp. #1
"qualifier not found", and #4/#5 which the SGDC itself flags as a
"TODO: add explicit latching regs") to real synchronisers/qualifiers.
The `Ac_glitch03` (10) are the 2-FF first-stage meta flops with
multi-source fanin — typical, review alongside. `Clock_sync06` (5) =
`PRDATA` APB read-mux multi-domain fanout — expected for the shared
read path.

## Verdict for ASIC readiness

- **Infra gap CLOSED**: `make cdc` now completes and yields a summary
  artefact every run (CI `spyglass-cdc` can be promoted off
  `allow_failure` once the 6 are signed off).
- **Sign-off NOT yet clean**: 6 documented-but-unsynchronised crossings
  remain, by design. They are *characterised and tracked*, not hidden —
  but a CDC owner must record an explicit accept/*fix decision per row
  before tape-out (the SGDC's own §Control-Bus TODO is the natural
  starting point: add explicit ADDR/WDATA latch regs to close #4/#5).
