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

# Floorplan target. Aspect 1.0 / util 0.7 are conservative starting points
# for top_ahb_qspi (10 SRAM macros along the bottom edge, std cells filling
# the rest). Tighten once post-route congestion is characterised.
export FC_ASPECT_RATIO    ?= 1.0
export FC_CORE_UTILIZATION ?= 0.7
export FC_CORE_OFFSET     ?= 10

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

# Sentinels (touched after each stage, so make can dependency-track stages)
INIT_DONE      = $(FC_WORK)/.init.done
SYNTH_DONE     = $(FC_WORK)/.synth.done
CTS_DONE       = $(FC_WORK)/.cts.done
ROUTE_DONE     = $(FC_WORK)/.route.done
SIGNOFF_DONE   = $(FC_WORK)/.signoff.done
ABSTRACT_DONE  = $(FC_WORK)/.abstract.done

FC_SHELL = fc_shell

.PHONY: fc fc_init fc_synth fc_cts fc_route fc_signoff fc_abstract \
        gui clean help dirs fusion_lib

# ── Workspace setup ───────────────────────────────────────────────────────
dirs:
	@mkdir -p $(FC_WORK) $(FC_LIBS) $(FC_LOGS) $(FC_REPORTS) $(FC_OUTPUTS)

# ── Fusion reference library (shared with rtl-architect) ─────────────────
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

$(ABSTRACT_DONE): $(SIGNOFF_DONE)
	@echo "INFO: [Phase 4c] partition export (LEF, DEF, NDM, GDS, Verilog)"
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
	for cand in $$b signoff.design route.design cts.design compile.design init.design; do \
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
	@echo "  make fc_signoff                - Signoff (DRC, parasitic, reports)"
	@echo "  make fc_abstract               - Write LEF/DEF/Verilog/SDC/SDF"
	@echo "  make fusion_lib                - Build fusion ref lib only"
	@echo "  make gui                       - fc_shell -gui"
	@echo "  make clean                     - Remove all generated files"
	@echo ""
	@echo "Module    : $(MODULE)"
	@echo "Flist     : $(FLIST)"
	@echo "Work dir  : $(FC_WORK)"
	@echo "Reports   : $(FC_REPORTS)/"
	@echo "Outputs   : $(FC_OUTPUTS)/"
