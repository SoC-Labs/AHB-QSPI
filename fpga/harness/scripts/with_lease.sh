#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# with_lease.sh — run a command under a fpgahub lease.
#
# Acquires a lease on the named board (or first free board matching a
# capability tag), exports the resolved SSH coordinates, runs the user
# command, and releases the lease on exit — even if the command crashes,
# is Ctrl-C'd, or the lease times out.
#
# Usage:
#     with_lease.sh --board <name>      --ttl 3600 -- <cmd> [args...]
#     with_lease.sh --capability <tag>  --ttl 3600 -- <cmd> [args...]
#
# Placeholders in <cmd> [args...] are substituted before exec, so recipes
# don't need an inner `bash -c` to defer shell expansion of FPGA_BOARD etc.
#     {board}      → resolved board name (FPGA_BOARD)
#     {ssh}        → board.host_ssh        (PYNQ_HOST)
#     {proxy}      → board.host_proxy      (PYNQ_PROXY, with FQDN fallback)
#     {dev_host}   → board.host_dev_host   (PYNQ_DEV_HOST)
# Substitutions are literal within an argv slot; mid-argument forms like
# 'user={board}' work and produce a single argument. Unknown placeholders
# are left untouched so existing strings that happen to contain `{…}` pass
# through unmangled.
#
# Re-entrancy: if FPGA_BOARD and FPGA_LEASE_TOKEN are already set in the
# environment (e.g. when a parent `fpga_use` shell, CI runner, or outer
# with_lease.sh has already taken the lease), the wrapper *does not*
# re-lease — it just exports the SSH coordinates derived from the
# existing board and runs the command. This lets composite flows (build
# → program → deploy → stress) all run inside a single lease.
#
# Env exported to the child command:
#     FPGA_BOARD          board name (resolved if --capability was used)
#     FPGA_LEASE_TOKEN    lease token (for explicit release / heartbeat)
#     PYNQ_HOST           board.host_ssh   (e.g. xilinx@pynq-z2-03-pl.fpga)
#     PYNQ_PROXY          board.host_proxy (jump host; may be empty)
#     PYNQ_DEV_HOST       board.host_dev_host (USB-attached server; may be empty)
#-----------------------------------------------------------------------------
set -euo pipefail

usage() {
    cat >&2 <<EOF
usage: with_lease.sh (--board <name> | --capability <tag>) [--ttl <secs>] -- <cmd> [args...]
EOF
    exit 2
}

BOARD=""
CAPABILITY=""
TTL=3600

while [ $# -gt 0 ]; do
    case "$1" in
        --board)       BOARD="$2";       shift 2 ;;
        --capability)  CAPABILITY="$2";  shift 2 ;;
        --ttl)         TTL="$2";         shift 2 ;;
        --)            shift; break ;;
        -h|--help)     usage ;;
        *)             echo "unknown arg: $1" >&2; usage ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "with_lease.sh: missing command after '--'" >&2
    usage
fi

if [ -z "$BOARD" ] && [ -z "$CAPABILITY" ]; then
    echo "with_lease.sh: pass --board <name> or --capability <tag>" >&2
    exit 2
fi

if ! command -v fpgahub >/dev/null 2>&1; then
    echo "with_lease.sh: fpgahub not on PATH" >&2
    exit 127
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "with_lease.sh: python3 not on PATH" >&2
    exit 127
fi

# Pull one JSON value via python3 (stdlib). Replaces jq for portability —
# the SoC-lab interactive shells don't always have jq on PATH.
_json_get() {
    # _json_get <json-string> <dotted.key.path>
    python3 - "$1" "$2" <<'PY'
import json, sys
doc = json.loads(sys.argv[1])
for key in sys.argv[2].split('.'):
    if doc is None:
        break
    doc = doc.get(key) if isinstance(doc, dict) else None
print('' if doc is None else doc)
PY
}

# If a hostname has no dots AND doesn't resolve locally AND an FQDN with
# FPGAHUB_DEFAULT_DOMAIN appended would resolve, return the FQDN form.
# Otherwise return the input unchanged. Lets fpgahub return short names
# (which work from inside the lab network) without breaking client hosts
# whose DNS only has the FQDN.
_maybe_fqdn() {
    local target="$1"
    local user="" host="$target"
    case "$target" in
        *@*) user="${target%@*}@"; host="${target#*@}" ;;
    esac
    case "$host" in
        *.*) echo "$target"; return ;;          # already qualified
    esac
    if getent hosts "$host" >/dev/null 2>&1; then
        echo "$target"; return                  # short name resolves
    fi
    local domain="${FPGAHUB_DEFAULT_DOMAIN:-ecs.soton.ac.uk}"
    if getent hosts "$host.$domain" >/dev/null 2>&1; then
        echo "${user}${host}.${domain}"
        return
    fi
    echo "$target"                              # give up; let SSH fail loudly
}

resolve_env_for() {
    # Populate PYNQ_HOST / PYNQ_PROXY / PYNQ_DEV_HOST from board status.
    # Board IPs typically live on a private per-board subnet on the
    # daemon host, so when host_proxy is empty we transparently fall
    # back to host_dev_host as the SSH jump host. Operators can still
    # override with PYNQ_PROXY= in the calling environment.
    local name="$1"
    local json
    json=$(fpgahub board status "$name" --json) || return 1
    PYNQ_HOST=$(_json_get "$json" host_ssh)
    PYNQ_PROXY=$(_json_get "$json" host_proxy)
    PYNQ_DEV_HOST=$(_json_get "$json" host_dev_host)
    if [ -z "$PYNQ_PROXY" ] && [ -n "$PYNQ_DEV_HOST" ]; then
        PYNQ_PROXY="$PYNQ_DEV_HOST"
    fi
    PYNQ_PROXY=$(_maybe_fqdn "$PYNQ_PROXY")
    PYNQ_DEV_HOST=$(_maybe_fqdn "$PYNQ_DEV_HOST")
    export PYNQ_HOST PYNQ_PROXY PYNQ_DEV_HOST
}

substitute_argv() {
    # Echoes the substituted argv, one element per line — caller must
    # re-read it with `mapfile -t` to preserve word boundaries.
    local a
    for a in "$@"; do
        a="${a//\{board\}/$FPGA_BOARD}"
        a="${a//\{ssh\}/$PYNQ_HOST}"
        a="${a//\{proxy\}/$PYNQ_PROXY}"
        a="${a//\{dev_host\}/$PYNQ_DEV_HOST}"
        printf '%s\n' "$a"
    done
}

# Re-entrancy: parent already holds a lease — just run the command.
if [ -n "${FPGA_BOARD:-}" ] && [ -n "${FPGA_LEASE_TOKEN:-}" ]; then
    if [ -n "$BOARD" ] && [ "$BOARD" != "$FPGA_BOARD" ]; then
        echo "with_lease.sh: parent shell holds lease on '$FPGA_BOARD' but you asked for '$BOARD'." >&2
        echo "with_lease.sh: release the parent lease first (fpga_release) or drop --board." >&2
        exit 1
    fi
    resolve_env_for "$FPGA_BOARD"
    echo "with_lease.sh: reusing existing lease on $FPGA_BOARD" >&2
    mapfile -t CHILD_ARGV < <(substitute_argv "$@")
    exec "${CHILD_ARGV[@]}"
fi

# `fpgahub lease acquire` here emits text:  `granted token=ABC expires=...`
# It has no JSON output flag in this CLI build, and no --capability flag,
# so capability tags are resolved client-side via `board list`.
list_capability_boards() {
    # COLUMNS=300 prevents Rich from truncating column widths, so we can
    # parse a clean ─┼─separated table out of `fpgahub board list`.
    COLUMNS=300 NO_COLOR=1 fpgahub board list --capability "$1" \
        | awk -F'│' '/^│/ && $2 !~ /Name/ { gsub(/^ +| +$/, "", $2); print $2 }'
}

try_lease() {
    # Try one acquire. Echoes the token to stdout on success, nothing
    # on failure. Caller already saw stderr.
    local name="$1" out
    out=$(fpgahub lease acquire "$name" --ttl "$TTL" 2>&1) || return 1
    # Expected: "granted token=ABC expires=YYYY-MM-DDThh:mm:ssZ"
    echo "$out" | sed -n 's/.*token=\([^ ]*\).*/\1/p'
}

if [ -n "$BOARD" ]; then
    CANDIDATES="$BOARD"
else
    CANDIDATES=$(list_capability_boards "$CAPABILITY")
    if [ -z "$CANDIDATES" ]; then
        echo "with_lease.sh: no board found matching capability '$CAPABILITY'" >&2
        exit 1
    fi
fi

FPGA_LEASE_TOKEN=""
FPGA_BOARD=""
for cand in $CANDIDATES; do
    tok=$(try_lease "$cand" 2>/dev/null) || continue
    if [ -n "$tok" ]; then
        FPGA_LEASE_TOKEN="$tok"
        FPGA_BOARD="$cand"
        break
    fi
done

if [ -z "$FPGA_LEASE_TOKEN" ]; then
    echo "with_lease.sh: failed to lease any of: $CANDIDATES" >&2
    # Re-run the first attempt loudly so the user sees the actual error.
    set -- $CANDIDATES
    fpgahub lease acquire "$1" --ttl "$TTL" >&2 || true
    exit 1
fi

if [ -z "$FPGA_BOARD" ] || [ "$FPGA_BOARD" = "null" ]; then
    echo "with_lease.sh: failed to parse lease response" >&2
    cat "$LEASE_JSON" >&2
    exit 1
fi

export FPGA_BOARD FPGA_LEASE_TOKEN
resolve_env_for "$FPGA_BOARD"

# Release on any exit path (success, error, signal). Clear traps inside
# the handler so a signal taken mid-release can't re-enter us.
release_lease() {
    local rc=$?
    trap - EXIT INT TERM HUP
    fpgahub lease release "$FPGA_BOARD" --token "$FPGA_LEASE_TOKEN" >/dev/null 2>&1 || true
    exit "$rc"
}
trap release_lease EXIT INT TERM HUP

echo "with_lease.sh: leased $FPGA_BOARD (ttl=${TTL}s) ssh=$PYNQ_HOST proxy=${PYNQ_PROXY:-none}" >&2

mapfile -t CHILD_ARGV < <(substitute_argv "$@")
"${CHILD_ARGV[@]}"
