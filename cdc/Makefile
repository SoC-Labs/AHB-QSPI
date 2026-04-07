export SOCLABS_AHB_QSPI_DIR := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/..)

# ── SpyGlass tool ────────────────────────────────────────────────────────────
SPYGLASS_HOME ?= /eda/synopsys/2022-23/RHELx86/SPYGLASS_2022.06-SP2/SPYGLASS_HOME
SPYGLASS      := $(SPYGLASS_HOME)/bin/spyglass

# ── Target module ────────────────────────────────────────────────────────────
MODULE ?= top_ahb_qspi

# ── Paths ────────────────────────────────────────────────────────────────────
# SpyGlass cannot resolve $(VAR) syntax in flists. We generate a resolved
# flat flist with ${VAR} syntax that SpyGlass can process.
RESOLVED_FLIST := $(SOCLABS_AHB_QSPI_DIR)/cdc/resolved.flist
export FLIST   := $(RESOLVED_FLIST)
export SGDC    := $(SOCLABS_AHB_QSPI_DIR)/cdc/top_ahb_qspi.sgdc
export SWL     := $(SOCLABS_AHB_QSPI_DIR)/cdc/waiver.swl
export SG_TOP  := $(MODULE)
PRJ            := $(SOCLABS_AHB_QSPI_DIR)/cdc/top_ahb_qspi.prj

# SpyGlass output directory
SG_WORK := $(MODULE)
RPTDIR  := $(SG_WORK)/$(MODULE)/cdc/cdc_verify/spyglass_reports

# Report files
RPT_SUMMARY := $(MODULE)_cdc_summary.rpt
RPT_DETAIL  := $(MODULE)_cdc_detail.rpt

# ── SpyGlass flags ───────────────────────────────────────────────────────────
SG_FLAGS := -batch \
            -project $(PRJ) \
            -goals "cdc/cdc_verify"

.PHONY: cdc cdc-report clean help

# ── Generate resolved flist ──────────────────────────────────────────────────
# Recursively flatten nested -f includes and convert $(VAR) to ${VAR} so
# SpyGlass can resolve environment variables.
$(RESOLVED_FLIST): $(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI.flist
	@echo "Generating resolved flist for SpyGlass..."
	@python3 $(SOCLABS_AHB_QSPI_DIR)/cdc/resolve_flist.py \
		$(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI.flist \
		$(RESOLVED_FLIST)

# ── Default target: run CDC analysis ─────────────────────────────────────────
cdc: $(RESOLVED_FLIST)
	@echo "══════════════════════════════════════════════════════════"
	@echo "  SpyGlass CDC: $(MODULE)"
	@echo "══════════════════════════════════════════════════════════"
	$(SPYGLASS) $(SG_FLAGS)
	@echo ""
	@echo "CDC analysis complete. Results in $(SG_WORK)/"
	@$(MAKE) --no-print-directory cdc-report

# ── Extract summary report ───────────────────────────────────────────────────
cdc-report:
	@{ \
	echo "══════════════════════════════════════════════════════════"; \
	echo "  SpyGlass CDC Report: $(MODULE)"; \
	echo "══════════════════════════════════════════════════════════"; \
	echo ""; \
	echo "── Violation Summary ─────────────────────────────────────"; \
	if ls $(RPTDIR)/*summary* 1>/dev/null 2>&1; then \
		cat $(RPTDIR)/*summary*; \
	elif ls $(RPTDIR)/*.rpt 1>/dev/null 2>&1; then \
		grep -h -E '(Error|Warning|Info|Total)' $(RPTDIR)/*.rpt 2>/dev/null || echo "  (no summary lines found)"; \
	else \
		echo "  (no report files found — run 'make cdc' first)"; \
	fi; \
	echo ""; \
	echo "── CDC Crossings (AHB QSPI RTL) ─────────────────────────"; \
	if ls $(RPTDIR)/*.rpt 1>/dev/null 2>&1; then \
		grep -h -iE '(qspi_|ahb_qspi|apb_qspi|cache_)' $(RPTDIR)/*.rpt 2>/dev/null | head -50 || echo "  (none found)"; \
	else \
		echo "  (no report files)"; \
	fi; \
	echo ""; \
	} | tee $(RPT_SUMMARY)
	@echo "Report saved to: $(RPT_SUMMARY)"

# ── Clean ────────────────────────────────────────────────────────────────────
clean:
	rm -rf *_spyglass $(MODULE) *_cdc_summary.rpt *_cdc_detail.rpt \
	       spyglass_output spyglass.log sg_shell.log resolved.flist

# ── Help ─────────────────────────────────────────────────────────────────────
help:
	@echo "AHB QSPI SpyGlass CDC Flow"
	@echo ""
	@echo "Usage:"
	@echo "  make cdc                       - Run CDC analysis (default: $(MODULE))"
	@echo "  make cdc-report                - Re-extract summary from last run"
	@echo "  make clean                     - Remove SpyGlass work directories"
	@echo ""
	@echo "Prerequisites:"
	@echo "  SPYGLASS_HOME:        $(SPYGLASS_HOME)"
	@echo "  ARM_IP_LIBRARY_PATH:  $(ARM_IP_LIBRARY_PATH)"
	@echo ""
	@echo "Clock Domains:"
	@echo "  HCLK          - AHB system clock"
	@echo "  PCLK          - APB peripheral clock"
	@echo "  QSPI_SCLK_i  - Generated QSPI serial clock (divided from HCLK)"
