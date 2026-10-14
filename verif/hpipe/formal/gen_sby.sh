#!/usr/bin/env bash
# Generate one .sby per check for a given RTL file, in a given work dir.
#   gen_sby.sh <abs path to ahb_qspi_interface.sv> <workdir> [MODE]
# MODE: bmc (default) | prove | cover
#
# Source: assessor A2, ~/SoCLabs/qspi-assess-A2 assess/A2 80e2ee8,
# formal/ahb_qspi_interface/gen_sby.sh (AHB-QSPI PR #1 assessment, 13 Oct
# 2026). Additions for the H-PIPE fix:
#   - *_wdsr* checks: watchdog reachable (WDW=4) with a short soft-reset pulse
#     (SOFT_RESET_HCLK_CYCLES=4), so reads AFTER the soft reset are inside the
#     BMC depth. They need the parameter, i.e. the fixed RTL; on older RTL
#     they are skipped. A2's original *_wd checks are kept unchanged.
#   - FRONTEND=slang (env) reads through yosys-slang instead of read -formal;
#     INV=1 (env) adds the helper invariants (-DHPIPE_INV, ahb_if_formal.sv)
#     used for k-induction; they use hierarchical references, so INV=1
#     implies FRONTEND=slang.
# The RTL and the harness are read IN PLACE with absolute paths ([script]);
# no [files] section is used, so sby never copies the RTL.
set -euo pipefail
RTL=$(realpath "$1")
WD=$2
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HARN=$HERE/ahb_if_formal.sv
mkdir -p "$WD"
INV=${INV:-0}
FRONTEND=${FRONTEND:-read}
[ "$INV" = 1 ] && FRONTEND=slang
HAS_SRC=0
grep -q "parameter SOFT_RESET_HCLK_CYCLES" "$RTL" && HAS_SRC=1

# name : defines : CTRL_MODEL : MULTI : XIP_FREE : WDW : bmc-depth : SRC
CHECKS=(
  "p1_model:P1:1:0:0:8:40:"
  "p2_model:P2:1:0:0:8:40:"
  "p6_model:P6:1:0:0:8:40:"
  "p1_rdonly:P1 -DRDONLY:1:0:0:8:40:"
  "p2_rdonly:P2 -DRDONLY:1:0:0:8:40:"
  "p1_nopipe:P1 -DRDONLY -DNOPIPE:1:0:0:8:40:"
  "p2_nopipe:P2 -DRDONLY -DNOPIPE:1:0:0:8:40:"
  "p1_wd:P1 -DRDONLY -DNOPIPE:1:0:0:4:40:"
  "p2_wd:P2 -DRDONLY -DNOPIPE:1:0:0:4:40:"
  "p3_free:P3:0:0:1:4:30:"
  "p4_free:P4:0:0:1:4:30:"
  "p5_free:P5:0:0:1:4:30:"
  "p3_multi:P3:0:1:1:4:30:"
  "p4_multi:P4:0:1:1:4:30:"
  "p5_multi:P5:0:1:1:4:30:"
  "p1_multi:P1:1:1:0:8:40:"
  "p2_multi:P2:1:1:0:8:40:"
  "p6_multi:P6:1:1:0:8:40:"
  "p1_wdsr:P1 -DRDONLY -DNOPIPE:1:0:0:4:60:4"
  "p2_wdsr:P2 -DRDONLY -DNOPIPE:1:0:0:4:60:4"
  "p1_wdsr_model:P1:1:0:0:4:60:4"
  "p2_wdsr_model:P2:1:0:0:4:60:4"
  "p6_wdsr_model:P6:1:0:0:4:60:4"
  "p1_wdsr_multi:P1:1:1:0:4:60:4"
)
COVER="cover_model::1:0:0:4:40:"
COVER_WD="cover_wdsr:WDCOVER:1:0:0:4:60:4"

emit() {
  local name=$1 defs=$2 cm=$3 mu=$4 xf=$5 wdw=$6 depth=$7 src=$8 mode=$9
  local d=""
  [ -n "$defs" ] && d="-D$defs"
  [ "$INV" = 1 ] && d="$d -DHPIPE_INV"
  [ -n "$src" ] && d="$d -DHPIPE_SRC=$src"
  {
    printf '[options]\nmode %s\ndepth %s\nmulticlock off\n\n[engines]\nsmtbmc yices\n\n[script]\n' "$mode" "$depth"
    if [ "$FRONTEND" = slang ]; then
      local g="-G WDW=$wdw -G CTRL_MODEL=$cm -G MULTI=$mu -G XIP_FREE=$xf"
      echo "plugin -i slang"
      echo "read_slang -I $HERE -DSLANG $d $g $RTL $HARN --top ahb_if_formal"
    else
      echo "read -formal $d $RTL"
      echo "read -formal -I$HERE $d $HARN"
      echo "chparam -set WDW $wdw -set CTRL_MODEL $cm -set MULTI $mu -set XIP_FREE $xf ahb_if_formal"
    fi
    echo "prep -top ahb_if_formal"
  } > "$WD/$name.sby"
}

MODE=${3:-bmc}
if [ "$MODE" = cover ]; then
  for c in "$COVER" "$COVER_WD"; do
    IFS=: read -r n d cm mu xf w dep src <<<"$c"
    [ -n "$src" ] && [ "$HAS_SRC" = 0 ] && continue
    emit "$n" "$d" "$cm" "$mu" "$xf" "$w" "$dep" "$src" cover
  done
else
  for c in "${CHECKS[@]}"; do
    IFS=: read -r n d cm mu xf w dep src <<<"$c"
    [ -n "$src" ] && [ "$HAS_SRC" = 0 ] && continue
    if [ "$MODE" = prove ]; then dep=${PROVE_K:-20}; fi
    emit "${n}_${MODE}" "$d" "$cm" "$mu" "$xf" "$w" "$dep" "$src" "$MODE"
  done
fi
ls "$WD"/*.sby
