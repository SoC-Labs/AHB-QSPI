#-----------------------------------------------------------------------------
# Calibre signoff-DRC for the top_ahb_qspi partition.
#
# Wires the run_drc.sh helper against the TSMC cln65lp Calibre PDK and
# the partition's exported GDS. Run with:
#
#   make calibre_drc                  # default: 1p9m_6X2Z0U deck
#   make calibre_drc STACK=1p9m_6X1Z1U
#
# Outputs land in work/ (gitignored). Exit code reflects success of
# Calibre invocation, NOT pass/fail of DRC — interpret the
# ${MODULE}.drc.summary report for the actual verdict.
#-----------------------------------------------------------------------------

include $(dir $(lastword $(MAKEFILE_LIST)))/../common.mk

export FC_DIR        = $(SOCLABS_AHB_QSPI_DIR)/syn/asic/fusion-compiler
export CALIBRE_DIR   = $(SOCLABS_AHB_QSPI_DIR)/syn/asic/calibre
export CALIBRE_WORK  = $(CALIBRE_DIR)/work
export PARTITION_GDS = $(FC_DIR)/outputs/$(MODULE).gds.gz

# Per-stack TSMC cln65lp Calibre deck. Default 1p9m_6X2Z0U matches the
# common.mk TF_FILE (arm_tech/r2p0/milkyway/1p9m_6x2z/sc12_tech.tf).
# Override via STACK=...  on the command line.
STACK ?= 1p9m_6X2Z0U
export TSMC65_CALIBRE_PDK ?= /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/pdk/Calibre
export TSMC65_DRC_DECK    ?= $(TSMC65_CALIBRE_PDK)/online/drc_online/$(STACK)/calibre.drc
export CALIBRE_BIN        ?= /eda/mentor/calibre/bin/calibre

.PHONY: calibre_drc check_prereqs clean help

calibre_drc: check_prereqs
	@echo "INFO: [calibre_drc] $(MODULE) stack=$(STACK)"
	@echo "INFO:   deck   : $(TSMC65_DRC_DECK)"
	@echo "INFO:   layout : $(PARTITION_GDS)"
	@echo "INFO:   bin    : $(CALIBRE_BIN)"
	@echo "INFO:   work   : $(CALIBRE_WORK)"
	bash $(CALIBRE_DIR)/run_drc.sh

check_prereqs:
	@test -x "$(CALIBRE_BIN)" \
	    || (echo "ERROR: Calibre binary not found: $(CALIBRE_BIN)"; exit 1)
	@test -f "$(TSMC65_DRC_DECK)" \
	    || (echo "ERROR: TSMC DRC deck not found: $(TSMC65_DRC_DECK)"; \
	        echo "       (set TSMC65_DRC_DECK or STACK= to override)"; exit 1)
	@test -f "$(PARTITION_GDS)" \
	    || (echo "ERROR: partition GDS not found: $(PARTITION_GDS)"; \
	        echo "       run 'make -C $(FC_DIR) fc_abstract' first"; exit 1)

clean:
	rm -rf $(CALIBRE_WORK)

help:
	@echo "Calibre signoff-DRC for $(MODULE) (TSMC cln65lp)"
	@echo ""
	@echo "Targets:"
	@echo "  make calibre_drc                  - run nmDRC, default stack 1p9m_6X2Z0U"
	@echo "  make calibre_drc STACK=1p9m_6X1Z1U  - use a different stack deck"
	@echo "  make check_prereqs                - verify Calibre + deck + GDS exist"
	@echo "  make clean                        - remove work/"
	@echo ""
	@echo "Outputs in $(CALIBRE_WORK)/:"
	@echo "  $(MODULE).drc.summary             - per-rule violation counts"
	@echo "  $(MODULE).drc.db                  - ASCII DRC results database (coords)"
	@echo "  $(MODULE).drc.log                 - calibre stdout/stderr"
