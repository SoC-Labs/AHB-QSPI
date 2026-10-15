#!/usr/bin/env bash
# Run every A2 formal check against one copy of ahb_qspi_interface.sv.
# Source: ~/SoCLabs/qspi-assess-A2 assess/A2 80e2ee8 formal/ahb_qspi_interface/
# run_all.sh; changed only to run every cover_*.sby (cover_wdsr added).
#   run_all.sh <abs path to ahb_qspi_interface.sv> <workdir> [modes...]
# modes default: bmc prove cover. Prints one PASS/FAIL/UNKNOWN line per check
# and writes <workdir>/SUMMARY.txt.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RTL=$1; WD=$2; shift 2
MODES=${*:-bmc prove cover}
export PATH=$HOME/tools/oss-cad-suite/bin:$PATH
mkdir -p "$WD"; : > "$WD/SUMMARY.txt"
for m in $MODES; do
  rm -f "$WD"/*.sby; "$HERE/gen_sby.sh" "$RTL" "$WD" "$m" >/dev/null
  for f in "$WD"/*_"$m".sby "$WD"/cover_*.sby; do
    [ -f "$f" ] || continue
    case "$m:$(basename "$f")" in cover:cover_*) ;; cover:*) continue ;; *:cover_*) continue ;; esac
    n=$(basename "$f" .sby)
    ( cd "$WD" && nice -n 19 timeout 1800 sby -f "$n.sby" > "$n.log" 2>&1 )
    st=$(grep -oE 'DONE \([A-Z]+' "$WD/$n.log" | tail -1 | sed 's/DONE (//')
    step=$(grep -oE '(failed assertion|reached cover statement).* step [0-9]+' "$WD/$n.log" | grep -oE 'step [0-9]+' | tr '\n' ' ')
    printf '%-22s %-8s %s\n' "$n" "${st:-ERROR}" "$step" | tee -a "$WD/SUMMARY.txt"
  done
done
