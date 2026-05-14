# Fusion Compiler Flow Comparison

**Flow A** — AHB QSPI, TSMC 65 nm LP, **hierarchical block / partition**
`/home/dam1n19/SoCLabs/ahb_qspi/syn/asic/fusion-compiler/`

**Flow B** — nanosoc 38-pin chip, TSMC 28 nm HPC+, **full-chip with pad-ring**
`/home/dam1n19/SoCLabs/nanosoc-chiplet-tech/ASIC/TSMC28nm/38pin/Synopsys_FC/`

The two flows share the same Synopsys-recommended outer skeleton (init → synth → CTS → route → signoff) but diverge sharply on everything that depends on **scope** (partition vs. die), **process node** (65 nm single-Vdd vs. 28 nm multi-Vdd UPF) and **execution rigour** (sentinel-driven Make vs. straight-line shell targets).

---

## 1. Scope and intent

| | Flow A — AHB QSPI partition | Flow B — nanosoc full chip |
|--|--|--|
| Target | One block that will be **dropped into a chip-top** as a hardened macro | One full **tape-out-ready ASIC** including pad ring |
| Final products | LEF / DEF / NDM / gate Verilog / SDC / SDF — *consumed by an integrator* | Merged GDSII, gate Verilog, SDF — *sent to fab* |
| Sign-off scope | Block-ready check + opt-in ICV DRC; chip-level signoff deferred upstream | Full-chip DRC + Formality LEC |
| Die strategy | Absolute die size driven by macro footprint (970 × 190 µm) | Pad-ring driven die (1111 × 1667 µm) |

This is the single most important difference: Flow A is a *macro-builder*, Flow B is a *chip-builder*. Almost every other divergence falls out of this.

---

## 2. Stage decomposition and execution model

**Flow A — 7 stages, Make-orchestrated with sentinels**

`syn/asic/fusion-compiler/scripts/`:
```
1_init_design.tcl      2_synthesis.tcl       3_clock.tcl
4_route.tcl            5_signoff.tcl         6_partition_export.tcl
7_drc.tcl              + helpers: setup.tcl, setup_design_options.tcl,
                         pg_mesh.tcl, place_memories.tcl, place_pins.tcl
```

The makefile (`syn/asic/fusion-compiler/makefile`) drives each stage with:
- A `.done` sentinel in `$(FC_WORK)`
- A grep for the `FC_STAGE_OK: <stage>` marker that every Tcl script prints at the end (e.g. `1_init_design.tcl:162-166`)
- A `save_block` checkpoint per stage (`init.design`, `compile.design`, `cts.design`, `route.design`, `signoff.design`, `drc.design`)

`fc_shell` exits 0 even on Tcl errors, so the marker is the only reliable "stage actually finished" signal — the Make wrapper enforces that. A failed stage leaves no sentinel, so `make -j` and incremental re-runs are safe.

**Flow B — 6 stages, plain `cd $(WORK_DIR); fc_shell -f …`**

`ASIC/TSMC28nm/38pin/Synopsys_FC/scripts/`:
```
1_design_setup.tcl    2_synthesis.tcl       3_clock.tcl
4_route.tcl           5_signoff.tcl         6_formality_signoff.tcl
+ config.tcl, setup.tcl, pvt_setup.tcl, lib_cells.tcl, floorplan.tcl,
  io_plan.tcl, power_plan.tcl, route_opt.tcl, routing_rules.tcl,
  synopsys_lib_conversion.tcl, nanosoc_chip_pads.upf
+ subdirs: calibre_drc, calibre_drc_new, virtual_pads, io_file
```

The makefile (`ASIC/TSMC28nm/38pin/Synopsys_FC/makefile`) is a flat list of targets — no sentinels, no log-marker validation, no per-stage dependency. Reruns require manual housekeeping. The trade-off is fine for a final tape-out chip, but less robust for the iteration loop typical of block bring-up.

Notably, Flow B has **a dedicated stage 6 for Formality** (LEC against RTL); Flow A keeps Formality in a sibling tree (`syn/asic/formality/`) and uses stage 6 for *partition export* instead.

---

## 3. Library and corner setup

**Flow A** (`scripts/setup.tcl`, `setup_design_options.tcl`, `1_init_design.tcl:48-92`):
- Std-cell ref-lib: `sc12_cln65lp_base_rvt` (sc12 65 nm LP, RVT only)
- Memory frames: `flash_cache_data` + `flash_cache_tag` (LEF + .db)
- Single core voltage: **1.08 V**
- MCMM: **2 scenarios** — `scen_slow` (setup) and `scen_fast` (hold)
- Single `inputs/constraints.sdc` overlaid on both scenarios
- TLU+ parasitics inferred from the shared reference flow (`syn/asic/scripts/`)

**Flow B** (`scripts/setup.tcl`, `lib_cells.tcl`, `pvt_setup.tcl`):
- Std-cell ref-libs: `cln28ht` (base), `cln28ht_pmk` (power-mux), `cln28ht_hpk` (high-perf)
- Memories: `sram_16k`, `rom_via`
- I/O cells: `io_lib` (1.8 V), `pad_lib` (flip-chip pads)
- Two core voltages: **0.9 V** (VDD / VDDACC) + **1.8 V** (VDDIO)
- MCMM: **5 scenarios** — `hold_ffgnp`, `hold_ssgnp`, `setup`, `em`, `typical` (`pvt_setup.tcl:29-76`)
- Per-corner SDC: `constraints_hold_ffg.sdc`, `constraints_hold_ssg.sdc`, `constraints_setup.sdc`, `constraints_typical.sdc`
- **9 TLU+ corners** (cbest / cworst / rcbest / rcworst, each with a `_T` temperature-derate variant, plus `typical`) — `pvt_setup.tcl:5-24`
- Per-library `set_operating_conditions` nested per scenario

The 65 nm flow can get away with two corners; the 28 nm flow needs the full corner matrix for setup/hold/EM/leakage closure.

---

## 4. Floorplan

**Flow A — absolute die, hand-placed macros**

Die size is set in the makefile (`FC_DIE_WIDTH=970`, `FC_DIE_HEIGHT=190`, `FC_CORE_OFFSET=10`) and consumed by `1_init_design.tcl`:
```tcl
initialize_floorplan -control_type die -shape R \
                     -side_length {970 190} -core_offset 10
```
`place_memories.tcl` then locks 10 cache macros into a **split-column** layout:
- 4 × `flash_cache_data` stacked on the LEFT edge
- 4 × `flash_cache_data` stacked on the RIGHT edge
- 2 × `flash_cache_tag` side-by-side in the **centre gap**
- All macros `physical_status = fixed`, with 5 µm hard + 8 µm soft keepouts (`place_memories.tcl:131-139`)

`place_pins.tcl` assigns block ports to the four die edges (QSPI on top, AHB on bottom, APB on left, IRQ/debug on right) — **no physical pad cells**.

**Flow B — pad-ring full-chip floorplan**

`floorplan/floorplan.tcl` initialises a 1111.11 × 1666.67 µm die with a 135 µm core offset. `scripts/io_plan.tcl` builds a 38-pin pad ring:
- 7 pads on top (TEST_I, SWDCK_I, VDD/VSS/VDDIO, P1_00/01)
- 9 pads on bottom (including `PRCUT_L`/`PRCUT_R` and 3 × VDDACC)
- 12 pads each on left and right (CLK_I, SWDIO_IO, NRST_I, SE_I, …)
- 4 × `PCORNER_G` corner cells
- `create_io_filler_cells` injects PFILLER20_G / PFILLER10_G between signal pads
- Wire-bond ring overlay: 60 × `PAD60GU` cells offset from the signal pad ring (`floorplan.tcl:137-166`) in four orientations (R0/R90/R180/R270)

This is a flip-chip-style pad-ring built directly in FC — there is no equivalent in Flow A because the chip-top integrator owns that responsibility.

---

## 5. Power planning

**Flow A — single-domain mesh, no UPF** (`pg_mesh.tcl`)
- One power domain (VDD/VSS only) — block exposes VDD/VSS as supply ports for the integrator
- M1 follow-pin rails (std-cell built-in)
- M5 horizontal mesh + M6 vertical mesh, 2 µm wide, 50 µm pitch
- `trim_strap = true` to keep straps from blocking macro pins
- Single `compile_pg` invocation

**Flow B — UPF-driven multi-Vdd mesh** (`power_plan.tcl` + `nanosoc_chip_pads.upf`)
- Loads UPF defining two core domains: `DEFAULT_VA` (VDD/VSS) and `ACCEL` (VDDACC/VSS), each with its own voltage area shape
- Supply set: VDD, VDDACC, VSS, VDDIO, VSSIO, POC
- AP/M9 power ring around the core (4 µm wide, 60 µm pitch)
- Top-layer mesh M9 + AP @ 4 µm, 60 µm pitch
- M5 macro straps over ROM/SRAM (0.21 µm × 10 µm pitch)
- M2 std-cell rails — *two separate strategies* per voltage area
- `ENDCAPTIE3` end-caps + `FILLTIE5` tap cells (132 µm spacing) per voltage area
- `read_virtual_pad_file` for the pad-side rail constraints

The Flow B power plan is genuinely a chip-power plan; the Flow A plan is a block-mesh that hands off to a chip-level power network.

---

## 6. Synthesis (stage 2)

Both flows use the same compile-fusion split: `-to logic_opto`, then `-from initial_place -to initial_opto`, then `-from final_place`, with `set_qor_strategy -stage synthesis -metric timing -high_effort_timing`.

Differences:
- **Flow A** prints QoR reports between sub-stages and tags the log with `FC_STAGE_OK: synth`.
- **Flow B** adds explicit `add_tie_cells` (`TIEHI_X1M_A7PP140ZTS_C30` / `TIELO_…`), commented-out DFT/scan hooks (`2_synthesis.tcl:37-51`), an `analyze_power_plan` after place, and custom `report_intermediate_step` / `report_end_step` wrappers.

---

## 7. CTS (stage 3)

Both flows: `clock_opt -from build_clock -to build_clock` → `-from route_clock -to route_clock` → `-from final_opto`.

Flow B additionally enables AOCVM for the final opto pass:
```tcl
set_app_options -name time.aocvm_enable_analysis -value true
```
and applies a non-default routing rule (NDR1) to the clock nets (`1_design_setup.tcl:55-56`, `routing_rules.tcl`).

---

## 8. Routing (stage 4)

**Flow A** — minimal: `route_auto` → `route_opt` → implicit fillers.

**Flow B** — full chip rigour:
- `add_via_mapping -from_icc_file n28_ICC_DFMSWAP_5X1Y1Z1U_VHV.tcl` (foundry DFM via swap)
- Explicit `create_stdcell_fillers -lib_cells {FILL128 … FILL1}`
- `routing_rules.tcl` defines per-layer antenna rules across M1–M9 + AP and the NDR1 clock rule

65 nm at this die size doesn't need antenna or DFM-swap rigour; 28 nm with an AP/RDL stack does.

---

## 9. Sign-off (stage 5)

**Flow A** (`5_signoff.tcl`): timing / area / power QoR + a `signoff.design` checkpoint. No GDS, no Formality from this stage — both are deferred (GDS is optional in stage 6; LEC lives in `syn/asic/formality/`).

**Flow B** (`5_signoff.tcl`): produces the **tape-out artefacts**:
- `write_gds -merge_files [list <std-cell GDS> <SRAM GDS> <ROM GDS> …]` — merged final GDSII
- `write_verilog -hierarchy all -exclude {leaf_module_declarations empty_modules corner_cells filler_cells flip_chip_pad_cells pad_spacer_cells}` — clean gate netlist for sim/sign-off, plus a `_power` variant
- `write_sdf` for back-annotated sim
- Sets `impl.svf` for Formality traceability, consumed by stage 6

---

## 10. DRC

**Flow A** (`7_drc.tcl`) — explicit two-tier scheme:
- **Always-on, in-design checks**: `check_design -checks {block_ready_for_top legality routes analyze_design_violations pin_placement}`, `check_legality`, `check_pg_connectivity`, `check_pg_drc`, `check_routes`. The `block_ready_for_top` check is the partition-specific one — it validates that the block can be stitched into a chip-top.
- **Opt-in ICV sign-off DRC**: triggered only if `ICV_DRC_RUNSET` env var points to a foundry `.rs` runset, with optional `ICV_DRC_STRATEGY` override.
- A summary table is parsed out of the per-check reports into `reports/07_summary.rep` and re-displayable via `make drc_summary`.

**Flow B** — sign-off DRC is configured via app options in `setup.tcl`:
```
signoff.check_drc.runset        {…/ICVLN28HP_9M_5X1Y1Z1U_002.22a.encrypt}
signoff.physical.layer_map_file {…/gdsout_5X1Y1Z1U.map}
```
…and runs inside stage 5. Two `calibre_drc*` directories under `scripts/` indicate that Calibre is also wired in as an external sign-off step (independent of FC). No `block_ready_for_top` check, because there is no top to be ready for.

---

## 11. Partition export (only in Flow A)

`6_partition_export.tcl` is the artefact that makes Flow A a hierarchical flow. It writes the integrator-facing hand-off:
- `write_lef` — physical abstract for top-level placement
- `write_def` — floorplan-stitch geometry
- `write_verilog` (logic) **and** `write_verilog -include {pg_objects}` (with PG pins)
- `write_sdc` — boundary timing
- `write_sdf` — slow-corner timing for back-annotated sim
- Plus the `signoff.design` block in the design library, used for hierarchical STA at chip-top
- GDS export is stubbed out (commented) pending layer-map tuning

Flow B has no equivalent stage; its "export" is the merged GDSII written in stage 5.

---

## 12. I/O strategy

| | Flow A | Flow B |
|--|--|--|
| Approach | Logical port placement on die edges | Physical pad-ring with bond-pad overlay |
| Script | `place_pins.tcl` (set_individual_pin_constraints) | `io_plan.tcl` + `floorplan/floorplan.tcl` + UPF |
| Pad cells | None | 38 signal pads (io_lib) + 4 corner (PCORNER_G) + 60 bond pads (PAD60GU) + fillers |
| Voltage rails through ring | n/a — block-internal | VDD / VDDACC / VDDIO / VSS / VSSIO / POC |
| ESD / PRCUT | n/a | `PRCUT_L`, `PRCUT_R` for de-cap reference |

---

## 13. Process-specific items

| | Flow A — 65 nm LP | Flow B — 28 nm HPC+ |
|--|--|--|
| Std-cell flavours | RVT only (sc12_cln65lp_base_rvt) | base + power-mux (`pmk`) + high-perf (`hpk`) |
| Metal stack | ~9-10M (M5/M6 used for mesh) | 9M + AP RDL (used in PG ring + antenna rules) |
| Antenna rules | Implicit | Explicit per-layer in `routing_rules.tcl` |
| Tie cells | Default | Explicit `TIEHI/TIELO_X1M_A7PP140ZTS_C30` |
| Filler cells | Implicit | Explicit list `FILL128 … FILL1` |
| Memory IP | Flash-cache data + tag macros | `sram_16k` + `rom_via` |

---

## 14. Execution rigour & ergonomics

Flow A's makefile is materially more sophisticated:
- `.done` sentinels per stage with grep-based `FC_STAGE_OK` validation
- Per-module sub-trees (`$(MODULE).dlib`) so multiple blocks can coexist
- Opt-in env-var knobs (`ICV_DRC_RUNSET`, `ICV_DRC_STRATEGY`)
- A `gui` target that auto-picks the latest checkpoint and opens FC read-only by default
- A `help` target that documents the full surface area
- Clean separation: per-module `inputs/`, `libs/`, `logs/`, `reports/`, `outputs/`

Flow B's makefile is a flat list of targets that call `fc_shell` per stage and copies the netlist to a fixed location at the end. No sentinels, no markers, no per-module isolation. This is consistent with its role as a one-time tape-out flow rather than an iteration loop.

---

## 15. Summary

| Dimension | Flow A — AHB QSPI 65 nm partition | Flow B — nanosoc 28 nm full chip |
|-----------|------------------------------------|----------------------------------|
| Technology | TSMC 65 nm LP (RVT only) | TSMC 28 nm HPC+ (base + pmk + hpk) |
| Scope | Hierarchical macro hand-off | Full-chip tape-out |
| Die size | 970 × 190 µm, macro-driven | 1111 × 1667 µm, pad-ring-driven |
| I/O | Logical edge pins | 38 flip-chip pads + bond ring |
| Power domains | 1 (VDD/VSS) | 2 core (VDD, VDDACC) + I/O (VDDIO), UPF-driven |
| Core voltage | 1.08 V | 0.9 V |
| MCMM scenarios | 2 (slow, fast) | 5 (hold_ffgnp, hold_ssgnp, setup, em, typical) |
| TLU+ corners | Inferred (2) | 9 explicit |
| SDC | Single shared file | 4 corner-specific files |
| Stages | 7 (incl. partition export + DRC) | 6 (incl. Formality) |
| Checkpoint discipline | `.done` sentinels + `FC_STAGE_OK` grep | Stage scripts only |
| Floorplan strategy | Absolute die + fixed macro coords | Pad-ring guide + macro auto-place |
| PG strategy | M1 rails + M5/M6 mesh @ 50 µm | AP/M9 ring + M9/AP mesh @ 60 µm + M5 macro straps + M2 rails per voltage area |
| Routing rigour | `route_auto` + `route_opt` | + via mapping, antenna rules, explicit fillers, NDR1 clock |
| Sign-off DRC | In-design always + opt-in ICV (env-gated) | App-option ICV + Calibre dir |
| LEC | Sibling `formality/` tree | Stage 6 (in-flow) |
| Final artefacts | LEF / DEF / NDM / Verilog / SDC / SDF / .dlib | Merged GDSII / gate Verilog / SDF |
| Make ergonomics | Per-module dirs, sentinels, GUI helper, help target | Flat target list |

### Take-away

Flow B is the more *complete* full-chip flow — it owns the pad ring, multi-voltage UPF, corner matrix, via mapping, and GDS merge that a tape-out demands. Flow A is the more *disciplined* partition flow — its makefile and stage instrumentation are engineered for iteration on a single block that will be integrated upstream, and its scope is intentionally narrower (single Vdd, two corners, no pads, no Calibre). They are not the same flow at different nodes; they are different flows because they sit at different points in the SoC hierarchy.
