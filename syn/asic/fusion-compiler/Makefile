include $(dir $(lastword $(MAKEFILE_LIST)))/../common.mk

# ── Paths ──────────────────────────────────────────────────────────────────
export FC_DIR         = $(SOCLABS_AHB_QSPI_DIR)/syn/asic/fusion-compiler
export SHARED_SCRIPTS = $(SOCLABS_AHB_QSPI_DIR)/syn/asic/scripts
export FC_WORK        = $(FC_DIR)/work
export FC_LIBS        = $(FC_DIR)/libs
export FC_LOGS        = $(FC_DIR)/logs
export FC_REPORTS     = $(FC_DIR)/reports
export FC_OUTPUTS     = $(FC_DIR)/outputs

# Per-module sub-tree (so multiple MODULEs can coexist on disk)
export FC_BLOCK_DIR   = $(FC_WORK)/$(MODULE).dlib

# Floorplan target — absolute die dimensions (μm).
# place_memories.tcl arranges the cache macros in a split-column
# pattern: 4× flash_cache_data stacked at the LEFT edge, 4× stacked
# at the RIGHT edge, and the 2 flash_cache_tag cells side-by-side
# centred in the middle gap. Width budget:
#   margin + data + middle_gap + 2×tag + middle_gap + data + margin
#   = 5 + 312 + ~60 + 275 + ~60 + 312 + 5 ≈ 1029 μm
# Height budget:
#   margin + 4×data_H + 3×V_channel + margin
#   = 5 + 145.4 + 15 + 5 ≈ 170 μm  (round up to 220 for std-cell rows)
# Util-driven sizing ignores the macro footprint at floorplan time
# so we always set side_length explicitly.
export FC_DIE_WIDTH        ?= 970
export FC_DIE_HEIGHT       ?= 190
export FC_CORE_OFFSET      ?= 10

# ── EDA tool binaries ─────────────────────────────────────────────────────
FC_BIN_DIR   = /eda/synopsys/2022-23/RHELx86/FS-COMPILER_2022.12/bin
ICC2_BIN_DIR = /eda/synopsys/2022-23/RHELx86/ICC2_2022.12/bin
LC_BIN_DIR   = /eda/synopsys/2022-23/RHELx86/LC_2022.12/bin
export PATH := $(FC_BIN_DIR):$(ICC2_BIN_DIR):$(LC_BIN_DIR):$(PATH)

# ── Library / fusion-lib ──────────────────────────────────────────────────
LEF_FILE     = $(PHYS_IP_PATH)/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_9lmT2.lef
export LEF_FILE
export FUSION_LIB := $(FC_DIR)/libs/sc12_lib

# Stage checkpoint blocks (FC save_block aliases inside the design library)
INIT_BLOCK     = init.design
SYNTH_BLOCK    = compile.design
CTS_BLOCK      = cts.design
ROUTE_BLOCK    = route.design
PG_BLOCK       = pg.design
SIGNOFF_BLOCK  = signoff.design
DRC_BLOCK      = drc.design

# Sentinels (touched after each stage, so make can dependency-track stages)
INIT_DONE      = $(FC_WORK)/.init.done
SYNTH_DONE     = $(FC_WORK)/.synth.done
CTS_DONE       = $(FC_WORK)/.cts.done
ROUTE_DONE     = $(FC_WORK)/.route.done
PG_DONE        = $(FC_WORK)/.pg.done
SIGNOFF_DONE   = $(FC_WORK)/.signoff.done
DRC_DONE       = $(FC_WORK)/.drc.done
ABSTRACT_DONE  = $(FC_WORK)/.abstract.done
LEC_DONE       = $(FC_WORK)/.lec.done
ETM_DONE       = $(FC_WORK)/.etm.done

FC_SHELL = fc_shell

# Sibling Formality tree — fc_lec delegates here so there is one LEC
# implementation (run_lec.tcl), not a duplicate inside the FC flow.
FM_FLOW_DIR = $(SOCLABS_AHB_QSPI_DIR)/syn/asic/formality

# Sibling PrimeTime tree — fc_etm delegates here for the boundary
# timing model fc_shell U-2022.12 cannot write (no write_lib_model
# -format etm). SCAFFOLD: not yet silicon-validated.
PT_FLOW_DIR = $(SOCLABS_AHB_QSPI_DIR)/syn/asic/primetime

.PHONY: fc fc_all fc_init fc_synth fc_cts fc_route fc_pg fc_signoff fc_drc \
        fc_abstract fc_lec fc_etm drc_summary mem_ff_db gui clean help \
        dirs fusion_lib fc_pg_probe

# ── Workspace setup ───────────────────────────────────────────────────────
dirs:
	@mkdir -p $(FC_WORK) $(FC_LIBS) $(FC_LOGS) $(FC_REPORTS) $(FC_OUTPUTS)

# ── Fusion reference library (shared with rtl-architect) ─────────────────
# ── Memory FF .db build (lc_shell) ────────────────────────────────────────
# /research/precompiled_mems/TSMC65 ships only the SS .db for the
# flash_cache_* macros. lc_shell compiles the FF .lib's into local .db's
# under $(MEM_FF_DB_DIR) so scen_fast can be enabled in the FC flow.
LC_SHELL = lc_shell
LC_BIN_DIR = /eda/synopsys/2022-23/RHELx86/LC_2022.12/bin

$(FCD_DB_FF) $(FCT_DB_FF): $(SHARED_SCRIPTS)/build_mem_ff_db.tcl
	@mkdir -p $(MEM_FF_DB_DIR)
	@echo "INFO: building FF .db files for flash_cache_data + flash_cache_tag"
	cd $(MEM_FF_DB_DIR) && $(LC_BIN_DIR)/$(LC_SHELL) -f $(SHARED_SCRIPTS)/build_mem_ff_db.tcl 2>&1 \
	    | tee $(MEM_FF_DB_DIR)/build_mem_ff_db.log
	@test -s $(FCD_DB_FF) -a -s $(FCT_DB_FF) \
	    || (echo "ERROR: FF .db build failed — see $(MEM_FF_DB_DIR)/build_mem_ff_db.log"; exit 1)
	@echo "INFO: FF .db files ready under $(MEM_FF_DB_DIR)"

mem_ff_db: $(FCD_DB_FF) $(FCT_DB_FF)

$(FUSION_LIB): | dirs
	@echo "INFO: Creating fusion reference library from LEF + .db..."
	cd $(FC_LIBS)/.. && lm_shell -f $(SHARED_SCRIPTS)/create_fusion_lib.tcl 2>&1 \
	    | tee $(FC_LOGS)/create_fusion_lib.log
	@test -d $@ || (echo "ERROR: Fusion library creation failed"; exit 1)

fusion_lib: $(FUSION_LIB)

# ── Stage targets ────────────────────────────────────────────────────────
# Each stage cd's into $(FC_WORK), opens (or creates) the design library,
# saves a named block alias, then touches its sentinel.
#
# Each stage greps the log for FC_STAGE_OK at the end before touching its
# sentinel. fc_shell exits 0 even on Tcl errors, so the marker is the only
# reliable signal that the stage actually completed.

$(INIT_DONE): $(FUSION_LIB) | dirs
	@echo "INFO: [Phase 1] init_design + analyze + elaborate + MCMM + floorplan"
	cd $(FC_WORK) && $(FC_SHELL) -f $(FC_DIR)/scripts/1_init_design.tcl 2>&1 \
	    | tee $(FC_LOGS)/1_init_design.log
	@grep -q "^FC_STAGE_OK: init" $(FC_LOGS)/1_init_design.log \
	    || (echo "ERROR: fc_init did not reach FC_STAGE_OK marker — see $(FC_LOGS)/1_init_design.log"; exit 1)
	@touch $@

fc_init: $(INIT_DONE)

$(SYNTH_DONE): $(INIT_DONE)
	@echo "INFO: [Phase 2] compile_fusion (synthesis + initial place + final place)"
	cd $(FC_WORK) && $(FC_SHELL) -f $(FC_DIR)/scripts/2_synthesis.tcl 2>&1 \
	    | tee $(FC_LOGS)/2_synthesis.log
	@grep -q "^FC_STAGE_OK: synth" $(FC_LOGS)/2_synthesis.log \
	    || (echo "ERROR: fc_synth did not reach FC_STAGE_OK marker — see $(FC_LOGS)/2_synthesis.log"; exit 1)
	@touch $@

fc_synth: $(SYNTH_DONE)

$(CTS_DONE): $(SYNTH_DONE)
	@echo "INFO: [Phase 3] clock_opt (build / route / final)"
	cd $(FC_WORK) && $(FC_SHELL) -f $(FC_DIR)/scripts/3_clock.tcl 2>&1 \
	    | tee $(FC_LOGS)/3_clock.log
	@grep -q "^FC_STAGE_OK: cts" $(FC_LOGS)/3_clock.log \
	    || (echo "ERROR: fc_cts did not reach FC_STAGE_OK marker — see $(FC_LOGS)/3_clock.log"; exit 1)
	@touch $@

fc_cts: $(CTS_DONE)

$(ROUTE_DONE): $(CTS_DONE)
	@echo "INFO: [Phase 4] route_auto + route_opt + fillers"
	cd $(FC_WORK) && $(FC_SHELL) -f $(FC_DIR)/scripts/4_route.tcl 2>&1 \
	    | tee $(FC_LOGS)/4_route.log
	@grep -q "^FC_STAGE_OK: route" $(FC_LOGS)/4_route.log \
	    || (echo "ERROR: fc_route did not reach FC_STAGE_OK marker — see $(FC_LOGS)/4_route.log"; exit 1)
	@touch $@

fc_route: $(ROUTE_DONE)

# Phase 4a — post-route PG rail + M3-stitch (Blocker-1 fix). Stitches
# the M1 std-cell rails to the M5/M6 mesh via a fine-pitch M3 vertical
# strap, against the final routed layout (init-stage compile_pg
# structurally cannot). Probe-validated: floating std cells 814/487 ->
# 0/0 at PG_M3_PITCH=3.0. Produces pg.design, consumed by 5_signoff.tcl.
$(PG_DONE): $(ROUTE_DONE)
	@echo "INFO: [Phase 4a] post-route PG rail + M3 stitch"
	cd $(FC_WORK) && $(FC_SHELL) -f $(FC_DIR)/scripts/pg_rails.tcl 2>&1 \
	    | tee $(FC_LOGS)/pg_rails.log
	@grep -q "^FC_STAGE_OK: pg" $(FC_LOGS)/pg_rails.log \
	    || (echo "ERROR: fc_pg did not reach FC_STAGE_OK marker — see $(FC_LOGS)/pg_rails.log"; exit 1)
	@touch $@

fc_pg: $(PG_DONE)

$(SIGNOFF_DONE): $(PG_DONE)
	@echo "INFO: [Phase 4b] signoff (DRC, parasitic-SI, reports)"
	cd $(FC_WORK) && $(FC_SHELL) -f $(FC_DIR)/scripts/5_signoff.tcl 2>&1 \
	    | tee $(FC_LOGS)/5_signoff.log
	@grep -q "^FC_STAGE_OK: signoff" $(FC_LOGS)/5_signoff.log \
	    || (echo "ERROR: fc_signoff did not reach FC_STAGE_OK marker — see $(FC_LOGS)/5_signoff.log"; exit 1)
	@touch $@

fc_signoff: $(SIGNOFF_DONE)

$(DRC_DONE): $(SIGNOFF_DONE)
	@echo "INFO: [Phase 5] DRC (in-design + optional ICV signoff)"
	@rm -f $(FC_REPORTS)/07_*.rep
	cd $(FC_WORK) && $(FC_SHELL) -f $(FC_DIR)/scripts/7_drc.tcl 2>&1 \
	    | tee $(FC_LOGS)/7_drc.log
	@grep -q "^FC_STAGE_OK: drc" $(FC_LOGS)/7_drc.log \
	    || (echo "ERROR: fc_drc did not reach FC_STAGE_OK marker — see $(FC_LOGS)/7_drc.log"; exit 1)
	@touch $@

fc_drc: $(DRC_DONE)

# drc_summary — re-display the per-check summary table that 7_drc.tcl
# wrote during fc_drc. The summary parses each check's canonical
# violation line (e.g. "Total number of DRCs = N") rather than greping
# for "violation" everywhere, so the counts are exact and not heuristic.
drc_summary:
	@if [ ! -f "$(FC_REPORTS)/07_summary.rep" ]; then \
	    echo "ERROR: $(FC_REPORTS)/07_summary.rep not found — run 'make fc_drc' first"; \
	    exit 1; \
	fi
	@cat $(FC_REPORTS)/07_summary.rep

$(ABSTRACT_DONE): $(DRC_DONE)
	@echo "INFO: [Phase 6] partition export (LEF, DEF, NDM, GDS, Verilog)"
	cd $(FC_WORK) && $(FC_SHELL) -f $(FC_DIR)/scripts/6_partition_export.tcl 2>&1 \
	    | tee $(FC_LOGS)/6_partition_export.log
	@grep -q "^FC_STAGE_OK: abstract" $(FC_LOGS)/6_partition_export.log \
	    || (echo "ERROR: fc_abstract did not reach FC_STAGE_OK marker — see $(FC_LOGS)/6_partition_export.log"; exit 1)
	@touch $@

fc_abstract: $(ABSTRACT_DONE)

# ── Formality LEC (post-export) ───────────────────────────────────────────
# The gate netlist LEC verifies ($(FC_OUTPUTS)/$(MODULE).v) is written by
# 6_partition_export.tcl, so LEC depends on the abstract sentinel. We
# delegate to the sibling Formality Makefile rather than re-implement
# match/verify: it already greps FM_LEC_OK and exits non-zero on a
# failing/aborted point, so a LEC failure propagates and the sentinel is
# not touched. This is the partition's LEC sign-off — the
# check_lec_compatibility advisory that doesn't exist as an fc_shell
# atomic is covered here properly, RTL-vs-netlist.
$(LEC_DONE): $(ABSTRACT_DONE)
	@echo "INFO: [Phase 7] Formality LEC — RTL vs post-layout netlist"
	$(MAKE) -C $(FM_FLOW_DIR) lec
	@touch $@

fc_lec: $(LEC_DONE)

# ── PrimeTime ETM (post-export) ───────────────────────────────────────────
# Boundary timing model — depends on the same fc_abstract products LEC
# uses (gate netlist + per-scenario SPEF + boundary SDC). Delegates to
# the sibling PrimeTime Makefile (PT_ETM_OK marker enforced there), so a
# failed extraction does not touch the sentinel. NOT in fc_all: it is an
# unverified scaffold and an optional, heavy deliverable — run it
# explicitly (`make fc_etm`) once validated, or fold into a future
# `fc_deliver` aggregate.
$(ETM_DONE): $(ABSTRACT_DONE)
	@echo "INFO: [Phase 7b] PrimeTime ETM — boundary timing model"
	$(MAKE) -C $(PT_FLOW_DIR) etm
	@touch $@

fc_etm: $(ETM_DONE)

# Full flow (through partition export — matches the historical `fc`)
fc: fc_abstract
	@echo ""
	@echo "INFO: Fusion Compiler partition flow complete for $(MODULE)"
	@echo "INFO: Reports : $(FC_REPORTS)/"
	@echo "INFO: Outputs : $(FC_OUTPUTS)/"
	@echo "INFO: Logs    : $(FC_LOGS)/"

# Full flow + LEC sign-off. Kept separate from `fc` so a site without
# the Formality tool can still run the PnR flow end-to-end; CI / tape-in
# should use `fc_all`.
fc_all: fc fc_lec
	@echo ""
	@echo "INFO: Fusion Compiler flow + Formality LEC complete for $(MODULE)"
	@echo "INFO: LEC reports : $(FM_FLOW_DIR)/reports/"

# ── Blocker-1 diagnostic: post-route PG rail-stitch probe ────────────────
# NON-DESTRUCTIVE. Operates on a copy of route.design (pg_probe.design);
# route/signoff/drc blocks are untouched. Reproduces the post-route
# std-cell-rail compile_pg and captures the exact failing command that
# INTEGRATION_CHANGES.md's PG deep-dive hands off as "needs an
# interactive run to see". ~6 min. Requires a prior `make fc_route`
# (route.design must exist) — does NOT rebuild the flow.
fc_pg_probe: $(FUSION_LIB)
	@if [ ! -d "$(FC_BLOCK_DIR)/$(MODULE)/design_label.route" ]; then \
	    echo "ERROR: route.design not found — run 'make fc_route' first"; exit 1; \
	fi
	@echo "INFO: [pg_probe] post-route PG rail-stitch diagnostic (non-destructive)"
	cd $(FC_WORK) && $(FC_SHELL) -f $(FC_DIR)/scripts/pg_postroute_probe.tcl 2>&1 \
	    | tee $(FC_LOGS)/pg_postroute_probe.log
	@grep -q "^FC_STAGE_OK: pg_probe" $(FC_LOGS)/pg_postroute_probe.log \
	    || (echo "ERROR: pg_probe did not reach its marker — see $(FC_LOGS)/pg_postroute_probe.log"; exit 1)
	@echo "INFO: [pg_probe] summary:"; cat $(FC_REPORTS)/pg_postroute_probe.rep
	@echo "INFO: [pg_probe] failing-command detail (grep PGPROBE_ERR in the log):"
	@grep -nE "PGPROBE_(FAIL|ERR_MSG|ERR_CODE|BASELINE_FLOAT|POST_FLOAT|RESULT)" $(FC_LOGS)/pg_postroute_probe.log || true

# ── GUI on the most recently saved block ─────────────────────────────────
# Opens fc_shell's GUI on a saved checkpoint. Override BLOCK to view a
# different stage (e.g. `make gui BLOCK=route.design` or compile.design).
# Defaults to signoff.design if it exists, else falls back through the
# stage chain to whatever is available.
BLOCK ?= signoff.design

gui: $(FUSION_LIB)
	@b="$(BLOCK)"; \
	for cand in $$b drc.design signoff.design route.design cts.design compile.design init.design; do \
	    if [ -d "$(FC_BLOCK_DIR)/$(MODULE)/design_label.$${cand%.design}" ]; then b="$$cand"; break; fi; \
	done; \
	echo "INFO: opening $(MODULE).dlib:$(MODULE)/$$b (read-only — pass MODE=edit for editable)"; \
	mode_flag=""; \
	if [ "$(MODE)" != "edit" ]; then mode_flag=" -read"; fi; \
	cd $(FC_WORK) && $(FC_SHELL) -x "open_lib $(MODULE).dlib; open_block$$mode_flag $(MODULE).dlib:$(MODULE)/$$b; gui_start"

# ── Clean ────────────────────────────────────────────────────────────────
clean:
	rm -rf $(FC_WORK) $(FC_LIBS) $(FC_LOGS) $(FC_REPORTS) $(FC_OUTPUTS)
	rm -rf $(FC_DIR)/*.svf $(FC_DIR)/alib-* $(FC_DIR)/work $(FC_DIR)/.synopsys*

# ── Help ─────────────────────────────────────────────────────────────────
help:
	@echo "AHB QSPI — Fusion Compiler Partition Flow (TSMC 65 LP)"
	@echo ""
	@echo "Stages run in order; each depends on the previous stage's"
	@echo "save_block sentinel so make -j is safe across blocks."
	@echo ""
	@echo "Usage:"
	@echo "  make fc                        - Run the full flow (through export)"
	@echo "  make fc_all                    - fc + Formality LEC (CI / tape-in)"
	@echo "  make fc_init                   - Phase 1: init_design + floorplan"
	@echo "  make fc_synth                  - Phase 2: compile_fusion"
	@echo "  make fc_cts                    - Phase 3: clock_opt"
	@echo "  make fc_route                  - Phase 4: route_auto + route_opt"
	@echo "  make fc_pg                     - Phase 4a: post-route PG rail +"
	@echo "                                   M3 stitch (Blocker-1 fix; closes"
	@echo "                                   814/487 floating cells -> 0/0)"
	@echo "  make fc_signoff                - Signoff QoR (timing/area/power)"
	@echo "  make fc_drc                    - DRC checks (tier0/1/1b + ICV opt-in)"
	@echo "  make drc_summary               - Grep DRC reports for violation counts"
	@echo "  make fc_abstract               - Write LEF/DEF/GDS/UPF/Verilog/SDC/"
	@echo "                                   per-scenario SDF+SPEF + manifest"
	@echo "  make fc_lec                    - Formality LEC (delegates to"
	@echo "                                   ../formality; needs fc_abstract)"
	@echo "  make fc_etm                    - PrimeTime boundary ETM (delegates"
	@echo "                                   to ../primetime; SCAFFOLD, not in"
	@echo "                                   fc_all; needs fc_abstract+SPEF)"
	@echo "  make fusion_lib                - Build fusion ref lib only"
	@echo "  make mem_ff_db                 - Build FF mem .db (enables scen_fast"
	@echo "                                   -> multi-corner SDF/SPEF + hold)"
	@echo "  make fc_pg_probe               - Blocker-1 diagnostic: post-route"
	@echo "                                   PG rail-stitch probe (needs"
	@echo "                                   fc_route; non-destructive, ~6 min)"
	@echo "  make gui                       - fc_shell -gui"
	@echo "  make clean                     - Remove all generated files"
	@echo ""
	@echo "Opt-in vars / files:"
	@echo "  ICV_DRC_RUNSET=<path>          - foundry .rs runset; enables"
	@echo "                                   ICV signoff DRC at fc_drc"
	@echo "  ICV_DRC_STRATEGY=<name>        - pre-defined strategy name"
	@echo "                                   (defaults to 'qspi_drc')"
	@echo "  GDS_LAYER_MAP=<path>           - enables GDS stream-out at"
	@echo "                                   fc_abstract (default in common.mk)"
	@echo "  inputs/routing_rules.tcl       - NDR/antenna rules at fc_route"
	@echo "                                   (copy .template; off by default)"
	@echo ""
	@echo "Module    : $(MODULE)"
	@echo "Flist     : $(FLIST)"
	@echo "Work dir  : $(FC_WORK)"
	@echo "Reports   : $(FC_REPORTS)/"
	@echo "Outputs   : $(FC_OUTPUTS)/"
