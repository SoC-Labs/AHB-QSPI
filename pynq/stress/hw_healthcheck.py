#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - on-board health gate (fast go/no-go)
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Strict, exit-coded board+flash+overlay health check. Unlike
# pynq/flash_diag.py (a human-readable diagnostic dump that always exits
# 0), this returns NON-ZERO the moment the proven qspi_hw path fails, so
# CI can fail fast and cheap before spending the full stress budget
# discovering a dead board via phase failures.
#
# It is invoked by the shared harness exactly like the stress runner:
#     python3 -u -m stress.hw_healthcheck --budget <s>
# (run_stress.sh hardcodes that argv shape and gates on the exit code;
#  --budget is accepted for harness-contract compatibility and ignored.)
#
# Checks, in order, all via the canonical stress.qspi_hw Micron path:
#   1. AXI->APB alive   : PIDR0==0x59, CIDR0==0x50
#   2. flash responding : jedec_id() == 0x20ba19 (Micron N25Q256)
#                         (0xffffff / 0x000000 == dead/absent PmodSF3 —
#                          see docs/cocotb-silicon-findings.md)
#   3. write path alive : one 64K sector erase + page program + readback
#                         round-trip at a fixed scratch address
#
# On ANY failure it dumps flash_diag.diag_state(apb) for triage, then
# exits 1 (write/flash fault) or 2 (controller/AXI path fault).
#-----------------------------------------------------------------------------

import argparse
import os
import sys
import time
import traceback

# Make the parent pynq/ importable so `import flash_diag` and
# `from stress.qspi_hw import ...` resolve regardless of cwd (mirrors
# stress/runner.py's bootstrap).
_HERE   = os.path.dirname(os.path.abspath(__file__))
_PARENT = os.path.dirname(_HERE)
for _p in (_PARENT, _HERE):
    if _p not in sys.path:
        sys.path.insert(0, _p)

EXPECTED_JEDEC = 0x20BA19          # Micron N25Q256 (PmodSF3)
SCRATCH_ADDR   = 0x000000          # sector-0; erased+rewritten every run


def _p(*a):
    print(*a, flush=True)


def main():
    ap = argparse.ArgumentParser(description="QSPI board health gate")
    ap.add_argument("--budget", type=float, default=None)   # harness contract
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.parse_args()

    # Reuse flash_diag's proven bare-overlay open (fpga_manager already
    # loaded the bitstream during deploy).
    import flash_diag
    from stress.qspi_hw import QspiHw, QspiTimeout

    _p("hw_healthcheck: opening overlay (bare, fpga_manager already loaded)")
    overlay = flash_diag._open_overlay()
    apb     = overlay.apb

    # 1. AXI->APB path.
    pidr0 = apb.read(0xFE0) & 0xFF
    cidr0 = apb.read(0xFF0) & 0xFF
    _p(f"hw_healthcheck: PIDR0=0x{pidr0:02x} (expect 0x59)  "
       f"CIDR0=0x{cidr0:02x} (expect 0x50)")
    if pidr0 != 0x59 or cidr0 != 0x50:
        _p("hw_healthcheck: FAIL — AXI/APB path broken (ID readback wrong)")
        flash_diag.diag_state(apb)
        return 2

    hw = QspiHw(overlay, timeout_s=3.0)
    hw.reset_controller()
    hw.set_clk_div(5)

    # 2. Flash responding.
    try:
        jid = hw.jedec_id()
    except QspiTimeout as e:
        _p(f"hw_healthcheck: FAIL — jedec_id() timed out: {e}")
        flash_diag.diag_state(apb)
        return 1
    _p(f"hw_healthcheck: JEDEC ID = 0x{jid:06x} "
       f"(expect 0x{EXPECTED_JEDEC:06x})")
    if jid != EXPECTED_JEDEC:
        _p("hw_healthcheck: FAIL — flash not responding / wrong part "
           "(dead or absent PmodSF3; cf. docs/cocotb-silicon-findings.md)")
        flash_diag.diag_state(apb)
        return 1

    # 3. Write path: erase + program + read-back round-trip.
    try:
        pat = bytes((0xA0 + i) & 0xFF for i in range(16))
        t0  = time.monotonic()
        hw.sector_erase_64k(SCRATCH_ADDR, timeout=8.0)
        hw.page_program(SCRATCH_ADDR, pat)
        rb  = hw.read_buffer(SCRATCH_ADDR, len(pat))
        dt  = time.monotonic() - t0
    except QspiTimeout as e:
        _p(f"hw_healthcheck: FAIL — write path timed out: {e}")
        flash_diag.diag_state(apb)
        return 1
    if rb != pat:
        _p(f"hw_healthcheck: FAIL — read-back mismatch "
           f"(wrote {pat.hex()} read {rb.hex()})")
        flash_diag.diag_state(apb)
        return 1

    _p(f"hw_healthcheck: PASS — AXI/APB + flash + write path healthy "
       f"(erase+program+readback in {dt:.2f}s)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:                                       # noqa: BLE001
        _p("hw_healthcheck: FAIL — unhandled exception:")
        traceback.print_exc()
        sys.exit(1)
