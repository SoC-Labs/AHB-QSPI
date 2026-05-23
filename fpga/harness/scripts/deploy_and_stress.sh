#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# deploy_and_stress.sh — orchestrate deploy_overlay.sh + run_stress.sh
# under whichever fpgahub lease is already active. Exists so the
# Makefile `stress` recipe is one clean line instead of `bash -c
# 'deploy && stress'`.
#
# Usage:
#     deploy_and_stress.sh <bit> <bin> <hwh> <pynq_src> <dest> <pwd> \
#                          <budget_s> <python_module> [firmware_name]
#
# All args are forwarded straight through to deploy_overlay.sh and
# run_stress.sh; see those scripts for what each one means.
#-----------------------------------------------------------------------------
set -euo pipefail

if [ $# -lt 8 ] || [ $# -gt 9 ]; then
    echo "usage: deploy_and_stress.sh <bit> <bin> <hwh> <pynq_src> <dest> <pwd> <budget> <module> [firmware_name]" >&2
    exit 2
fi

BIT="$1"; BIN="$2"; HWH="$3"; PYNQ_SRC="$4"; DEST="$5"; PASSWORD="$6"
BUDGET="$7"; MODULE="$8"; FIRMWARE_NAME="${9:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/deploy_overlay.sh" \
    "$BIT" "$BIN" "$HWH" "$PYNQ_SRC" "$DEST" "$PASSWORD" "$FIRMWARE_NAME"
bash "$SCRIPT_DIR/run_stress.sh" \
    "$DEST" "$BUDGET" "$PASSWORD" "$MODULE"
