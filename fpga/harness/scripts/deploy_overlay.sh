#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# deploy_overlay.sh — scp a bitstream + overlay onto a leased PYNQ board
# and hot-load it via /sys/class/fpga_manager.
#
# Designed to run *inside* with_lease.sh — relies on PYNQ_HOST and
# (optionally) PYNQ_PROXY being exported by the lease wrapper.
#
# Project-agnostic: takes paths and the firmware-filename as args so the
# same script ships with the harness across projects.
#
# Usage:
#     deploy_overlay.sh <bit> <bin> <hwh> <pynq_src_dir> <dest_dir> \
#                       <sudo_pw> [firmware_name]
#
#   <bit> <bin> <hwh>  artefacts to scp into <dest_dir>
#   <pynq_src_dir>     extra dir whose contents are scp -r'd into <dest_dir>
#                      (typically the project's pynq/ overlay + test source)
#   <dest_dir>         directory on the board (created if missing)
#   <sudo_pw>          password for `sudo -S` on the board
#   [firmware_name]    file under <dest_dir> to install into /lib/firmware/.
#                      Defaults to basename(<bin>). Must end in .bin and match
#                      what your overlay loader expects.
#-----------------------------------------------------------------------------
set -euo pipefail

if [ $# -lt 6 ] || [ $# -gt 7 ]; then
    echo "usage: deploy_overlay.sh <bit> <bin> <hwh> <pynq_src> <dest> <pwd> [firmware_name]" >&2
    exit 2
fi

BIT="$1"; BIN="$2"; HWH="$3"; PYNQ_SRC="$4"; DEST="$5"; PASSWORD="$6"
FIRMWARE_NAME="${7:-$(basename "$BIN")}"

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

echo "[deploy] target $PYNQ_HOST ${PYNQ_PROXY:+(via $PYNQ_PROXY)}"

ssh "${SSH_OPTS[@]}" "$PYNQ_HOST" "mkdir -p $DEST"

scp "${SSH_OPTS[@]}" "$BIT" "$PYNQ_HOST:$DEST/"
scp "${SSH_OPTS[@]}" "$BIN" "$PYNQ_HOST:$DEST/"
scp "${SSH_OPTS[@]}" "$HWH" "$PYNQ_HOST:$DEST/"
scp "${SSH_OPTS[@]}" -r "$PYNQ_SRC/"* "$PYNQ_HOST:$DEST/"

echo "[deploy] hot-loading $FIRMWARE_NAME via fpga_manager"
ssh "${SSH_OPTS[@]}" "$PYNQ_HOST" "
    echo '$PASSWORD' | sudo -S cp $DEST/$FIRMWARE_NAME /lib/firmware/ &&
    echo '$PASSWORD' | sudo -S bash -c 'echo $FIRMWARE_NAME > /sys/class/fpga_manager/fpga0/firmware' &&
    state=\$(cat /sys/class/fpga_manager/fpga0/state) &&
    echo \"fpga_manager state: \$state\"
"

echo "[deploy] done"
