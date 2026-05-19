#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - cocotb-silicon project adapter
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# THE canonical adapter for running verif/cocotb/ahb_qspi_tests.py on a real
# PYNQ-Z2 via the standalone `cocotb-silicon` package. Reproduces, field for
# field, the behaviour the legacy pynq/tests/run_tests.py + qspi_ahb_shim.py
# + N25Q256A.py hardcoded - now as one declarative class.
#
# This is the in-repo equivalent of cocotb-silicon's
# examples/ahb_qspi/adapter.py; it lives here so this project owns and
# versions its own hardware contract. The example in the package repo is a
# copy for documentation.
#
# Deployed flat into the board overlay dir by `make -C fpga cocotb_hw`
# (which stages pynq/ + the cocotb_silicon package + verif/cocotb/*.py
# side by side, so test_module / SST26VF064B resolve from the cwd).
#-----------------------------------------------------------------------------

import asyncio
import time

from cocotb_silicon import Adapter, Region

# cocotb passes poll timeouts in microseconds; default ceiling when a test
# doesn't pass one (verbatim from the legacy qspi_ahb_shim.py).
POLL_TIMEOUT_S = 5.0


class QspiAdapter(Adapter):
    # ahb_qspi_tests.py and SST26VF064B.py are staged next to this file in
    # the board overlay dir, so "." (the runner cwd) is enough.
    test_module  = "ahb_qspi_tests"
    helper_paths = (".",)

    # Block-design address map (keep in sync with
    # fpga/targets/pynq-z2/qspi_design.tcl).
    regions = (
        Region("apb", 0x4200_0000, 0x0001_0000),   # QSPI regs + cache @ +0x1000
        Region("ahb", 0x4000_0000, 0x0100_0000),   # read-only XiP window
    )

    bus_masters = {
        "config_ahb_master": "apb",
        "data_ahb_master":   "ahb",
    }

    sanity = (
        ("apb", 0xFE0, 0xFF, 0x59),     # PIDR0
        ("apb", 0xFF0, 0xFF, 0x50),     # CIDR0 ('P')
    )

    reset_writes = (
        ("apb", 0x00, 0x000),           # CTRL = 0
        ("apb", 0x04, 0x100),           # IRQ_CLR
        ("apb", 0x08, 0x000),           # SPI_CMD = 0
        ("apb", 0x0C, 0x000),           # SPI_ADDR = 0
        ("apb", 0x30, 0x000),           # AHB_SPI_SETUP = 0
        ("apb", 0x34, 0x005),           # CLK_DIV = 5 (HCLK/10, safe)
    )

    patch_helpers = {
        "SST26VF064B": ["poll_busy_clear", "poll_busy_set", "wait_for_irq",
                        "SET_QPI_MODE", "LEAVE_QPI_MODE",
                        "SPI_READ_STAT_REG", "QPI_READ_STAT_REG"],
        "ahb_qspi_tests": ["poll_busy_clear", "wait_for_irq"],
    }

    # PmodSF3 is Micron N25Q256A, not the SST the sim helper hardcodes.
    device_overrides = {"SST26VF064B.ID": 0x20BA1900}

    # Tests that cannot be replayed on this board. Established by the
    # on-hardware parity regression + pynq/README.md "Known caveats":
    #   - AHB_BAD_BEHAVIOUR does an errored AHB write; on silicon that
    #     MMIO store raises SIGBUS and kills the process (now contained
    #     by per-test isolation, but still pointless to run).
    #   - test_bug{1,2,3}_* poke internal DUT nets -> no-ops on hardware.
    skip = (
        "AHB_BAD_BEHAVIOUR",
        "test_bug1_rdata_latch",
        "test_bug2_enable_ack_latch",
        "test_bug3_no_cmd_last_addr",
    )
    # Run but a fail/crash is expected and informative, not a regression.
    # Each entry is an *inherent* silicon limitation (see the design doc
    # limitations table), not something a Micron-correct flash path fixes:
    xfail = (
        # flash JEDEC-ID asserted byte-for-byte vs the simulated SST part
        "QSPI_TESTS", "QSPI_READ_TESTS",
        # soft-reset can't reproduce the bitstream power-on default
        "test_register_reset_values", "test_reset_during_transaction",
        # read dut.IRQ_* directly - no signal visibility on silicon
        "test_irq_lifecycle", "test_irq_multiple_commands",
        # count QSPI_SCLK edges via sim-time - no clock to count on silicon
        "test_spi_write_clock_count", "test_qpi_write_clock_count",
        "test_spi_write_single_byte_clock_count",
        # force internal DUT nets / CDC metastability - no such nodes on HW
        "test_xip_hang_on_stuck_busy", "test_xip_timeout_recovery",
        "test_cdc_ack_retry_after_watchdog",
        "test_cdc_control_bus_metastability",
        # builds explicit cocotbext.ahb AHBWrite transaction objects (a
        # BFM construct with no MMIO equivalent)
        "test_xip_cache_pipelined_rw_interleave_regression",
    )

    # ---- Micron-correct flash status read (the write-path fix) --------
    # The SST helper's SPI/QPI_READ_STAT_REG does a 1-byte RDSR
    # (N_RW_BYTES=0, 2 dummy). pynq/stress/qspi_hw.py documents that the
    # short-read DATA_I path is fragile on real silicon, so it uses a
    # 4-byte RDSR (N_RW_BYTES=3, 0 dummy) - the well-tested full-word
    # path. Without this the WIP bit is never observed clear and every
    # page-program / erase times out "flash busy". Tests inspect bit 24
    # (WIP = SR.0) and bit 25 (WEL = SR.1), i.e. they expect the status
    # byte at [31:24]; the flash drives SR on all 4 received bytes so
    # RDATA0 = 0xSRSRSRSR and (RDATA0>>24)&0xFF = SR.

    async def _read_status_robust(self, dut, tb):
        base = 0x05 | (1 << 9) | (3 << 16)        # RDSR | READ | N_RW=4
        await tb.config_ahb_master.write(0x08, base)
        await tb.config_ahb_master.write(0x08, base | (1 << 8))   # ENABLE
        await self.wait_for_irq(dut, tb)
        await self.poll_busy_clear(dut, tb)
        data = await tb.config_ahb_master.read(0x10, 4)
        sr = (int(data[0]['data'], 16) >> 24) & 0xFF
        return sr << 24                            # SR -> bits[31:24]

    async def SPI_READ_STAT_REG(self, dut, tb):
        return await self._read_status_robust(dut, tb)

    async def QPI_READ_STAT_REG(self, dut, tb):
        # Framing (SPI vs QPI) follows CTRL.QIO_MODE set by the caller;
        # the robust 4-byte/0-dummy RDSR encoding is identical.
        return await self._read_status_robust(dut, tb)

    # ---- register-poll coroutines (verbatim bodies from qspi_ahb_shim.py) ----

    async def poll_busy_clear(self, dut, tb, timeout=None):
        deadline = time.monotonic() + (POLL_TIMEOUT_S if timeout is None
                                       else timeout * 1e-6)
        while time.monotonic() < deadline:
            data = await tb.config_ahb_master.read(0x04, 4)
            if not (int(data[0]['data'], 16) & 1):
                return
            await asyncio.sleep(0)
        raise AssertionError("QSPI_BUSY did not clear within timeout")

    async def poll_busy_set(self, dut, tb, timeout=None):
        deadline = time.monotonic() + (POLL_TIMEOUT_S if timeout is None
                                       else timeout * 1e-6)
        while time.monotonic() < deadline:
            data = await tb.config_ahb_master.read(0x04, 4)
            if int(data[0]['data'], 16) & 1:
                return
            await asyncio.sleep(0)
        raise AssertionError("QSPI_BUSY did not set within timeout")

    async def wait_for_irq(self, dut, tb, timeout=None):
        # BUSY-clear precedes IRQ assertion in the controller FSM, so this
        # preserves the original sim post-condition: by return the txn is
        # done and the IRQ has been acknowledged.
        await self.poll_busy_clear(dut, tb, timeout)
        await tb.config_ahb_master.write(0x04, 0x00000100)
        await asyncio.sleep(0)

    # ---- Micron QPI mode entry/exit (ex-N25Q256A.py): a CODE override ----

    async def SET_QPI_MODE(self, dut, tb):
        await tb.config_ahb_master.write(0x08, 0x00000035)   # ENTER QUAD I/O
        await tb.config_ahb_master.write(0x08, 0x00000135)
        await self.wait_for_irq(dut, tb)
        await self.poll_busy_clear(dut, tb)

    async def LEAVE_QPI_MODE(self, dut, tb):
        await tb.config_ahb_master.write(0x08, 0x000000F5)   # EXIT QUAD I/O
        await tb.config_ahb_master.write(0x08, 0x000001F5)
        await self.wait_for_irq(dut, tb)
        await self.poll_busy_clear(dut, tb)


# Lets the CLI take `--adapter cocotb_silicon_adapter` (no :Class needed).
adapter = QspiAdapter()
