#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# Stress-test bisector — runs each of the six stress phases individually,
# captures serial + stdout, checks if the board survived, and emits a CSV
# of verdicts. First-failing phase tells us the scope of the bug.
#
# Usage:
#     pynq/scripts/stress_bisect.sh
#     pynq/scripts/stress_bisect.sh --phases concurrent,clk_div_sweep
#     pynq/scripts/stress_bisect.sh --budget 60
#     pynq/scripts/stress_bisect.sh --prompt-between   # pause for power-cycle
#
# Env:
#     PYNQ_HOST      default xilinx@192.168.2.99
#     PYNQ_PROXY     default mapstone-dev.ecs.soton.ac.uk
#     PYNQ_PASSWORD  default xilinx
#     PYNQ_DEST      default /home/xilinx/qspi_overlay
#-----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$REPO_ROOT/pynq/logs/bisect-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$LOG_DIR"

PYNQ_HOST="${PYNQ_HOST:-xilinx@192.168.2.99}"
PYNQ_PROXY="${PYNQ_PROXY:-mapstone-dev.ecs.soton.ac.uk}"
PYNQ_PASSWORD="${PYNQ_PASSWORD:-xilinx}"
PYNQ_DEST="${PYNQ_DEST:-/home/xilinx/qspi_overlay}"

BUDGET=60
PROMPT=0
# Order matters: we run the highest-risk phases first (based on manual
# inspection of which tests do the most aggressive things). User can
# override with --phases.
PHASES="concurrent clk_div_sweep irq_storm mode_flip soak xip_torture"

while [ $# -gt 0 ]; do
    case "$1" in
        --phases) PHASES="$(echo "$2" | tr ',' ' ')" ; shift 2 ;;
        --budget) BUDGET="$2" ; shift 2 ;;
        --prompt-between) PROMPT=1 ; shift ;;
        *) echo "unknown arg: $1" >&2 ; exit 2 ;;
    esac
done

SSH_BASE=(ssh -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o "ProxyJump=$PYNQ_PROXY" "$PYNQ_HOST")

REPORT="$LOG_DIR/report.csv"
echo "phase,verdict,elapsed_s,last_serial,last_stdout,notes" > "$REPORT"

probe_board() {
    # Returns 0 if SSH works, 1 otherwise.
    "${SSH_BASE[@]}" -o ConnectTimeout=5 true >/dev/null 2>&1
}

probe_serial() {
    # Returns 0 if serial console answers.
    "$SCRIPT_DIR/refresh_board.sh" >/dev/null 2>&1
}

classify_state() {
    if probe_board; then
        echo "alive"
    elif probe_serial; then
        echo "hung-net-only"
    else
        echo "hung-fully"
    fi
}

run_phase() {
    local phase="$1"
    local phase_log="$LOG_DIR/$phase.stdout"
    local serial_log="$LOG_DIR/$phase.serial"

    echo "=============================================="
    echo "[bisect] phase=$phase budget=${BUDGET}s"
    echo "=============================================="

    # 1. pre-flight
    if ! probe_board; then
        echo "[bisect] board unreachable before phase '$phase' — skipping remaining phases"
        echo "$phase,SKIPPED_BOARD_DEAD,0,,,pre-flight SSH failed" >> "$REPORT"
        return 1
    fi

    # 2. start serial capture in background
    PYNQ_BOARD_JSON=/dev/null \
        "$SCRIPT_DIR/serial_capture.sh" --stop >/dev/null 2>&1 || true
    "$SCRIPT_DIR/serial_capture.sh" --out "$serial_log" >/dev/null

    # 3. run stress phase with timeout protection (budget + 30s buffer)
    local total_budget=$((BUDGET + 30))
    local start_s=$(date +%s)
    set +e
    timeout "${total_budget}s" "${SSH_BASE[@]}" \
        "cd $PYNQ_DEST && echo '$PYNQ_PASSWORD' | sudo -S python3 -u -m stress.runner \
            --tests $phase --budget $BUDGET 2>&1" \
        > "$phase_log" 2>&1
    local rc=$?
    set -e
    local elapsed=$(($(date +%s) - start_s))

    # 4. stop serial capture
    "$SCRIPT_DIR/serial_capture.sh" --stop >/dev/null 2>&1 || true
    # Give the remote ssh a moment to flush the TTY buffer
    sleep 2

    # 5. classify outcome
    local state=$(classify_state)
    local last_serial=""
    local last_stdout=""
    [ -s "$serial_log" ] && last_serial=$(tail -1 "$serial_log" | tr -d ',' | head -c 120)
    [ -s "$phase_log"  ] && last_stdout=$(tail -1 "$phase_log"  | tr -d ',' | head -c 120)

    local verdict
    local notes=""
    case "$rc" in
        0)
            if [ "$state" = "alive" ]; then
                verdict="PASS"
            else
                verdict="PASS_BUT_WEDGED"
                notes="stress returned 0 but post-check classifies $state"
            fi
            ;;
        124)
            verdict="HUNG_$(echo "$state" | tr '[:lower:]' '[:upper:]')"
            notes="ssh hit ${total_budget}s timeout"
            ;;
        *)
            verdict="ERROR_$(echo "$state" | tr '[:lower:]' '[:upper:]')"
            notes="stress exit=$rc"
            ;;
    esac

    printf "%s,%s,%s,%s,%s,%s\n" \
        "$phase" "$verdict" "$elapsed" \
        "\"$last_serial\"" "\"$last_stdout\"" "\"$notes\"" >> "$REPORT"

    echo "[bisect] $phase => $verdict ($elapsed s)"
    [ -n "$last_stdout" ] && echo "    last stdout: $last_stdout"
    [ -n "$last_serial" ] && echo "    last serial: $last_serial"

    # 6. hand off to user / recovery if needed
    if [ "$state" != "alive" ]; then
        echo "[bisect] board is '$state' after phase '$phase'"
        if [ "$PROMPT" = "1" ]; then
            read -rp "Power-cycle the PYNQ, then press ENTER to continue (or Ctrl-C to abort): "
            # Wait for board to come back up
            for i in $(seq 1 60); do
                if probe_board; then break; fi
                sleep 5
            done
        else
            echo "[bisect] --prompt-between not set; aborting run"
            return 1
        fi
    fi

    return 0
}

for phase in $PHASES; do
    run_phase "$phase" || break
done

echo ""
echo "=============================================="
echo "[bisect] report: $REPORT"
column -s, -t "$REPORT" 2>/dev/null || cat "$REPORT"
