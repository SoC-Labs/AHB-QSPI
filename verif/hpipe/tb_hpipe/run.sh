#!/bin/bash
# verif/hpipe/tb_hpipe/run.sh [IP_DIR] -- standalone H-PIPE bench for
# ahb_qspi_interface (VCS). Exit 0 = 0 errors.
#
# Source: assessor A3's bench, ~/SoCLabs/qspi-assess-A3-ip branch assess/A3
# f1961d6, verif/assess_a3/{tb_hpipe.sv,run.sh} (AHB-QSPI PR #1 assessment,
# 13 Oct 2026). tb_hpipe.sv is unchanged; this script only moves the work dir
# out of the source tree (simulate/ is git-ignored).
#   IP_DIR    : tree whose logical/ RTL is simulated (default: this checkout)
#   HPIPE_WORK: work dir (default: <this checkout>/simulate/hpipe/tb_hpipe)
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../.." && pwd)
IP=${1:-$ROOT}
W=${HPIPE_WORK:-$ROOT/simulate/hpipe/tb_hpipe}
mkdir -p "$W" && cd "$W" || exit 2
vcs -full64 -sverilog -q +lint=none -timescale=1ns/1ps \
    "$IP/logical/ahb_qspi_interface/logical/ahb_qspi_interface.sv" "$H/tb_hpipe.sv" \
    -top tb_hpipe -o simv_hpipe > compile.log 2>&1 || { tail -20 compile.log; exit 2; }
./simv_hpipe > run.log 2>&1
grep "TB_HPIPE\|DATA:\|R1:\|R2:\|R3:\|HANG" run.log
grep -q "TB_HPIPE: 0 errors" run.log
