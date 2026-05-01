#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - Bare-metal overlay loader (no pynq dependency)
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Drop-in replacement for pynq.MMIO + pynq.Overlay.download() that depends
# only on /dev/mem + /sys/class/fpga_manager. The PYNQ image v2.7 on this
# board is missing pydantic/pynqutils which the standard pynq.Overlay path
# needs - rather than fight Python deps offline, we just go direct to the
# kernel interfaces PYNQ wraps anyway.
#
# Bitstream loading is via the FPGA manager + .bin format. .bit is converted
# to .bin (header stripped, 32-bit word byte-swapped) at the host side; here
# we just expect a .bin file already in /lib/firmware/.
#-----------------------------------------------------------------------------

import mmap
import os
import struct


class BareMMIO:
    """Tiny pynq.MMIO-compatible class backed by /dev/mem + mmap.

    Maps `length` bytes starting at `base_addr` (must be page-aligned).
    Provides word-aligned read(off) / write(off, val) at byte offsets within
    the mapping.
    """

    PAGE_SIZE = 4096

    def __init__(self, base_addr, length):
        if base_addr % self.PAGE_SIZE:
            raise ValueError(
                f"base_addr 0x{base_addr:x} not page-aligned ({self.PAGE_SIZE})")
        self._base = base_addr
        self._len  = length
        # Round length up to page boundary so mmap accepts it
        rounded = (length + self.PAGE_SIZE - 1) & ~(self.PAGE_SIZE - 1)
        self._fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
        try:
            self._mm = mmap.mmap(
                self._fd, rounded,
                mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE,
                offset=base_addr,
            )
        except Exception:
            os.close(self._fd)
            raise

    def read(self, offset, length=4):
        if length != 4:
            raise NotImplementedError("only 32-bit reads supported")
        if offset & 0x3:
            raise ValueError("offset must be 32-bit aligned")
        return struct.unpack('<I', self._mm[offset:offset+4])[0]

    def write(self, offset, value):
        if offset & 0x3:
            raise ValueError("offset must be 32-bit aligned")
        self._mm[offset:offset+4] = struct.pack('<I', value & 0xFFFFFFFF)

    def close(self):
        try:
            self._mm.close()
        finally:
            os.close(self._fd)

    def __del__(self):
        try:
            self.close()
        except Exception:
            pass


def load_bitstream(bin_filename, mgr_path='/sys/class/fpga_manager/fpga0'):
    """Trigger FPGA configuration via the kernel FPGA manager.

    `bin_filename` must be the basename of a file already placed in
    /lib/firmware/. The kernel reads from there. Returns when the FPGA
    manager reports state=operating.
    """
    fw_path = os.path.join(mgr_path, 'firmware')
    state_path = os.path.join(mgr_path, 'state')
    with open(fw_path, 'w') as f:
        f.write(bin_filename)
    # The write blocks until configuration is done (or fails).
    with open(state_path) as f:
        state = f.read().strip()
    if state != 'operating':
        raise RuntimeError(f"FPGA manager state after load = {state!r}")


# ---------------------------------------------------------------------------
# QspiOverlay drop-in - same interface as pynq/qspi_overlay.py:QspiOverlay
# but without any pynq dependency.
# ---------------------------------------------------------------------------

APB_BASE_ADDR = 0x4200_0000
APB_RANGE     = 0x0001_0000
AHB_BASE_ADDR = 0x4000_0000
AHB_RANGE     = 0x0100_0000


class QspiOverlay:
    """Bare-metal QSPI overlay. Loads bitstream + opens MMIO regions."""

    def __init__(self, bitfile=None, fw_name=None, skip_load=False):
        if not skip_load:
            if fw_name is None:
                # Convention: deploy step copies qspi.bin into /lib/firmware/
                fw_name = 'qspi.bin'
            load_bitstream(fw_name)
        self.apb = BareMMIO(APB_BASE_ADDR, APB_RANGE)
        self.ahb = BareMMIO(AHB_BASE_ADDR, AHB_RANGE)

    def read_pidr(self):
        v = 0
        for i, off in enumerate([0xFE0, 0xFE4, 0xFE8, 0xFEC,
                                 0xFD0, 0xFD4, 0xFD8, 0xFDC]):
            v |= (self.apb.read(off) & 0xFF) << (8 * i)
        return v

    def read_cidr(self):
        v = 0
        for i, off in enumerate([0xFF0, 0xFF4, 0xFF8, 0xFFC]):
            v |= (self.apb.read(off) & 0xFF) << (8 * i)
        return v

    def reset_controller(self):
        self.apb.write(0x00, 0x0)
        self.apb.write(0x04, 0x100)
        self.apb.write(0x08, 0x0)
        self.apb.write(0x0C, 0x0)
        self.apb.write(0x30, 0x0)
        self.apb.write(0x34, 0x5)
