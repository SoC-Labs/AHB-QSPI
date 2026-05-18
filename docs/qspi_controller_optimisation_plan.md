# QSPI Controller — Area & Timing Optimisation Plan

Plan for reducing area and logic depth in
[`logical/qspi_controller/logical/qspi_controller.sv`](../logical/qspi_controller/logical/qspi_controller.sv),
based on lint and TSMC65LP synthesis runs (2026-04-16).

## Baseline measurements

Synthesis library: `sc12_cln65lp_base_rvt` ss / 0.9 V / 125 °C.

### Standalone `qspi_controller` (10 ns SCLK)

| Metric | Value |
| --- | --- |
| Cell area | 8627 µm² |
| Sequential cells | 350 |
| Combinational cells | 1498 |
| Logic levels | 8 |
| Critical path slack | +0.22 ns |
| Critical path | `current_state[1] → NAND2XB(fanout 131) → INV → NAND3 → INV(fanout 127) → AOI222 → INV → QSPI_WDATA_reg[124]` |

Reports: [`imp/ASIC/qspi_controller_only/`](../imp/ASIC/qspi_controller_only/).

### Top-level `top_ahb_qspi` (HCLK / PCLK = 4 ns, QSPI_SCLK = 8 ns)

| Path group | Levels | Slack |
| --- | --- | --- |
| HCLK | 21 | 0.000 ns |
| PCLK | 8 | +0.270 ns |
| QSPI_SCLK | 14 | +0.013 ns |

Worst QSPI_SCLK path: `APB.QSPI_QIO_MODE → next_state[1] decode → last_QSPI_ADDR_reg[2]`.
Reports: [`imp/ASIC/`](../imp/ASIC/).

### Lint summary

`make lint MODULE=qspi_controller` → 0 errors, 75 warnings. Categorised:

- 17 × UELCIT (case-tag width mismatches in `QSPI_RDATA` mux)
- 17 × NEFLOP / 17 × FFNMOD (intentional negedge shift-out bank)
- 11 × UELOPR / 8 × IMPTYP (counter `+ 1` width inference)
- 4 × ULCMPE / 2 × ULRELE / 1 × BITUNS (other width mismatches)
- 2 × IOCOMB / 2 × CLKUCL (intentional SCLK output mux)

---

## Optimisation tasks

Tasks are ordered by expected payoff. Targets are predicted from cell counts in
[`qspi_controller_refs.rep`](../imp/ASIC/qspi_controller_only/qspi_controller_refs.rep).

### Task 1 — Stop reloading `QSPI_WDATA_reg` in every state

**Where:** [`qspi_controller.sv:269,280,308,319,323,332`](../logical/qspi_controller/logical/qspi_controller.sv#L269)

**Problem.** `QSPI_WDATA_reg <= QSPI_WDATA;` is repeated in every FSM branch
except DATA_O (which shifts). Combined with the two shift variants this forces
synthesis to build a 4-input mux on every one of the 128 negedge flops. The
result dominates combinational area: 471 × `AOI22_X0P5M` (~1583 µm²) and
168 × `OAI222_X0P5M` (~806 µm²) — together about 28 % of the design.

**Fix.** Load `QSPI_WDATA_reg` once on the transition into DATA_O (or in IDLE
once `QSPI_ENABLE` is sampled). Inside DATA_O, only shift. The CDC SYNTH_133
note at [line 254](../logical/qspi_controller/logical/qspi_controller.sv#L254)
constrains the *shift-out* branches, not the load source.

**Expected payoff.** 1500–2000 µm² area reduction (~20 %), one mux level
removed from the D-side cone of `QSPI_WDATA_reg`.

**Validation.** Re-run `dc_synth_qspi_controller.tcl`; cocotb regression
under [`verif/cocotb/`](../verif/cocotb/) must pass (page-program test in
particular — that exposed the original spurious-bit bug).

---

### Task 2 — Drop async reset on the shift-register bank

**Where:** flops `op_code`, `addr_code`, `qspi_mode_reg`, `QSPI_WDATA_reg`
in the negedge `always` block ([`qspi_controller.sv:257-337`](../logical/qspi_controller/logical/qspi_controller.sv#L257-L337)).

**Problem.** All four registers are loaded from inputs before they are read.
The async-reset clear is functionally redundant but forces DC to use
`DFFNRPQ_X1M` (12.0 µm²) instead of a plain `DFFNQ` (~10 µm²) on 165 flops.

**Fix.** Move these four registers into a separate `always @(negedge SCLK)`
block with no reset branch.

**Expected payoff.** ~250–400 µm². No timing impact.

**Risk.** SDC / DFT may want a defined reset value at scan-shift. Coordinate
with the DFT flow before merging.

---

### Task 3 — Collapse the 16-way 128-bit `QSPI_RDATA` mux

**Where:** [`qspi_controller.sv:404-423`](../logical/qspi_controller/logical/qspi_controller.sv#L404-L423)

**Problem.** Each case entry permutes `data_in_reg` slices in a
non-shareable way (e.g. `{data_in_reg[31:0], data_in_reg[39:32]}` vs.
`{data_in_reg[31:0], data_in_reg[63:32], data_in_reg[71:64]}`). DC cannot
share these as one mux. Also, `QSPI_N_RW_BYTES` is 5 bits but case tags are
4 bits (16 × UELCIT) — values 16..31 silently return 0.

**Fix options.**

1. Align the byte order while *sampling* into `data_in_reg` (recommended) so
   `QSPI_RDATA` becomes a width-mask / zero-extend.
2. Build a 16-input *byte-mux* instead of a 128-input *bit-mux*.

Either fixes the silent-zero functional bug too.

**Expected payoff.** Several hundred µm² (combinational only). Removes 16
UELCIT lint warnings.

---

### Task 4 — Move `±1` constants off the critical path

**Where:**
- [`qspi_controller.sv:188`](../logical/qspi_controller/logical/qspi_controller.sv#L188)
  `dummy_counter >= QSPI_DUMMY_CYCLES - 1`
- [`qspi_controller.sv:392,395`](../logical/qspi_controller/logical/qspi_controller.sv#L392)
  `byte_counter != QSPI_N_RW_BYTES + 1`

**Problem.** A subtractor/adder feeds a comparator on the same combinational
cone as the next-state logic. This is part of the QSPI_SCLK 14-level path
at top level.

**Fix options.**

1. Store `cycles_minus_1` / `bytes_plus_1` in the APB register file instead.
2. Use down-counters that terminate at 0 (single OR-reduction vs. N-bit
   equality).

**Expected payoff.** 1–3 logic levels off the QSPI_SCLK group; recovers
slack from 0.013 ns to ~0.5 ns and gives headroom for cross-domain delay.

---

### Task 5 — Factor the shared "post-phase" next-state decode

**Where:** [`qspi_controller.sv:105-198`](../logical/qspi_controller/logical/qspi_controller.sv#L105-L198)
(repeated in OP, ADDR, MODE, DUMMY).

**Problem.** The priority chain
`if(CONT_READ)→MODE elsif(DUMMY_CYCLES!=0)→DUMMY elsif(READ)→DATA_I elsif(WRITE)→DATA_O else→IDLE`
appears verbatim in four places. DC will share, but the RTL depth still
limits structuring choices on the next-state cone.

**Fix.** Compute `wire [STATE_W-1:0] post_phase_state;` once and reuse it
in every terminal branch.

**Expected payoff.** 1 logic level off the next-state cone; readability and
maintainability win is the bigger benefit.

---

### Task 6 — Right-size the address counter and register

**Where:** [`qspi_controller.sv:43,49,376-377`](../logical/qspi_controller/logical/qspi_controller.sv#L43)

**Problem.** `addr_counter` is 5 bits but only counts up to 0x17 (24).
`addr_code` is 24 bits but the loaded value is `{2'b00, QSPI_ADDR}` where
`QSPI_ADDR` is 22 bits — top two bits are constant zero.

**Fix.** Tie off the unused MSBs of `addr_code`. Leaves DC free to constant-
propagate the upper bits across the shift logic.

**Expected payoff.** Small (~50–100 µm²); also removes the `5'h17` 4-input
AND on the next-state path.

---

### Task 7 — Free lint cleanup

**Where:** various, listed in
[`lint/qspi_controller_hal_report.txt`](../lint/qspi_controller_hal_report.txt).

- `4'b0` → `4'b0000` at [line 326](../logical/qspi_controller/logical/qspi_controller.sv#L326)
- All `counter + 1` → sized literal (kills 11 UELOPR + 8 IMPTYP)
- Factor the redundant `QSPI_enable_sync==1'b1` at [line 87](../logical/qspi_controller/logical/qspi_controller.sv#L87) (IFSMCD)
- Width-match the `QSPI_RDATA` case tags (covered by Task 3)

**Expected payoff.** Zero gates; cleaner lint baseline so real warnings
stand out.

---

## Suggested sequencing

1. Tasks 1 + 2 first — biggest area win, low timing risk, easy regression.
2. Re-synth, capture new baseline, then Task 4 to recover QSPI_SCLK slack.
3. Tasks 3, 5, 6, 7 in any order; rerun lint after Task 7.

Each task should be regressed against the cocotb suite in
[`verif/cocotb/ahb_qspi_tests.py`](../verif/cocotb/ahb_qspi_tests.py)
(particularly the page-program path — that flushed out the spurious-bit
bug noted at [line 286](../logical/qspi_controller/logical/qspi_controller.sv#L286)).

## Out of scope

- The `flash_cache_tag` `WEN` width mismatch surfaced during top-level synth
  (`Error: Width mismatch on port 'WEN' of reference to 'flash_cache_tag'`).
  This is in [`logical/cache_models/tsmc65/cache_ram.v`](../logical/cache_models/tsmc65/cache_ram.v),
  not the QSPI controller — separate fix.

---

## Outcome — 2026-05-18 (honest results; supersedes the predicted payoffs)

Tasks 1+2 (Agent B) and 4+7 (this pass) were implemented and measured.
The plan's predicted payoffs (~20% area from Task 1, slack recovery
from Task 4) **did not materialise** at standalone synthesis. What
actually happened:

**The single most important finding — caught by synthesis, NOT cocotb:**
Agent B's merged Task 1/2 (`7afecfd`) was **non-synthesisable** — the
block split left `op_code/addr_code/qspi_mode_reg/QSPI_WDATA_reg`
driven by two `always` blocks (`ELAB-366` multi-driver). VCS tolerates
mutually-exclusive multi-driver so cocotb passed 55/55 and gave false
confidence; `feat-nanosoc_int` could not be synthesised at all until
the redundant pin-drive-block reset of those regs was removed. Running
synthesis (not trusting the functional regression) is what surfaced it.
**This fix is mandatory, independent of any optimisation goal.**

**Measured (standalone qspi_controller, 10 ns QSPI_SCLK, sc12 ss/0.9/125),
against the correct pre-Agent-B baseline `cda2c86` (NOT the stale Apr
report, which predated this project's CDC hardening — that +1084 µm² /
+73 flops is CDC, not Blocker 2):**

| | cda2c86 (pre-B) | final (T1/2/4/7 + fixes) |
|--|--|--|
| Total cell area | 9711.8 µm² | 9553.0 µm² (**−1.6 %**) |
| Sequential cells | 423 | 432 (+9 = Task 4 `m1`/`p1`) |
| Logic levels | 7 | 8 (+1) |
| Critical-path slack | +0.05 ns | +0.04 ns |
| Synthesisable | yes | yes (was BROKEN at `7afecfd`) |
| cocotb | 55/55 | 55/55 |

Net: a small (~1.6 %) area improvement and a mandatory
synthesisability repair — *not* the headline optimisation the plan
projected. Task 4's ±1-precompute is timing-neutral here (its real
target is the top-level QSPI_SCLK 14-level path, which standalone
synth does not exercise — re-measure at top-level FC signoff). Task 2
made truly reset-free per spec (Agent B's first cut kept a sync-reset
mux); area-neutral — DC was already optimising that mux.

**Tasks 5 & 6 — deliberately NOT done.** Task 5 (factor the shared
post-phase next-state decode) is a readability/1-level change on an
FSM with a documented spurious-bit-bug history — poor risk/reward.
Task 6 (~50 µm², right-size addr_code) is entangled with the SPI
24-bit address framing — real regression risk for marginal gain.
Both are low value relative to the verification cost on this fragile
block; revisit only if top-level QSPI_SCLK timing closure needs them.
