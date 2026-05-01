#!/bin/bash
#-----------------------------------------------------------------------------
# fpga_lock.sh — Acquire an exclusive lock on a specific FPGA board before
# running a command. Prevents two users / CI jobs / make targets from
# programming, flashing, or debugging the same board simultaneously.
#
# Usage:
#   fpga_lock.sh <board_id> <command> [args...]
#
# Examples:
#   fpga_lock.sh pynq-z2 openocd -f /tmp/swd_flash.cfg
#   fpga_lock.sh pynq-z2 vivado -mode batch -source program.tcl
#   fpga_lock.sh pynq-z2 bash -c 'scp bit host:~/ && ssh host load'
#
# The lock is held for the duration of <command>. If another process
# already holds the lock, this script blocks until it's released (with
# a configurable timeout). On timeout it exits non-zero without running
# <command>.
#
# Environment:
#   FPGA_LOCK_DIR     Directory for lock files (default: /tmp/fpga_locks)
#   FPGA_LOCK_TIMEOUT Seconds to wait for the lock (default: 300 = 5 min)
#   FPGA_LOCK_HOST    SSH host where the lock lives. If set, the lock is
#                     acquired remotely (for when the build machine is not
#                     the same as the FPGA host). Default: empty (local).
#
# How it works:
#   - Lock file: $FPGA_LOCK_DIR/<board_id>.lock
#   - Uses flock(1) for POSIX advisory locking — automatically released
#     when the fd closes (process exit, kill, SSH drop, etc.)
#   - The lock file also stores the holder's identity (user@host, PID,
#     timestamp) for diagnostics when someone else is waiting.
#
# Integrating into a Makefile:
#   fpga_flash: firmware
#       fpga/scripts/fpga_lock.sh $(TARGET) fpga/scripts/swd_flash.sh $(BIN)
#
#   deploy: bitstream
#       fpga/scripts/fpga_lock.sh $(TARGET) \
#           ssh $(PYNQ_HOST) 'sudo fpga_manager_load ...'
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
set -euo pipefail

BOARD_ID=${1:?"Usage: $0 <board_id> <command> [args...]"}
shift

if [[ $# -eq 0 ]]; then
    echo "ERROR: no command specified after board_id '$BOARD_ID'" >&2
    exit 1
fi

FPGA_LOCK_DIR=${FPGA_LOCK_DIR:-/tmp/fpga_locks}
FPGA_LOCK_TIMEOUT=${FPGA_LOCK_TIMEOUT:-300}

LOCKFILE="$FPGA_LOCK_DIR/$BOARD_ID.lock"

# Ensure lock directory exists
mkdir -p "$FPGA_LOCK_DIR"

# Resolve the project name from the nearest git remote or directory name
resolve_project () {
    local proj
    proj=$(git -C "${ETH_SS_HOME:-.}" remote get-url origin 2>/dev/null | sed 's|.*/||;s|\.git$||') || true
    [[ -z "$proj" ]] && proj=$(basename "${ETH_SS_HOME:-$(pwd)}")
    echo "$proj"
}

# Write holder info into the lockfile (advisory — doesn't affect locking).
# This is what a blocked user sees when they're waiting, so pack in
# everything that helps them decide whether to keep waiting or go ask
# the holder to hurry up.
write_holder_info () {
    {
        echo "═══════════════════════════════════════════════════════"
        echo " FPGA board '$BOARD_ID' is locked"
        echo "═══════════════════════════════════════════════════════"
        echo ""
        echo "  holder:   $(whoami)@$(hostname)"
        echo "  pid:      $$"
        echo "  started:  $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "  project:  $(resolve_project)"
        echo "  git ref:  $(git -C "${ETH_SS_HOME:-.}" describe --always --dirty 2>/dev/null || echo 'n/a')"
        echo "  branch:   $(git -C "${ETH_SS_HOME:-.}" branch --show-current 2>/dev/null || echo 'n/a')"
        echo "  cwd:      $(pwd)"
        echo "  command:  $*"
        echo ""
        echo "  To contact the holder:  finger $(whoami) 2>/dev/null || echo '(no finger)'"
        echo "  To forcibly release:    kill $$   (sends SIGTERM; lock auto-releases)"
        echo ""
        echo "═══════════════════════════════════════════════════════"
    } > "$LOCKFILE"
}

# Open fd 9 on the lockfile, then flock it.
exec 9>"$LOCKFILE"

echo "Acquiring lock on '$BOARD_ID' (timeout ${FPGA_LOCK_TIMEOUT}s)..."

if ! flock -w "$FPGA_LOCK_TIMEOUT" 9; then
    echo "" >&2
    echo "╔═══════════════════════════════════════════════════════╗" >&2
    echo "║  BLOCKED: '$BOARD_ID' is in use by another process   ║" >&2
    echo "╚═══════════════════════════════════════════════════════╝" >&2
    echo "" >&2
    cat "$LOCKFILE" >&2 || true
    echo "" >&2
    echo "Waited ${FPGA_LOCK_TIMEOUT}s. Giving up." >&2
    exit 1
fi

write_holder_info "$@"
echo "Lock acquired on '$BOARD_ID'. Running: $*"

# Run the command — lock is held until this process exits.
exec "$@"
