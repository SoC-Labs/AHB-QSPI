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
LEF_FILE     = $(PHYS_IP_PATH)/sc12_base_rvt/r0p0/lef/sc12_cln65lp_base_rvt.lef
export LEF_FILE
export FUSION_LIB := $(FC_DIR)/libs/sc12_lib

# Stage checkpoint blocks (FC save_block aliases inside the design library)
INIT_BLOCK     = init.design
SYNTH_BLOCK    = compile.design
CTS_BLOCK      = cts.design
ROUTE_BLOCK    = route.design
SIGNOFF_BLOCK  = signoff.design
DRC_BLOCK      = drc.design

# Sentinels (touched after each stage, so make can dependency-track stages)
INIT_DONE      = $(FC_WORK)/.init.done
SYNTH_DONE     = $(FC_WORK)/.synth.done
CTS_DONE       = $(FC_WORK)/.cts.done
ROUTE_DONE     = $(FC_WORK)/.route.done
SIGNOFF_DONE   = $(FC_WORK)/.signoff.done
DRC_DONE       = $(FC_WORK)/.drc.done
ABSTRACT_DONE  = $(FC_WORK)/.abstract.done

FC_SHELL = fc_shell

.PHONY: fc fc_init fc_synth fc_cts fc_route fc_signoff fc_drc fc_abstract \
        drc_summary mem_ff_db gui clean help dirs fusion_lib

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

$(SIGNOFF_DONE): $(ROUTE_DONE)
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

# Full flow
fc: fc_abstract
	@echo ""
	@echo "INFO: Fusion Compiler partition flow complete for $(MODULE)"
	@echo "INFO: Reports : $(FC_REPORTS)/"
	@echo "INFO: Outputs : $(FC_OUTPUTS)/"
	@echo "INFO: Logs    : $(FC_LOGS)/"

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
	@echo "  make fc                        - Run the full flow"
	@echo "  make fc_init                   - Phase 1: init_design + floorplan"
	@echo "  make fc_synth                  - Phase 2: compile_fusion"
	@echo "  make fc_cts                    - Phase 3: clock_opt"
	@echo "  make fc_route                  - Phase 4: route_auto + route_opt"
	@echo "  make fc_signoff                - Signoff QoR (timing/area/power)"
	@echo "  make fc_drc                    - DRC checks (in-design + ICV opt-in)"
	@echo "  make drc_summary               - Grep DRC reports for violation counts"
	@echo "  make fc_abstract               - Write LEF/DEF/Verilog/SDC/SDF"
	@echo "  make fusion_lib                - Build fusion ref lib only"
	@echo "  make gui                       - fc_shell -gui"
	@echo "  make clean                     - Remove all generated files"
	@echo ""
	@echo "Opt-in vars:"
	@echo "  ICV_DRC_RUNSET=<path>          - foundry .rs runset; enables"
	@echo "                                   ICV signoff DRC at fc_drc"
	@echo "  ICV_DRC_STRATEGY=<name>        - pre-defined strategy name"
	@echo "                                   (defaults to 'qspi_drc')"
	@echo ""
	@echo "Module    : $(MODULE)"
	@echo "Flist     : $(FLIST)"
	@echo "Work dir  : $(FC_WORK)"
	@echo "Reports   : $(FC_REPORTS)/"
	@echo "Outputs   : $(FC_OUTPUTS)/"
