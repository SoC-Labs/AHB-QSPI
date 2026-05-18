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
