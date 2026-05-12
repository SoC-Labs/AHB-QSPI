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
ssh "${SSH_OPTS[@]}" "$PYNQ_HOST" "
    cd $DEST &&
    echo '$PASSWORD' | sudo -S python3 -u -m $MODULE --budget $BUDGET
"
echo "[stress] done"
