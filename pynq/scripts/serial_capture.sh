#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# PYNQ serial-console capture — SSHes into the host where the board's
# FTDI is attached (`host_dev_host` from `fpgahub board status`),
# timestamps every line, writes to pynq/logs/serial-<timestamp>.log.
#
# Purpose: when the stress test locks the board, the PS UART0 panic
# banner (if any) dumps just before the hang. This script captures it.
#
# Usage:
#     BOARD=pynq_z2_03_pl pynq/scripts/serial_capture.sh
#     BOARD=pynq_z2_03_pl pynq/scripts/serial_capture.sh --tail
#     pynq/scripts/serial_capture.sh --stop
#     pynq/scripts/serial_capture.sh --out my.log
#
# Inputs (env):
#     BOARD            fpgahub board name (required unless PYNQ_SSH_HOST set)
#     PYNQ_SSH_HOST    bypass fpgahub: explicit ssh target
#     PYNQ_SERIAL      tty path on the USB host
#                      (default /dev/serial/by-id/usb-Xilinx_TUL*-if01-port0)
#-----------------------------------------------------------------------------

set -euo pipefail

BOARD="${BOARD:-}"
SSH_HOST="${PYNQ_SSH_HOST:-}"
# Use the stable by-id symlink — ttyUSB<N> enumeration rotates whenever the
# FTDI disappears/reappears (e.g. after a lockup re-enumerates the USB).
SERIAL="${PYNQ_SERIAL:-/dev/serial/by-id/usb-Xilinx_TUL*-if01-port0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$REPO_ROOT/pynq/logs"
PID_FILE="$LOG_DIR/.serial_capture.pid"

TAIL=0
STOP=0
OUT_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --tail) TAIL=1 ; shift ;;
        --stop) STOP=1 ; shift ;;
        --out)  OUT_FILE="$2" ; shift 2 ;;
        *)      echo "unknown arg: $1" >&2 ; exit 2 ;;
    esac
done

if [ "$STOP" = "1" ]; then
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
        echo "stopped capture (pid $pid)"
    else
        echo "no capture running"
    fi
    exit 0
fi

# Resolve dev-host from fpgahub unless PYNQ_SSH_HOST is explicit.
if [ -z "$SSH_HOST" ]; then
    if [ -z "$BOARD" ]; then
        echo "[serial_capture] ERROR: set BOARD=<fpgahub-name> or PYNQ_SSH_HOST=<host>" >&2
        exit 2
    fi
    if ! command -v fpgahub >/dev/null 2>&1; then
        echo "[serial_capture] ERROR: fpgahub not on PATH" >&2
        exit 127
    fi
    SSH_HOST="$(fpgahub board status "$BOARD" --json \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("host_dev_host") or "")')"
    if [ -z "$SSH_HOST" ] || [ "$SSH_HOST" = "null" ]; then
        echo "[serial_capture] ERROR: board '$BOARD' has no host_dev_host" >&2
        exit 1
    fi
fi

if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        echo "capture already running (pid $old_pid). Use --stop first." >&2
        exit 1
    fi
    rm -f "$PID_FILE"
fi

mkdir -p "$LOG_DIR"
if [ -z "$OUT_FILE" ]; then
    OUT_FILE="$LOG_DIR/serial-$(date -u +%Y%m%dT%H%M%SZ).log"
fi

echo "[serial_capture] writing $OUT_FILE (via $SSH_HOST)" >&2

# Remote command: resolve glob → device, configure tty (raw, 115200, no
# echo), then cat forever. exec 3<> holds the device open so the kernel
# doesn't TTY-flow-control us out. Line buffering via stdbuf so the log
# sees characters immediately.
#
# The remote side intentionally writes to stdout — our local side tees it
# into the log file with timestamps, so a board-side panic "kernel BUG at
# ..." arrives live in the log even if SSH drops a moment later.
REMOTE_CMD="set -e; dev=\$(ls $SERIAL 2>/dev/null | head -1); \
            if [ -z \"\$dev\" ]; then echo 'no tty matched $SERIAL' >&2; exit 4; fi; \
            stty -F \$dev 115200 cs8 -cstopb -parenb -icanon -echo -icrnl -ixon 2>/dev/null; \
            exec stdbuf -oL cat \$dev"

# Prepend each line with a millisecond timestamp so we can correlate with
# the stress runner's own timestamps later.
TS_FILTER='while IFS= read -r line; do printf "%s %s\n" "$(date +%H:%M:%S.%3N)" "$line"; done'

if [ "$TAIL" = "1" ]; then
    ssh -o ConnectTimeout=5 "$SSH_HOST" "$REMOTE_CMD" 2>&1 \
        | bash -c "$TS_FILTER" \
        | tee "$OUT_FILE" &
    pid=$!
    echo "$pid" > "$PID_FILE"
    echo "[serial_capture] pid=$pid (tailing live; Ctrl-C to stop tee, capture keeps running)"
    wait $pid
else
    ssh -o ConnectTimeout=5 "$SSH_HOST" "$REMOTE_CMD" 2>&1 \
        | bash -c "$TS_FILTER" \
        > "$OUT_FILE" &
    pid=$!
    echo "$pid" > "$PID_FILE"
    echo "[serial_capture] pid=$pid (background)"
fi
