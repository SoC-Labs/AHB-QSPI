#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - FPGA Build Flow Makefile
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Build flow:
#   make all          - Full flow: package_ip -> build_design
#   make package_ip   - Package qspi_vivado_wrapper as Vivado XCI IP
#   make build_design - Create block design, synthesise, implement, generate bitstream + .hwh
#   make program      - JTAG-program the PL via Vivado Hardware Manager
#   make deploy       - scp bitstream + .hwh to a PYNQ running PYNQ Linux
#   make clean        - Remove all build outputs
#
# FPGA board selection (program / deploy / run-on-board targets):
#   BOARD=fpga1                       # explicit board name from fpgahub config
#   BOARD_TAG=pynq_z2                 # auto-allocate first free matching board
#   PYNQ_HOST=..., PYNQ_PROXY=...     # manual override (bypasses fpgahub)
#
# The "via_fpgahub" variants of program / deploy drive the manifest at
# fpga/fpgahub.toml through `fpgahub actions run`, which acquires a lease
# and auto-extends it via extend_for_action for the action's timeout_s.
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

# FPGA directories
FPGA_DIR        := $(QSPI_HOME)/fpga
VIVADO_IP_DIR   := $(FPGA_DIR)/vivado_ip
TARGET          ?= pynq-z2
TARGET_DIR      := $(FPGA_DIR)/targets/$(TARGET)

# Xilinx part
XILINX_PART     := xc7z020clg400-1

# Build output directories
BUILD_DIR       := $(QSPI_HOME)/imp/fpga
IP_OUTPUT_DIR   := $(BUILD_DIR)/qspi_ip
RUN_DIR         := $(BUILD_DIR)/run
PROJECT_DIR     := $(BUILD_DIR)/project/$(TARGET)
OUTPUT_DIR      := $(BUILD_DIR)/output/$(TARGET)

# IP metadata
FPGA_VENDOR     := soclabs.org
FPGA_CORE_REV   := 1
FPGA_NUM_JOBS   ?= 4

.PHONY: all package_ip build_design clean program deploy \
        program_via_fpgahub deploy_via_fpgahub stress_via_fpgahub ci_full_via_fpgahub \
        resolve_board

all: build_design

#-----------------------------------------------------------------------------
# Step 1: Package qspi_vivado_wrapper as Vivado XCI IP
#-----------------------------------------------------------------------------
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
# Step 2: Build block design + synthesis + implementation + bitstream
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
	@echo " Bitstream: $(OUTPUT_DIR)/qspi.bit"
	@echo " HWH:       $(OUTPUT_DIR)/qspi.hwh"
	@echo "=========================================="

#-----------------------------------------------------------------------------
# Deployment helpers
#-----------------------------------------------------------------------------
BITSTREAM       := $(OUTPUT_DIR)/qspi.bit
BITBIN          := $(OUTPUT_DIR)/qspi.bin
HWH             := $(OUTPUT_DIR)/qspi.hwh
BIT2BIN         := $(FPGA_DIR)/scripts/bit2bin.py

# FPGA board selection — preferred path is via fpgahub:
#   BOARD=fpga1          explicit board name in the local fpgahub config
#   BOARD_TAG=pynq_z2    auto-allocate first free board declaring this capability
#
# When BOARD is set, PYNQ_HOST / PYNQ_PROXY default to the board's
# configured host.ssh / host.proxy looked up via `fpgahub board status`.
# When neither BOARD nor BOARD_TAG is set, callers must export PYNQ_HOST
# and PYNQ_PROXY explicitly (useful for ad-hoc runs outside fpgahub).
BOARD           ?=
BOARD_TAG       ?=

ifneq ($(BOARD),)
# Hide "command not found" from shells that haven't installed fpgahub/jq
# yet — a missing tool turns into an empty string and the deploy target
# prints a clean "set BOARD or PYNQ_HOST" error instead of leaking shell
# noise through make -n output.
PYNQ_HOST       ?= $(shell sh -c 'fpgahub board status $(BOARD) --json 2>/dev/null | jq -r ".host_ssh // empty"' 2>/dev/null)
PYNQ_PROXY      ?= $(shell sh -c 'fpgahub board status $(BOARD) --json 2>/dev/null | jq -r ".host_proxy // empty"' 2>/dev/null)
endif
PYNQ_DEST       ?= /home/xilinx/qspi_overlay
PYNQ_PASSWORD   ?= xilinx

ifneq ($(PYNQ_PROXY),)
SSH_OPTS  := -o "ProxyJump=$(PYNQ_PROXY)"
SCP_OPTS  := -o "ProxyJump=$(PYNQ_PROXY)"
else
SSH_OPTS  :=
SCP_OPTS  :=
endif

# Board identifier passed to `fpgahub actions run` — either the explicit
# BOARD, or --capability $(BOARD_TAG) for auto-allocation.
ifneq ($(BOARD),)
FPGAHUB_TARGET  := $(BOARD)
else ifneq ($(BOARD_TAG),)
FPGAHUB_TARGET  := --capability $(BOARD_TAG)
else
FPGAHUB_TARGET  :=
endif

# Print the resolved SSH target so CI / dev shells can sanity-check it.
resolve_board:
	@if [ -z "$(BOARD)" ] && [ -z "$(BOARD_TAG)" ]; then \
	    echo "ERROR: set BOARD=<name> or BOARD_TAG=<capability>" >&2; exit 2; \
	fi
	@if [ -n "$(BOARD)" ]; then \
	    fpgahub board status $(BOARD) --json | \
	        jq -r '"board=\(.name)\nssh=\(.host_ssh // "-")\nproxy=\(.host_proxy // "-")\nlease=\(.lease_state)"'; \
	else \
	    echo "Resolve via: fpgahub lease acquire --capability $(BOARD_TAG) --ttl 1h"; \
	    fpgahub board list --capability $(BOARD_TAG); \
	fi

program:
	@test -f $(BITSTREAM) || (echo "ERROR: $(BITSTREAM) not found - run 'make build_design' first"; exit 1)
	@echo "Programming $(BITSTREAM) via JTAG..."
	cd $(OUTPUT_DIR) && \
	vivado -mode batch -nojournal -nolog \
	    -source $(FPGA_DIR)/program_bitstream.tcl \
	    -tclargs $(BITSTREAM)

# bit-to-bin conversion for Linux fpga_manager - strips header, bit-reverses.
$(BITBIN): $(BITSTREAM) $(BIT2BIN)
	python3 $(BIT2BIN) $(BITSTREAM) $(BITBIN)

deploy: $(BITSTREAM) $(BITBIN) $(HWH)
	@if [ -z "$(PYNQ_HOST)" ]; then \
	    echo "ERROR: PYNQ_HOST is empty. Set BOARD=<name> (fpgahub lookup) or PYNQ_HOST=user@host." >&2; \
	    exit 2; \
	fi
	@echo "Copying overlay to $(PYNQ_HOST)$(if $(PYNQ_PROXY), via $(PYNQ_PROXY),)..."
	@ssh $(SSH_OPTS) $(PYNQ_HOST) "mkdir -p $(PYNQ_DEST)"
	@scp $(SCP_OPTS) $(BITSTREAM)            $(PYNQ_HOST):$(PYNQ_DEST)/
	@scp $(SCP_OPTS) $(BITBIN)               $(PYNQ_HOST):$(PYNQ_DEST)/
	@scp $(SCP_OPTS) $(HWH)                  $(PYNQ_HOST):$(PYNQ_DEST)/
	@scp $(SCP_OPTS) -r $(QSPI_HOME)/pynq/*  $(PYNQ_HOST):$(PYNQ_DEST)/
	@echo "Installing .bin into /lib/firmware/ and loading via fpga_manager..."
	@ssh $(SSH_OPTS) $(PYNQ_HOST) "echo $(PYNQ_PASSWORD) | sudo -S cp $(PYNQ_DEST)/qspi.bin /lib/firmware/ && \
	    echo $(PYNQ_PASSWORD) | sudo -S bash -c \"echo qspi.bin > /sys/class/fpga_manager/fpga0/firmware\" && \
	    cat /sys/class/fpga_manager/fpga0/state"
	@echo ""
	@echo "Deployed and loaded. To run stress test from PYNQ:"
	@echo "  ssh $(SSH_OPTS) $(PYNQ_HOST)"
	@echo "  cd $(PYNQ_DEST) && sudo python3 -m stress.runner --budget 300"

#-----------------------------------------------------------------------------
# fpgahub-driven variants — run the same targets through the manifest so
# the lease is acquired, extend_for_action keeps it alive, and no two
# jobs clash on the same board. See fpga/fpgahub.toml for action defs.
#-----------------------------------------------------------------------------

program_via_fpgahub:
	@echo "[deprecated] 'program_via_fpgahub' was a thin Vivado wrapper" >&2
	@echo "[deprecated] retired; delegating to program_via_plugin." >&2
	$(MAKE) program_via_plugin

# fpgahub board-plugin path: hands the freshly-built bitstream to whichever
# program plugin the operator declared in [boards.<n>.program.default]
# (vivado_jtag, pynq_overlay, sd_install, …). Doesn't go through the
# manifest, so it works for any board whose hub config carries [program]
# without requiring a project manifest binding. Pass FPGAHUB_METHOD=...
# to pick a non-default method.
FPGAHUB_METHOD  ?=
program_via_plugin: $(BITSTREAM)
	@if [ -z "$(BOARD)" ]; then \
	    echo "ERROR: set BOARD=<name> (program plugin needs an explicit board)" >&2; \
	    exit 2; \
	fi
	fpgahub board program $(BOARD) $(BITSTREAM) \
	    $(if $(FPGAHUB_METHOD),--method $(FPGAHUB_METHOD)) \
	    $(if $(FPGAHUB_FORCE),--force)

deploy_via_fpgahub:
	@if [ -z "$(FPGAHUB_TARGET)" ]; then \
	    echo "ERROR: set BOARD=<name> or BOARD_TAG=<capability>" >&2; exit 2; \
	fi
	fpgahub actions run $(FPGAHUB_TARGET) deploy

stress_via_fpgahub:
	@if [ -z "$(FPGAHUB_TARGET)" ]; then \
	    echo "ERROR: set BOARD=<name> or BOARD_TAG=<capability>" >&2; exit 2; \
	fi
	fpgahub actions run $(FPGAHUB_TARGET) stress_test

ci_full_via_fpgahub:
	@if [ -z "$(FPGAHUB_TARGET)" ]; then \
	    echo "ERROR: set BOARD=<name> or BOARD_TAG=<capability>" >&2; exit 2; \
	fi
	fpgahub actions run $(FPGAHUB_TARGET) ci_full

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR)
