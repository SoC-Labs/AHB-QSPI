#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - CI hardware-regression entrypoint
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# The phase set the nightly hardware-regression pipeline runs. It is the
# PS-STABLE subset of stress.runner's six phases: it deliberately EXCLUDES
# `xip_torture` and `concurrent`, which are documented to wedge the Zynq
# PS even on healthy silicon (docs/cocotb-silicon-findings.md, run 6b:
# "Aborted mid-run when XIP-heavy tests hung the PS"). Including them
# would hang the runner while holding a shared board lease and red-wall
# every nightly until that XIP/PS-stability issue is fixed — see the
# PROMOTION PATH note below.
#
# This is a thin shim, NOT a second stress implementation: it injects the
# curated `--tests` list into argv and delegates to stress.runner.main(),
# so there is exactly one stress engine, summary format and exit-code
# contract. The shared harness invokes it like the runner:
#     python3 -u -m stress.ci_regression --budget <s>
# (run_stress.sh hardcodes that argv shape; an explicit caller-supplied
#  --tests still wins, so this stays usable for ad-hoc subsets too.)
#
# PROMOTION PATH — once the XIP PS-wedge is fixed and a clean full run is
# achieved on the runner, add 'xip_torture' and 'concurrent' back to
# CI_PHASES (or just point the pipeline at stress.runner) so the nightly
# regresses the whole suite again.
#-----------------------------------------------------------------------------

import sys

try:
    from . import runner
except ImportError:                                         # python3 stress/ci_regression.py
    from stress import runner

# Keep in sync with docs/cocotb-silicon-findings.md "What is out of
# scope" §2 (XIP PS-wedge). Order matches stress.runner's phase order.
CI_PHASES = ["soak", "mode_flip", "clk_div_sweep", "irq_storm"]


def main():
    argv = sys.argv[1:]
    if "--tests" not in argv:
        argv = argv + ["--tests", *CI_PHASES]
    # stress.runner.main() re-parses sys.argv; rewrite it in place.
    sys.argv = [sys.argv[0], *argv]
    return runner.main()


if __name__ == "__main__":
    sys.exit(main())
