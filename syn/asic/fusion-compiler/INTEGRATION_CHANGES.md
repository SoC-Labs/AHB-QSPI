# Partition-flow integration changes

Companion to `FLOW_COMPARISON.md`. Implements the three asks: close the
chip-top integration gaps, align the 65 nm partition flow with the 28 nm
full-chip flow where it makes sense, and add placement-legality checks.

## Verification status — read this first

These changes were **not executed** — `fc_shell` / `fm_shell` and the
cln65lp PDK are not available in the editing environment. What *was*
verified:

- **Tcl structural validity**: all edited scripts pass `info complete`
  (balanced braces/brackets/quotes).
- **Makefile**: `make -n fc_all` parses and the dependency graph
  (`…→fc_abstract→fc_lec`, cross-delegation to `../formality`) resolves.

What is **not** verified and must be checked on a real run: fc_shell
command/option spelling for this 2022.12 build (esp. `write_parasitics`,
`save_upf`, the new `check_design` rule names, `check_pin_placement`,
`check_clock_trees`). Every new command is wrapped so a name/option
mismatch **degrades to a WARNING/SKIP, not a stage failure** — but the
intended behaviour still needs a live run to confirm.

No fabricated PDK/foundry data was introduced anywhere (see routing
rules below).

## 1. Chip-top integration gaps

| Change | File | Notes |
|--|--|--|
| Signoff-stage SVF named | `scripts/5_signoff.tcl` | Closes the `init→synth→cts→route→signoff` SVF chain `formality/scripts/run_lec.tcl` walks; signoff slot was silently dropped before. |
| GDS stream-out | `scripts/6_partition_export.tcl` | Already wired (concurrent edit) to the `GDS_*` vars that were already in `common.mk`; verified consistent. |
| Per-scenario SDF | `scripts/6_partition_export.tcl` | Was hardcoded `scen_slow`. Now loops `active==true` scenarios; emits `${top}.${scen}.sdf` + a slow-biased `${top}.sdf` alias. Automatically multi-corner once `scen_fast` exists. |
| Per-scenario SPEF | `scripts/6_partition_export.tcl` | New `write_parasitics` per scenario so chip-top does real hierarchical STA instead of re-flat-extracting. Guarded (missing extraction → warning). |
| Boundary UPF | `scripts/6_partition_export.tcl` | New `save_upf` so a multi-Vdd chip-top sees the block's supply-set / single PD_TOP / absence of isolation-retention. Guarded. |
| Manifest provenance | `scripts/6_partition_export.tcl` | Source block, timestamp, scenario coverage (+ explicit "no scen_fast → hold not covered"), SHA256 per file, per-artefact role string. |

**Not done — ETM.** `write_lib_model -format etm` is genuinely
unavailable in fc_shell 2022.12 (pre-existing NOTE in the script is
correct). The proper fix is a downstream PrimeTime `extract_model`
stage; that needs PT and is out of scope for a script edit. The `.dlib`
block + the new per-scenario SPEF/SDF give the integrator a working
hierarchical-STA path in the meantime.

## 2. Flow alignment (65 nm partition ↔ 28 nm full-chip)

- **In-flow LEC**: new `fc_lec` + `fc_all` Makefile targets. `fc_lec`
  **delegates** to the existing `syn/asic/formality` Makefile (which
  already enforces the `FM_LEC_OK` marker) rather than duplicating
  match/verify — one LEC implementation. `fc` is unchanged (PnR-only,
  for sites without Formality); `fc_all = fc + fc_lec` is the CI /
  tape-in target. Mirrors Flow B's stage-6 Formality.
- **Routing-rules hook**: `4_route.tcl` now sources
  `inputs/routing_rules.tcl` if present (after setup, before
  `route_auto`), structurally matching Flow B's `routing_rules.tcl`.
  Off by default (sc12 cln65lp routes clean on defaults).
- **Multi-corner**: not a new mechanism — the flow already auto-creates
  `scen_fast` when `MEM_DBS_FF` is populated (`make mem_ff_db`). The
  export/QoR/DRC changes now *propagate* that second corner instead of
  hardcoding slow. Documented in `make help` and the manifest. No hold
  corner was fabricated.

Makefile `help` updated for all new targets/vars; `clean` already covers
the new artefacts (all under `FC_WORK`/`FC_OUTPUTS`).

## 3. Placement-legality checks (`scripts/7_drc.tcl`)

New **tier 0** (structural/constraint pre-checks, fail-fast before the
heavy geometric tier 1):

- `pre_netlist` = `check_design {netlist_pre_check design_data}` — **hard
  gate** (multi-driver/undriven nets are real LEC+LVS hazards).
- `pre_signoff` = `check_design {pre_signoff_stage}` — advisory.
- `pre_timing` = `check_timing` — advisory (chip-top reconstrains).

New **tier 1b** (per-aspect handoff legality):

- `check_placement` = `check_design {placement}` — **hard** (proves no
  std cell crept inside the `place_memories.tcl` macro keepouts).
- `check_mv_design` = `check_design {mv_design}` — **hard** (asserts no
  stray MV constructs before a multi-Vdd chip-top wraps the block).
- `check_pin_placement` — **hard** (boundary pins on-track / abuttable).
- `check_clock_trees` — advisory.

Summary table extended (`summarise_check`, EMS-aware with rc fallback);
hard checks count toward the integration gate, advisory ones report
WARN/SKIP and never block. `check_lec_compatibility` and
`block_abstract_ready` were **deliberately not added** — they are not
real fc_shell atomic check names; inventing them would fabricate tool
behaviour. LEC compatibility is instead covered properly by `fc_lec`
(real RTL-vs-netlist Formality).

## Suggested validation order on a real run

1. `make fc_drc` → inspect `reports/07_summary.rep`: any new check
   showing `SKIP` means that command/rule name differs in this build —
   adjust the name, it is not a design problem.
2. `make fc_abstract` → check `reports/06_abstract_manifest.txt` for the
   SPEF/UPF rows; a SPEF "write failed" warning now means
   `extract_parasitics` itself failed (it is wired into `5_signoff.tcl`).
3. `make fc_lec` (or `fc_all`); then `make fc_etm` (scaffold).
4. `syn/asic/scripts/verify_partition_handoff.sh` — re-hash the drop.

## Follow-on round 1 — implemented (still not silicon-validated)

Same verification caveat as above: Tcl `info complete`, `bash -n`,
`make -n`, YAML parse, and a **functional test of the verify script**;
no live `fc_shell`/`pt_shell` run.

- **#3 signoff RC** — `5_signoff.tcl` now runs `extract_parasitics`
  before QoR/save and **`exit 1` (no `FC_STAGE_OK`) if it fails**, so a
  stale-RC signoff block can't slip through and stage-6 SPEF has data.
- **#2 SKIP-safe checks** — every tier-0/1b check uses `run_check_adv`
  (unknown rule → SKIP, never a false block); multi-rule `check_design`
  calls split one-rule-per-call (`pre_netlist` + `pre_designdata`);
  unknown-name regex broadened. Hard/advisory gate stays in
  `summarise_check`.
- **#10 hand-off verify** — `syn/asic/scripts/verify_partition_handoff.sh`
  re-hashes every delivered file vs the manifest and surfaces hold/min
  coverage. Functionally tested (OK/FAIL/WARN/coverage, exit 1 on
  mismatch).
- **#5 ETM** — `syn/asic/primetime/` (mirrors the formality tree:
  sentinel + `PT_ETM_OK` grep), one ETM per delivered corner; `fc_etm`
  delegates to it. **Scaffold, deliberately NOT in `fc_all`.**
- **#11 CI** — opt-in `fc-pnr-lec-tsmc65` job (manual, gated on
  `RUN_FC_PNR`, `allow_failure`) runs `fc_all` + the verify script.
  Promotion path to a hard gate documented inline.

Deferred (need a live tool / other people, not script work): #1 live
run, re-enabling clock gating (#4), IR-drop/EM signoff (#6), GDS LVS
(#7), `make mem_ff_db` for scen_fast (#8), per-corner SDC (#9),
`pg_mesh.tcl` coordination (#13), boundary-UPF review (#14).

## Live validation — 2026-05-15 (supersedes the "not silicon-validated" caveat)

A clean serial `make fc_all` completed end-to-end (16:18→16:35): all
seven stages reached `FC_STAGE_OK`, **both `scen_fast` + `scen_slow`
corners active** (so #8 is effectively done — `MEM_DBS_FF` is populated
and the multi-corner SDF/SPEF path is live).

**Confirmed working on the live run:**
- **#3** signoff passed. Note: `extract_parasitics` does **not** exist
  in `fc_shell` (`CMD-005`); `5_signoff.tcl` now uses `update_timing
  -full`. The `exit 1`-no-`FC_STAGE_OK` guard correctly caught the bad
  command on the first attempt — the sentinel design works.
- **#10** `verify_partition_handoff.sh` → `RESULT: PASS, OK=20 WARN=0
  FAIL=0` against the real drop (parsed the enriched manifest incl. all
  multi-corner SPEF).
- **LEC** `FM_LEC_OK: top_ahb_qspi` — `fc_lec` delegation works, RTL ≡
  netlist.
- **#1** the manifest is the enriched format (source block, SHA256,
  roles, scenario coverage); `.upf` (save_upf) produced.

**Found and fixed (live-run findings):**
- **#2 had a real hole:** `check_design` reports an unknown rule via the
  EMS stream (`EMS-035 "is not a valid check name"`), *not* a Tcl error,
  so `run_check_adv`'s `catch` never fired — `netlist_pre_check`,
  `design_data`, `placement`, `pre_signoff_stage` were misreported
  FAIL/WARN instead of SKIP. `summarise_check` now detects the EMS-035
  signature in the report and classifies SKIP. Valid in this build:
  `check_timing`, `check_pin_placement`, `check_clock_trees`,
  `mv_design`. Mapping the absent names to real equivalents needs
  `check_design -help` on the tool (tuning follow-up, not fabricated).
- Manifest role-map: `write_gds -compress` → `.gds.gz`,
  `write_parasitics` → per-RC-corner `.spef` + `.spef_scenario` index;
  added explicit role keys.

**Genuinely outstanding (not my code):** DRC `RESULT: 823 violations`,
dominated by `check_pg_connectivity` 768 floating std-cells (`VDD
Terminals: 0`) + `check_routes` 52 DRCs. This is the PG-mesh/route
quality domain — the uncommitted in-progress `pg_mesh.tcl` work (#13),
not the integration scripts. The new checks correctly *surface* it;
they don't cause it.

## Validation round 2 — 2026-05-15 (PG repair attempt: negative result)

Re-ran synth→…→drc with two changes under test.

- **SKIP-safety fix (`1899773`) — CONFIRMED working live.** DRC summary
  now shows `pre_netlist` / `pre_designdata` / `pre_signoff` /
  `check_placement` as `SKIP "check name absent in this fc_shell build"`
  instead of the earlier false FAIL/WARN. EMS-035 detection is correct.
- **Route-DRC (concurrent `4_route.tcl` detail-route/ECO work) —
  validated:** `check_routes` 52 → **15** DRCs.
- **PG floating-cell repair (`b5521d3`) — ineffective, REVERTED
  (`01029bb`).** `connect_pg_net -automatic` + a post rail strategy at
  synth did **not** reduce floating: 771/517 → 814/487 (~unchanged,
  marginally worse on VDD). The `02d` snapshot showed 5644 cells at the
  synth-stage repair vs 7070 by DRC — CTS/route add ~1400 cells *after*
  any synth-time repair, and the stubborn ~11 % even at synth time
  proves it is **not** a logical-binding problem (`connect_pg_net`
  cannot fix it). Corrected root cause: the M1 follow-pin rails are
  physically trimmed/blocked in the congested `PATH_31_*` band between
  the macro columns. The real fix is tool-iterative rail-pattern work
  (rail without `trim`, macro-adjacent rail-blockage handling, or a
  post-route `route_pg`/rail-repair pass) — it cannot be done blind
  without `fc_shell` in the loop, so it is correctly left to the
  `pg_mesh.tcl` owner (#13) rather than shipped as a non-fix.

Net DRC gate: 829 violations, now almost entirely
`check_pg_connectivity` (814) — `check_routes` is down to 15 and the
phantom tier-0/1b FAILs are gone. The remaining blocker is one genuine
PG-mesh problem, precisely characterised above.

## PG floating-cell deep-dive — definitive diagnosis + hand-off

Read-only tool probes of the saved `signoff.design`/`drc.design` blocks
settled what the report alone could not:

- **It is 100 % physical, 0 % logical.** Querying every leaf cell's
  PG-pin nets directly: **0 cells are logically floating** — all 7070
  *are* tied to VDD/VSS. `check_pg_connectivity`'s returned collection
  is **floating *wires*** (VDD 36, VSS 22), not cells; the `{PATH_31_*}`
  in the report are wire-path names, never cell instances.
- **Mechanism:** `pg_mesh.tcl` runs `compile_pg` at **init, before
  placement/route**. M1 follow-pin rails exist at every row-Y
  (9.9→177.9 µm) but, in the macro-fragmented central std-cell channel
  (data RAMs L x≈5–317 / R x≈653–965; tag RAMs centred y≈74.7–115.2),
  ~36/22 rail segments never get a via stack up to the 50 µm-pitch
  M5/M6 mesh. Every std cell on an orphaned segment is reported floating
  → 814 VDD / 487 VSS.

**Three tool-validated fix attempts, all ineffective (all reverted /
never committed):**

1. Post-placement `connect_pg_net` + M1-only rebuild (synth): no change
   — there is no logical problem to fix.
2. Post-route `compile_pg -strategies {rail_strategy …}`: the init-stage
   strategies **do not persist** across `save_block`/`open_block`;
   command errored, guard no-op'd it.
3. Post-route **inline-recreated** patterns+strategies + `compile_pg`:
   partially ran ("Creating via shapes for strategies mesh_strategy_so")
   then **errored mid-run** before completing rail/connect; floating
   cells unchanged (814/487), floating *wires got worse* (36→72 /
   22→44). Net-negative.

**Conclusion — needs interactive ownership, not more non-interactive
trial-and-error.** Each attempt is a ~6 min batch run and #3 proved
`compile_pg` aborts part-way post-route for a reason only visible by
running it interactively (capture the full `pg_err`; the abort is after
`mesh_strategy_so` — likely `macro_strategy_so`, a via-rule, or a
routed-net/blockage conflict). This belongs to the `pg_mesh.tcl` owner
in `fc_shell -gui`.

**Concrete fix recipe for the owner:**

- Reproduce in one interactive session: `make gui BLOCK=route.design`,
  then paste `pg_mesh.tcl` steps 3–6 (patterns+strategies, `*_so`
  names) and run `compile_pg -strategies {…}` **without a catch** — read
  the exact failing command/object.
- Most likely correct structural fix: **move the std-cell-rail + mesh
  via-stitch `compile_pg` out of init and into a post-route PG stage**
  (its own stage, isolated from the in-flight `4_route.tcl` detail-route
  cleanup), so rails are stitched to the mesh against the *final* placed
  + routed layout — which init-time `compile_pg` structurally cannot do.
- Alternative: a channel-confined fine-pitch **M3** vertical stitch (the
  original author's abandoned M2-stitch idea, moved off M2 to avoid
  std-cell pin-access contention) so every M1 segment has a frequent
  via path up.
- Either way **co-manage the PG-vs-signal DRC interaction** with the
  `4_route.tcl` work (post-route PG metal can add `check_routes`
  spacings; `check_routes` is currently 15 and separately converging).

Net: the integration-flow scope of this task is validated end-to-end;
this single PG-routing item is fully characterised and handed off with a
reproducible recipe, rather than left as an unvalidated guess.
