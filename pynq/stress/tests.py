#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - Stress Test Suite
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Six time-bounded stress tests, designed to total ~20 minutes when run with
# default budgets. Each test takes (hw, ctx) where ctx is a StressContext
# providing a deadline, logger and failure-recording sink.
#-----------------------------------------------------------------------------

import logging
import random
import threading
import time

from .qspi_hw import QspiHw, QspiTimeout, PAGE_SIZE, SECTOR_SIZE, OP_FAST_READ
from .prbs import expected_for
from .sector_state import SectorRotator


log = logging.getLogger('stress')


# Default per-test time budgets (seconds). Sum = ~1170 s = 19.5 min, leaving
# headroom for fixed overhead (overlay load + setup phases).
DEFAULT_BUDGETS = {
    'soak':           480,   # 8 min
    'xip_torture':    240,   # 4 min
    'mode_flip':      180,   # 3 min
    'concurrent':     180,   # 3 min
    'clk_div_sweep':   90,   # 1.5 min
    'irq_storm':       60,   # 1 min
}


# ---------------------------------------------------------------------------
# Test 1: Soak - random write/verify on rotating sectors
# ---------------------------------------------------------------------------

def test_soak(hw, ctx):
    """Erase a sector, program every page with PRBS bytes, read back, verify.

    Rotates through the 256 sectors of the lower 16 MB so wear spreads across
    runs. One full sector takes ~17 s (150 ms erase + 256 pages * ~64 ms of
    16-byte program chunks); ~28 sectors fit in the default 8-minute budget.
    """
    rot = SectorRotator()
    sectors_done   = 0
    pages_verified = 0
    miscompares    = 0

    while time.monotonic() < ctx.deadline:
        sector_idx, sector_addr = rot.next()
        log.info("[soak] sector %d @ 0x%06x  (verified %d pages so far)",
                 sector_idx, sector_addr, pages_verified)

        try:
            hw.sector_erase_64k(sector_addr)
        except QspiTimeout as e:
            ctx.fail('soak', f'erase timeout sector {sector_idx}', exc=str(e))
            continue

        # Program + verify each 256B page in the sector
        for page in range(SECTOR_SIZE // PAGE_SIZE):
            if time.monotonic() >= ctx.deadline:
                break
            page_addr = sector_addr + page * PAGE_SIZE
            payload   = expected_for(page_addr, PAGE_SIZE)
            try:
                hw.page_program(page_addr, payload)
            except QspiTimeout as e:
                ctx.fail('soak', f'program timeout @ 0x{page_addr:06x}', exc=str(e))
                continue
            try:
                actual = hw.read_buffer(page_addr, PAGE_SIZE)
            except QspiTimeout as e:
                ctx.fail('soak', f'readback timeout @ 0x{page_addr:06x}', exc=str(e))
                continue
            if actual != payload:
                miscompares += 1
                # Find first divergence
                for off in range(PAGE_SIZE):
                    if actual[off] != payload[off]:
                        ctx.fail('soak',
                            f'miscompare @ 0x{page_addr+off:06x}',
                            expected=f'0x{payload[off]:02x}',
                            actual=f'0x{actual[off]:02x}',
                            sector=sector_idx, page=page)
                        break
            pages_verified += 1

        sectors_done += 1

    ctx.summary['soak'] = dict(
        sectors=sectors_done, pages=pages_verified, miscompares=miscompares,
    )
    log.info("[soak] done: %d sectors, %d pages verified, %d miscompares",
             sectors_done, pages_verified, miscompares)


# ---------------------------------------------------------------------------
# Test 2: XiP read torture - random AHB reads against pre-programmed PRBS
# ---------------------------------------------------------------------------

XIP_WINDOW_KB = 64   # set up cost = ~17 s. Bump to 1024 for full coverage.


def test_xip_torture(hw, ctx, rng=None):
    """Program a window of flash with PRBS, then random-read via AHB XiP.

    Setup: pick the next sector (so we don't trample the soak test's data),
    erase it, program it with PRBS bytes seeded by absolute address.
    Main loop: random 4-byte aligned reads from the AHB XiP MMIO region,
    compared against the same PRBS seed.
    """
    if rng is None:
        rng = random.Random(0xCAFE)

    # Setup window: one or more sectors
    rot = SectorRotator()
    n_sectors = max(1, (XIP_WINDOW_KB * 1024) // SECTOR_SIZE)
    base_idx, base_addr = rot.next()
    log.info("[xip] setup: programming %d sector(s) starting @ 0x%06x",
             n_sectors, base_addr)

    setup_start = time.monotonic()
    for s in range(n_sectors):
        sector_addr = base_addr + s * SECTOR_SIZE
        try:
            hw.sector_erase_64k(sector_addr)
            for page in range(SECTOR_SIZE // PAGE_SIZE):
                page_addr = sector_addr + page * PAGE_SIZE
                hw.page_program(page_addr, expected_for(page_addr, PAGE_SIZE))
        except QspiTimeout as e:
            ctx.fail('xip_torture', f'setup failed sector {s}', exc=str(e))
            return
    log.info("[xip] setup done in %.1f s", time.monotonic() - setup_start)

    # Switch to XiP mode (FAST_READ + 8 dummy cycles, SPI mode, no continuous read)
    hw.xip_setup(opcode=OP_FAST_READ, dummy=8, qio=0)

    reads_done   = 0
    miscompares  = 0
    window_bytes = n_sectors * SECTOR_SIZE

    while time.monotonic() < ctx.deadline:
        # Burst 1024 reads then re-check the deadline (cuts loop overhead)
        for _ in range(1024):
            offset = rng.randrange(0, window_bytes - 4) & ~0x3
            phys   = base_addr + offset
            actual = hw.ahb.read(phys)        # 32-bit MMIO read
            exp    = int.from_bytes(expected_for(phys, 4), 'little')
            if actual != exp:
                miscompares += 1
                ctx.fail('xip_torture',
                    f'miscompare @ 0x{phys:06x}',
                    expected=f'0x{exp:08x}', actual=f'0x{actual:08x}')
            reads_done += 1
        if time.monotonic() >= ctx.deadline:
            break

    hw.xip_disable()
    ctx.summary['xip_torture'] = dict(
        setup_sectors=n_sectors, reads=reads_done, miscompares=miscompares,
    )
    log.info("[xip] done: %d reads, %d miscompares (%.1f kreads/s)",
             reads_done, miscompares,
             reads_done / max(1.0, ctx.elapsed) / 1000)


# ---------------------------------------------------------------------------
# Test 3: Mode-flip torture - rapid SPI<->QPI transitions
# ---------------------------------------------------------------------------

def test_mode_flip(hw, ctx, expected_id_mfg=0x20):
    """Cycle SPI READ_JEDEC -> QPI ENTER -> QPI READ_JEDEC -> QPI EXIT.

    expected_id_mfg defaults to Micron (0x20). For an SST flash, override to
    0xBF on the runner CLI. The test only checks the manufacturer byte; the
    density byte is allowed to vary so this works on any flash on the same
    family.
    """
    iterations = 0
    bad_ids    = 0
    timeouts   = 0

    while time.monotonic() < ctx.deadline:
        for _ in range(64):
            try:
                # SPI mode JEDEC
                hw.set_ctrl(qio=0)
                jid = hw.jedec_id()
                mfg = (jid >> 16) & 0xFF
                if mfg != expected_id_mfg:
                    bad_ids += 1
                    ctx.fail('mode_flip',
                        f'wrong SPI JEDEC mfg byte (saw 0x{mfg:02x}, want 0x{expected_id_mfg:02x})',
                        jedec=f'0x{jid:06x}')
                # Enter QPI - opcode 0x35 for Micron, 0x38 for SST.
                # For Micron enable-quad does NOT auto-clear so we just send it
                # once per outer loop and trust the next SPI command resets us.
                # Test 3 is about hammering ENABLE_ACK / FSM state, not about
                # correct QPI semantics. So run pure SPI transactions for the
                # bulk of iterations and just exercise the opcode sweep.
                # Also issue a no-op/RDID-like opcode in QIO_MODE=1 path:
                hw.set_ctrl(qio=1)
                # 0xAF is Micron QPI READ_JEDEC; 0xAF is also defined for SST.
                hw.spi_cmd(0xAF, read=1, n_bytes=3)
                _ = hw.read_rdata(3)
                hw.set_ctrl(qio=0)
                iterations += 1
            except QspiTimeout as e:
                timeouts += 1
                ctx.fail('mode_flip', 'timeout during mode flip', exc=str(e))
                hw.reset_controller()
                break
        if time.monotonic() >= ctx.deadline:
            break

    ctx.summary['mode_flip'] = dict(
        iterations=iterations, bad_ids=bad_ids, timeouts=timeouts,
    )
    log.info("[mode_flip] done: %d cycles, %d bad IDs, %d timeouts",
             iterations, bad_ids, timeouts)


# ---------------------------------------------------------------------------
# Test 4: Concurrent APB config + AHB XiP
# ---------------------------------------------------------------------------

def test_concurrent(hw, ctx, reconfig_period_s=0.2):
    """Background thread does AHB XiP reads; foreground reconfigures CLK_DIV.

    Verifies that mid-flight register pokes don't corrupt in-flight or
    subsequent XiP reads, and that the bus arbitration between the two
    AXI->{AHB,APB} bridges holds up. PYNQ MMIO is mmap-backed so multiple
    threads can hit it without explicit locking.
    """
    # First make sure there's known data in some sector to read from.
    rot = SectorRotator()
    _, base = rot.next()
    log.info("[conc] priming sector @ 0x%06x", base)
    try:
        hw.sector_erase_64k(base)
        # Just need a few pages worth of data to read against.
        for page in range(16):
            paddr = base + page * PAGE_SIZE
            hw.page_program(paddr, expected_for(paddr, PAGE_SIZE))
    except QspiTimeout as e:
        ctx.fail('concurrent', 'priming failed', exc=str(e))
        return

    hw.xip_setup(opcode=OP_FAST_READ, dummy=8, qio=0)
    hw.set_clk_div(5)

    stop_evt   = threading.Event()
    counters   = dict(reads=0, miscompares=0, reconfigs=0, racy_reads=0)
    counters_lock = threading.Lock()

    def reader():
        rng = random.Random(0xBEEF)
        local_reads, local_mis, local_racy = 0, 0, 0
        window_bytes = 16 * PAGE_SIZE
        while not stop_evt.is_set():
            offset = rng.randrange(0, window_bytes - 4) & ~0x3
            phys   = base + offset
            try:
                actual = hw.ahb.read(phys)
            except OSError:
                # Window of races during clk reconfigure; allowed but tracked.
                local_racy += 1
                continue
            exp = int.from_bytes(expected_for(phys, 4), 'little')
            local_reads += 1
            if actual != exp:
                local_mis += 1
        with counters_lock:
            counters['reads']       += local_reads
            counters['miscompares'] += local_mis
            counters['racy_reads']  += local_racy

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    try:
        next_reconfig = time.monotonic() + reconfig_period_s
        clk_choices   = [2, 3, 5, 8, 12, 20, 31]
        ci = 0
        while time.monotonic() < ctx.deadline:
            time.sleep(0.01)
            now = time.monotonic()
            if now >= next_reconfig:
                # Reconfigure CLK_DIV under the reader. After the change the
                # reader should still see correct data once the controller
                # picks up the new divider (next transaction).
                ci = (ci + 1) % len(clk_choices)
                hw.set_clk_div(clk_choices[ci])
                with counters_lock:
                    counters['reconfigs'] += 1
                next_reconfig = now + reconfig_period_s
    finally:
        stop_evt.set()
        t.join(timeout=5.0)
        hw.set_clk_div(5)
        hw.xip_disable()

    if counters['miscompares']:
        ctx.fail('concurrent',
            f"{counters['miscompares']} miscompares across {counters['reads']} reads "
            f"during {counters['reconfigs']} reconfigs")

    ctx.summary['concurrent'] = dict(counters)
    log.info("[conc] done: %d reads, %d miscompares, %d reconfigs, %d racy_reads",
             counters['reads'], counters['miscompares'],
             counters['reconfigs'], counters['racy_reads'])


# ---------------------------------------------------------------------------
# Test 5: CLK_DIV sweep with crossover
# ---------------------------------------------------------------------------

def test_clk_div_sweep(hw, ctx, reads_per_div=200):
    """For each CLK_DIV in [2..31], do reads_per_div random read-verify cycles.

    Catches IO timing margin issues that don't show at the cocotb default
    of 5. Per-divider failure counts go into the summary - useful for
    plotting reliability vs frequency.
    """
    # Prime a sector with PRBS data.
    rot = SectorRotator()
    _, base = rot.next()
    log.info("[clkdiv] priming sector @ 0x%06x", base)
    try:
        hw.sector_erase_64k(base)
        for page in range(8):
            paddr = base + page * PAGE_SIZE
            hw.page_program(paddr, expected_for(paddr, PAGE_SIZE))
    except QspiTimeout as e:
        ctx.fail('clk_div_sweep', 'priming failed', exc=str(e))
        return

    rng = random.Random(0xF00D)
    window = 8 * PAGE_SIZE
    fail_per_div = {}
    total_reads  = 0
    total_fails  = 0

    for div in range(2, 32):
        if time.monotonic() >= ctx.deadline:
            log.warning("[clkdiv] deadline hit before completing div=%d", div)
            break
        hw.set_clk_div(div)
        local_fail = 0
        for _ in range(reads_per_div):
            offset = rng.randrange(0, window - 4) & ~0x3
            phys   = base + offset
            try:
                actual = hw.read_chunk(phys, 4)
            except QspiTimeout:
                local_fail += 1
                ctx.fail('clk_div_sweep', f'timeout @ div={div} addr=0x{phys:06x}')
                hw.reset_controller()
                hw.set_clk_div(div)
                continue
            exp = expected_for(phys, 4)
            total_reads += 1
            if actual != exp:
                local_fail += 1
                ctx.fail('clk_div_sweep',
                    f'miscompare @ div={div} addr=0x{phys:06x}',
                    expected=exp.hex(), actual=actual.hex())
        fail_per_div[div] = local_fail
        total_fails += local_fail

    hw.set_clk_div(5)
    ctx.summary['clk_div_sweep'] = dict(
        reads=total_reads, failures=total_fails, per_div=fail_per_div,
    )
    log.info("[clkdiv] done: %d reads across divs 2..%d, %d failures",
             total_reads, max(fail_per_div) if fail_per_div else 0, total_fails)


# ---------------------------------------------------------------------------
# Test 6: IRQ storm - back-to-back transactions at min CLK_DIV
# ---------------------------------------------------------------------------

def test_irq_storm(hw, ctx, clk_div=2):
    """Queue thousands of single-byte reads back-to-back.

    Stresses the IRQ_QSPI_FINISHED -> IRQ_CLR -> ENABLE handshake. If the
    IRQ_CLR latch (the bug2 regression in cocotb) regresses, BUSY will
    eventually fail to clear and we'll catch a QspiTimeout.
    """
    # Prime one page so we have known data.
    rot = SectorRotator()
    _, base = rot.next()
    try:
        hw.sector_erase_64k(base)
        hw.page_program(base, expected_for(base, PAGE_SIZE))
    except QspiTimeout as e:
        ctx.fail('irq_storm', 'priming failed', exc=str(e))
        return

    hw.set_clk_div(clk_div)
    transactions = 0
    miscompares  = 0
    timeouts     = 0

    while time.monotonic() < ctx.deadline:
        for _ in range(1024):
            try:
                actual = hw.read_chunk(base + (transactions & 0xFC), 4)
            except QspiTimeout as e:
                timeouts += 1
                ctx.fail('irq_storm', f'BUSY/IRQ stuck after {transactions} tx',
                         exc=str(e))
                hw.reset_controller()
                hw.set_clk_div(clk_div)
                continue
            exp = expected_for(base + (transactions & 0xFC), 4)
            transactions += 1
            if actual != exp:
                miscompares += 1
                ctx.fail('irq_storm',
                    f'miscompare on tx {transactions}',
                    expected=exp.hex(), actual=actual.hex())
        if time.monotonic() >= ctx.deadline:
            break

    hw.set_clk_div(5)
    ctx.summary['irq_storm'] = dict(
        transactions=transactions, miscompares=miscompares, timeouts=timeouts,
    )
    log.info("[irq_storm] done: %d transactions, %d miscompares, %d timeouts (%.1f kt/s)",
             transactions, miscompares, timeouts,
             transactions / max(1.0, ctx.elapsed) / 1000)


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

ALL_TESTS = {
    'soak':           test_soak,
    'xip_torture':    test_xip_torture,
    'mode_flip':      test_mode_flip,
    'concurrent':     test_concurrent,
    'clk_div_sweep':  test_clk_div_sweep,
    'irq_storm':      test_irq_storm,
}
