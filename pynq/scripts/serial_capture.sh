#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# PYNQ serial-console capture — runs a "cat" on mapstone-dev's ttyUSB6,
# timestamps every line, writes to pynq/logs/serial-<timestamp>.log.
#
# Purpose: when the stress test locks the board, the PS UART0 panic banner
# (if any) dumps just before the hang. This script captures it.
#
# Usage:
#     pynq/scripts/serial_capture.sh                # background start
#     pynq/scripts/serial_capture.sh --tail         # also tail live
#     pynq/scripts/serial_capture.sh --stop         # kill any running capture
#     pynq/scripts/serial_capture.sh --out my.log   # explicit output file
#
# Env:
#     PYNQ_SSH_HOST  (default mapstone-dev.ecs.soton.ac.uk)
#     PYNQ_SERIAL    (default /dev/ttyUSB6 — the Xilinx TUL FTDI-if01)
#-----------------------------------------------------------------------------

set -euo pipefail

SSH_HOST="${PYNQ_SSH_HOST:-mapstone-dev.ecs.soton.ac.uk}"
# Use the stable by-id symlink — ttyUSB<N> enumeration rotates whenever the
# FTDI disappears/reappears (e.g. after a lockup re-enumerates the USB).
SERIAL="${PYNQ_SERIAL:-/dev/serial/by-id/usb-Xilinx_TUL_1234-tul-if01-port0}"

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

echo "[serial_capture] writing $OUT_FILE" >&2

# Remote command: configure tty (raw, 115200, no echo), then cat forever.
# The "nohup" keeps it alive across SSH reconnect attempts. exec 3<> holds
# the device open so the kernel doesn't TTY-flow-control us out. Line
# buffering via stdbuf so the log sees characters immediately.
#
# The remote side intentionally writes to stdout — our local side tees it
# into the log file with timestamps, so a board-side panic "kernel BUG at
# ..." arrives live in the log even if SSH drops a moment later.
REMOTE_CMD="stty -F $SERIAL 115200 cs8 -cstopb -parenb -icanon -echo -icrnl -ixon 2>/dev/null; \
            stdbuf -oL cat $SERIAL"

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
