#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - Micron N25Q256A / MT25QL256 helper module
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Companion to verif/cocotb/SST26VF064B.py for the PmodSF3 module on real
# hardware. Re-exports every helper from SST26VF064B verbatim because the
# vast majority of opcodes (WREN, WRDI, READ, FAST_READ, PAGE_PROGRAM,
# erase, status reads) are SPI-standard and identical across vendors.
#
# Only device-specific overrides:
#   ID  - Micron JEDEC signature (0x20BAxx) instead of the SST 0x4326BF00
#   SET_QPI_MODE / LEAVE_QPI_MODE - Micron uses 0x35 / 0xF5 (Enable / Disable
#       Quad I/O Mode) rather than the SST 0x38 / 0xFF
#
# When porting tests, expect to skip or relax assertions that compare the
# JEDEC ID byte-for-byte against the SST signature.
#-----------------------------------------------------------------------------

# Re-export everything from the cocotb-side SST26VF064B helpers. The shim
# layer (qspi_ahb_shim) replaces the AHBLiteMaster these helpers call with
# an MMIO-backed equivalent, so they work unchanged on real hardware for
# any opcode the two flashes share.
from SST26VF064B import *           # noqa: F401,F403
from SST26VF064B import (           # explicit re-export of names used elsewhere
    poll_busy_clear,
    poll_busy_set,
    wait_for_irq,
    POLL_TIMEOUT_CYCLES,
)


# Override the device ID. The full Micron JEDEC ID is 0x20BAxx where xx
# encodes density: 0x19 = 256 Mb (N25Q256A / MT25QL256ABA).
ID = 0x20BA1900


# ---------------------------------------------------------------------------
# Micron-specific QPI mode entry / exit
#
# SST26VF064B uses opcode 0x38 to enter QPI and 0xFF to exit. Micron N25Q
# uses 0x35 (Enable Quad I/O Mode) and 0xF5 (Disable Quad I/O Mode). The
# SET_QPI_MODE / LEAVE_QPI_MODE helpers from SST26VF064B issue 0x38/0xFF
# unconditionally, so we override them here.
# ---------------------------------------------------------------------------

async def SET_QPI_MODE(dut, tb):
    # 0x35 = ENTER QUAD I/O MODE on Micron
    await tb.config_ahb_master.write(0x08, 0x00000035)
    await tb.config_ahb_master.write(0x08, 0x00000135)
    await wait_for_irq(dut, tb)
    await poll_busy_clear(dut, tb)


async def LEAVE_QPI_MODE(dut, tb):
    # 0xF5 = EXIT QUAD I/O MODE on Micron
    await tb.config_ahb_master.write(0x08, 0x000000F5)
    await tb.config_ahb_master.write(0x08, 0x000001F5)
    await wait_for_irq(dut, tb)
    await poll_busy_clear(dut, tb)
