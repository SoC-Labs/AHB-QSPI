#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - Synchronous controller helpers for stress tests
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Direct, synchronous QSPI controller wrapper for the stress test runner.
# Distinct from qspi_ahb_shim - that module mimics the cocotb async API for
# replaying simulation tests; this one is plain blocking calls because the
# stress tests are written natively for hardware and have no need to look
# like cocotb.
#-----------------------------------------------------------------------------

import time

# APB register offsets (from src/rdl/apb_qspi_regs.rdl)
REG_CTRL          = 0x00
REG_STATUS        = 0x04
REG_SPI_CMD       = 0x08
REG_SPI_ADDR      = 0x0C
REG_RDATA         = (0x10, 0x14, 0x18, 0x1C)
REG_WDATA         = (0x20, 0x24, 0x28, 0x2C)
REG_AHB_SPI_SETUP = 0x30
REG_CLK_DIV       = 0x34

# ARM CG092 p_flash_cache_f0 register block — lives at APB offset 0x1000
# within the same APB window as the QSPI regs (block-design mux port 1).
# Must be enabled and polled-for-ready before any AHB XIP read, or the
# cache won't respond and the PS will wedge on the MMIO load.
REG_CACHE_CONFIG  = 0x1000
REG_CACHE_STATUS  = 0x1004
CACHE_STATUS_READY_MASK = 0x3
CACHE_STATUS_READY_VAL  = 0x2

# CTRL bit positions
CTRL_QIO_MODE     = 0
CTRL_XIP_ACTIVE   = 8
CTRL_MODE_CODE_SH = 16
CTRL_CONT_READ    = 24
CTRL_NO_CMD       = 25

# STATUS bit positions
STATUS_BUSY       = 0
STATUS_IRQ_CLR    = 8

# SPI_CMD bit positions
CMD_ENABLE        = 8
CMD_READ          = 9
CMD_WRITE         = 10
CMD_ADDR_EN       = 11
CMD_DUMMY_SH      = 12
CMD_N_RW_BYTES_SH = 16

# Standard SPI flash opcodes (vendor-agnostic)
OP_WREN           = 0x06
OP_WRDI           = 0x04
OP_RDSR           = 0x05
OP_RDID_SPI       = 0x9F
OP_FAST_READ      = 0x0B
OP_PAGE_PROGRAM   = 0x02
OP_SECTOR_ERASE_4K  = 0x20
OP_SECTOR_ERASE_64K = 0xD8
OP_BULK_ERASE     = 0xC7

# Flash status register bits
SR_WIP            = 1 << 0   # Write in progress
SR_WEL            = 1 << 1   # Write enable latch

# Flash geometry (PmodSF3 / N25Q256A: 32 MB)
SECTOR_SIZE       = 64 * 1024
PAGE_SIZE         = 256
TOTAL_SECTORS     = 256       # only the lower 16 MB is reachable via SPI_ADDR[21:0]


class QspiTimeout(Exception):
    pass


class QspiHw:
    """Thin synchronous wrapper around the QSPI APB register bank.

    Constructed from a `QspiOverlay` instance. All methods block until the
    transaction completes; raises `QspiTimeout` if BUSY does not clear or
    the flash WIP bit stays set within the configured deadline.
    """

    def __init__(self, overlay, timeout_s=2.0):
        self.overlay = overlay
        self.apb     = overlay.apb
        self.ahb     = overlay.ahb
        self.timeout = timeout_s

    # ---- low-level register access ----------------------------------------

    def reset_controller(self):
        """Soft reset - put every writable register back to a known idle."""
        self.apb.write(REG_CTRL,          0)
        self.apb.write(REG_STATUS,        1 << STATUS_IRQ_CLR)
        self.apb.write(REG_SPI_CMD,       0)
        self.apb.write(REG_SPI_ADDR,      0)
        self.apb.write(REG_AHB_SPI_SETUP, 0)
        self.apb.write(REG_CLK_DIV,       5)

    # CLK_DIV lower bound. At HCLK=50 MHz, CLK_DIV=n gives QSPI_SCLK=50/(2n) MHz.
    # CLK_DIV=0 -> 50 MHz, CLK_DIV=1 -> 25 MHz. The PmodSF3 (N25Q family) specs
    # 108 MHz max for dedicated DTR modes but only ~50 MHz in SDR SPI mode with
    # the margins we're running; empirically CLK_DIV < 2 produces wrong data
    # from FAST_READ (not a hang — bytes just come back scrambled). Enforce
    # CLK_DIV >= 2 at the Python API boundary so callers don't silently corrupt
    # data. Override by passing force=True if you're deliberately exercising
    # the failing edge (e.g. to characterise flash timing margins).
    CLK_DIV_MIN_SAFE = 2

    def set_clk_div(self, n, *, force=False):
        if not 0 <= n <= 31:
            raise ValueError("CLK_DIV out of range [0, 31]")
        if n < self.CLK_DIV_MIN_SAFE and not force:
            raise ValueError(
                f"CLK_DIV={n} exceeds PmodSF3 SPI-mode timing "
                f"(need >= {self.CLK_DIV_MIN_SAFE}); pass force=True to override")
        self.apb.write(REG_CLK_DIV, n & 0x1F)

    def set_ctrl(self, *, qio=0, xip_active=0, mode_code=0, cont_read=0, no_cmd=0):
        v = ((qio        & 1) << CTRL_QIO_MODE)     \
          | ((xip_active & 1) << CTRL_XIP_ACTIVE)   \
          | ((mode_code  & 0xFF) << CTRL_MODE_CODE_SH) \
          | ((cont_read  & 1) << CTRL_CONT_READ)    \
          | ((no_cmd     & 1) << CTRL_NO_CMD)
        self.apb.write(REG_CTRL, v)

    def get_status(self):
        return self.apb.read(REG_STATUS)

    def is_busy(self):
        return bool(self.get_status() & (1 << STATUS_BUSY))

    def clear_irq(self):
        self.apb.write(REG_STATUS, 1 << STATUS_IRQ_CLR)

    def wait_busy_clear(self, timeout=None):
        deadline = time.monotonic() + (timeout if timeout is not None else self.timeout)
        while time.monotonic() < deadline:
            if not self.is_busy():
                return
        raise QspiTimeout("controller BUSY did not clear")

    # ---- generic SPI command issue ----------------------------------------

    def spi_cmd(self, opcode, *, read=0, write=0, addr_en=0, dummy=0, n_bytes=1):
        """Issue a single SPI/QPI command. n_bytes = data phase length in bytes (1..16).

        The data phase length register field is N-1; pass the actual byte count
        and we encode it for you. For opcode-only commands (e.g. WREN) pass
        read=write=0 and n_bytes=1 - the field is ignored when neither READ
        nor WRITE is set.
        """
        if not 1 <= n_bytes <= 16:
            raise ValueError("n_bytes must be in [1, 16]")
        if not 0 <= dummy <= 15:
            raise ValueError("dummy must be in [0, 15]")
        flags = (read    << CMD_READ)        \
              | (write   << CMD_WRITE)       \
              | (addr_en << CMD_ADDR_EN)     \
              | (dummy   << CMD_DUMMY_SH)    \
              | ((n_bytes - 1) << CMD_N_RW_BYTES_SH)
        base = (opcode & 0xFF) | flags
        # Two-write pattern: configure descriptor, then strobe ENABLE.
        self.apb.write(REG_SPI_CMD, base)
        self.apb.write(REG_SPI_CMD, base | (1 << CMD_ENABLE))
        self.wait_busy_clear()
        self.clear_irq()

    def write_addr(self, addr):
        self.apb.write(REG_SPI_ADDR, addr & 0x3FFFFF)

    def write_wdata(self, data_bytes):
        """Pack up to 16 bytes into WDATA0..3 (little-endian word order).

        The apb_qspi_regs module applies a per-byte bit-reversal transform
        to WDATA before feeding the shift register, and the shift register
        emits LSB-first. Net effect: the byte at WDATA0[7:0] is the FIRST
        byte stored at flash[addr+0], WDATA0[15:8] goes to flash[addr+1],
        and so on.

        So `bytes[0]` (first byte to store) goes at WDATA0[7:0], which
        means packing with 'little' — the byte-order `int.from_bytes`
        would produce if you wrote WDATA0 as the 32-bit int.
        """
        if len(data_bytes) > 16:
            raise ValueError("max 16 bytes per WDATA load")
        padded = bytes(data_bytes) + b'\x00' * (16 - len(data_bytes))
        for i, off in enumerate(REG_WDATA):
            self.apb.write(off, int.from_bytes(padded[i*4:(i+1)*4], 'little'))

    def read_rdata_words(self):
        """Read all four RDATA registers as raw 32-bit words."""
        return [self.apb.read(off) for off in REG_RDATA]

    def read_rdata(self, n_bytes):
        """Read n_bytes (1..16) from RDATA0..3 in flash byte-order.

        Hardware packing rules (apb_qspi_regs.v QSPI_RDATA case + PRDATA
        byte-swap):

        * n_bytes == 4: the 4 captured bytes land at QSPI_RDATA[31:0] in
          received order (MSB first). The per-word byte-swap at
          apb_qspi_regs.v:211 reverses them, which is *also* what
          `to_bytes('little')` does back, so raw[:4] is flash order.

        * n_bytes < 4: QSPI_RDATA zero-pads in the TOP bits of the word
          (e.g. for n_rw=2 the slice is {8'b0, data_in_reg[23:0]}). The
          byte-swap moves those zero bytes to PRDATA's MSB. Read as a
          little-endian int, the padding shows up at the START of raw.
          The real flash bytes live in raw[4-n_bytes : 4].

        * n_bytes >= 4 for multi-word reads: word 0 through word N-1
          each follow the n_bytes==4 rule, and concatenating them in
          little-endian order reassembles the flash bytes in order. (The
          5-7 byte asymmetric packings in the RDATA case aren't
          exercised by current tests — FAST_READ uses n_bytes in {4,16}.)

        Verified: JEDEC read (n_bytes=3) now returns [mfg, type, cap]
        (was [0x00, mfg, type] before this fix, which caused every
        mode_flip JEDEC assertion to fail).
        """
        if not 1 <= n_bytes <= 16:
            raise ValueError("n_bytes must be in [1, 16]")
        words = self.read_rdata_words()
        raw = b''.join(w.to_bytes(4, 'little') for w in words)
        if n_bytes < 4:
            return raw[4 - n_bytes:4]
        return raw[:n_bytes]

    # ---- flash operations -------------------------------------------------

    def write_enable(self):
        self.spi_cmd(OP_WREN)

    def write_disable(self):
        self.spi_cmd(OP_WRDI)

    def read_status(self):
        """Read flash status register. Returns the raw SR byte.

        Uses a 4-byte read (N_RW_BYTES=3). The flash returns SR
        continuously while CS is low, so all four received bytes are
        copies of SR. read_rdata(1) returns the first byte in flash
        order (LSB of RDATA0 after little-endian extract), which is SR.

        Rationale: short reads (N_RW<3) land data at RDATA0's MSB due
        to a different mux path, and the DATA_I exit-condition timing
        for single-byte reads has proved fragile in testing. N_RW=3
        exercises the same well-tested full-word DATA_I path as our
        FAST_READ calls, so we reuse that path rather than special-case.
        """
        self.spi_cmd(OP_RDSR, read=1, n_bytes=4)
        return self.read_rdata(1)[0]

    def jedec_id(self):
        """Return 24-bit JEDEC ID (manufacturer | type | density)."""
        self.spi_cmd(OP_RDID_SPI, read=1, n_bytes=3)
        raw = self.read_rdata(3)
        return (raw[0] << 16) | (raw[1] << 8) | raw[2]

    def wait_flash_idle(self, timeout=None):
        """Poll the flash status register until WIP clears."""
        deadline = time.monotonic() + (timeout if timeout is not None else self.timeout)
        while time.monotonic() < deadline:
            if not (self.read_status() & SR_WIP):
                return
        raise QspiTimeout("flash WIP did not clear")

    def sector_erase_64k(self, addr, timeout=None):
        """Erase one 64KB sector. Blocks until the flash reports idle."""
        self.write_enable()
        self.write_addr(addr)
        self.spi_cmd(OP_SECTOR_ERASE_64K, addr_en=1)
        self.wait_flash_idle(timeout if timeout is not None else 1.0)

    def page_program_chunk(self, addr, data_bytes):
        """Program up to 16 bytes at `addr`. Caller must keep within one page."""
        if (addr & 0xFF) + len(data_bytes) > PAGE_SIZE:
            raise ValueError("chunk crosses a 256B page boundary")
        self.write_enable()
        self.write_addr(addr)
        self.write_wdata(data_bytes)
        self.spi_cmd(OP_PAGE_PROGRAM, write=1, addr_en=1, n_bytes=len(data_bytes))
        self.wait_flash_idle()

    def page_program(self, addr, data_bytes):
        """Program an arbitrary-length buffer starting at `addr`.

        Splits the buffer into 16-byte controller-sized chunks and into 256-byte
        flash-page boundaries. Caller is responsible for the sector being
        already erased.
        """
        i = 0
        while i < len(data_bytes):
            page_off  = (addr + i) & 0xFF
            chunk_max = min(16, PAGE_SIZE - page_off, len(data_bytes) - i)
            self.page_program_chunk(addr + i, data_bytes[i:i+chunk_max])
            i += chunk_max

    def read_chunk(self, addr, n_bytes, dummy=8):
        """Read up to 16 bytes via APB FAST_READ (opcode 0x0B)."""
        if not 1 <= n_bytes <= 16:
            raise ValueError("n_bytes must be in [1, 16]")
        self.write_addr(addr)
        self.spi_cmd(OP_FAST_READ, read=1, addr_en=1, dummy=dummy, n_bytes=n_bytes)
        return self.read_rdata(n_bytes)

    def read_buffer(self, addr, n_bytes):
        """Read an arbitrary-length buffer starting at `addr` via APB."""
        out = bytearray()
        while len(out) < n_bytes:
            chunk = min(16, n_bytes - len(out))
            out.extend(self.read_chunk(addr + len(out), chunk))
        return bytes(out)

    # ---- AHB XiP path -----------------------------------------------------

    def cache_enable(self, timeout=5.0, verbose=True, skip_status_check=False):
        """Enable the ARM CG092 flash cache and poll until it reports ready.

        Follows the verif/cocotb/ahb_qspi_tests.py pattern — the poll loop
        reads both CFG and STATUS each iteration, matching what cocotb's
        passing AHB-XIP test does. Without this, the cache stays wedged
        in its transitional state and AHB reads hang the PS.
        """
        import logging
        log = logging.getLogger('stress.cache')
        pre_cfg    = self.apb.read(REG_CACHE_CONFIG)
        pre_status = self.apb.read(REG_CACHE_STATUS)
        if verbose:
            log.info("cache_enable pre: CFG=0x%08x STATUS=0x%08x", pre_cfg, pre_status)
        # Prime: read STATUS once (matches cocotb's init sequence), then
        # enable (bit 0), then read CFG back.
        self.apb.read(REG_CACHE_STATUS)
        self.apb.write(REG_CACHE_CONFIG, 0x1)
        self.apb.read(REG_CACHE_CONFIG)
        if skip_status_check:
            return self.apb.read(REG_CACHE_STATUS)
        deadline = time.monotonic() + timeout
        polls    = 0
        while time.monotonic() < deadline:
            polls += 1
            # Read CFG then STATUS each iteration, like the cocotb test
            cfg    = self.apb.read(REG_CACHE_CONFIG)
            status = self.apb.read(REG_CACHE_STATUS)
            if (status & CACHE_STATUS_READY_MASK) == CACHE_STATUS_READY_VAL:
                if verbose:
                    log.info("cache_enable ready after %d polls: CFG=0x%08x STATUS=0x%08x",
                             polls, cfg, status)
                return status
            if verbose and polls in (1, 10, 100, 1000):
                log.info("cache_enable poll %d: CFG=0x%08x STATUS=0x%08x "
                         "(want STATUS & 0x3 == 0x2)", polls, cfg, status)
            time.sleep(0.001)
        last_cfg    = self.apb.read(REG_CACHE_CONFIG)
        last_status = self.apb.read(REG_CACHE_STATUS)
        raise QspiTimeout(
            "cache did not become ready within %.2fs (CFG=0x%08x STATUS=0x%08x polls=%d)"
            % (timeout, last_cfg, last_status, polls))

    def cache_disable(self):
        """Quiesce the cache — writes CONFIG=0. Useful in teardown so a
        subsequent APB-only test doesn't leave the cache enabled."""
        self.apb.write(REG_CACHE_CONFIG, 0x0)

    def xip_setup(self, opcode=OP_FAST_READ, dummy=8, qio=0, no_cmd=0, enable_cache=True):
        """Configure the AHB XiP path. Sets CTRL.XIP_ACTIVE=1.

        `enable_cache=True` (default) turns on the CG092 flash cache for
        significantly faster re-reads. The earlier "cache stuck at CS=01
        Enabling" bug was actually a consequence of the APB bridge
        dropping PPROT[0]=0 writes and the AXI bridge never accepting
        single-cycle AHB errors — both fixed in the RTL + BD. With those
        in place, CCR.EN=1 reliably transitions to CS=10 Enabled and
        cached AHB reads work. Pass `enable_cache=False` to exercise the
        pass-through path explicitly.
        """
        self.apb.write(REG_AHB_SPI_SETUP, (opcode & 0xFF) | ((dummy & 0xF) << 12))
        self.set_ctrl(qio=qio, xip_active=1, no_cmd=no_cmd)
        if enable_cache:
            self.cache_enable(skip_status_check=True)

    def xip_disable(self):
        self.set_ctrl()
        self.cache_disable()
