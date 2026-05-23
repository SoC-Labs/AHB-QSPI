#-----------------------------------------------------------------------------
# AHB QSPI Subsystem — FPGA project Makefile.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Layout:
#   This Makefile defines the *project-specific* build (Vivado IP
#   packaging + block-design assembly + bitstream gen) and points
#   `harness/fpga.mk` at the resulting artefacts so the harness can
#   lease a board and program / deploy / stress under that lease.
#
# Public targets:
#   make all / build_design  - Vivado: package IP, build BD, generate .bit + .hwh
#   make package_ip          - Just package qspi_vivado_wrapper as XCI
#   make program             - (harness) JTAG-program a leased board via fpgahub
#   make program_jtag_local  - (harness) Vivado JTAG to a local cable
#   make deploy              - (harness) scp + hot-load on PYNQ Linux
#   make stress              - (harness) deploy + pynq.stress.runner
#   make ci_full             - (harness) deploy + stress in one lease
#   make resolve_board       - (harness) print resolved SSH coords
#   make clean               - remove build outputs
#
# Per-invocation board selection (any board-touching target):
#   make program BOARD=pynq_z2_03_pl
#   make stress  BOARD_TAG=qspi_flash_pmod
#-----------------------------------------------------------------------------

# Project root - assumes this Makefile lives in $SOCLABS_AHB_QSPI_DIR/fpga
QSPI_HOME       := $(realpath ..)

# Surface SOCLABS_AHB_QSPI_DIR if not already set (e.g. when the parent shell
# didn't source set_env.sh). Both the filelist and any sub-tools rely on it.
ifeq ($(SOCLABS_AHB_QSPI_DIR),)
SOCLABS_AHB_QSPI_DIR := $(QSPI_HOME)
export SOCLABS_AHB_QSPI_DIR
endif

ifeq ($(ARM_IP_LIBRARY_PATH),)
$(error ARM_IP_LIBRARY_PATH is not set - source the SoC Labs environment first)
endif
export ARM_IP_LIBRARY_PATH

#-----------------------------------------------------------------------------
# Vivado build inputs (project-specific)
#-----------------------------------------------------------------------------
FPGA_DIR        := $(QSPI_HOME)/fpga
VIVADO_IP_DIR   := $(FPGA_DIR)/vivado_ip
TARGET          ?= pynq-z2
TARGET_DIR      := $(FPGA_DIR)/targets/$(TARGET)

XILINX_PART     := xc7z020clg400-1

BUILD_DIR       := $(QSPI_HOME)/imp/fpga
IP_OUTPUT_DIR   := $(BUILD_DIR)/qspi_ip
RUN_DIR         := $(BUILD_DIR)/run
PROJECT_DIR     := $(BUILD_DIR)/project/$(TARGET)
OUTPUT_DIR      := $(BUILD_DIR)/output/$(TARGET)

FPGA_VENDOR     := soclabs.org
FPGA_CORE_REV   := 1
FPGA_NUM_JOBS   ?= 4

#-----------------------------------------------------------------------------
# Harness inputs — wire up paths so harness/fpga.mk knows what to deploy.
#-----------------------------------------------------------------------------
FPGA_BIT            := $(OUTPUT_DIR)/qspi.bit
FPGA_BIN            := $(OUTPUT_DIR)/qspi.bin
FPGA_HWH            := $(OUTPUT_DIR)/qspi.hwh
FPGA_PYNQ_SRC       := $(QSPI_HOME)/pynq
FPGA_DEST           := /home/xilinx/qspi_overlay
FPGA_FIRMWARE_NAME  := qspi.bin
FPGA_STRESS_MODULE  := stress.runner
# Pull runner.py's structured results back off the board after `make
# stress` (its argparse defaults — see pynq/stress/runner.py). Land them
# in the build tree next to $(RUN_DIR), so CI/after_script can grab them.
FPGA_STRESS_RESULTS     := qspi_stress_summary.json qspi_stress_failures.jsonl
FPGA_STRESS_RESULTS_DIR := $(BUILD_DIR)/stress
FPGA_PROGRAM_TCL    := $(FPGA_DIR)/program_bitstream.tcl

#-----------------------------------------------------------------------------
# cocotb-silicon wiring — run the verif/cocotb suite on hardware via the
# standalone `cocotb-silicon` package (see docs/cocotb-silicon-design.md).
# The board run is driven by the SAME harness as `stress`; only the python
# module differs (pynq/run_cocotb_silicon.py).
#-----------------------------------------------------------------------------
# Sibling checkout of the cocotb-silicon repo (override on the cmd line if
# elsewhere). realpath is empty if absent; the stage step errors clearly.
COCOTB_SILICON_DIR ?= $(realpath $(QSPI_HOME)/../cocotb-silicon)
COCOTB_HW_STAGE    := $(BUILD_DIR)/cocotb_hw_stage
# 0 => no wall-clock guard (run the whole suite). Override for a time box.
COCOTB_HW_BUDGET   ?= 0

# Pull in the reusable harness — defines program / deploy / stress /
# ci_full / program_jtag_local / resolve_board on top of the FPGA_*
# variables above.
include $(FPGA_DIR)/harness/fpga.mk

#-----------------------------------------------------------------------------
# Vivado: package qspi_vivado_wrapper as XCI IP
#-----------------------------------------------------------------------------
.PHONY: all package_ip build_design clean

all: build_design

package_ip:
	@mkdir -p $(RUN_DIR) $(IP_OUTPUT_DIR)
	cd $(RUN_DIR) && \
	export FPGA_COMPONENT_FILELIST=$(FPGA_DIR)/filelist.tcl && \
	export FPGA_COMPONENT_LIB=$(IP_OUTPUT_DIR) && \
	export FPGA_VENDOR=$(FPGA_VENDOR) && \
	export FPGA_CORE_REV=$(FPGA_CORE_REV) && \
	vivado -mode batch -source $(VIVADO_IP_DIR)/package_qspi_ip.tcl \
	    -log $(RUN_DIR)/package_ip.log \
	    -journal $(RUN_DIR)/package_ip.jou

#-----------------------------------------------------------------------------
# Vivado: block design + synthesis + implementation + bitstream
#-----------------------------------------------------------------------------
build_design: package_ip
	@mkdir -p $(RUN_DIR) $(PROJECT_DIR) $(OUTPUT_DIR)
	cd $(RUN_DIR) && \
	export FPGA_PART=$(XILINX_PART) && \
	export FPGA_PROJECT_DIR=$(PROJECT_DIR) && \
	export FPGA_IP_REPO=$(IP_OUTPUT_DIR) && \
	export FPGA_TARGET_DIR=$(TARGET_DIR) && \
	export FPGA_OUTPUT_DIR=$(OUTPUT_DIR) && \
	export FPGA_NUM_JOBS=$(FPGA_NUM_JOBS) && \
	vivado -mode batch -source $(FPGA_DIR)/build_qspi_design.tcl \
	    -log $(RUN_DIR)/build_design.log \
	    -journal $(RUN_DIR)/build_design.jou
	@echo ""
	@echo "=========================================="
	@echo " FPGA build complete!"
	@echo " Bitstream: $(FPGA_BIT)"
	@echo " HWH:       $(FPGA_HWH)"
	@echo "=========================================="

clean:
	rm -rf $(BUILD_DIR)

#-----------------------------------------------------------------------------
# cocotb_hw — deploy + run the cocotb suite on a leased board via
# cocotb-silicon. Reuses the shared harness verbatim (lease → deploy →
# `python3 -m run_cocotb_silicon --budget N` → scp results back); the only
# project-specific bit is staging a self-contained bundle so the board
# import works without a repo checkout or pip on the board.
#
#   make -C fpga cocotb_hw BOARD=pynq_z2_03_pl
#   make -C fpga cocotb_hw BOARD_TAG=qspi_flash_pmod COCOTB_HW_BUDGET=600
#-----------------------------------------------------------------------------
.PHONY: cocotb_hw stage_cocotb_hw

# Flat bundle: pynq/ (incl. the adapter + entrypoint) + the cocotb_silicon
# package + verif/cocotb/*.py, all side by side, so `python3 -m
# run_cocotb_silicon` from the overlay cwd resolves every import.
stage_cocotb_hw:
	@echo "Staging cocotb-silicon bundle -> $(COCOTB_HW_STAGE)"
	@rm -rf $(COCOTB_HW_STAGE)
	@mkdir -p $(COCOTB_HW_STAGE)
	@cp -r $(FPGA_PYNQ_SRC)/. $(COCOTB_HW_STAGE)/
	@test -d "$(COCOTB_SILICON_DIR)/src/cocotb_silicon" || { \
	    echo "ERROR: cocotb_silicon not found at '$(COCOTB_SILICON_DIR)/src'."; \
	    echo "       set COCOTB_SILICON_DIR=<path to cocotb-silicon checkout>."; \
	    exit 2; }
	@cp -r $(COCOTB_SILICON_DIR)/src/cocotb_silicon $(COCOTB_HW_STAGE)/
	@cp $(QSPI_HOME)/verif/cocotb/*.py $(COCOTB_HW_STAGE)/
	@echo "Staged pynq/ + cocotb_silicon/ + verif/cocotb/*.py (flat)"

# Mirrors harness/fpga.mk:stress but with module=run_cocotb_silicon and the
# staged dir as the deploy source. FPGA_STRESS_RESULTS/_DIR are
# target-scoped so the harness scp's the cocotb result JSON back.
cocotb_hw: FPGA_STRESS_RESULTS     := qspi_cocotb_results.json
cocotb_hw: FPGA_STRESS_RESULTS_DIR := $(BUILD_DIR)/cocotb_hw
cocotb_hw: _require_harness_inputs _require_board stage_cocotb_hw \
           $(FPGA_BIT) $(FPGA_BIN) $(FPGA_HWH)
	$(WITH_LEASE) $(LEASE_TARGET) --ttl $(FPGAHUB_TTL) -- \
	    bash $(FPGA_HARNESS_SCRIPTS)/deploy_and_stress.sh \
	        "$(FPGA_BIT)" "$(FPGA_BIN)" "$(FPGA_HWH)" \
	        "$(COCOTB_HW_STAGE)" "$(FPGA_DEST)" "$(FPGA_PASSWORD)" \
	        "$(COCOTB_HW_BUDGET)" "run_cocotb_silicon" \
	        "$(FPGA_FIRMWARE_NAME)"

#-----------------------------------------------------------------------------
# flash_diag — one-shot on-board ground-truth probe (pynq/flash_diag.py):
# proven qspi_hw Micron path vs the raw cocotb-SST sequence, side by side.
# Same staging/lease path as cocotb_hw; output is ssh-streamed (no result
# file -> empty FPGA_STRESS_RESULTS so the harness skips the pull-back).
#
#   make -C fpga flash_diag BOARD_TAG=qspi_flash_pmod
#-----------------------------------------------------------------------------
.PHONY: flash_diag
flash_diag: FPGA_STRESS_RESULTS :=
flash_diag: _require_harness_inputs _require_board stage_cocotb_hw \
            $(FPGA_BIT) $(FPGA_BIN) $(FPGA_HWH)
	$(WITH_LEASE) $(LEASE_TARGET) --ttl $(FPGAHUB_TTL) -- \
	    bash $(FPGA_HARNESS_SCRIPTS)/deploy_and_stress.sh \
	        "$(FPGA_BIT)" "$(FPGA_BIN)" "$(FPGA_HWH)" \
	        "$(COCOTB_HW_STAGE)" "$(FPGA_DEST)" "$(FPGA_PASSWORD)" \
	        "0" "flash_diag" \
	        "$(FPGA_FIRMWARE_NAME)"
