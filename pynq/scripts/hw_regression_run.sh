#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - nightly hardware-regression driver
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Runs the two on-board phases of the hardware regression under ONE
# fpgahub lease:
#
#   1. fast go/no-go : make stress FPGA_STRESS_MODULE=stress.hw_healthcheck
#                      (PIDR/CIDR + JEDEC + erase/program/readback; fails
#                       in ~tens of seconds on a dead board so we don't
#                       burn the stress budget discovering it).
#   2. regression    : make stress FPGA_STRESS_MODULE=stress.ci_regression
#                      (PS-stable phase subset; writes qspi_stress_*.json
#                       which the harness scp's back into imp/fpga/stress).
#
# Designed to run *inside* with_lease.sh:
#     with_lease.sh --board pynq_z2_03_pl --ttl <s> -- \
#         bash pynq/scripts/hw_regression_run.sh
# with_lease.sh has already leased the board (handling the chiplet-pair
# `pair_required` -> `--solo` retry for z2_03) and exported FPGA_BOARD /
# FPGA_LEASE_TOKEN. Each `make stress` below calls the harness's own
# with_lease.sh, which is re-entrant: it sees those vars and REUSES the
# lease instead of re-acquiring, so both phases share one lease and the
# board can't be grabbed between them.
#
# `set -e` + the explicit budgets make this a hard gate: phase 1 failing
# aborts before phase 2; either non-zero exit fails the CI job.
#
# Env (required, exported by the CI job):
#   SOCLABS_AHB_QSPI_DIR   repo root of the CI clone
#   FPGA_BOARD             set by the outer with_lease.sh (== pynq_z2_03_pl)
# Env (optional):
#   QSPI_CI_STRESS_BUDGET  total seconds for phase 2 (default 300)
#-----------------------------------------------------------------------------
set -euo pipefail

REPO="${SOCLABS_AHB_QSPI_DIR:?SOCLABS_AHB_QSPI_DIR not set}"
BOARD="${FPGA_BOARD:?FPGA_BOARD not set — run me under with_lease.sh}"
BUDGET="${QSPI_CI_STRESS_BUDGET:-300}"

echo "=============================================================="
echo " hw-regression  board=$BOARD  (lease reused from with_lease.sh)"
echo "=============================================================="

echo "--- phase 1/2: fast health gate (stress.hw_healthcheck) -------"
# FPGA_STRESS_RESULTS:= empty so run_stress.sh doesn't warn about the
# summary files the health check doesn't write (mirrors the Makefile's
# `flash_diag:` target pattern). Budget 0 — the probe ignores it.
make -C "$REPO/fpga" stress \
    BOARD="$BOARD" \
    FPGA_STRESS_MODULE=stress.hw_healthcheck \
    FPGA_STRESS_BUDGET=0 \
    FPGA_STRESS_RESULTS= \
    2>&1 | tee "$REPO/fpga_healthcheck.log"

echo "--- phase 2/2: PS-stable regression (stress.ci_regression) ----"
make -C "$REPO/fpga" stress \
    BOARD="$BOARD" \
    FPGA_STRESS_MODULE=stress.ci_regression \
    FPGA_STRESS_BUDGET="$BUDGET" \
    2>&1 | tee "$REPO/fpga_stress.log"

echo "hw-regression: both phases passed"
