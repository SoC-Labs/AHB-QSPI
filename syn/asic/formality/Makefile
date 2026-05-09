include $(dir $(lastword $(MAKEFILE_LIST)))/../common.mk

# ── Paths ──────────────────────────────────────────────────────────────────
export FM_DIR     = $(SOCLABS_AHB_QSPI_DIR)/syn/asic/formality
export FM_LOGS    = $(FM_DIR)/logs
export FM_REPORTS = $(FM_DIR)/reports
export FM_WORK    = $(FM_DIR)/work

# Inherit FC outputs / work for netlist + SVF lookup
export FC_DIR     = $(SOCLABS_AHB_QSPI_DIR)/syn/asic/fusion-compiler
export FC_OUTPUTS = $(FC_DIR)/outputs
export FC_WORK    = $(FC_DIR)/work

# ── Tool binary ────────────────────────────────────────────────────────────
FM_BIN_DIR = /eda/synopsys/2022-23/RHELx86/FM_2022.12/bin
export PATH := $(FM_BIN_DIR):$(PATH)

FM_SHELL = fm_shell

NETLIST = $(FC_OUTPUTS)/$(MODULE).v

.PHONY: lec gui clean help dirs

dirs:
	@mkdir -p $(FM_LOGS) $(FM_REPORTS) $(FM_WORK)

# ── LEC ───────────────────────────────────────────────────────────────────
# Depends on the FC netlist. The reference RTL is the same _ASIC.flist
# synthesis read.
lec: $(NETLIST) | dirs
	@echo "INFO: Formality LEC: RTL ($(FLIST)) vs $(NETLIST)"
	@cd $(FM_WORK) && set -o pipefail; \
	    $(FM_SHELL) -file $(FM_DIR)/scripts/run_lec.tcl 2>&1 \
	    | tee $(FM_LOGS)/run_lec.log; \
	    rc=$${PIPESTATUS[0]}; \
	    grep -q "^FM_LEC_OK" $(FM_LOGS)/run_lec.log || rc=1; \
	    if [ $$rc -ne 0 ]; then \
	        echo "ERROR: LEC did not pass — see $(FM_REPORTS)/04_failing.rep"; \
	        exit 1; \
	    fi
	@echo "INFO: LEC PASS — reports in $(FM_REPORTS)/"

# Surface a clear error if FC hasn't been run yet
$(NETLIST):
	@echo "ERROR: $(NETLIST) missing — run \`make -C $(FC_DIR) fc\` first" >&2
	@exit 1

# ── GUI on a finished session ─────────────────────────────────────────────
# Re-runs the same script in GUI mode so failing points can be schematic-
# debugged. fm_shell -gui can also open a saved session via -session.
gui: dirs
	cd $(FM_WORK) && $(FM_SHELL) -gui -file $(FM_DIR)/scripts/run_lec.tcl

# ── Clean ────────────────────────────────────────────────────────────────
clean:
	rm -rf $(FM_LOGS) $(FM_REPORTS) $(FM_WORK)
	rm -f  $(FM_DIR)/fm_shell_command.log $(FM_DIR)/*.svf

# ── Help ─────────────────────────────────────────────────────────────────
help:
	@echo "AHB QSPI — Formality LEC (TSMC 65 LP)"
	@echo ""
	@echo "Compares the RTL described by ahb_QSPI_ASIC.flist (reference)"
	@echo "against the post-layout netlist FC dropped at"
	@echo "  $(NETLIST)"
	@echo ""
	@echo "Targets:"
	@echo "  make lec     - Run match + verify, fail if any failing points"
	@echo "  make gui     - fm_shell -gui (debug failing points schematically)"
	@echo "  make clean   - Remove logs/reports/work/svf"
	@echo ""
	@echo "Module    : $(MODULE)"
	@echo "Reference : $(FLIST)"
	@echo "Impl      : $(NETLIST)"
	@echo "Reports   : $(FM_REPORTS)/"
	@echo "Logs      : $(FM_LOGS)/"
