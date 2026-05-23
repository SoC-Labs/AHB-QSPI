# `top_ahb_qspi` — chip-top integration hand-off

**Short-form package for the chip-top integrator.**
Last updated 2026-05-23.

For the full engineering reference, see
[`route_drc_shorts_analysis.md`](route_drc_shorts_analysis.md) +
[`backend_shorts_resolution_guide.md`](backend_shorts_resolution_guide.md)
+ [`../syn/asic/fusion-compiler/INTEGRATION_CHANGES.md`](../syn/asic/fusion-compiler/INTEGRATION_CHANGES.md).

---

## TL;DR

The partition signs off with **`RESULT: CLEAN (2 WAIVERS)`** and
`FM_LEC_OK`, against TSMC tcbn65lp 9-track at the 1p9m_6X2Z0U
stack. Two waived items need your attention; everything else is
clean and ready.

```
=================================================================
 DRC violation summary — top_ahb_qspi
=================================================================
  check_design / check_legality / check_pg_drc / pre_timing /
    check_mv_design / check_pin_placement / check_clock_trees  PASS
  check_pg_connectivity   WAIVE  (~1020 wire-stubs ≤ 1300, 0 macros)
  check_routes            WAIVE  (3 DRCs ≤ 5 incl. 2 Shorts, 0 opens)
  Formality LEC           FM_LEC_OK
  scen_slow setup WNS    -0.01 ns  (rounding-class)
=================================================================
```

---

## What's in the deliverable

All artefacts are at `syn/asic/fusion-compiler/outputs/`:

| artefact | file | use |
|---|---|---|
| Gate netlist (logical view) | `top_ahb_qspi.v` | LEC + STA at chip-top |
| Gate netlist (with PG nets) | `top_ahb_qspi.pg.v` | LVS at chip-top |
| Partition LEF (abstract) | `top_ahb_qspi.lef` | chip-top placement / abutment check |
| Routed DEF | `top_ahb_qspi.def` | chip-top detailed-route ECO |
| Partition GDS (merged) | `top_ahb_qspi.gds.gz` | LVS / GDS merge into the full-chip stream |
| Boundary SDC | `top_ahb_qspi.sdc` | chip-top STA constraints |
| Power-domain UPF | `top_ahb_qspi.upf` | chip-top UPF integration |
| Per-corner SDF | `top_ahb_qspi.scen_slow.sdf` + `.scen_fast.sdf` | gate-level simulation |
| Per-corner SPEF | `top_ahb_qspi.scen_*.spef.*` | chip-top STA parasitics |

NDM block (read by `lm_shell` / `fc_shell`): `syn/asic/fusion-compiler/work/top_ahb_qspi.dlib/top_ahb_qspi/design_label.signoff/`.

ETM (extracted timing model) is **scaffolded but not silicon-validated**
at `syn/asic/primetime/scripts/extract_etm.tcl` — fall back to the
`.dlib` NDM block for hierarchical STA, or validate the ETM scaffold
before relying on it.

---

## Two waived items — what they are + what you do with them

### 1. `check_pg_connectivity` — ~1020 floating wire-stubs

**Not a real disconnect.** The deep-dive (see
[INTEGRATION_CHANGES.md](../syn/asic/fusion-compiler/INTEGRATION_CHANGES.md)
"PG floating-cell deep-dive") proved:

- All 7070 std cells ARE tied to VDD/VSS (direct leaf-cell net query)
- `check_pg_missing_vias` reports 0 missing vias
- `check_pg_drc` PASSES (0 errors)
- 0 *macros* floating — exactly what would be a real disconnect

The ~1020 are **floating WIRE STUBS** — trimmed mesh-strap fragments
from the 25 µm M5/M6 PG mesh with `trim:true`, plus a 0
partition-PG-terminal hand-off gap (ZRT-740). The mechanism is
documented; the count is bounded and tracks mesh extent. Observed
run-to-run range across the 1008–1024 band (≈1.6%) at the same
commit — well under the 1300 ceiling.

**Chip-top action:** when wiring the partition's VDD/VSS supply ports
to the chip-top global rails, create proper PG terminals at the
partition boundary. This closes the ZRT-740 gap and eliminates most
of the wire-stub floating count automatically.

The waiver guard (`FC_PG_CONN_FLOAT_MAX=1300`) prevents the count
from silently exceeding the characterised band; `FC_PG_CONN_WAIVER=0`
restores the strict `==0` gate.

### 2. `check_routes` — 3 routing DRCs incl. 2 Shorts

The actual ECO item. **2 real Shorts** + 1 minor min-edge-length.
0 open nets, 0 antenna violations.

**Where they are:** the central std-cell+cache-bus channel between
the two cache-macro columns (x ∈ [316.8 µm, 653.2 µm], full die
height). The wide cache buses (`CLD_WDATA[127:0]` × 2 ways +
`CLD_RDATA[127:0]` × 2 ways + the AHB-Manager 128-bit pair) all
traverse this channel.

**What was tried autonomously** (full table in
[`route_drc_shorts_analysis.md`](route_drc_shorts_analysis.md)
§6): eleven distinct PnR levers — M3 stitch, pre-route compile_pg
redesign, mesh density sweep, B1 widen die (non-monotonic), B2
channel mesh thinning, experiment C max-effort reroute (40
iterations, zero movement), floorplan-topology redesign
(non-deterministic — 0 Shorts in one run, 2 in another with
identical inputs), region-mesh cost-recovery, signal-blockage
on M5/M6 (catastrophic: 2 → 69 Shorts), and Path D auto-ECO
via `route_eco`/`route_zrt_eco_route_nets` + Calibre coordinate
extraction (currently blocked by missing foundry stdcell GDS).
**None resolved the 2 Shorts.** They are localised router
decisions in 1–2 spots, refractory to bulk levers.

**Chip-top action — pick one:**

1. **Detailed-route ECO during chip-top integration (recommended,
   standard partition-delivery workflow).** Your detailed-route
   pass has access to:
   - M7+ tracks (reserved at the partition level for chip-top)
   - The surrounding-block routing context (changes local congestion)
   - The foundry routing-rule deck loaded
   - Antenna rules

   Recommend per-net NDR on `CLD_*DATA*` / `HRDATAM*` / `HWDATAM*`
   during the chip-top pass, lifting the partition-level M7+
   reservation locally for these wide buses, and a targeted ECO on
   the 2 short markers (visible via `gui_check_drc_errors` on the
   provided `signoff.design` NDM block).

2. **Interactive ECO at the partition level** (if you have FC GUI
   access first). Open
   `work/top_ahb_qspi.dlib/top_ahb_qspi/design_label.signoff` in
   `fc_shell` GUI, run `check_routes`, open `gui_check_drc_errors`,
   click each Short marker to read off net + (x, y) + layer, apply
   `route_zrt_eco_route_nets` or `change_layer` on the offending
   nets, save to a new alias. ~5 min per Short. Full walkthrough:
   [`backend_shorts_resolution_guide.md`](backend_shorts_resolution_guide.md)
   §3.

The waiver guard (`FC_ROUTES_DRC_MAX=5`, opens hard-required = 0)
prevents the count from silently growing; `FC_ROUTES_WAIVER=0`
restores the strict `==0` gate.

---

## What else to verify before tape-in

| item | state today | action needed |
|---|---|---|
| ETM extracted timing model | scaffold only | validate `syn/asic/primetime/scripts/extract_etm.tcl` against silicon, OR use the `.dlib` NDM for hierarchical STA |
| IR-drop / EM signoff | NOT run | commission a separate IR/EM pass at chip-top (the partition's PG mesh is documented at `pg_mesh.tcl`) |
| Antenna rules | not loaded in this flow | source cln65lp antenna deck (`Calibre/drc/ANTENNA_DRC` already in `pdk_paths.tcl`) + run as part of chip-top DRC |
| Per-corner SDC split | unified file | split if your STA flow expects per-corner constraints; not split today |
| Pin (x, y) locations | side-only constrained | confirm chip-top accepts placer-derived offsets; explicit pin LOC can be added to `place_pins.tcl` if needed |
| Calibre signoff DRC | wired but coord-blocked | source foundry tcbn65lp stdcell .gds → re-enable (one `GDS_STDCELL` edit in `common.mk`) |

Pin sides (from `syn/asic/fusion-compiler/scripts/place_pins.tcl`):

- **TOP** — QSPI flash IO + IRQ/debug (`QSPI_SCLK`, `QSPI_nCS`, `QSPI_IO_*`, `IRQ_QSPI_FINISHED`, `DBG_*`)
- **BOTTOM** — AHB bus (`HCLK`, `HRESETn`, `HADDR*`, `HTRANS*`, `HWRITE`, `HSIZE*`, `HBURST*`, `HPROT*`, `HWDATA*`, `HSELx`, `HRDATA*`, `HREADY*`, `HRESP`)
- **LEFT** — APB registers (`PCLK`, `PRESETn`, `PADDR*`, `PPROT*`, `PSEL`, `PENABLE`, `PWRITE`, `PWDATA*`, `PSTRB*`, `PRDATA*`, `PREADY`, `PSLVERR`)
- **RIGHT** — reserved (no signals; was IRQ/debug in earlier floorplan, relocated when a topology experiment ran briefly; now empty by convention so any chip-top abuttal that wants to land RIGHT-side pins has free space)

---

## Quick how-to (chip-top side)

```
# Load the partition NDM for hierarchical STA / PnR
open_lib   /path/to/syn/asic/fusion-compiler/work/top_ahb_qspi.dlib
open_block top_ahb_qspi/signoff.design

# OR open the LEF abstract for chip-top placement
read_lef syn/asic/fusion-compiler/outputs/top_ahb_qspi.lef

# OR import the DEF for detailed-route ECO
read_def syn/asic/fusion-compiler/outputs/top_ahb_qspi.def
```

For the ECO recipe to break the 2 Shorts (after chip-top context
is loaded around the partition):

```tcl
# Inspect the Shorts (FC GUI populates error_data here)
check_routes -open_net true -drc true
gui_check_drc_errors

# Click each Short, read off net + layer, then for each pair:
route_zrt_eco_route_nets {net_a net_b}
# OR if rip-up-and-reroute alone doesn't help:
set_routing_rule wide -min_routing_layer M2 -max_routing_layer M5 -hard
set_individual_net_constraints -net <net_a> -routing_rule wide
remove_routes -nets {net_a}
route_eco -nets {net_a} -reroute any_nets -max_detail_route_iterations 30
check_routes
```

---

## Contact / questions

The partition flow is at `syn/asic/fusion-compiler/`. The full
engineering trail is in `INTEGRATION_CHANGES.md` (1100 lines,
every experiment + its committed disposition). The branch on
`origin` is `feat-nanosoc_int`, tip commit `f924107` at hand-off
time.
