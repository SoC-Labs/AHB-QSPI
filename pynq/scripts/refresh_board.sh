#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# PYNQ board discovery via serial console.
#
# Finds the PYNQ-Z2's FT2232 UART by its stable /dev/serial/by-id/ symlink
# on the USB host (mapstone-dev), wakes the serial console, logs in if
# needed, runs `ip -br addr` + `hostname`, parses the result, and writes
# pynq/board.json so downstream scripts/tests know how to reach the board
# after a power-cycle.
#
# Usage:
#   pynq/scripts/refresh_board.sh                # defaults (host, creds, serial)
#   PYNQ_LOGIN_USER=root pynq/scripts/refresh_board.sh
#-----------------------------------------------------------------------------

set -euo pipefail

SSH_HOST="${PYNQ_SSH_HOST:-mapstone-dev.ecs.soton.ac.uk}"
SERIAL_GLOB="${PYNQ_SERIAL_GLOB:-/dev/serial/by-id/usb-Xilinx_TUL*-if01-port0}"
LOGIN_USER="${PYNQ_LOGIN_USER:-xilinx}"
LOGIN_PASS="${PYNQ_LOGIN_PASS:-xilinx}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_FILE="${PYNQ_BOARD_JSON:-$REPO_ROOT/pynq/board.json}"

echo "[refresh_board] probing via $SSH_HOST ($SERIAL_GLOB)..." >&2

# Remote Python probe. Stdlib only (mapstone-dev has no pyserial). The
# script prints JSON on stdout; progress/debug go to stderr.
REMOTE_OUTPUT=$(
    ssh -o ConnectTimeout=10 "$SSH_HOST" \
        "SERIAL_GLOB='$SERIAL_GLOB' LOGIN_USER='$LOGIN_USER' LOGIN_PASS='$LOGIN_PASS' python3 -" \
        <<'PYEOF'
import glob, json, os, re, select, subprocess, sys, time

ANSI_RE = re.compile(r'\x1b\[[0-9;?]*[a-zA-Z]')

SERIAL_GLOB = os.environ['SERIAL_GLOB']
LOGIN_USER  = os.environ['LOGIN_USER']
LOGIN_PASS  = os.environ['LOGIN_PASS']

def log(*a):
    print(*a, file=sys.stderr, flush=True)

def find_device():
    matches = sorted(glob.glob(SERIAL_GLOB))
    if not matches:
        log("ERR: no serial device matched", SERIAL_GLOB)
        log("available:")
        for p in sorted(glob.glob("/dev/serial/by-id/*")):
            log("  ", p)
        sys.exit(2)
    return matches[0]

def diagnose_busy(dev):
    """Produce actionable hints when the port is held by someone else."""
    hints = []
    try:
        out = subprocess.check_output(
            ["ps", "-eo", "pid,user,cmd"], stderr=subprocess.DEVNULL
        ).decode(errors="replace")
    except Exception:
        out = ""
    for line in out.splitlines():
        low = line.lower()
        if "hw_server" in low:
            hints.append("Vivado hw_server is running (claims the whole FTDI):")
            hints.append("  " + line.strip())
            hints.append("  fix: `pkill -f hw_server` on the USB host and rerun.")
        if "modemmanager" in low:
            hints.append("ModemManager is running (often probes new USB-serial):")
            hints.append("  " + line.strip())
            hints.append("  long-term fix: udev rule setting ID_MM_DEVICE_IGNORE=1")
            hints.append("                 for idVendor==0403 on the USB host.")
    if not hints:
        hints.append("No obvious claimant found. Check with:")
        hints.append("  sudo lsof %s   (shows root-owned holders)" % dev)
    return hints

def configure_tty(dev):
    # Raw 115200-8N1; no echo/icrnl/ixon. Using stty keeps us stdlib-only.
    try:
        subprocess.check_call([
            "stty", "-F", dev,
            "115200", "cs8", "-cstopb", "-parenb",
            "-icanon", "-echo", "-echoe", "-echok", "-icrnl", "-ixon", "-opost",
            "min", "1", "time", "0",
        ])
    except subprocess.CalledProcessError:
        log("ERR: stty -F %s failed (device busy or permission denied)" % dev)
        for h in diagnose_busy(dev):
            log("    " + h)
        sys.exit(5)

def drain(fd, deadline):
    """Read whatever's available up to `deadline` (monotonic seconds)."""
    buf = b""
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        r, _, _ = select.select([fd], [], [], remaining)
        if not r:
            break
        try:
            chunk = os.read(fd, 4096)
        except BlockingIOError:
            break
        if not chunk:
            break
        buf += chunk
    return buf

def wait_for(fd, patterns, timeout):
    """Read until any of `patterns` (bytes) appears, or timeout."""
    deadline = time.monotonic() + timeout
    buf = b""
    while time.monotonic() < deadline:
        r, _, _ = select.select([fd], [], [], deadline - time.monotonic())
        if not r:
            break
        try:
            chunk = os.read(fd, 4096)
        except BlockingIOError:
            continue
        if not chunk:
            break
        buf += chunk
        for p in patterns:
            if p in buf:
                return buf, p
    return buf, None

def send(fd, data):
    os.write(fd, data)

def login_if_needed(fd):
    # Wake the console - might need a newline or two
    send(fd, b"\r\n")
    time.sleep(0.4)
    buf, hit = wait_for(fd, [b"login:"], 1.5)
    log("[probe] initial:", repr(buf[-160:]))
    if hit == b"login:":
        log("[probe] saw login prompt, sending user/pass")
        send(fd, LOGIN_USER.encode() + b"\r\n")
        wait_for(fd, [b"Password:", b"assword:"], 3.0)
        send(fd, LOGIN_PASS.encode() + b"\r\n")
        time.sleep(1.5)
        drain(fd, time.monotonic() + 1.0)

    # Sticky state from an earlier probe may have left PS1 empty and echo
    # off, so we can't rely on prompt characters. Instead, verify the shell
    # is alive by running a unique echo and waiting for its output — works
    # whether the prompt is visible or not.
    marker = "READY_%d" % int(time.monotonic() * 1000)
    send(fd, ("echo " + marker + "\n").encode())
    buf, hit = wait_for(fd, [marker.encode()], 3.0)
    if hit is None:
        log("ERR: shell not responsive (board off/booting/wedged?)")
        log("    last bytes:", repr(buf[-200:]))
        sys.exit(4)

    # Tidy the remote shell for clean sentinel parsing each run. Safe to
    # repeat: these are idempotent.
    send(fd, b"stty -echo; export PS1='' PS2=''\n")
    time.sleep(0.4)
    drain(fd, time.monotonic() + 0.4)

def run_cmd(fd, cmd, overall_timeout=3.0):
    # Remote echo is disabled in login_if_needed(), so the only time the
    # sentinel appears on the wire is from our `echo sentinel` at the end —
    # everything before it is the real command output.
    sentinel = "__DONE_%d__" % int(time.monotonic() * 1000)
    full = "{ %s ; } 2>&1; echo %s\n" % (cmd, sentinel)
    drain(fd, time.monotonic() + 0.1)
    send(fd, full.encode())
    buf, hit = wait_for(fd, [sentinel.encode()], overall_timeout)
    if hit is None:
        log("WARN: timeout waiting for sentinel on cmd:", cmd)
        log("      last bytes:", repr(buf[-200:]))
        return ""
    text = buf.decode(errors="replace")
    content = text.split(sentinel, 1)[0]
    # Strip ANSI escapes (bracketed-paste disable, cursor codes, etc.)
    content = ANSI_RE.sub('', content)
    return content.strip()

def parse_ip_br(output):
    # `ip -br addr` format: IFNAME STATE IP/MASK [IP/MASK ...]
    ifaces = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        name, state = parts[0], parts[1]
        ips = [p for p in parts[2:] if re.match(r"\d+\.\d+\.\d+\.\d+/\d+", p)]
        ifaces[name] = {"state": state, "ips": ips}
    return ifaces

def parse_mac(output, ifname):
    # `ip link show $IFNAME` has "link/ether <mac>"
    m = re.search(r"link/ether\s+([0-9a-f:]{17})", output)
    return m.group(1) if m else None

def main():
    dev = find_device()
    log("[probe] using device:", dev)
    configure_tty(dev)
    fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        login_if_needed(fd)
        hostname  = run_cmd(fd, "hostname")
        ipbr      = run_cmd(fd, "ip -br addr")
        log("[probe] ip -br addr:\n" + ipbr)
        ifaces    = parse_ip_br(ipbr)
        # Fetch MACs for any interface that reported IPs
        for name in list(ifaces):
            if not ifaces[name]["ips"]:
                continue
            linkout = run_cmd(fd, "ip link show %s" % name)
            ifaces[name]["mac"] = parse_mac(linkout, name)
    finally:
        os.close(fd)

    # Pick the "preferred SSH target": first UP non-loopback interface with an IP
    ssh_ip = None
    for name, info in ifaces.items():
        if name == "lo" or not info["ips"]:
            continue
        # Prefer non-USB-gadget for SSH (some setups don't route sshd there)
        if name.startswith(("eth", "en")) and not name.startswith("usb"):
            ssh_ip = info["ips"][0].split("/")[0]
            break
    if ssh_ip is None:
        for name, info in ifaces.items():
            if name == "lo" or not info["ips"]:
                continue
            ssh_ip = info["ips"][0].split("/")[0]
            break

    out = {
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "serial_device": dev,
        "hostname": hostname,
        "interfaces": ifaces,
        "ssh_target": ("%s@%s" % (LOGIN_USER, ssh_ip)) if ssh_ip else None,
        "ssh_ip": ssh_ip,
    }
    print(json.dumps(out, indent=2, sort_keys=True))

if __name__ == "__main__":
    main()
PYEOF
)

# The remote shell may print junk before our JSON (ssh-agent startup
# messages, MOTD, etc.). Extract the JSON block: first line starting with
# '{' through the matching closing '}' at start of line.
CLEAN_JSON=$(printf '%s\n' "$REMOTE_OUTPUT" | awk '
    /^{/  { inj=1 }
    inj   { print }
    /^}/  { if (inj) exit }
')

if ! printf '%s' "$CLEAN_JSON" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "[refresh_board] ERROR: remote probe did not return valid JSON" >&2
    echo "--- raw output ---" >&2
    printf '%s\n' "$REMOTE_OUTPUT" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"
printf '%s\n' "$CLEAN_JSON" > "$OUT_FILE"

echo "[refresh_board] wrote $OUT_FILE" >&2
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print("  hostname :", d.get("hostname"))
print("  ssh      :", d.get("ssh_target"))
for name, info in (d.get("interfaces") or {}).items():
    if info.get("ips"):
        print("  %-8s: %s  mac=%s  state=%s" % (
            name, ",".join(info["ips"]), info.get("mac"), info.get("state")))
' "$OUT_FILE"
