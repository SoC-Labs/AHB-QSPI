#!/bin/bash
# H-PIPE regression runner for assessor A1's cocotb tests (VCS).
#   run_a1.sh [OUTDIR] [TEST1,TEST2,...]     (default: all 21 tests)
#   RTL_DIR=<tree with logical/>  simulate another tree (default: this checkout)
#
# Source: ~/SoCLabs/qspi-assess-A1 assess/A1 0c3ca6c verif/cocotb_a1/run_a1.sh
# (A1 exported a commit with git archive; this version simulates RTL_DIR in
# place). Needs cocotb 2.0.x on PATH (cocotb-config), VCS, and
# verif/VIP/SST26VF064B.v (make get_flash_model). No Arm IP is needed.
# Expected on the H-PIPE fix: 21/21 PASS. On c8af8ee (master with PR #1):
# 10 PASS, 11 FAIL (the H-PIPE tests and a1_q1_apb_frames_and_clocks, which
# is the separate QPI command-only doubling, qspi_controller.sv:271).
set -eu
A1=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$A1/../../.." && pwd)
OUT=${1:-$ROOT/simulate/hpipe/cocotb_a1}; TC=${2:-}
RTL_DIR=${RTL_DIR:-$ROOT}
export PYTHONDONTWRITEBYTECODE=1
mkdir -p "$OUT"; cd "$OUT"
: > "$OUT/run.log"
if [ -z "$TC" ]; then
  make -f "$A1/Makefile" RTL_DIR="$RTL_DIR" VIP_DIR="${VIP_DIR:-$ROOT/verif/VIP}" \
       SIM_BUILD="$OUT/sim_build" >> "$OUT/run.log" 2>&1 || true
else
  for t in ${TC//,/ }; do
    make -f "$A1/Makefile" RTL_DIR="$RTL_DIR" VIP_DIR="${VIP_DIR:-$ROOT/verif/VIP}" \
         SIM_BUILD="$OUT/sim_build" COCOTB_TEST_FILTER="[.]${t}\$\$" >> "$OUT/run.log" 2>&1 || true
  done
fi
sed 's/\x1b\[[0-9;]*m//g' "$OUT/run.log" | grep -aE "\*\* test_a1|TESTS=" || true
