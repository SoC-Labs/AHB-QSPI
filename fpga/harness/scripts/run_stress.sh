#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# run_stress.sh — invoke a project's stress runner on a leased PYNQ board.
#
# Designed to run *inside* with_lease.sh: relies on PYNQ_HOST / PYNQ_PROXY
# being exported by the lease wrapper.
#
# Project-agnostic: the python module to run is passed as the 4th arg, so
# the same script ships with the harness across projects.
#
# Usage:
#     run_stress.sh <dest_dir> <budget_seconds> <sudo_pw> <python_module>
#
#   <python_module>  argument to `python3 -m`, e.g. 'stress.runner'
#                    or 'tests.stress'. The runner must accept
#                    `--budget <seconds>`.
#
# Optional env (opt-in; unset → behaves exactly as before):
#   FPGA_STRESS_RESULTS      space-separated basenames the runner writes
#                            into <dest_dir> on the board, e.g.
#                            'qspi_stress_summary.json qspi_stress_failures.jsonl'.
#                            scp'd back after the run.
#   FPGA_STRESS_RESULTS_DIR  local dir to place them in
#                            (default: ./fpga_stress_results).
# Results are pulled even when the run FAILS (a partial summary aids
# triage); a pull error only warns — the remote stress exit code stays
# the pass/fail gate.
#-----------------------------------------------------------------------------
set -euo pipefail

if [ $# -ne 4 ]; then
    echo "usage: run_stress.sh <dest_dir> <budget_s> <pwd> <python_module>" >&2
    exit 2
fi

DEST="$1"; BUDGET="$2"; PASSWORD="$3"; MODULE="$4"

: "${PYNQ_HOST:?PYNQ_HOST not set - run me under with_lease.sh}"
PYNQ_PROXY="${PYNQ_PROXY:-}"

SSH_OPTS=()
if [ -n "$PYNQ_PROXY" ]; then
    SSH_OPTS=(-o "ProxyJump=$PYNQ_PROXY")
fi
SSH_OPTS+=(
    -o "StrictHostKeyChecking=no"
    -o "UserKnownHostsFile=/dev/null"
    -o "ConnectTimeout=15"
    -o "ServerAliveInterval=15"
)

echo "[stress] running $MODULE on $PYNQ_HOST (budget=${BUDGET}s)"
set +e
ssh "${SSH_OPTS[@]}" "$PYNQ_HOST" "
    cd $DEST &&
    echo '$PASSWORD' | sudo -S python3 -u -m $MODULE --budget $BUDGET
"
rc=$?
set -e

# ── Best-effort: pull structured result files back off the board ─────────
# Pulled even on rc!=0 so a failed run still yields its partial summary
# for triage. scp reuses SSH_OPTS (incl. ProxyJump). A missing/failed
# pull only warns; the remote stress rc below is the real gate.
results="${FPGA_STRESS_RESULTS:-}"
if [ -n "$results" ]; then
    rdir="${FPGA_STRESS_RESULTS_DIR:-./fpga_stress_results}"
    mkdir -p "$rdir"
    for f in $results; do
        if scp "${SSH_OPTS[@]}" "$PYNQ_HOST:$DEST/$f" "$rdir/" 2>/dev/null; then
            echo "[stress] pulled $f -> $rdir/"
        else
            echo "[stress] WARNING: could not pull '$f' from $DEST (runner may not have written it)" >&2
        fi
    done
fi

if [ "$rc" -ne 0 ]; then
    echo "[stress] FAILED (remote exit $rc)" >&2
    exit "$rc"
fi
echo "[stress] done"
