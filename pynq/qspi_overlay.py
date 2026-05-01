#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - PYNQ Overlay
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# PYNQ Overlay class for the AHB QSPI subsystem on PYNQ-Z2.
#
# The block design exposes two MMIO apertures:
#   APB regs   at PS address 0x4200_0000, 64 KB    -> QSPI register bank
#   AHB XiP    at PS address 0x4000_0000, 16 MB    -> read-only flash window
#
# Usage:
#   from qspi_overlay import QspiOverlay
#   ol = QspiOverlay()                  # loads ./qspi.bit by default
#   ol.apb.write(0x34, 5)               # set CLK_DIV
#   pidr0 = ol.apb.read(0xFE0)          # read PIDR0 (= 0x59)
#-----------------------------------------------------------------------------

import os
from pynq import Overlay, MMIO


# Block design address map - keep in sync with fpga/targets/pynq-z2/qspi_design.tcl
APB_BASE_ADDR = 0x4200_0000
APB_RANGE     = 0x0001_0000     # 64 KB - covers PADDR[15:0] + cache regs at 0x1000

AHB_BASE_ADDR = 0x4000_0000
AHB_RANGE     = 0x0100_0000     # 16 MB - covers SPI_ADDR[21:0] XiP window


class QspiOverlay(Overlay):
    """PYNQ Overlay for the AHB QSPI subsystem.

    Exposes:
        apb: MMIO region for QSPI APB register bank
        ahb: MMIO region for QSPI AHB-Lite XiP read window
    """

    def __init__(self, bitfile=None, **kwargs):
        if bitfile is None:
            bitfile = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   'qspi.bit')
        super().__init__(bitfile, **kwargs)
        self.apb = MMIO(APB_BASE_ADDR, APB_RANGE)
        self.ahb = MMIO(AHB_BASE_ADDR, AHB_RANGE)

    def read_pidr(self):
        """Return the 8-byte CoreSight peripheral ID as an integer."""
        pidr = 0
        for i, off in enumerate([0xFE0, 0xFE4, 0xFE8, 0xFEC,
                                 0xFD0, 0xFD4, 0xFD8, 0xFDC]):
            pidr |= (self.apb.read(off) & 0xFF) << (8 * i)
        return pidr

    def read_cidr(self):
        """Return the 4-byte CoreSight component ID as an integer (= 'PQLS')."""
        cidr = 0
        for i, off in enumerate([0xFF0, 0xFF4, 0xFF8, 0xFFC]):
            cidr |= (self.apb.read(off) & 0xFF) << (8 * i)
        return cidr

    def reset_controller(self):
        """Software reset: write zeros to all writeable control regs.

        Not a true hardware reset (the bitstream load is the only true reset),
        but puts the controller into a known idle state between tests.
        """
        # CTRL = 0 (clears QIO_MODE, XIP_ACTIVE, MODE_CODE, CONT_READ, NO_CMD)
        self.apb.write(0x00, 0x0)
        # IRQ_CLR
        self.apb.write(0x04, 0x100)
        # SPI_CMD = 0
        self.apb.write(0x08, 0x0)
        # SPI_ADDR = 0
        self.apb.write(0x0C, 0x0)
        # AHB_SPI_SETUP = 0
        self.apb.write(0x30, 0x0)
        # CLK_DIV = 5 (HCLK/10 = safe default)
        self.apb.write(0x34, 0x5)
