#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# Calibre signoff DRC for the top_ahb_qspi partition.
#
# Invokes Calibre nmDRC against the partition's exported GDS using the
# TSMC cln65lp 1p9m_6X2Z0U rule deck. Outputs a per-rule violation
# report with exact coordinates + foundry rule numbers — i.e. the
# information `check_routes` cannot give headlessly in this fc_shell
# version.
#
# Usage:    make calibre_drc
#  or:      bash syn/asic/calibre/run_drc.sh
#
# Required env (exported by syn/asic/calibre/Makefile):
#   MODULE                — partition top cell name (top_ahb_qspi)
#   PARTITION_GDS         — path to outputs/<MODULE>.gds.gz
#   TSMC65_DRC_DECK       — path to the TSMC Calibre DRC deck
#   CALIBRE_BIN           — path to the calibre executable
#   CALIBRE_WORK          — work directory (logs, summary, .lef.layermap)
#   STDCELL_GDS, MEM_GDS  — optional merge sources (already in
#                            PARTITION_GDS if exported with
#                            -merge_files; left here as a hook)
#-----------------------------------------------------------------------------
set -euo pipefail

: "${MODULE:?MODULE not set}"
: "${PARTITION_GDS:?PARTITION_GDS not set}"
: "${TSMC65_DRC_DECK:?TSMC65_DRC_DECK not set}"
: "${CALIBRE_BIN:?CALIBRE_BIN not set (typically /eda/mentor/calibre/bin/calibre)}"
: "${CALIBRE_WORK:?CALIBRE_WORK not set}"

mkdir -p "$CALIBRE_WORK"
cd "$CALIBRE_WORK"

# Decompress if needed — Calibre wants a raw .gds / .gds2 / .oasis file.
gds_in="$PARTITION_GDS"
if [[ "$PARTITION_GDS" == *.gz ]]; then
    gds_in="$CALIBRE_WORK/$(basename "${PARTITION_GDS%.gz}")"
    if [[ ! -s "$gds_in" || "$PARTITION_GDS" -nt "$gds_in" ]]; then
        echo "INFO: decompressing $PARTITION_GDS -> $gds_in"
        gunzip -kc "$PARTITION_GDS" > "$gds_in"
    fi
fi

# The TSMC deck is a self-contained runset (no INCLUDEs), with
# placeholders at lines 174-178 that must be substituted:
#   LAYOUT PATH    "GDSFILENAME"
#   LAYOUT PRIMARY "TOPCELLNAME"
#   DRC RESULTS DATABASE "DRC_RES.db"
#   DRC SUMMARY REPORT   "DRC.rep"
# (Wrapping with INCLUDE produces SPC1 "superfluous specification
# statement" because the deck already declares LAYOUT SYSTEM etc.)
# We sed-copy the deck with the placeholders pointed at our work dir
# and ASCII keyword added to the results database so coords are
# human-readable.
deck_run="$CALIBRE_WORK/${MODULE}_drc.runset"
# Override deck PRECISION (default 1000 = 1nm/DBU) to 10000
# (0.1nm/DBU) so it matches the FC-exported GDS database precision.
# Rule values in the deck are in µm (user units) so they are
# unaffected by the precision change; only the DBU granularity used
# for coordinate snapping changes.
sed -e "s|\"GDSFILENAME\"|\"$gds_in\"|"                                      \
    -e "s|\"TOPCELLNAME\"|\"$MODULE\"|"                                      \
    -e "s|\"DRC_RES.db\"|\"$CALIBRE_WORK/${MODULE}.drc.db\" ASCII|"          \
    -e "s|\"DRC.rep\"|\"$CALIBRE_WORK/${MODULE}.drc.summary\" REPLACE HIER|" \
    -e "s|^PRECISION\s\+[0-9]\+|PRECISION    10000|"                         \
    "$TSMC65_DRC_DECK" > "$deck_run"

# NOTE: this signoff DRC needs the foundry tcbn65lp stdcell .gds merged
# into the partition GDS. The _FE_ pack on this host ships LEF/.db/.v
# only — see syn/asic/common.mk GDS_STDCELL block for the auto-detect
# wiring. With GDS_STDCELL empty, Calibre aborts on "Cell <name>
# referenced but not defined" before running spacing checks. To enable:
#   1. Drop the matching tcbn65lp_220a_BE pack into place (sibling of
#      tcbn65lp_220a_FE), or override TCBN65LP_BE in common.mk.
#   2. Rerun "make -C syn/asic/fusion-compiler fc_all" to restream the
#      partition GDS with stdcell content.
#   3. Rerun this script — the drc.db is now populated, and the result
#      summary surfaces Short coordinates ready for path_d_eco.tcl's
#      Phase A0 (set CALIBRE_DRC_REPORT to the drc.results dump).
# Three SVRF "tolerate missing cells" variants (LAYOUT IGNORE UNDEFINED
# REFERENCE, LAYOUT WARN MISSING CELL, LAYOUT REFERENCE CELL "*"
# ABSENT_OK YES) were rejected with INP1/INP7 — keep the comment for
# future explorers, but the supported path is "source the BE pack".

echo "INFO: runset (placeholders substituted): $deck_run"
echo "INFO: deck   : $TSMC65_DRC_DECK"
echo "INFO: layout : $gds_in (primary cell: $MODULE)"
echo "INFO: launching calibre nmDRC ..."

# nmDRC = native multi-threaded DRC. -hier = hierarchical, -64 = 64-bit
# binary, -turbo enables multi-CPU. Logs go to ${MODULE}.drc.log.
"$CALIBRE_BIN" -drc -hier -64 -turbo "$deck_run" \
    2>&1 | tee "$CALIBRE_WORK/${MODULE}.drc.log"

# Quick verdict summary
echo
echo "==================================================================="
echo " Calibre DRC summary (head)"
echo "==================================================================="
head -60 "$CALIBRE_WORK/${MODULE}.drc.summary" 2>/dev/null || \
    echo "(no summary written — check ${MODULE}.drc.log for errors)"

# Count violations by rule (sort -k count)
if [[ -s "$CALIBRE_WORK/${MODULE}.drc.summary" ]]; then
    echo
    echo "Per-rule violation counts (top 20):"
    awk '/^RULECHECK / { n=$NF; rule=$2; if (n>0) print n, rule }' \
        "$CALIBRE_WORK/${MODULE}.drc.summary" \
        | sort -rn | head -20
fi

echo "DONE: $CALIBRE_WORK/${MODULE}.drc.summary"
