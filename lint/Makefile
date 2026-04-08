export SOCLABS_AHB_QSPI_DIR := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/..)
export ARM_IP_LIBRARY_PATH  ?= /research/AAA/ip_library

# ── Target module (override on command line: make MODULE=qspi_controller) ──
MODULE ?= top_ahb_qspi

# ── All lintable modules ─────────────────────────────────────────
# Standalone modules (no external IP dependencies)
STANDALONE_MODULES = qspi_controller qspi_clock_div apb_qspi_regs ahb_qspi_interface

# Modules requiring external IP (CG092 cache, Corstone-101)
IP_MODULES = top_ahb_qspi

# ── Module-to-top mapping ────────────────────────────────────────
# Flist basenames and SV module names are the same for this IP
TOP ?= $(MODULE)

# ── Module-to-flist mapping ──────────────────────────────────────
# Standalone modules use their own source file directly
FLIST_qspi_controller     = $(SOCLABS_AHB_QSPI_DIR)/lint/flist/qspi_controller.flist
FLIST_qspi_clock_div      = $(SOCLABS_AHB_QSPI_DIR)/lint/flist/qspi_clock_div.flist
FLIST_apb_qspi_regs       = $(SOCLABS_AHB_QSPI_DIR)/lint/flist/apb_qspi_regs.flist
FLIST_ahb_qspi_interface  = $(SOCLABS_AHB_QSPI_DIR)/lint/flist/ahb_qspi_interface.flist
FLIST_top_ahb_qspi        = $(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI.flist

FLIST = $(or $(FLIST_$(MODULE)),$(error No flist defined for MODULE=$(MODULE)))

# ── Paths ─────────────────────────────────────────────────────────
LOGFILE = $(MODULE)_hal.log
XMLFILE = $(MODULE)_hal.xml
RPTFILE = $(MODULE)_hal_report.txt

# ── HAL flags ─────────────────────────────────────────────────────
HAL       = hal
HAL_FLAGS = -64bit \
            -sv \
            -top $(TOP) \
            -check ALL_RTL \
            -logfile $(LOGFILE) \
            -xmlfile $(XMLFILE) \
            -messages \
            -stats \
            -lintpragma

# Add waiver rule file
HAL_FLAGS += -file $(SOCLABS_AHB_QSPI_DIR)/lint/hal.tcl

# Include path for CG092 flash cache IP (needed for top_ahb_qspi)
HAL_FLAGS += -incdir $(ARM_IP_LIBRARY_PATH)/CG092/CG092-BU-50000-r2p0-00rel0/p_flash_cache_f0/logical/p_flash_cache_f0/verilog

.PHONY: lint lint-synth lint-all lint-standalone lint-each report gui clean help

# Default target: RTL lint checks for a single module
lint:
	$(HAL) $(HAL_FLAGS) -f $(FLIST)

# Synthesizability-focused checks only
lint-synth:
	$(HAL) $(HAL_FLAGS) -nohalcheck -f $(FLIST)

# All checks (RTL + structural + synthesizability) for a single module
lint-all:
	$(HAL) $(HAL_FLAGS) -check ALL -f $(FLIST)

# Lint all standalone modules (no external IP dependency)
lint-standalone:
	@for mod in $(STANDALONE_MODULES); do \
		echo "══════════════════════════════════════════════════════════"; \
		echo "  Linting: $$mod"; \
		echo "══════════════════════════════════════════════════════════"; \
		$(MAKE) lint MODULE=$$mod || exit 1; \
	done

# Lint every module individually (standalone + IP-dependent)
lint-each:
	@for mod in $(STANDALONE_MODULES) $(IP_MODULES); do \
		echo "══════════════════════════════════════════════════════════"; \
		echo "  Linting: $$mod"; \
		echo "══════════════════════════════════════════════════════════"; \
		$(MAKE) lint MODULE=$$mod || exit 1; \
	done

# Generate a warnings/errors report from the lint log
report: $(LOGFILE)
	@{ \
	echo "══════════════════════════════════════════════════════════"; \
	echo "  HAL Lint Report: $(MODULE)"; \
	echo "  Source: $(LOGFILE)"; \
	echo "══════════════════════════════════════════════════════════"; \
	echo ""; \
	echo "── Summary ─────────────────────────────────────────────"; \
	grep -E 'Total (errors|warnings)' $(LOGFILE) || true; \
	echo ""; \
	echo "── Errors (AHB QSPI RTL) ────────────────────────────────"; \
	grep '\*E' $(LOGFILE) | grep -v 'BP210\|CG092\|cmsdk' || echo "  (none)"; \
	echo ""; \
	echo "── Warnings (AHB QSPI RTL) ──────────────────────────────"; \
	grep '\*W' $(LOGFILE) | grep -v 'BP210\|CG092\|cmsdk' | grep -v 'xmelab' || echo "  (none)"; \
	echo ""; \
	echo "── Warning Breakdown (AHB QSPI RTL) ─────────────────────"; \
	grep '\*W' $(LOGFILE) | grep -v 'BP210\|CG092\|cmsdk' | grep -v 'xmelab' \
	  | sed 's/.*\*W,\([A-Z]*\).*/\1/' | sort | uniq -c | sort -rn || true; \
	echo ""; \
	echo "── Warnings (External IP) ───────────────────────────────"; \
	ip_count=$$(grep '\*W' $(LOGFILE) | grep -cE 'BP210|CG092|cmsdk' 2>/dev/null || echo 0); \
	echo "  $$ip_count warnings (suppressed — third-party IP)"; \
	echo ""; \
	} | tee $(RPTFILE)
	@echo "Report saved to: $(RPTFILE)"

# Open results in Cadence report browser
gui:
	$(HAL) $(HAL_FLAGS) -gui -f $(FLIST)

clean:
	rm -rf *_hal.log *_hal.xml *_hal_report.txt hal.design_facts hal.log \
	       INCA_libs xcelium.d *.log.bak .hal-irun.history

help:
	@echo "AHB QSPI HAL Lint Flow"
	@echo ""
	@echo "Usage:"
	@echo "  make lint                      - Lint single module (default: $(MODULE))"
	@echo "  make lint MODULE=<name>        - Lint a specific module"
	@echo "  make lint-synth                - Synthesizability checks only"
	@echo "  make lint-all                  - All checks (RTL + structural + synth)"
	@echo "  make lint-standalone           - Lint all standalone modules"
	@echo "  make lint-each                 - Lint every module (needs IP for some)"
	@echo "  make report                    - Extract warnings/errors from lint log"
	@echo "  make gui                       - Open report browser"
	@echo "  make clean                     - Remove generated files"
	@echo ""
	@echo "Standalone modules (no external deps):"
	@echo "  $(STANDALONE_MODULES)"
	@echo ""
	@echo "IP-dependent modules:"
	@echo "  $(IP_MODULES)"
	@echo ""
	@echo "Examples:"
	@echo "  make lint MODULE=qspi_controller"
	@echo "  make lint-standalone"
	@echo "  make lint report               - Lint then show warnings/errors"
