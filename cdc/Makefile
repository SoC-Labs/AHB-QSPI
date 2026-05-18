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

# ── CDC goal ─────────────────────────────────────────────────────────────────
# Default to the STRUCTURAL goal (cdc_verify_struct). The full
# `cdc/cdc_verify` goal additionally runs the advanced formal Ac_cdc
# metastability rules (Ac_cdc01a et al.) which DO NOT TERMINATE in batch
# on this design — the run hangs at rule 429/533, so no summary is ever
# produced (this is exactly why `top_ahb_qspi_cdc_summary.rpt` never
# existed). cdc_verify_struct completes in minutes and produces the
# moresimple.rpt CDC sign-off summary. Override for the (long/opt-in)
# advanced run:  make cdc SG_GOAL=cdc/cdc_verify
SG_GOAL ?= cdc/cdc_verify_struct

# SpyGlass output directory. Reports land in a per-goal subtree, so
# RPTDIR tracks $(SG_GOAL)'s leaf name.
SG_WORK   := $(MODULE)
SG_GOALLEAF := $(notdir $(SG_GOAL))
RPTDIR  := $(SG_WORK)/$(MODULE)/cdc/$(SG_GOALLEAF)/spyglass_reports
CONSRPT := $(SG_WORK)/consolidated_reports/$(MODULE)_cdc_$(subst /,_,$(SG_GOAL))/moresimple.rpt

# Report files
RPT_SUMMARY := $(MODULE)_cdc_summary.rpt
RPT_DETAIL  := $(MODULE)_cdc_detail.rpt

# ── SpyGlass flags ───────────────────────────────────────────────────────────
SG_FLAGS := -batch \
            -project $(PRJ) \
            -goals "$(SG_GOAL)"

.PHONY: cdc cdc-report clean help

# ── Generate resolved flist ──────────────────────────────────────────────────
# Recursively flatten nested -f includes and convert $(VAR) to ${VAR} so
# SpyGlass can resolve environment variables.
$(RESOLVED_FLIST): $(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI_SIM.flist
	@echo "Generating resolved flist for SpyGlass..."
	@python3 $(SOCLABS_AHB_QSPI_DIR)/cdc/resolve_flist.py \
		$(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI_SIM.flist \
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
# moresimple.rpt is SpyGlass's roll-up. Prefer the consolidated copy,
# fall back to the per-goal spyglass_reports copy. Surfaces the
# message/waiver totals, the per-rule tally, and (sign-off-critical)
# every Ac_unsync02 unsynchronised crossing.
cdc-report:
	@RPT=""; \
	if [ -f "$(CONSRPT)" ]; then RPT="$(CONSRPT)"; \
	elif [ -f "$(RPTDIR)/moresimple.rpt" ]; then RPT="$(RPTDIR)/moresimple.rpt"; fi; \
	{ \
	echo "══════════════════════════════════════════════════════════"; \
	echo "  SpyGlass CDC Report: $(MODULE)   goal=$(SG_GOAL)"; \
	echo "══════════════════════════════════════════════════════════"; \
	if [ -z "$$RPT" ]; then \
		echo "  (no moresimple.rpt — run 'make cdc' first; the full"; \
		echo "   cdc/cdc_verify goal hangs at the advanced Ac_cdc rules,"; \
		echo "   use the default cdc/cdc_verify_struct goal)"; \
	else \
		echo "  source: $$RPT"; \
		echo ""; \
		echo "── Message totals ────────────────────────────────────"; \
		grep -hE 'Total Number of Generated Messages|Number of Waived Messages|Reported Messages:' "$$RPT" 2>/dev/null | sed 's/^#* */  /'; \
		echo ""; \
		echo "── Per-rule tally ────────────────────────────────────"; \
		grep -hoE '(Ac_unsync02|Ac_sync01|Ac_conv0[0-9]|Ac_glitch03|Clock_sync0[0-9]|Reset_sync0[0-9]|Ac_cdc01a?)' "$$RPT" 2>/dev/null | sort | uniq -c | sort -rn; \
		echo ""; \
		echo "── Unsynchronised crossings (Ac_unsync02 — sign-off review) ──"; \
		grep -hE 'Ac_unsync02' "$$RPT" 2>/dev/null | sed -E 's/.*(Unsynchronized Crossing:.*)/  \1/' || echo "  (none)"; \
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
	@echo "  make cdc                       - Structural CDC (cdc_verify_struct);"
	@echo "                                   completes + writes a summary"
	@echo "  make cdc SG_GOAL=cdc/cdc_verify - Full incl. advanced formal CDC"
	@echo "                                   (OPT-IN: hangs at rule 429/533 in"
	@echo "                                   batch on this design — long/manual)"
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
