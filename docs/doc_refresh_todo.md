# Documentation refresh — TODO

Started 2026-05-23. Tracks the doc-refresh pass that brings every
user-facing document up to the current state of the repo (post the
TSMC tcbn65lp 9-track migration + Calibre signoff DRC wiring +
bounded check_routes waiver close-out).

Scope: 1–4 from the prior status report, plus 5 (MR description) and
6 (chip-top hand-off note). Out of scope: items 7–11 from that
report (parked branches, lint refresh, full from-init validation
run).

## Tasks

- [x] **`README.md`** — root file. Currently still implies Arm sc12,
      mentions "Some timing violations occur with Arm standard cell
      timings" (line ~74) and has no pointer to `docs/` or the
      backend documentation. Add a short backend-status section that
      states the partition signs off `CLEAN (2 WAIVERS)` on TSMC
      tcbn65lp 9-track, and links into `docs/route_drc_shorts_analysis.md`
      + `docs/backend_shorts_resolution_guide.md` + the FC tree.

- [x] **`syn/asic/fusion-compiler/FLOW_COMPARISON.md`** — still
      references `sc12_cln65lp_base_rvt` at lines 66 / 235 / 262
      (per the prior agent audit). Replace with the
      tcbn65lp tcbn65lp_220a / `tcbn65lpwc.db` / `tcbn65lp_9lmT2.lef`
      pointers that the migrated `common.mk` now uses.

- [x] **`syn/asic/fusion-compiler/INTEGRATION_CHANGES.md`** —
      narrative log of all PnR work. Currently ends 2026-05-19 with
      the signal-blockage negative; doesn't yet cover:
      - TSMC tcbn65lp 9-track migration (commits `fb7b879` →
        `da954e8` → `e47efb8` → `7781e88`)
      - Calibre signoff DRC wiring (`dda66c8`) + the SVRF
        missing-cell dead end discovered this session
      - The bounded `check_routes` waiver close-out (`f924107`)
      - The final `RESULT: CLEAN (2 WAIVERS)` state and what it
        means for chip-top integration

- [x] **`docs/route_drc_shorts_analysis.md`** — engineering
      reference. Already has Path A/B/C/D characterised through
      `f924107`'s addendum. Needs a small additional section at the
      end that documents the final headless dead-end (Calibre missing
      stdcell .gds + no SVRF directive to tolerate missing cells +
      route_eco has no -error_data) and the bounded check_routes
      waiver as the chosen close-out methodology.

- [x] **`docs/backend_shorts_resolution_guide.md`** — beginner
      walkthrough. Path C section (line ~289) still says "only if
      your site has a TSMC65 runset"; should reflect what we now
      know: Calibre IS installed, the runset IS present, the
      `make calibre_drc` invocation works, but the partition GDS
      missing tcbn65lp stdcell internals + no SVRF directive to
      tolerate them currently blocks coordinate extraction. Plus
      add an item to the TL;DR table for the new "ship with bounded
      check_routes waiver + chip-top ECO" option.

- [x] **`docs/chip_top_handoff.md`** (NEW) — standalone 1-pager for
      the chip-top integrator. Pulls the §8 hand-off package + the
      copy-pasteable hand-off note from `route_drc_shorts_analysis.md`
      into a single short doc that doesn't require reading the
      full engineering analysis.

- [x] **`docs/mr_description.md`** (NEW) — paste-ready GitLab MR
      description summarising the work on `feat-nanosoc_int` since
      the last merge to `master`. Sections: what changed (TSMC
      migration + Calibre wiring + Shorts characterisation +
      waiver close-out), how to review (key commits + key files),
      what's still open (the user-action items from the punchlist).

- [x] **Commit + push** the doc bundle as one logical commit.
      Pushed as `4725d64` on `feat-nanosoc_int`.

## Notes

- All files are documentation only; no code/script changes in this
  pass.
- Each task should be completed in one focused edit; if the file is
  long enough to warrant multiple sections, prefer a single
  coherent addendum at the end rather than scattered insertions.
- Cross-reference between docs (e.g., README points at
  `docs/route_drc_shorts_analysis.md`; that file points at
  `docs/chip_top_handoff.md` for the short-form version) so a
  reader can navigate the chain.
