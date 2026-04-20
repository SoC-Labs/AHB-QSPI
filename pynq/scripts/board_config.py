#-----------------------------------------------------------------------------
# pynq/board.json loader.
#
# board.json is written by pynq/scripts/refresh_board.sh after it probes
# the board over serial. Downstream scripts (stress runner, cocotb HW
# bridge, makefiles) use this helper to find the current SSH target
# without hardcoding an IP.
#
# Shell consumers can `jq -r .ssh_target pynq/board.json` directly; this
# file is for Python callers.
#-----------------------------------------------------------------------------

import json
import os
from pathlib import Path


def default_path():
    env = os.environ.get("PYNQ_BOARD_JSON")
    if env:
        return Path(env)
    # Walk up from this file to find pynq/board.json
    here = Path(__file__).resolve()
    return here.parent.parent / "board.json"


def load(path=None):
    p = Path(path) if path else default_path()
    if not p.exists():
        raise FileNotFoundError(
            "%s not found. Run pynq/scripts/refresh_board.sh first." % p
        )
    with p.open() as f:
        return json.load(f)


def ssh_target(path=None):
    return load(path).get("ssh_target")


def ssh_ip(path=None):
    return load(path).get("ssh_ip")


if __name__ == "__main__":
    import sys
    key = sys.argv[1] if len(sys.argv) > 1 else "ssh_target"
    print(load().get(key, ""))
