#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - cocotb AHBLiteMaster Shim for PYNQ MMIO
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Adapter that lets the existing cocotb test suite (verif/cocotb/) run on a
# real PYNQ-Z2 board without modification. Reproduces the subset of the
# cocotbext.ahb.AHBLiteMaster API that ahb_qspi_tests.py exercises:
#
#   await master.write(addr, val)
#   await master.read(addr, nbytes)   -> [{'data': '0xXXXXXXXX'}]
#
# Both methods are async so existing `await` call sites work unchanged.
#
# Also provides a HwTB class that mimics the cocotb TB() but is constructed
# from a QspiOverlay instance, plus replacement DUT-signal poll helpers.
#-----------------------------------------------------------------------------

import asyncio
import time


class MmioAhbShim:
    """Drop-in replacement for cocotbext.ahb.AHBLiteMaster.

    Wraps a pynq.MMIO instance. All accesses are 32-bit aligned. The cocotb
    `nbytes` argument is honoured for sub-word reads by masking, but in the
    QSPI testbench all reads are 32-bit aligned anyway.
    """

    def __init__(self, mmio):
        self._mmio = mmio

    async def write(self, addr, value, **_kwargs):
        # cocotb passes value as int; some callers may pass bytes/bytearray
        if isinstance(value, (bytes, bytearray)):
            value = int.from_bytes(value, 'little')
        # Round addr down to 32-bit boundary; sub-word writes aren't used here
        word_addr = addr & ~0x3
        self._mmio.write(word_addr, value & 0xFFFFFFFF)

    async def read(self, addr, nbytes=4, **_kwargs):
        word_addr = addr & ~0x3
        byte_off  = addr & 0x3
        word = self._mmio.read(word_addr)
        if nbytes < 4:
            # Sub-word read - extract requested byte range
            mask = (1 << (nbytes * 8)) - 1
            word = (word >> (byte_off * 8)) & mask
        # Match cocotbext.ahb return shape: list of {'data': hex string}
        return [{'data': f'0x{word:08x}'}]


class _DummyDutSignal:
    """Stand-in for a cocotb DUT signal - just stores a value attribute.

    Some tests do `dut.HRESETn.setimmediatevalue(0)` or check
    `dut.IRQ_QSPI_FINISHED.value` - both become no-ops on real hardware
    because reset is only via bitstream load and IRQ status is read via
    the STATUS register instead.
    """

    def __init__(self, name='dummy'):
        self._name = name
        self.value = 0

    def setimmediatevalue(self, v):
        self.value = v

    def __int__(self):
        return int(self.value)


class HwDut:
    """Stand-in for the cocotb `dut` object passed into each @cocotb.test.

    Any signal access returns a no-op _DummyDutSignal; the only signals the
    cocotb tests poke directly are HCLK (used for ClockCycles waits, which
    we replace) and HRESETn (handled in HwTB.cycle_reset).
    """

    def __init__(self):
        self._signals = {}

    def __getattr__(self, name):
        sig = self._signals.get(name)
        if sig is None:
            sig = _DummyDutSignal(name)
            self._signals[name] = sig
        return sig


class HwTB:
    """Hardware-side replacement for the cocotb TB class.

    Mirrors the public interface of verif/cocotb/ahb_qspi_tests.py:TB so the
    rest of the testbench works unchanged:
        tb.dut, tb.log, tb.config_ahb_master, tb.data_ahb_master
        await tb.cycle_reset()
    """

    def __init__(self, overlay, log=None):
        import logging
        self.dut    = HwDut()
        self.log    = log or logging.getLogger("hw.tb")
        self.config_ahb_master = MmioAhbShim(overlay.apb)
        self.data_ahb_master   = MmioAhbShim(overlay.ahb)
        self._overlay = overlay

    async def cycle_reset(self):
        """Software-reset the controller. Not a true hardware reset, but
        puts every writable register back to its idle state - sufficient
        for inter-test isolation."""
        self._overlay.reset_controller()
        # Brief settle time for the CDC synchronisers
        await asyncio.sleep(0.001)


# -------------------------------------------------------------------------
# Replacement helpers for verif/cocotb/SST26VF064B.py poll/wait functions.
# These are the only functions in the test bench that touch DUT signals
# directly - everything else routes through the AHB master shims above.
# -------------------------------------------------------------------------

POLL_TIMEOUT_S = 5.0


async def poll_busy_clear(dut, tb, timeout=None):
    """Poll STATUS[0] (BUSY) until clear. dut arg unused on hardware."""
    deadline = time.monotonic() + (POLL_TIMEOUT_S if timeout is None else timeout * 1e-6)
    while time.monotonic() < deadline:
        data = await tb.config_ahb_master.read(0x04, 4)
        if not (int(data[0]['data'], 16) & 1):
            return
        await asyncio.sleep(0)
    raise AssertionError("QSPI_BUSY did not clear within timeout")


async def poll_busy_set(dut, tb, timeout=None):
    """Poll STATUS[0] (BUSY) until set."""
    deadline = time.monotonic() + (POLL_TIMEOUT_S if timeout is None else timeout * 1e-6)
    while time.monotonic() < deadline:
        data = await tb.config_ahb_master.read(0x04, 4)
        if int(data[0]['data'], 16) & 1:
            return
        await asyncio.sleep(0)
    raise AssertionError("QSPI_BUSY did not set within timeout")


async def wait_for_irq(dut, tb, timeout=None):
    """Wait for IRQ_QSPI_FINISHED then clear it.

    On hardware we don't have a free-floating signal poke, so we wait for
    BUSY to clear (which precedes IRQ assertion in the controller FSM)
    and then write IRQ_CLR. This preserves the original semantics: by the
    time wait_for_irq returns, the transaction is done and the IRQ has
    been cleared.
    """
    await poll_busy_clear(dut, tb, timeout)
    await tb.config_ahb_master.write(0x04, 0x00000100)
    await asyncio.sleep(0)
