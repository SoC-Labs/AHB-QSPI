#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - on-board flash write-path diagnostic
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# One-shot ground-truth probe for the cocotb-silicon parity investigation.
# The cocotb suite's ~27 "Page program / Sector erase did not complete
# (flash busy)" failures persisted even after the 4-byte-RDSR status
# override. This compares, on the SAME board in ONE run:
#
#   A. the PROVEN pynq/stress/qspi_hw.py Micron path (known-good on this
#      board per the stress suite) - reference: does WREN/erase/program/
#      read-back actually work here right now?
#   B. the raw register sequence the cocotb SST helper uses - dumping the
#      actual RDATA0..3 for a 1-byte vs 4-byte RDSR, WEL-after-WREN, and
#      live CLK_DIV / CTRL at poll time.
#
# Decisive for "small fix vs genuinely deep": if (A) works and (B)'s
# RDSR RDATA0 is e.g. 0xFFFFFFFF / 0x00000000 / wrong-laned, or CLK_DIV
# is 0/1, or CTRL is left in QPI/continuous-read, the divergence is
# pinpointed without further speculation.
#
# Deployed + run by `make -C fpga flash_diag` (same staging/lease path
# as cocotb_hw). Accepts --budget for harness-contract compatibility
# (ignored). All output is plain prints (ssh-streamed into the run log).
#-----------------------------------------------------------------------------

import argparse
import sys
import time
import traceback


def _p(*a):
    print(*a, flush=True)


def _open_overlay():
    # Deploy already fpga_manager-loaded qspi.bin; just map MMIO.
    from bare_overlay import QspiOverlay
    return QspiOverlay(skip_load=True)


def _wait_ctrl_idle(apb, tag, limit=200000):
    """Spin on STATUS[0] (controller BUSY). Bounded; reports if stuck."""
    for i in range(limit):
        if not (apb.read(0x04) & 1):
            return True
        if i and i % 50000 == 0:
            _p(f"   [{tag}] still BUSY after {i} polls")
    _p(f"   [{tag}] CONTROLLER BUSY DID NOT CLEAR ({limit} polls)")
    return False


def _raw_cmd(apb, base, tag):
    """Issue a two-write SPI_CMD (base, then base|ENABLE), wait controller
    idle, clear IRQ, dump RDATA0..3."""
    apb.write(0x08, base)
    apb.write(0x08, base | (1 << 8))
    _wait_ctrl_idle(apb, tag)
    apb.write(0x04, 0x100)                       # IRQ_CLR
    w = [apb.read(0x10), apb.read(0x14), apb.read(0x18), apb.read(0x1C)]
    _p(f"   [{tag}] base=0x{base:08x} RDATA0..3 = "
       f"{w[0]:08x} {w[1]:08x} {w[2]:08x} {w[3]:08x}")
    return w


def diag_resurrect(overlay):
    """Aggressively try to get ANY response from a non-responsive flash.

    Soft reset (0x66/0x99) does NOT wake a flash in Deep Power-Down -
    only 0xAB (Release from DPD) does. Also sweep CLK_DIV (a marginal
    Pmod/power/SI fault may only answer slowly) and try alternative ID /
    SFDP / status opcodes. If every read is 0x00000000 / 0xffffffff
    across all of these, the part is genuinely dead/absent."""
    section("RESURRECT: deep-power-down release + CLK_DIV & opcode sweep")
    apb = overlay.apb

    def two(base):                                  # command-only strobe
        apb.write(0x08, base)
        apb.write(0x08, base | (1 << 8))
        _wait_ctrl_idle(apb, "rx")
        apb.write(0x04, 0x100)

    apb.write(0x00, 0x0)                             # SPI framing, no XIP
    apb.write(0x34, 0x5)                             # safe CLK_DIV
    apb.write(0x0C, 0x0)

    _p("-- Release from Deep Power-Down (0xAB) x3, ~1ms settle each --")
    for _ in range(3):
        two(0xAB)
        time.sleep(0.001)
    _raw_cmd(apb, 0xAB | (1 << 9) | (1 << 11), "RES-0xAB (device id)")

    _p("\n-- RDID 0x9F across a CLK_DIV sweep (slow may rescue marginal) --")
    for cd in (1, 2, 3, 5, 8, 16, 31):
        apb.write(0x34, cd)
        _raw_cmd(apb, 0x9F | (1 << 9) | (2 << 16), f"RDID CLK_DIV={cd:>2}")
    apb.write(0x34, 0x5)

    _p("\n-- alternative ID / SFDP / status opcodes --")
    apb.write(0x0C, 0x0)
    _raw_cmd(apb, 0x9E | (1 << 9) | (2 << 16), "RDID-0x9E")
    apb.write(0x0C, 0x0)
    _raw_cmd(apb, 0x90 | (1 << 9) | (1 << 11) | (1 << 16), "REMS-0x90")
    apb.write(0x0C, 0x0)
    _raw_cmd(apb, 0x5A | (1 << 9) | (1 << 11) | (8 << 12) | (3 << 16),
             "SFDP-0x5A (expect 'SFDP'=0x50444653)")
    _raw_cmd(apb, 0x70 | (1 << 9), "FLAG-STATUS-0x70 (Micron)")
    _raw_cmd(apb, 0x05 | (1 << 9) | (3 << 16), "RDSR-0x05 (4-byte)")
    _raw_cmd(apb, 0x35 | (1 << 9), "RDCR-0x35")
    _p("\n   VERDICT: any RDATA above that is NOT 0x00000000 / 0xffffffff "
       "= the flash answered something; all 00/ff on every opcode & speed "
       "= no electrical response (dead / absent / unpowered Pmod).")


def section(title):
    _p("\n" + "=" * 64)
    _p("== " + title)
    _p("=" * 64)


def diag_state(apb):
    section("STATE")
    pidr0 = apb.read(0xFE0) & 0xFF
    cidr0 = apb.read(0xFF0) & 0xFF
    _p(f"PIDR0=0x{pidr0:02x} (expect 0x59)  CIDR0=0x{cidr0:02x} (expect 0x50)")
    _p(f"CTRL(0x00)   = 0x{apb.read(0x00):08x}")
    _p(f"STATUS(0x04) = 0x{apb.read(0x04):08x}")
    _p(f"CLK_DIV(0x34)= 0x{apb.read(0x34):08x}")
    _p(f"AHB_SETUP(0x30)=0x{apb.read(0x30):08x}")


def diag_reference(overlay):
    """Path A: the proven qspi_hw Micron implementation."""
    section("A. PROVEN qspi_hw PATH (reference - should work on this board)")
    from stress.qspi_hw import QspiHw, QspiTimeout
    hw = QspiHw(overlay, timeout_s=3.0)
    hw.reset_controller()
    hw.set_clk_div(5)
    jid = hw.jedec_id()
    _p(f"qspi_hw.jedec_id() = 0x{jid:06x}  (Micron N25Q256 expect 0x20ba19)")
    sr = hw.read_status()
    _p(f"qspi_hw.read_status() = 0x{sr:02x}  (WIP=bit0={sr & 1}, WEL=bit1={(sr >> 1) & 1})")
    addr = 0x000000
    try:
        _p(f"sector_erase_64k(0x{addr:06x}) ...")
        t0 = time.monotonic()
        hw.sector_erase_64k(addr, timeout=8.0)
        _p(f"  erase OK in {time.monotonic() - t0:.2f}s, SR=0x{hw.read_status():02x}")
        pat = bytes((0xA0 + i) & 0xFF for i in range(16))
        hw.page_program(addr, pat)
        _p(f"  page_program OK, SR=0x{hw.read_status():02x}")
        rb = hw.read_buffer(addr, 16)
        _p(f"  wrote={pat.hex()}")
        _p(f"  read ={rb.hex()}  MATCH={rb == pat}")
    except QspiTimeout as e:
        _p(f"  qspi_hw REFERENCE FAILED: {e}  <-- board/flash fault, not cocotb")


def diag_cocotb_style(overlay):
    """Path B: the raw sequence the SST cocotb helper uses."""
    section("B. cocotb SST-helper RAW sequence (where parity diverges)")
    apb = overlay.apb
    # Match the cocotb inter-test reset (adapter.reset_writes).
    for off, val in ((0x00, 0), (0x04, 0x100), (0x08, 0),
                     (0x0C, 0), (0x30, 0), (0x34, 5)):
        apb.write(off, val)
    _p(f"after reset_writes: CLK_DIV=0x{apb.read(0x34):08x} CTRL=0x{apb.read(0x00):08x}")

    _p("\n-- RDSR variants (what SPI_READ_STAT_REG returns) --")
    # SST helper original: 1-byte RDSR, encoding 0x2005 / 0x2305.
    w1 = _raw_cmd(apb, 0x00002005, "RDSR-1byte-SSTenc")
    # Our override: 4-byte RDSR (READ|N_RW=3), 0 dummy.
    base4 = 0x05 | (1 << 9) | (3 << 16)
    w4 = _raw_cmd(apb, base4, "RDSR-4byte-override")
    _p(f"   1-byte enc: SR-as-(RDATA0>>24)&0xFF = 0x{(w1[0] >> 24) & 0xFF:02x}, "
       f"(RDATA0&0xFF)=0x{w1[0] & 0xFF:02x}")
    _p(f"   4-byte enc: SR-as-(RDATA0>>24)&0xFF = 0x{(w4[0] >> 24) & 0xFF:02x}, "
       f"all-bytes-equal={len({(w4[0]>>s)&0xFF for s in (0,8,16,24)})==1}")

    _p("\n-- WREN then RDSR (does SST-style WREN set WEL?) --")
    apb.write(0x08, 0x00000006)                 # WREN opcode
    apb.write(0x08, 0x00000106)                 # | ENABLE
    _wait_ctrl_idle(apb, "WREN")
    apb.write(0x04, 0x100)
    w = _raw_cmd(apb, base4, "RDSR-after-WREN")
    sr = (w[0] >> 24) & 0xFF
    _p(f"   SR=0x{sr:02x}  WEL(bit1)={(sr >> 1) & 1}  (expect WEL=1 if WREN works)")

    _p("\n-- SST-style page program @ 0x010000 + WIP poll (raw) --")
    A = 0x010000
    apb.write(0x08, 0x00000006); apb.write(0x08, 0x00000106)   # WREN
    _wait_ctrl_idle(apb, "WREN2"); apb.write(0x04, 0x100)
    apb.write(0x0C, A)                                          # addr
    for i, off in enumerate((0x20, 0x24, 0x28, 0x2C)):
        apb.write(off, 0xDEADBE00 | i)
    # page program 0x02, write=1, addr_en=1, N_RW=15 (16 bytes)
    pp = 0x02 | (1 << 10) | (1 << 11) | (15 << 16)
    apb.write(0x08, pp); apb.write(0x08, pp | (1 << 8))
    _wait_ctrl_idle(apb, "PP")
    apb.write(0x04, 0x100)
    _p("   WIP poll (4-byte RDSR), up to 40 reads, ~5ms apart:")
    cleared = False
    for k in range(40):
        w = _raw_cmd(apb, base4, f"WIP[{k}]") if k < 3 else None
        if w is None:
            apb.write(0x08, base4); apb.write(0x08, base4 | (1 << 8))
            _wait_ctrl_idle(apb, f"WIP{k}"); apb.write(0x04, 0x100)
            w = [apb.read(0x10)]
        sr = (w[0] >> 24) & 0xFF
        if k in (0, 5, 10, 20, 39):
            _p(f"   WIP[{k}] RDATA0=0x{w[0]:08x} SR=0x{sr:02x} WIP={sr & 1}")
        if not (sr & 1):
            _p(f"   -> WIP cleared after {k} polls (SR=0x{sr:02x})")
            cleared = True
            break
        time.sleep(0.005)
    if not cleared:
        _p("   -> WIP NEVER CLEARED (this is the 'flash busy' failure)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--budget", type=float, default=None)   # harness contract
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.parse_args()

    _p("flash_diag: opening overlay (bare, fpga_manager already loaded)")
    overlay = _open_overlay()
    apb = overlay.apb

    def preamble():
        section("PREAMBLE: adapter.hardware_preamble (flash soft-reset)")
        from cocotb_silicon_adapter import QspiAdapter
        QspiAdapter().hardware_preamble(overlay)
        _p("preamble done; JEDEC should now read 0x20ba19 if the flash "
           "was merely wedged (vs physically faulty/absent)")

    for fn in (lambda: diag_state(apb),
               preamble,
               lambda: diag_resurrect(overlay),
               lambda: diag_state(apb),
               lambda: diag_reference(overlay),
               lambda: diag_state(apb),
               lambda: diag_cocotb_style(overlay),
               lambda: diag_state(apb)):
        try:
            fn()
        except Exception:                                   # noqa: BLE001
            _p("SECTION RAISED:")
            traceback.print_exc()
    _p("\nflash_diag: done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
