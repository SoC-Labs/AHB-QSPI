#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - PYNQ Test Runner
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Runs the cocotb test suite from verif/cocotb/ahb_qspi_tests.py against a
# real PYNQ-Z2 board with a PmodSF3 flash on PMODA.
#
# Setup:
#   1. Bitstream + .hwh (qspi.bit, qspi.hwh) sit alongside the python files
#   2. cocotb_stubs is installed before any cocotb-based file is imported
#   3. SST26VF064B helpers from verif/cocotb/ are made importable on path
#   4. The TB class in ahb_qspi_tests is monkey-patched to HwTB
#   5. SST26VF064B.poll_busy_clear / poll_busy_set / wait_for_irq are
#      replaced with the hardware-friendly versions from qspi_ahb_shim
#
# Usage:
#   sudo python3 run_tests.py                     # run all tests
#   sudo python3 run_tests.py APB_reg_tests       # run a single test
#   sudo python3 run_tests.py -k QSPI             # run tests matching 'QSPI'
#-----------------------------------------------------------------------------

import argparse
import asyncio
import logging
import os
import sys
import traceback


HERE = os.path.dirname(os.path.abspath(__file__))
PYNQ_ROOT = os.path.dirname(HERE)
REPO_ROOT = os.path.dirname(PYNQ_ROOT)
COCOTB_TEST_DIR = os.path.join(REPO_ROOT, 'verif', 'cocotb')


def _setup_paths():
    """Make the pynq overlay package + cocotb test helpers importable."""
    for p in (PYNQ_ROOT, COCOTB_TEST_DIR):
        if p not in sys.path:
            sys.path.insert(0, p)


def _patch_test_module():
    """Monkey-patch the cocotb test module so it runs against real hardware.

    Called after `import ahb_qspi_tests`. Replaces:
      - ahb_qspi_tests.TB                  -> qspi_ahb_shim.HwTB-bound factory
      - SST26VF064B.poll_busy_clear/_set   -> qspi_ahb_shim equivalents
      - SST26VF064B.wait_for_irq           -> qspi_ahb_shim equivalent
    """
    import qspi_ahb_shim
    import ahb_qspi_tests
    import SST26VF064B

    # The cocotb tests do `tb = TB(dut)`. We don't have a `dut` on hardware,
    # but ahb_qspi_tests references `dut` via the function arg. We replace
    # TB with a callable that ignores its arg and constructs HwTB.
    overlay_holder = {}

    def _tb_factory(_dut_arg):
        ov = overlay_holder['ov']
        return qspi_ahb_shim.HwTB(ov)

    ahb_qspi_tests.TB = _tb_factory

    # Replace the SST26VF064B sim helpers with their hardware counterparts.
    SST26VF064B.poll_busy_clear = qspi_ahb_shim.poll_busy_clear
    SST26VF064B.poll_busy_set   = qspi_ahb_shim.poll_busy_set
    SST26VF064B.wait_for_irq    = qspi_ahb_shim.wait_for_irq

    # ahb_qspi_tests does `from SST26VF064B import poll_busy_clear, ...`
    # at module load time, so the names are already bound in that namespace.
    # Rebind them too.
    ahb_qspi_tests.poll_busy_clear = qspi_ahb_shim.poll_busy_clear
    if hasattr(ahb_qspi_tests, 'wait_for_irq'):
        ahb_qspi_tests.wait_for_irq = qspi_ahb_shim.wait_for_irq

    return overlay_holder


def _make_dut_proxy(overlay):
    """Build a fake `dut` object for tests that touch dut signals directly.

    A handful of tests in ahb_qspi_tests do things like
    `dut.HRESETn.setimmediatevalue(0)` or check `dut.IRQ_QSPI_FINISHED.value`.
    These become harmless with the dummy signal class from qspi_ahb_shim.
    """
    from qspi_ahb_shim import HwDut
    d = HwDut()
    d._overlay = overlay
    return d


def main():
    ap = argparse.ArgumentParser(description="Run cocotb QSPI tests on PYNQ-Z2")
    ap.add_argument('test', nargs='*',
                    help='Specific test names to run (default: all)')
    ap.add_argument('-k', '--pattern', default=None,
                    help='Substring filter on test name')
    ap.add_argument('--bitfile', default=None,
                    help='Path to .bit (default: <pynq dir>/qspi.bit)')
    ap.add_argument('-v', '--verbose', action='store_true')
    args = ap.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format='%(asctime)s %(name)s %(levelname)s %(message)s',
    )
    log = logging.getLogger('runner')

    _setup_paths()

    # 1) Install cocotb stubs BEFORE importing any cocotb-based file
    import cocotb_stubs
    cocotb_stubs.install()

    # 2) Load overlay
    log.info("Loading PYNQ overlay...")
    from qspi_overlay import QspiOverlay
    overlay = QspiOverlay(args.bitfile) if args.bitfile else QspiOverlay()

    # 3) Import the cocotb test module - this registers all @cocotb.test
    #    functions with cocotb_stubs._REGISTERED_TESTS
    log.info("Importing test module...")
    import ahb_qspi_tests   # noqa: F401  - import has side effects (registration)

    # 4) Monkey-patch the test module so TB and poll helpers use HwTB
    overlay_holder = _patch_test_module()
    overlay_holder['ov'] = overlay

    # 5) Sanity check: read PIDR/CIDR via APB before running anything
    pidr0 = overlay.apb.read(0xFE0)
    cidr0 = overlay.apb.read(0xFF0)
    log.info("Sanity: PIDR0=0x%02x (expect 0x59), CIDR0=0x%02x (expect 0x50 'P')",
             pidr0 & 0xFF, cidr0 & 0xFF)
    if (pidr0 & 0xFF) != 0x59 or (cidr0 & 0xFF) != 0x50:
        log.error("ID readback wrong - AXI-APB path is broken. Aborting.")
        return 2

    # 6) Run tests
    tests = cocotb_stubs.get_registered_tests()
    if args.test:
        tests = [t for t in tests if t.__name__ in args.test]
    if args.pattern:
        tests = [t for t in tests if args.pattern in t.__name__]
    if not tests:
        log.error("No tests matched")
        return 1

    log.info("Running %d test(s)", len(tests))
    dut = _make_dut_proxy(overlay)

    passed = []
    failed = []
    for fn in tests:
        log.info("---- %s ----", fn.__name__)
        try:
            asyncio.run(fn(dut))
            log.info("PASS %s", fn.__name__)
            passed.append(fn.__name__)
        except Exception as exc:                 # noqa: BLE001
            log.error("FAIL %s: %s", fn.__name__, exc)
            log.debug(traceback.format_exc())
            failed.append((fn.__name__, str(exc)))
        # Soft-reset between tests to isolate state
        overlay.reset_controller()

    log.info("=" * 60)
    log.info("Summary: %d passed, %d failed", len(passed), len(failed))
    for name, why in failed:
        log.info("  FAIL %s -- %s", name, why)
    return 0 if not failed else 1


if __name__ == '__main__':
    sys.exit(main())
