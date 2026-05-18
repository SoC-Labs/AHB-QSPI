#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - cocotb-silicon board entrypoint
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Thin board-side entrypoint that binds QspiAdapter to the cocotb-silicon
# engine. Exists so the existing FPGA harness contract works UNCHANGED:
#
#     cd <overlay dir> && python3 -u -m run_cocotb_silicon --budget <secs>
#
# (that is exactly what fpga/harness/scripts/run_stress.sh issues). The
# `--adapter` flag of `python3 -m cocotb_silicon.run` is hardcoded here so
# no harness change is needed. Run via `make -C fpga cocotb_hw`.
#
# Import resolution order for the cocotb_silicon package:
#   1. already importable (pip-installed, or on PYTHONPATH)
#   2. $COCOTB_SILICON_DIR/src   (set by set_env.sh; sibling repo)
#   3. ./cocotb_silicon          (staged flat next to this file by the
#                                 cocotb_hw deploy - the board case)
#-----------------------------------------------------------------------------

import argparse
import json
import os
import sys


def _ensure_cocotb_silicon():
    try:
        import cocotb_silicon  # noqa: F401
        return
    except ImportError:
        pass
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = []
    env_dir = os.environ.get("COCOTB_SILICON_DIR")
    if env_dir:
        candidates.append(os.path.join(env_dir, "src"))
    candidates.append(here)                       # ./cocotb_silicon (staged)
    for c in candidates:
        if os.path.isdir(os.path.join(c, "cocotb_silicon")):
            sys.path.insert(0, c)
            return
    raise SystemExit(
        "cannot import cocotb_silicon. Either `pip install -e "
        "<cocotb-silicon>`, set COCOTB_SILICON_DIR, or deploy via "
        "`make -C fpga cocotb_hw` (which stages the package on the board).")


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="python3 -m run_cocotb_silicon",
        description="Run the ahb_qspi cocotb suite on hardware via "
                    "cocotb-silicon (QspiAdapter).")
    # --budget is what the shared harness passes; honoured as an overall
    # wall-clock guard by the engine.
    ap.add_argument("--budget", type=float, default=None,
                    help="overall wall-clock budget seconds (harness contract)")
    ap.add_argument("tests", nargs="*", help="specific test names (default: all)")
    ap.add_argument("-k", "--pattern", default=None,
                    help="substring filter on test name")
    ap.add_argument("--bitfile", default=None,
                    help="path to .bit (default: ./qspi.bit if present)")
    ap.add_argument("--firmware", default=None,
                    help="basename in /lib/firmware for the bare backend "
                         "(default: None - deploy already loaded the PL)")
    ap.add_argument("--results", default="qspi_cocotb_results.json",
                    help="result JSON path (scp'd back by the harness)")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    _ensure_cocotb_silicon()
    from cocotb_silicon import run
    from cocotb_silicon_adapter import QspiAdapter

    bitfile = args.bitfile
    if bitfile is None and os.path.exists("qspi.bit"):
        bitfile = "qspi.bit"                       # deploy puts it in cwd

    rc, summary = run(QspiAdapter(),
                      bitfile=bitfile, firmware=args.firmware,
                      tests=args.tests or None, pattern=args.pattern,
                      budget=args.budget, verbose=args.verbose)

    try:
        with open(args.results, "w") as f:
            json.dump(summary, f, indent=2)
    except OSError as e:
        print(f"warning: could not write {args.results}: {e}", file=sys.stderr)
    return rc


if __name__ == "__main__":
    sys.exit(main())
