#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - cocotb / cocotbext.ahb stubs for PYNQ
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Lightweight stubs for cocotb, cocotb.clock, cocotb.triggers and
# cocotbext.ahb so that the existing verif/cocotb test files can be imported
# on a PYNQ board where cocotb itself is not installed (and would not work
# even if it were - there is no simulator running).
#
# Call install() once before importing any cocotb-based test module.
#-----------------------------------------------------------------------------

import asyncio
import sys
import types


# Registry of @cocotb.test-decorated coroutines so the runner can iterate them.
_REGISTERED_TESTS = []


def get_registered_tests():
    return list(_REGISTERED_TESTS)


def install():
    """Inject fake cocotb / cocotbext modules into sys.modules.

    Must be called before importing any verif/cocotb file. Idempotent.
    """
    if 'cocotb' in sys.modules and getattr(sys.modules['cocotb'], '_pynq_stub', False):
        return  # already installed

    # ---- cocotb top-level ----
    cocotb_mod = types.ModuleType('cocotb')
    cocotb_mod._pynq_stub = True

    def _test_decorator(*dargs, **dkwargs):
        # Supports both @cocotb.test and @cocotb.test()
        def wrap(fn):
            _REGISTERED_TESTS.append(fn)
            return fn
        if len(dargs) == 1 and callable(dargs[0]) and not dkwargs:
            return wrap(dargs[0])
        return wrap

    def _start_soon(coro):
        # On HW we don't run background coroutines (no clock to generate).
        # Schedule on the running loop if there is one, else discard.
        try:
            loop = asyncio.get_event_loop()
            if loop.is_running():
                return asyncio.ensure_future(coro)
        except RuntimeError:
            pass
        # No running loop - safe to drop the coroutine without warning
        if hasattr(coro, 'close'):
            coro.close()
        return None

    cocotb_mod.test       = _test_decorator
    cocotb_mod.start_soon = _start_soon
    cocotb_mod.coroutine  = lambda fn: fn

    # ---- cocotb.clock ----
    clock_mod = types.ModuleType('cocotb.clock')

    class Clock:
        def __init__(self, signal, period, units='ns'):
            self.signal = signal
            self.period = period
            self.units  = units
        def start(self):
            async def _noop():
                return
            return _noop()

    clock_mod.Clock = Clock

    # ---- cocotb.triggers ----
    triggers_mod = types.ModuleType('cocotb.triggers')

    _UNIT_TO_S = {'fs': 1e-15, 'ps': 1e-12, 'ns': 1e-9,
                  'us': 1e-6,  'ms': 1e-3,  'sec': 1.0, 's': 1.0}

    class Timer:
        def __init__(self, time=0, units='ns'):
            self._delay = time * _UNIT_TO_S.get(units, 1e-9)
        def __await__(self):
            # asyncio.sleep is the closest analogue; sub-millisecond precision
            # is fine for our purposes (we only use Timer to stagger MMIO).
            return asyncio.sleep(self._delay).__await__()

    class ClockCycles:
        def __init__(self, signal, num_cycles):
            self._cycles = num_cycles
        def __await__(self):
            # No clock to count on real hardware - yield once so async machinery
            # progresses. The actual cycle count is irrelevant when we're going
            # over an AXI bus that already serializes everything.
            return asyncio.sleep(0).__await__()

    triggers_mod.Timer        = Timer
    triggers_mod.ClockCycles  = ClockCycles
    triggers_mod.RisingEdge   = lambda *_a, **_k: ClockCycles(None, 1)
    triggers_mod.FallingEdge  = lambda *_a, **_k: ClockCycles(None, 1)

    # ---- cocotbext.ahb ----
    cocotbext_mod     = types.ModuleType('cocotbext')
    cocotbext_ahb_mod = types.ModuleType('cocotbext.ahb')

    class _AHBBus:
        @classmethod
        def from_prefix(cls, *args, **kwargs):
            return cls()

    class _AHBLiteMaster:
        """Placeholder - real implementation lives in qspi_ahb_shim.MmioAhbShim.

        The HwTB constructor never instantiates this class directly, but the
        test file's TB.__init__ does. We monkey-patch TB out before running
        any test, so this stub is just here to satisfy import-time
        side effects.
        """
        def __init__(self, *args, **kwargs):
            pass
        async def write(self, *args, **kwargs):
            raise RuntimeError("Real AHBLiteMaster called - HwTB substitution missing")
        async def read(self, *args, **kwargs):
            raise RuntimeError("Real AHBLiteMaster called - HwTB substitution missing")

    cocotbext_ahb_mod.AHBBus        = _AHBBus
    cocotbext_ahb_mod.AHBLiteMaster = _AHBLiteMaster
    cocotbext_mod.ahb               = cocotbext_ahb_mod

    # Register everything
    sys.modules['cocotb']           = cocotb_mod
    sys.modules['cocotb.clock']     = clock_mod
    sys.modules['cocotb.triggers']  = triggers_mod
    sys.modules['cocotbext']        = cocotbext_mod
    sys.modules['cocotbext.ahb']    = cocotbext_ahb_mod
