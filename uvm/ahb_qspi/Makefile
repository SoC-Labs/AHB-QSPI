###############################################################################
# Makefile for AHB QSPI UVM Testbench
###############################################################################
# Uses Synopsys VCS with UVM-1.2.
#
# Targets:
#   make compile                  - Compile testbench
#   make run TEST=<test_name>     - Compile and run a specific test
#   make run_all                  - Run all tests (regression)
#   make coverage                 - Generate merged coverage report
#   make clean                    - Remove build artifacts
###############################################################################

# Tool paths
VCS_HOME    ?= /eda/synopsys/2022-23/RHELx86/VCS_2022.06-SP2
VERDI_HOME  ?= /eda/synopsys/2022-23/RHELx86/VERDI_2022.06-SP2

# Project paths
AHB_QSPI_HOME   ?= $(realpath ../..)
SOCLABS_AHB_QSPI_DIR ?= $(AHB_QSPI_HOME)
export SOCLABS_AHB_QSPI_DIR
export ARM_IP_LIBRARY_PATH
UVM_TB_DIR        = $(CURDIR)
TB_DIR            = $(UVM_TB_DIR)/tb
ENV_DIR           = $(UVM_TB_DIR)/env
AGENT_DIR         = $(UVM_TB_DIR)/agents/apb_master_agent
QSPI_MON_DIR      = $(UVM_TB_DIR)/agents/qspi_monitor
SEQ_DIR           = $(UVM_TB_DIR)/sequences
TEST_DIR          = $(UVM_TB_DIR)/tests

# Simulation output
SIM_DIR      = sim_build
COV_DIR      = coverage_report

# Default test
TEST        ?= ahb_qspi_register_test
SEED        ?= random
VERBOSITY   ?= UVM_MEDIUM

# ---------------------------------------------------------------
# VCS compile flags
# ---------------------------------------------------------------
VCS  = $(VCS_HOME)/bin/vcs

VCS_FLAGS  = -full64 -sverilog
VCS_FLAGS += -ntb_opts uvm-1.2
VCS_FLAGS += -timescale=1ns/1ps
VCS_FLAGS += -xprop=tmerge

# Code coverage — scoped to DUT hierarchy only
VCS_FLAGS += -cm line+cond+tgl+fsm+branch

# UVM include path
UVM_HOME    = $(VCS_HOME)/etc/uvm-1.2
VCS_FLAGS += +incdir+$(UVM_HOME)

# Testbench include paths
VCS_FLAGS += +incdir+$(TB_DIR)
VCS_FLAGS += +incdir+$(ENV_DIR)
VCS_FLAGS += +incdir+$(AGENT_DIR)
VCS_FLAGS += +incdir+$(QSPI_MON_DIR)
VCS_FLAGS += +incdir+$(SEQ_DIR)
VCS_FLAGS += +incdir+$(TEST_DIR)

# DUT source (expanded filelist — VCS cannot expand $(VAR) in .flist files)
FLIST_EXPANDED = $(SIM_DIR)/ahb_qspi_sim.flist
VCS_FLAGS += -f $(FLIST_EXPANDED)

# Top-level testbench
VCS_FLAGS += $(TB_DIR)/top.sv

# Output
VCS_FLAGS += -l $(SIM_DIR)/compile.log
VCS_FLAGS += -o $(SIM_DIR)/simv
VCS_FLAGS += -cm_dir $(SIM_DIR)/simv.vdb

# Suppress common warnings
VCS_FLAGS += +warn=noTFIPC +warn=noLINX_KNDX

# ---------------------------------------------------------------
# Simulation run flags
# ---------------------------------------------------------------
SIM_FLAGS  = +UVM_TESTNAME=$(TEST)
SIM_FLAGS += +UVM_VERBOSITY=$(VERBOSITY)
SIM_FLAGS += -cm line+cond+tgl+fsm+branch
SIM_FLAGS += -l $(TEST).log

ifneq ($(SEED),random)
  SIM_FLAGS += +ntb_random_seed=$(SEED)
else
  SIM_FLAGS += +ntb_random_seed_automatic
endif

# ---------------------------------------------------------------
# Test suite
# ---------------------------------------------------------------
TESTS = ahb_qspi_register_test \
        ahb_qspi_spi_cmd_test \
        ahb_qspi_qpi_cmd_test \
        ahb_qspi_xip_test \
        ahb_qspi_error_test \
        ahb_qspi_clkdiv_test \
        ahb_qspi_irq_test \
        ahb_qspi_arb_test \
        ahb_qspi_reset_test \
        ahb_qspi_stress_test

# ---------------------------------------------------------------
# Targets
# ---------------------------------------------------------------
.PHONY: compile run clean coverage run_all help waves

help:
	@echo "Usage:"
	@echo ""
	@echo "  make compile                    - Compile testbench"
	@echo "  make run TEST=<test_name>       - Compile and run a specific test"
	@echo "  make run_all                    - Run all tests (regression)"
	@echo "  make coverage                   - Generate merged coverage report"
	@echo "  make waves                      - Compile and run with VCD waveform dumping"
	@echo "  make clean                      - Remove all build artifacts"
	@echo ""
	@echo "Available tests:"
	@echo "  ahb_qspi_register_test          - Register reset values, read/write, PID/CID"
	@echo "  ahb_qspi_spi_cmd_test           - SPI mode: JEDEC ID, read, page program"
	@echo "  ahb_qspi_qpi_cmd_test           - QPI mode: enter/exit, JEDEC ID, fast read"
	@echo "  ahb_qspi_xip_test               - XIP memory-mapped reads via AHB"
	@echo "  ahb_qspi_error_test             - Error paths: write reject, no-XIP read"
	@echo "  ahb_qspi_clkdiv_test            - Clock divider sweep (0-31)"
	@echo "  ahb_qspi_irq_test               - Interrupt assert/clear"
	@echo "  ahb_qspi_arb_test               - XIP/APB arbitration"
	@echo "  ahb_qspi_reset_test             - Reset recovery"
	@echo "  ahb_qspi_stress_test            - Register storm, mode frenzy, dummy sweep"
	@echo ""
	@echo "Variables:"
	@echo "  TEST=<name>                     - Test to run (default: ahb_qspi_register_test)"
	@echo "  SEED=<value|random>             - Random seed (default: random)"
	@echo "  VERBOSITY=<UVM_NONE|...|UVM_DEBUG> - UVM verbosity (default: UVM_MEDIUM)"

# Generate expanded filelist (resolve env vars that VCS cannot expand)
$(FLIST_EXPANDED): | $(SIM_DIR)
	python3 $(UVM_TB_DIR)/expand_flist.py \
		$(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI_SIM.flist \
		$(UVM_TB_DIR)/$(FLIST_EXPANDED)

compile: $(FLIST_EXPANDED) | $(SIM_DIR)
	$(VCS) $(VCS_FLAGS)

$(SIM_DIR):
	mkdir -p $(SIM_DIR)

run: compile
	cd $(SIM_DIR) && ./simv $(SIM_FLAGS) -cm_dir simv.vdb

waves: VCS_FLAGS += +define+WAVES_VCD
waves: run

run_all: compile
	@pass=0; fail=0; \
	for test in $(TESTS); do \
		echo "======== Running $$test ========"; \
		if cd $(SIM_DIR) && ./simv +UVM_TESTNAME=$$test +UVM_VERBOSITY=$(VERBOSITY) \
			-cm line+cond+tgl+fsm+branch -cm_dir simv.vdb \
			+ntb_random_seed_automatic -l $$test.log; then \
			echo "  PASSED: $$test"; \
			pass=$$((pass + 1)); \
		else \
			echo "  FAILED: $$test"; \
			fail=$$((fail + 1)); \
		fi; \
		cd ..; \
	done; \
	echo "======== Regression complete: $$pass passed, $$fail failed ========"; \
	exit $$fail

coverage:
	$(VCS_HOME)/bin/urg -dir $(SIM_DIR)/simv.vdb -report $(COV_DIR) -format both

# ---------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------
clean:
	rm -rf $(SIM_DIR) $(COV_DIR) \
	       csrc *.log ucli.key vc_hdrs.h
