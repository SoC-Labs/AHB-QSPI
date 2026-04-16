#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - Stress Test Runner
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Time-bounded stress test runner. Default budget: ~20 minutes total across
# six tests. Per-test failures are streamed to a JSON log so successful
# tests aren't lost when a later one wedges.
#
# Usage (on the PYNQ board, after `make deploy` has copied the overlay):
#   sudo python3 -m stress.runner                        # all tests, default budgets
#   sudo python3 -m stress.runner --tests soak xip_torture
#   sudo python3 -m stress.runner --budget 1800          # 30 min total, scaled
#   sudo python3 -m stress.runner --reset-rotator        # start sector 0 again
#   sudo python3 -m stress.runner --bitfile /path/qspi.bit
#-----------------------------------------------------------------------------

import argparse
import json
import logging
import os
import sys
import time
import traceback

# Make the parent pynq/ importable so `from qspi_overlay import ...` works
# regardless of cwd
_HERE   = os.path.dirname(os.path.abspath(__file__))
_PARENT = os.path.dirname(_HERE)
for p in (_PARENT, _HERE):
    if p not in sys.path:
        sys.path.insert(0, p)

# Allow running as both `python3 -m stress.runner` (preferred) and
# `python3 stress/runner.py` (works when stress/ is the cwd).
try:
    from .qspi_hw import QspiHw, QspiTimeout
    from .tests   import ALL_TESTS, DEFAULT_BUDGETS
    from .sector_state import SectorRotator
except ImportError:
    from stress.qspi_hw import QspiHw, QspiTimeout
    from stress.tests   import ALL_TESTS, DEFAULT_BUDGETS
    from stress.sector_state import SectorRotator


log = logging.getLogger('stress.runner')


class StressContext:
    """Shared per-test context: deadline, failure sink, summary dict."""

    def __init__(self, name, budget_s, fail_log_path=None):
        self.name      = name
        self.start     = time.monotonic()
        self.deadline  = self.start + budget_s
        self.budget_s  = budget_s
        self.summary   = {}
        self.failures  = []
        self.fail_log_path = fail_log_path

    @property
    def elapsed(self):
        return time.monotonic() - self.start

    def fail(self, test_name, msg, **fields):
        rec = dict(test=test_name, time=time.time(), elapsed=self.elapsed,
                   message=msg, **fields)
        self.failures.append(rec)
        log.error("[%s] %s | %s", test_name, msg,
                  ' '.join(f'{k}={v}' for k, v in fields.items()))
        if self.fail_log_path:
            try:
                with open(self.fail_log_path, 'a') as f:
                    f.write(json.dumps(rec) + '\n')
            except OSError as e:
                log.warning("could not append to fail log: %s", e)


def _setup_logging(verbose):
    fmt = '%(asctime)s %(name)s %(levelname)s %(message)s'
    logging.basicConfig(level=logging.DEBUG if verbose else logging.INFO,
                        format=fmt)


def _load_overlay(bitfile):
    """Try the standard pynq.Overlay path first; fall back to bare-metal
    /dev/mem + fpga_manager if the PYNQ Python stack is broken (missing
    pydantic/pynqutils on this image, etc)."""
    try:
        from qspi_overlay import QspiOverlay
        return QspiOverlay(bitfile) if bitfile else QspiOverlay()
    except (ImportError, ModuleNotFoundError) as e:
        log.warning("PYNQ stack unavailable (%s) - using bare-metal overlay", e)
        from bare_overlay import QspiOverlay
        # bare_overlay loads via /sys/class/fpga_manager - it expects the
        # bitstream to already be in /lib/firmware/qspi.bin
        return QspiOverlay()


def _sanity_check(hw):
    """Read PIDR0/CIDR0 to verify the AXI->APB path is alive before stressing."""
    pidr0 = hw.apb.read(0xFE0) & 0xFF
    cidr0 = hw.apb.read(0xFF0) & 0xFF
    log.info("Sanity: PIDR0=0x%02x (expect 0x59) CIDR0=0x%02x (expect 0x50)",
             pidr0, cidr0)
    if pidr0 != 0x59 or cidr0 != 0x50:
        raise RuntimeError("ID readback wrong - AXI/APB path broken")
    jid = hw.jedec_id()
    log.info("Flash JEDEC ID: 0x%06x", jid)
    return jid


def _scale_budgets(total_s, selected):
    """Distribute `total_s` across `selected` tests proportional to defaults."""
    raw   = {t: DEFAULT_BUDGETS[t] for t in selected}
    raw_total = sum(raw.values()) or 1
    return {t: max(15.0, total_s * v / raw_total) for t, v in raw.items()}


def main():
    ap = argparse.ArgumentParser(description="QSPI controller stress runner")
    ap.add_argument('--tests', nargs='+', default=list(DEFAULT_BUDGETS),
                    choices=list(DEFAULT_BUDGETS),
                    help='Subset of tests to run (default: all)')
    ap.add_argument('--budget', type=float, default=None,
                    help='Total budget in seconds (default: ~1170 = 19.5 min)')
    ap.add_argument('--bitfile', default=None,
                    help='Path to .bit (default: pynq/qspi.bit)')
    ap.add_argument('--fail-log', default='./qspi_stress_failures.jsonl',
                    help='Append-only JSON-lines failure log')
    ap.add_argument('--summary', default='./qspi_stress_summary.json',
                    help='Per-test summary JSON written at the end')
    ap.add_argument('--reset-rotator', action='store_true',
                    help='Reset persistent sector cursor to 0 before starting')
    ap.add_argument('--seed', type=int, default=None,
                    help='Override RNG seed (currently used by xip_torture)')
    ap.add_argument('-v', '--verbose', action='store_true')
    args = ap.parse_args()

    _setup_logging(args.verbose)

    if args.reset_rotator:
        SectorRotator().reset()
        log.info("Sector rotator reset to 0")

    overlay = _load_overlay(args.bitfile)
    hw      = QspiHw(overlay)
    log.info("Loaded overlay; running soft reset of controller")
    hw.reset_controller()

    try:
        _sanity_check(hw)
    except (QspiTimeout, RuntimeError) as e:
        log.error("Sanity check failed: %s", e)
        return 2

    budgets = _scale_budgets(args.budget if args.budget is not None
                             else sum(DEFAULT_BUDGETS[t] for t in args.tests),
                             args.tests)
    log.info("Per-test budgets: " +
             ', '.join(f"{t}={budgets[t]:.0f}s" for t in args.tests))
    log.info("Failure log: %s", args.fail_log)

    overall_summary  = {}
    total_failures   = 0
    overall_start    = time.monotonic()

    for name in args.tests:
        log.info("=" * 68)
        log.info("Running: %s  (budget %.0fs)", name, budgets[name])
        log.info("=" * 68)
        ctx = StressContext(name, budgets[name], fail_log_path=args.fail_log)
        # Reset the controller between tests so a stuck FSM in one doesn't
        # poison the next.
        try:
            hw.reset_controller()
        except QspiTimeout as e:
            log.error("inter-test reset failed: %s", e)
        try:
            ALL_TESTS[name](hw, ctx)
        except Exception as e:                      # noqa: BLE001
            log.error("[%s] runner caught unhandled %s: %s",
                      name, type(e).__name__, e)
            log.debug(traceback.format_exc())
            ctx.fail(name, f'unhandled {type(e).__name__}', exc=str(e))
        overall_summary[name] = dict(
            elapsed_s=round(ctx.elapsed, 2),
            budget_s=ctx.budget_s,
            failures=len(ctx.failures),
            stats=ctx.summary.get(name, {}),
        )
        total_failures += len(ctx.failures)

    overall_summary['_meta'] = dict(
        total_elapsed_s=round(time.monotonic() - overall_start, 2),
        total_failures=total_failures,
        tests_run=args.tests,
    )

    log.info("=" * 68)
    log.info("STRESS RUN COMPLETE: %d failure(s) across %d test(s) in %.1f min",
             total_failures, len(args.tests),
             (time.monotonic() - overall_start) / 60.0)
    log.info("=" * 68)

    try:
        with open(args.summary, 'w') as f:
            json.dump(overall_summary, f, indent=2)
        log.info("Summary written to %s", args.summary)
    except OSError as e:
        log.warning("could not write summary: %s", e)

    return 0 if total_failures == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
