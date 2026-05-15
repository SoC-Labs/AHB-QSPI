#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# verify_partition_handoff.sh — chip-top side of the partition hand-off
# contract.
#
# 6_partition_export.tcl writes reports/06_abstract_manifest.txt with a
# SHA256 + size + role per delivered file, plus the source signoff block
# and the scenario coverage. An integrator who receives the outputs/
# drop runs THIS to prove the bytes match what FC wrote and to see, up
# front, whether the hold/min corner is actually covered.
#
# Usage:
#   verify_partition_handoff.sh [MANIFEST] [OUTPUTS_DIR]
#
#   MANIFEST     default: <fc>/reports/06_abstract_manifest.txt
#   OUTPUTS_DIR  default: <fc>/outputs   (dir the manifest's files live in)
#
#   <fc> is derived from this script's location
#   (syn/asic/scripts -> syn/asic/fusion-compiler) when args are omitted.
#
# Exit: 0 = every file present and SHA256 matches (coverage may still
#           WARN — see output);
#       1 = a file is missing or its SHA256 differs (hard fail);
#       2 = usage / manifest-not-found error.
#-----------------------------------------------------------------------------
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fc_dir="$(cd "${script_dir}/../fusion-compiler" 2>/dev/null && pwd || true)"

manifest="${1:-${fc_dir}/reports/06_abstract_manifest.txt}"
outputs_dir="${2:-${fc_dir}/outputs}"

if [[ ! -f "$manifest" ]]; then
    echo "ERROR: manifest not found: $manifest" >&2
    echo "       run 'make fc_abstract' first, or pass the manifest path." >&2
    exit 2
fi
if [[ ! -d "$outputs_dir" ]]; then
    echo "ERROR: outputs dir not found: $outputs_dir" >&2
    exit 2
fi

echo "================================================================="
echo " Partition hand-off verification"
echo "   manifest : $manifest"
echo "   outputs  : $outputs_dir"
echo "================================================================="

# Provenance / coverage lines — echo them so the integrator sees the
# source block and (critically) whether scen_fast/hold is covered.
grep -E '^[[:space:]]*(Source block|Generated|Scenarios|NOTE)[[:space:]]*:' \
    "$manifest" || true
echo "-----------------------------------------------------------------"

# A manifest data row is: "<size>  <64-hex-sha>  <file>  —  <role>"
# (size/sha/file are the first three whitespace-separated fields; "n/a"
# in the sha column means FC itself couldn't hash it at write time).
fail=0 ok=0 warn=0

while read -r size sha fname _rest; do
    [[ -z "${fname:-}" ]] && continue
    target="${outputs_dir}/${fname}"

    if [[ "$sha" == "n/a" ]]; then
        echo "WARN  : $fname — FC wrote no SHA (unverifiable, not blocking)"
        warn=$((warn + 1))
        continue
    fi
    if [[ ! -f "$target" ]]; then
        echo "FAIL  : $fname — listed in manifest but missing in outputs/"
        fail=$((fail + 1))
        continue
    fi

    actual="$(sha256sum "$target" | awk '{print $1}')"
    if [[ "$actual" != "$sha" ]]; then
        echo "FAIL  : $fname — SHA256 mismatch"
        echo "          manifest: $sha"
        echo "          on disk : $actual"
        fail=$((fail + 1))
        continue
    fi

    actual_size="$(stat -c %s "$target")"
    if [[ "$actual_size" != "$size" ]]; then
        # SHA already matched, so this is only an advisory inconsistency.
        echo "WARN  : $fname — size differs (manifest $size, disk $actual_size)"
        warn=$((warn + 1))
    fi
    echo "OK    : $fname"
    ok=$((ok + 1))
done < <(awk '$2 ~ /^[0-9a-f]{64}$/ || $2 == "n/a" {print $1, $2, $3, ""}' "$manifest")

# A drop with zero verifiable rows almost certainly means the manifest
# format drifted from this parser — treat as a hard error, not a pass.
if [[ $((ok + fail + warn)) -eq 0 ]]; then
    echo "ERROR: no parseable deliverable rows — manifest format mismatch?" >&2
    exit 2
fi

echo "-----------------------------------------------------------------"
echo "  OK=$ok  WARN=$warn  FAIL=$fail"
if grep -qE '^[[:space:]]*NOTE[[:space:]]*:[[:space:]]*no scen_fast' "$manifest"; then
    echo "  COVERAGE: hold/min corner NOT in this drop — chip-top must"
    echo "            close hold itself or request a scen_fast re-export."
fi
echo "================================================================="

if [[ $fail -gt 0 ]]; then
    echo "RESULT: FAIL — $fail file(s) missing or corrupted in transit"
    exit 1
fi
echo "RESULT: PASS — all deliverables verified against the manifest"
exit 0
