#-----------------------------------------------------------------------------
# fpga.mk — reusable fpgahub-driven FPGA harness for SoCLabs projects.
#
# Project-agnostic make targets that:
#   * lease a board via fpgahub (with mTLS / Bearer auth),
#   * resolve the board's SSH coords (host_ssh, host_proxy, host_dev_host),
#   * program / deploy / stress-test under that lease,
#   * release the lease on any exit path.
#
# Drop this file into your project as `fpga/harness/fpga.mk` (vendored) or
# point at it via an env var, then `include` it from your project's
# fpga/Makefile after setting the FPGA_* variables below.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.  Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

# Locate the harness's own directory so we can find our scripts/
# regardless of where the includer invokes us from. $(lastword
# $(MAKEFILE_LIST)) is the path of *this* file at the moment it's read.
FPGA_HARNESS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
FPGA_HARNESS_SCRIPTS := $(FPGA_HARNESS_DIR)/scripts

#-----------------------------------------------------------------------------
# Required inputs — the includer MUST set these. Unset values trigger
# a clear error before any board-touching recipe runs.
#-----------------------------------------------------------------------------
#   FPGA_BIT           Path to the built .bit file (Vivado bitstream).
#   FPGA_HWH           Path to the .hwh hardware handoff (PYNQ overlay loader
#                      needs it alongside the bit).
#   FPGA_PYNQ_SRC      Directory whose contents get scp -r'd to the board.
#                      Typically the project's pynq/ folder containing
#                      Overlay wrappers, stress runner, tests, etc.
#   FPGA_DEST          Destination dir on the board, e.g.
#                      /home/xilinx/qspi_overlay
#
#-----------------------------------------------------------------------------
# Optional inputs — defaults provided.
#-----------------------------------------------------------------------------
#   FPGA_BIN           Path to .bin (byte-swapped from .bit for fpga_manager).
#                      Default: $(FPGA_BIT) with .bit → .bin
#   FPGA_FIRMWARE_NAME File installed under /lib/firmware/ on the board.
#                      Default: basename($(FPGA_BIN))
#   FPGA_PASSWORD      sudo password on the board.  Default: xilinx
#   FPGA_STRESS_MODULE python -m argument for `make stress`.  Required for
#                      the stress target only; no default.
#   FPGA_STRESS_BUDGET seconds budget for the stress runner.  Default: 300
#   FPGAHUB_TTL        Lease seconds.  Default: 3600
#   FPGAHUB_METHOD     `fpgahub board program --method` selector
#                      (e.g. `linux` for pynq_overlay).  Default: empty
#                      (board's [program.default] entry is used).
#   FPGAHUB_FORCE      Non-empty → pass --force to `fpgahub board program`.
#   FPGAHUB_DEFAULT_DOMAIN  DNS suffix appended to short hostnames when
#                           they don't resolve locally.  Default: ecs.soton.ac.uk
#   FPGA_PROGRAM_TCL   TCL for program_jtag_local.  No default; only needed
#                      if you call `make program_jtag_local`.
#
#-----------------------------------------------------------------------------
# Per-invocation inputs (set on the `make` command line):
#-----------------------------------------------------------------------------
#   BOARD=<name>       Specific fpgahub board.
#   BOARD_TAG=<cap>    Auto-allocate first free board matching the capability.
#-----------------------------------------------------------------------------

# Defaults
FPGA_BIN             ?= $(FPGA_BIT:.bit=.bin)
FPGA_FIRMWARE_NAME   ?= $(notdir $(FPGA_BIN))
FPGA_PASSWORD        ?= xilinx
FPGA_STRESS_BUDGET   ?= 300
FPGAHUB_TTL          ?= 3600
FPGAHUB_METHOD       ?=
FPGAHUB_FORCE        ?=
FPGAHUB_DEFAULT_DOMAIN ?= ecs.soton.ac.uk
export FPGAHUB_DEFAULT_DOMAIN

#-----------------------------------------------------------------------------
# Internals
#-----------------------------------------------------------------------------
BOARD                ?=
BOARD_TAG            ?=

WITH_LEASE           := bash $(FPGA_HARNESS_SCRIPTS)/with_lease.sh
BIT2BIN              := $(FPGA_HARNESS_SCRIPTS)/bit2bin.py

LEASE_TARGET         := $(if $(BOARD),--board $(BOARD),$(if $(BOARD_TAG),--capability $(BOARD_TAG)))

.PHONY: program program_jtag_local deploy stress ci_full resolve_board \
        _require_board _require_harness_inputs _require_stress_module \
        _require_program_tcl

#-----------------------------------------------------------------------------
# Pre-flight: fail fast and loud when required inputs are missing.
#-----------------------------------------------------------------------------
_require_harness_inputs:
	@missing=""; \
	[ -n "$(FPGA_BIT)"      ] || missing="$$missing FPGA_BIT"; \
	[ -n "$(FPGA_HWH)"      ] || missing="$$missing FPGA_HWH"; \
	[ -n "$(FPGA_PYNQ_SRC)" ] || missing="$$missing FPGA_PYNQ_SRC"; \
	[ -n "$(FPGA_DEST)"     ] || missing="$$missing FPGA_DEST"; \
	if [ -n "$$missing" ]; then \
	    echo "ERROR: harness inputs unset:$$missing" >&2; \
	    echo "       see comments at the top of $(FPGA_HARNESS_DIR)/fpga.mk" >&2; \
	    exit 2; \
	fi

_require_board:
	@if [ -z "$(BOARD)" ] && [ -z "$(BOARD_TAG)" ]; then \
	    echo "ERROR: set BOARD=<name> or BOARD_TAG=<capability> for this target." >&2; \
	    echo "       e.g.  make program BOARD=pynq_z2_03_pl"       >&2; \
	    echo "             make stress  BOARD_TAG=qspi_flash_pmod" >&2; \
	    exit 2; \
	fi

_require_stress_module:
	@if [ -z "$(FPGA_STRESS_MODULE)" ]; then \
	    echo "ERROR: FPGA_STRESS_MODULE is unset — required by make stress." >&2; \
	    echo "       set it to your project's runner, e.g. 'stress.runner'." >&2; \
	    exit 2; \
	fi

_require_program_tcl:
	@if [ -z "$(FPGA_PROGRAM_TCL)" ]; then \
	    echo "ERROR: FPGA_PROGRAM_TCL is unset — required by program_jtag_local." >&2; \
	    exit 2; \
	fi

#-----------------------------------------------------------------------------
# bit → bin (generic; Vivado .bit → fpga_manager-ready .bin)
#-----------------------------------------------------------------------------
$(FPGA_BIN): $(FPGA_BIT) $(BIT2BIN)
	python3 $(BIT2BIN) $(FPGA_BIT) $(FPGA_BIN)

#-----------------------------------------------------------------------------
# Diagnostics — print the board's resolved SSH coords without leasing.
#-----------------------------------------------------------------------------
define RESOLVE_BOARD_PY
import json, sys
d = json.load(sys.stdin)
fields = [
    ("board",    "name"),
    ("ssh",      "host_ssh"),
    ("proxy",    "host_proxy"),
    ("dev_host", "host_dev_host"),
    ("lease",    "lease_state"),
]
for label, key in fields:
    print(f"{label}={d.get(key) or '-'}")
endef
export RESOLVE_BOARD_PY

resolve_board: _require_board
	@if [ -n "$(BOARD)" ]; then \
	    fpgahub board status $(BOARD) --json | python3 -c "$$RESOLVE_BOARD_PY"; \
	else \
	    echo "Resolve via: fpgahub lease acquire --capability $(BOARD_TAG) --ttl 1h"; \
	    fpgahub board list --capability $(BOARD_TAG); \
	fi

#-----------------------------------------------------------------------------
# program — lease a board, then call `fpgahub board program` under the lease.
#
# Auth note: this hits an admin endpoint — mTLS alone is NOT enough; set
# FPGAHUB_TOKEN=<bearer> (or have an admin mint you one via
# `fpgahub token create … --role write`) before invoking. If you only have
# mTLS, use `make deploy` (pynq-Linux fpga_manager path) instead.
#-----------------------------------------------------------------------------
program: _require_harness_inputs _require_board $(FPGA_BIT)
	$(WITH_LEASE) $(LEASE_TARGET) --ttl $(FPGAHUB_TTL) -- \
	    fpgahub board program {board} $(FPGA_BIT) \
	        $(if $(FPGAHUB_METHOD),--method $(FPGAHUB_METHOD)) \
	        $(if $(FPGAHUB_FORCE),--force)

#-----------------------------------------------------------------------------
# program_jtag_local — Vivado JTAG to a cable on *this* machine (bypasses
# fpgahub entirely). Useful when the dongle is local and not remotely shared.
#-----------------------------------------------------------------------------
program_jtag_local: _require_program_tcl $(FPGA_BIT)
	@echo "Programming $(FPGA_BIT) via local JTAG..."
	cd $(dir $(FPGA_BIT)) && \
	vivado -mode batch -nojournal -nolog \
	    -source $(FPGA_PROGRAM_TCL) \
	    -tclargs $(FPGA_BIT)

#-----------------------------------------------------------------------------
# deploy — lease a board, scp the overlay onto PYNQ Linux, hot-load via
# fpga_manager. SSH coords come from `fpgahub board status` (host_ssh and
# host_proxy / host_dev_host) — no hardcoded hostnames.
#-----------------------------------------------------------------------------
deploy: _require_harness_inputs _require_board $(FPGA_BIT) $(FPGA_BIN) $(FPGA_HWH)
	$(WITH_LEASE) $(LEASE_TARGET) --ttl $(FPGAHUB_TTL) -- \
	    bash $(FPGA_HARNESS_SCRIPTS)/deploy_overlay.sh \
	        "$(FPGA_BIT)" "$(FPGA_BIN)" "$(FPGA_HWH)" \
	        "$(FPGA_PYNQ_SRC)" "$(FPGA_DEST)" "$(FPGA_PASSWORD)" \
	        "$(FPGA_FIRMWARE_NAME)"

#-----------------------------------------------------------------------------
# stress — deploy then run the project's python stress runner under one lease.
#-----------------------------------------------------------------------------
stress: _require_harness_inputs _require_stress_module _require_board \
        $(FPGA_BIT) $(FPGA_BIN) $(FPGA_HWH)
	$(WITH_LEASE) $(LEASE_TARGET) --ttl $(FPGAHUB_TTL) -- \
	    bash $(FPGA_HARNESS_SCRIPTS)/deploy_and_stress.sh \
	        "$(FPGA_BIT)" "$(FPGA_BIN)" "$(FPGA_HWH)" \
	        "$(FPGA_PYNQ_SRC)" "$(FPGA_DEST)" "$(FPGA_PASSWORD)" \
	        "$(FPGA_STRESS_BUDGET)" "$(FPGA_STRESS_MODULE)" \
	        "$(FPGA_FIRMWARE_NAME)"

# ci_full is an alias for stress — covers the deploy-then-stress flow that
# CI typically wants. Add more steps to it in your project's Makefile if
# you have post-stress checks (e.g. coverage uploads).
ci_full: stress
