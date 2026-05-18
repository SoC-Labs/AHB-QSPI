export SOCLABS_AHB_QSPI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SOCLABS_SOCTOOLS_FLOW_DIR=$SOCLABS_AHB_QSPI_DIR/soctools_flow

# cocotb-silicon: standalone package that replays the verif/cocotb suite on
# hardware (see docs/cocotb-silicon-design.md). Default to a sibling
# checkout; override COCOTB_SILICON_DIR before sourcing if it lives
# elsewhere. Added to PYTHONPATH for host-side use (`make -C fpga cocotb_hw`
# stages it onto the board independently of this).
export COCOTB_SILICON_DIR="${COCOTB_SILICON_DIR:-$(cd "$SOCLABS_AHB_QSPI_DIR/../cocotb-silicon" 2>/dev/null && pwd)}"
if [ -n "$COCOTB_SILICON_DIR" ] && [ -d "$COCOTB_SILICON_DIR/src/cocotb_silicon" ]; then
    export PYTHONPATH="$COCOTB_SILICON_DIR/src${PYTHONPATH:+:$PYTHONPATH}"
fi

if [ ! -f $SOCLABS_AHB_QSPI_DIR/verif/VIP/SST26VF064B.v ]; then
    pushd $SOCLABS_AHB_QSPI_DIR
    make get_flash_model
    popd
fi

# -----------------------------------------------------------------------------
# fpga_use — grab an FPGA board via fpgahub and export the SSH targets.
#
#   fpga_use fpga1           # explicit board name, 1h lease
#   fpga_use pynq_z2 2h      # capability tag, 2h lease
#
# The lease is released automatically when the shell exits (EXIT trap).
# Requires `fpgahub` and `jq` on PATH; skips silently if fpgahub isn't
# installed so sourcing set_env.sh stays cheap in non-FPGA workflows.
# -----------------------------------------------------------------------------
fpga_use() {
    local tag_or_name=${1:-}
    local ttl=${2:-1h}
    if [ -z "$tag_or_name" ]; then
        echo "usage: fpga_use <board-name|capability> [ttl]" >&2
        return 2
    fi
    if ! command -v fpgahub >/dev/null 2>&1; then
        echo "fpga_use: fpgahub not found on PATH" >&2
        return 127
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "fpga_use: jq not found on PATH" >&2
        return 127
    fi

    local json
    if fpgahub board show "$tag_or_name" >/dev/null 2>&1; then
        json=$(fpgahub lease acquire "$tag_or_name" --ttl "$ttl" --json) || return $?
    else
        json=$(fpgahub lease acquire --capability "$tag_or_name" --ttl "$ttl" --json) || return $?
    fi

    local board token
    board=$(echo "$json" | jq -r '.board')
    token=$(echo "$json" | jq -r '.token')
    if [ -z "$board" ] || [ "$board" = "null" ]; then
        echo "fpga_use: could not parse board name from fpgahub output" >&2
        return 1
    fi

    export FPGA_BOARD="$board"
    export FPGA_LEASE_TOKEN="$token"
    export BOARD="$board"
    eval "$(fpgahub board status "$board" --json | jq -r '
        "export PYNQ_HOST=\(.host_ssh // "")\nexport PYNQ_PROXY=\(.host_proxy // "")"
    ')"

    # Release on shell exit so a Ctrl-D / logout drops the lease.
    trap "fpgahub lease release '$board' --token '$token' >/dev/null 2>&1" EXIT
    echo "fpga_use: acquired $board (ttl=$ttl) ssh=$PYNQ_HOST proxy=${PYNQ_PROXY:-none}"
}

fpga_release() {
    if [ -z "${FPGA_BOARD:-}" ] || [ -z "${FPGA_LEASE_TOKEN:-}" ]; then
        echo "fpga_release: no active lease in this shell" >&2
        return 1
    fi
    fpgahub lease release "$FPGA_BOARD" --token "$FPGA_LEASE_TOKEN"
    trap - EXIT
    unset FPGA_BOARD FPGA_LEASE_TOKEN BOARD PYNQ_HOST PYNQ_PROXY
}