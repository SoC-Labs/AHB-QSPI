"""A1 assessment tests on the standalone core (tb_a1_core.v).

Independent assessor A1, 13 Oct 2026. Questions (see the assessment brief):
  Q1/Q2  CDC fix: enable/BUSY handshakes, ordering, frame counts, XiP-mode
         switching, reset mid-transfer, CLK_DIV sweep.
  Q3     H-PIPE: an address phase accepted on the cycle the FSM leaves
         WAIT_READ or ERR2.
  Q4     AHB-Lite slave protocol (AhbChecker runs on EVERY test).

Every test runs unchanged on the base (master 71f8d1c) and the candidate
(703c7c4); the RTL is selected by RTL_DIR in the Makefile.
"""

import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.utils import get_sim_time
from cocotb.triggers import (ClockCycles, Edge, FallingEdge, ReadOnly,
                             RisingEdge, Timer)

from a1_ahb import (HT_BUSY, HT_IDLE, HT_NONSEQ, HT_SEQ, AhbChecker,
                    AhbMaster, Apb, Beat, QspiPinMonitor, idle_beat, _int)

# --------------------------------------------------------------------------
# constants
# --------------------------------------------------------------------------
REG_CTRL, REG_STATUS, REG_CMD, REG_ADDR = 0x00, 0x04, 0x08, 0x0C
REG_RDATA0, REG_AHB_SETUP, REG_CLKDIV = 0x10, 0x30, 0x34
XIP_ACTIVE = 1 << 8

REGION = 0x010000          # preloaded flash region (outside the parameter
REGION_LEN = 0x2000        # blocks at the bottom/top of the array)
SEED = int(os.environ.get("A1_SEED", "20261013"))
N_RAND = int(os.environ.get("A1_NRAND", "400"))


class Env:
    def __init__(self, dut):
        self.dut = dut
        self.log = dut._log
        self.mem = {}
        self.chk = None

    # ---- bring-up ----
    async def start(self, clk_div=1, preload=True):
        d = self.dut
        d.HRESETn.value = 0
        d.FLASH_LOAD.value = 0
        d.DFLT_WAIT.value = 0
        cocotb.start_soon(Clock(d.HCLK, 10, unit="ns").start())
        self.ahb = AhbMaster(d)
        self.apb = Apb(d)
        self.chk = AhbChecker(d, self.log).start()
        self.probes = HandshakeProbes(d, self.log).start()
        await ClockCycles(d.HCLK, 20)
        await FallingEdge(d.HCLK)
        d.HRESETn.value = 1
        await ClockCycles(d.HCLK, 10)
        if preload:
            await self.preload()
        await self.xip_on(clk_div)

    async def preload(self):
        rnd = random.Random(SEED)
        data = [rnd.randrange(256) for _ in range(REGION_LEN)]
        with open("a1_flash.hex", "w") as f:
            f.write(f"@{REGION:x}\n")
            for i, b in enumerate(data):
                f.write(f"{b:02x}\n")
                self.mem[REGION + i] = b
        self.dut.FLASH_LOAD.value = 1
        await Timer(1, "ns")
        self.dut.FLASH_LOAD.value = 0

    async def xip_on(self, clk_div=1, opcode=0x0B, dummy=8):
        await self.apb.write(REG_CLKDIV, clk_div)
        await self.apb.write(REG_AHB_SETUP, (dummy << 12) | opcode)
        await self.apb.write(REG_CTRL, XIP_ACTIVE)

    async def xip_off(self):
        await self.apb.write(REG_CTRL, 0)

    async def hard_reset(self, cycles=5):
        d = self.dut
        await FallingEdge(d.HCLK)
        d.HRESETn.value = 0
        await ClockCycles(d.HCLK, cycles)
        await FallingEdge(d.HCLK)
        d.HRESETn.value = 1
        await ClockCycles(d.HCLK, 5)

    # ---- reference model ----
    def line(self, addr):
        base = addr & ~0xF
        v = 0
        for i in range(16):
            v |= self.mem[base + i] << (8 * i)
        return v

    def lane(self, addr):
        return (self.line(addr) >> (32 * ((addr >> 2) & 3))) & 0xFFFFFFFF

    def score(self, comps, expect_err=None, label=""):
        """Check checker completions against the reference memory.
        expect_err(c) -> True if the transfer must ERROR. Returns a list of
        mismatch strings."""
        bad = []
        for c in comps:
            must_err = expect_err(c) if expect_err else bool(c.write)
            if must_err:
                if c.resp != 1:
                    bad.append(f"{label}{c!r}: expected ERROR, got OKAY"
                               + (" (WRITE silently accepted)" if c.write
                                  else ""))
                continue
            if c.resp != 0:
                bad.append(f"{label}{c!r}: expected OKAY, got ERROR")
                continue
            exp = self.lane(c.addr)
            got = None if c.rdata is None else \
                (c.rdata >> (32 * ((c.addr >> 2) & 3))) & 0xFFFFFFFF
            if got != exp:
                who = self.who_owns(c.rdata)
                bad.append(f"{label}{c!r}: HRDATA lane 0x{got if got is not None else -1:08x}"
                           f" != ref 0x{exp:08x} (returned line = {who})")
        return bad

    def who_owns(self, line):
        if line is None:
            return "X"
        hits = [a for a in range(REGION, REGION + REGION_LEN, 16)
                if self.line(a) == line]
        return ",".join(f"0x{a:06x}" for a in hits) or "no line in region"

    async def xip_read_isolated(self, addr):
        n0 = len(self.chk.completions)
        await self.ahb.run([Beat(1, HT_NONSEQ, addr, 0, 2)])
        return self.chk.completions[n0:]


class HandshakeProbes:
    """Q1 ordering invariants, sampled every HCLK on internal nets.

    H1 (AHB sink): when the interface first sees the synchronised
        acknowledge (ack_sync=1 while qspi_started=0 in WAIT_READ), the
        synchronised BUSY must already be 1. Otherwise `started` would be set
        with BUSY low and the very next cycle would capture HRDATA before the
        transfer ran (stale data).
    H2 (APB sink): whenever qspi_enable_ack_sync=1, qspi_busy_sync=1 (the
        software sequence 'ENABLE auto-clears, then poll BUSY=0' relies on
        BUSY being up before ENABLE clears).
    Also records SCLK-domain source transitions of the four crossing nets to
    detect zero-width/same-timestep glitches (G1)."""

    def __init__(self, dut, log):
        self.dut, self.log = dut, log
        self.h1 = []
        self.h2 = []
        self.glitch = []
        self.enable = True

    def start(self):
        cocotb.start_soon(self._run())
        for n in ("QSPI_ENABLE_ACK", "AHB_QSPI_ENABLE_ACK", "AHB_QSPI_BUSY",
                  "APB_QSPI_BUSY", "APB_QSPI_ENABLE_ACK"):
            cocotb.start_soon(self._glitch(n))
        return self

    async def _glitch(self, name):
        sig = getattr(self.dut, name)
        last_t = None
        while True:
            await Edge(sig)
            t = get_sim_time("ps")
            if last_t is not None and t == last_t and _int(self.dut.HRESETn) == 1:
                self.glitch.append((name, t))
            last_t = t

    async def _run(self):
        d = self.dut
        w = d.u_ahb_qspi_interface
        r = d.u_apb_qspi_regs
        while True:
            await RisingEdge(d.HCLK)
            await ReadOnly()
            if not self.enable or _int(d.HRESETn) != 1:
                continue
            st = _int(w.current_state)
            if (st == 1 and _int(w.ahb_qspi_enable_ack_sync) == 1
                    and _int(w.qspi_started) == 0
                    and _int(w.ahb_qspi_busy_sync) != 1):
                self.h1.append(get_sim_time("ns"))
            if (_int(r.qspi_enable_ack_sync) == 1
                    and _int(r.qspi_busy_sync) != 1):
                self.h2.append(get_sim_time("ns"))

    def assert_clean(self, glitch=False):
        msg = []
        if self.h1:
            msg.append(f"H1 AHB ack_sync before busy_sync at {self.h1[:5]} ns")
        if self.h2:
            msg.append(f"H2 APB ack_sync with busy_sync=0 at {self.h2[:5]} ns")
        if glitch and self.glitch:
            msg.append(f"G1 same-timestep double transitions {self.glitch[:5]}")
        if self.glitch:
            self.log.warning("G1 same-timestep double transitions on CDC "
                             "source nets: %d, first %s", len(self.glitch),
                             self.glitch[:5])
        assert not msg, "; ".join(msg)


async def finish(env, bad=None, glitch=False):
    if bad:
        for b in bad[:40]:
            env.log.error(b)
        raise AssertionError(f"{len(bad)} scoreboard mismatches; first: {bad[0]}")
    env.chk.check_drained()
    env.probes.assert_clean(glitch=glitch)


def addr_in_line(line_idx, word=0):
    return REGION + 16 * line_idx + 4 * word


# ==========================================================================
# Sanity: isolated reads (IDLE between transfers) must be correct, so any
# failure in the back-to-back tests is the back-to-back issue, not the TB.
# ==========================================================================
@cocotb.test()
async def a1_00_isolated_reads(dut):
    env = Env(dut)
    await env.start(clk_div=1)
    bad = []
    rnd = random.Random(SEED + 1)
    for div in (1, 2, 3, 5):
        await env.apb.write(REG_CLKDIV, div)
        for _ in range(6):
            a = REGION + 4 * rnd.randrange(REGION_LEN // 4)
            comps = await env.xip_read_isolated(a)
            assert len(comps) == 1, comps
            bad += env.score(comps, label=f"div{div} ")
    await finish(env, bad)


# ==========================================================================
# Q3  H-PIPE directed: address phase accepted on the exact cycle the FSM
# leaves WAIT_READ (read->read, read->write) or ERR2 (error->read).
# The AHB master issues back-to-back with zero gap, so the next address phase
# is on the bus throughout the previous data phase and is accepted on the
# completion edge (FSM WAIT_READ->IDLE or ERR2->IDLE).
# ==========================================================================
async def _q3_case(env, beats, label, expect_err=None):
    n0 = len(env.chk.completions)
    await env.ahb.run(beats)
    comps = env.chk.completions[n0:]
    exp_n = sum(1 for b in beats if b.sel and b.is_xfer())
    bad = []
    if len(comps) != exp_n:
        bad.append(f"{label}: {exp_n} transfers issued, {len(comps)} completed")
    bad += env.score(comps, expect_err=expect_err, label=f"{label}: ")
    for c in comps:
        env.log.info("  %s %r data=%s", label, c,
                     "X" if c.rdata is None else f"{c.rdata:032x}")
    return bad


def _R(a, tag="", late=False):
    return Beat(1, HT_NONSEQ, a, 0, 2, tag=tag, late=late)


def _W(a, d=0x11223344, tag="", late=False):
    return Beat(1, HT_NONSEQ, a, 1, 2, wdata=d, tag=tag, late=late)


@cocotb.test()
async def a1_q3_late_address_phase(dut):
    """Like read->read / read->write / error->read, but the master keeps IDLE
    on the bus during the wait and switches to NONSEQ only in the completion
    cycle: the address phase exists ONLY on the edge where the FSM leaves
    WAIT_READ / ERR2."""
    env = Env(dut)
    await env.start(clk_div=1)
    bad = []
    for div in (1, 2):
        await env.apb.write(REG_CLKDIV, div)
        bad += await _q3_case(env, [_R(addr_in_line(40)), _R(addr_in_line(44, 1), late=True)],
                              f"div{div} late-RR")
        bad += await _q3_case(env, [_R(addr_in_line(41)), _W(addr_in_line(45), late=True)],
                              f"div{div} late-RW")
        bad += await _q3_case(env, [_W(addr_in_line(42)), _R(addr_in_line(46, 3), late=True)],
                              f"div{div} late-ER")
    await finish(env, bad)


@cocotb.test()
async def a1_q1_cdc_source_glitch_scan(dut):
    """G1: the five SCLK->HCLK/PCLK crossing source nets must never change
    twice in one simulation timestep (a zero-time decode glitch), under APB
    and XiP traffic across CLK_DIV. A delta-cycle glitch in zero-delay RTL
    sim is the visible trace of a combinational source."""
    env = Env(dut)
    await env.start(clk_div=1)
    rnd = random.Random(SEED + 9)
    for div in (1, 2, 3, 5):
        await env.xip_on(div)
        for _ in range(3):
            await env.xip_read_isolated(REGION + 4 * rnd.randrange(REGION_LEN // 4))
        await env.xip_off()
        await env.apb.write(REG_ADDR, REGION)
        await apb_cmd(env, _spi_read_word())
        await apb_cmd(env, 0x06)
    await env.xip_on(1)
    await finish(env, [], glitch=True)


@cocotb.test()
async def a1_q3_read_read(dut):
    """read->read back-to-back, different lines (stale data detectable)."""
    env = Env(dut)
    await env.start(clk_div=1)
    bad = []
    for div in (1, 2, 3):
        await env.apb.write(REG_CLKDIV, div)
        bad += await _q3_case(env, [_R(addr_in_line(1, 0)), _R(addr_in_line(7, 1))],
                              f"div{div} RR")
        bad += await _q3_case(env, [_R(addr_in_line(9, 2)), _R(addr_in_line(9, 3))],
                              f"div{div} RR-same-line")
    await finish(env, bad)


@cocotb.test()
async def a1_q3_read_read_stream(dut):
    """A stream of 6 back-to-back reads to distinct lines."""
    env = Env(dut)
    await env.start(clk_div=1)
    seq = [_R(addr_in_line(i * 5 + 3, i % 4)) for i in range(6)]
    bad = await _q3_case(env, seq, "stream6")
    await finish(env, bad)


@cocotb.test()
async def a1_q3_read_write(dut):
    """read->write back-to-back. Writes to the XiP port must ERROR."""
    env = Env(dut)
    await env.start(clk_div=1)
    bad = await _q3_case(env, [_R(addr_in_line(2)), _W(addr_in_line(4))], "RW")
    bad += await _q3_case(env, [_R(addr_in_line(2)), _W(addr_in_line(4)),
                                _R(addr_in_line(6))], "RWR")
    await finish(env, bad)


@cocotb.test()
async def a1_q3_error_read(dut):
    """error->read: a write (ERROR) followed back-to-back by a read, so the
    read's address phase is accepted on the ERR2 completion edge."""
    env = Env(dut)
    await env.start(clk_div=1)
    bad = await _q3_case(env, [_W(addr_in_line(3)), _R(addr_in_line(11, 1))], "ER")
    bad += await _q3_case(env, [_W(addr_in_line(3)), _R(addr_in_line(11, 1)),
                                _R(addr_in_line(13, 2))], "ERR")
    await finish(env, bad)


@cocotb.test()
async def a1_q3_error_read_xip_off(dut):
    """With XIP_ACTIVE=0 every transfer must ERROR; back-to-back reads give
    error->error. Then XiP on and error(write)->read."""
    env = Env(dut)
    await env.start(clk_div=1)
    await env.xip_off()
    bad = await _q3_case(env, [_R(addr_in_line(1)), _R(addr_in_line(2))],
                         "xipoff-RR", expect_err=lambda c: True)
    await env.xip_on(1)
    await finish(env, bad)


@cocotb.test()
async def a1_q3_read_then_other_slave(dut):
    """read followed back-to-back by a transfer to ANOTHER slave (HSEL=0),
    with and without wait states from that slave, then a read."""
    env = Env(dut)
    await env.start(clk_div=1)
    bad = []
    for w in (0, 3):
        dut.DFLT_WAIT.value = w
        seq = [_R(addr_in_line(5)), Beat(0, HT_NONSEQ, 0x3F0000, 0, 2),
               _R(addr_in_line(8, 3))]
        bad += await _q3_case(env, seq, f"R-other(w{w})-R")
    dut.DFLT_WAIT.value = 0
    await finish(env, bad)


# ==========================================================================
# Q3  randomized zero-wait back-to-back stress with reference memory
# ==========================================================================
def _rand_beats(rnd, n, p_write=0.1, p_idle=0.15, p_other=0.1, p_burst=0.15):
    beats = []
    while len(beats) < n:
        r = rnd.random()
        a = REGION + 4 * rnd.randrange(REGION_LEN // 4)
        if r < p_write:
            beats.append(_W(a, rnd.getrandbits(32)))
        elif r < p_write + p_idle:
            beats.append(idle_beat(sel=rnd.randrange(2)))
        elif r < p_write + p_idle + p_other:
            beats.append(Beat(0, HT_NONSEQ, 0x3F0000, rnd.randrange(2), 2))
        elif r < p_write + p_idle + p_other + p_burst:
            # INCR burst of words with BUSY beats inside
            a &= ~0x3F
            beats.append(Beat(1, HT_NONSEQ, a, 0, 2, burst=1))
            for k in range(1, rnd.randrange(2, 6)):
                if rnd.random() < 0.4:
                    beats.append(Beat(1, HT_BUSY, a + 4 * k, 0, 2, burst=1))
                beats.append(Beat(1, HT_SEQ, a + 4 * k, 0, 2, burst=1))
        else:
            beats.append(_R(a))
    return beats


async def _stress(dut, p_other, seed_off, label):
    env = Env(dut)
    await env.start(clk_div=1)
    env.ahb.max_wait = 6000      # > a div-4 fetch (~1400 HCLK)
    rnd = random.Random(SEED + seed_off)
    bad = []
    total = 0
    hangs = 0
    for div in (1, 2, 4):
        await env.apb.write(REG_CLKDIV, div)
        for chunk in range(4):
            dut.DFLT_WAIT.value = rnd.randrange(4)
            beats = _rand_beats(rnd, N_RAND // 12, p_other=p_other)
            n0 = len(env.chk.completions)
            try:
                await env.ahb.run(beats)
            except AssertionError as e:
                # bus hang: record it, reset, carry on with the next chunk
                hangs += 1
                bad.append(f"div{div}/c{chunk} BUS HANG: {e}")
                env.ahb._drive(idle_beat())
                await env.hard_reset()
                env.chk.completions.clear()
                env.chk.accepted = 0
                await env.xip_on(div)
                continue
            comps = env.chk.completions[n0:]
            total += len(comps)
            bad += env.score(comps, label=f"div{div}/c{chunk} ")
    stale = sum(1 for b in bad if "HRDATA lane" in b)
    werr = sum(1 for b in bad if "expected ERROR" in b)
    env.log.info("%s: %d slave transfers checked; %d wrong-data reads, "
                 "%d writes/errored-reads completed OKAY, %d bus hangs",
                 label, total, stale, werr, hangs)
    await finish(env, bad)


@cocotb.test()
async def a1_q3_random_b2b_stress(dut):
    """Random zero-wait back-to-back AHB-Lite traffic, including transfers to
    another slave (HSEL=0) with 0-3 wait states, INCR bursts with BUSY,
    IDLEs and writes; reference-memory scoreboard."""
    await _stress(dut, 0.1, 7, "random stress (with other-slave beats)")


@cocotb.test()
async def a1_q3_random_b2b_stress_qspi_only(dut):
    """As a1_q3_random_b2b_stress but every NONSEQ/SEQ targets the QSPI
    slave (no other-slave beats), to count wrong-data events without bus
    hangs."""
    await _stress(dut, 0.0, 8, "random stress (QSPI only)")


@cocotb.test()
async def a1_q3_read_read_then_other_slave(dut):
    """read A, read B back-to-back, then a NONSEQ to ANOTHER slave. B's
    address phase is accepted as the FSM leaves WAIT_READ; the next address
    phase the FSM sees is not for it. All three must complete."""
    env = Env(dut)
    await env.start(clk_div=1)
    env.ahb.max_wait = 6000
    bad = []
    seq = [_R(addr_in_line(50)), _R(addr_in_line(52, 1)),
           Beat(0, HT_NONSEQ, 0x3F0000, 0, 2), idle_beat()]
    try:
        bad += await _q3_case(env, seq, "RR-other")
    except AssertionError as e:
        bad.append(f"RR-other BUS HANG: {e}")
    await finish(env, bad)


@cocotb.test()
async def a1_q3_random_isolated_control(dut):
    """Control for the stress test: the SAME random reads, but with an IDLE
    after each one (no back-to-back). Must pass on a correct TB."""
    env = Env(dut)
    await env.start(clk_div=1)
    rnd = random.Random(SEED + 7)
    beats = [b for b in _rand_beats(rnd, N_RAND // 12) if b.sel and b.is_xfer()
             and b.trans == HT_NONSEQ]
    spaced = []
    for b in beats:
        spaced += [b, idle_beat(), idle_beat()]
    n0 = len(env.chk.completions)
    # one beat at a time, so no address phase overlaps a data phase
    for b in beats:
        await env.ahb.run([b])
    bad = env.score(env.chk.completions[n0:], label="isolated ")
    await finish(env, bad)


# ==========================================================================
# Q4  protocol: IDLE/BUSY zero-wait OKAY, 2-cycle ERROR (checker), and the
# slave must ignore an address phase while HREADY=0 (another slave waiting).
# ==========================================================================
@cocotb.test()
async def a1_q4_idle_busy_zero_wait(dut):
    env = Env(dut)
    await env.start(clk_div=1)
    seq = [idle_beat(sel=1), idle_beat(sel=1), _R(addr_in_line(1)),
           Beat(1, HT_NONSEQ, addr_in_line(2), 0, 2, burst=1),
           Beat(1, HT_BUSY, addr_in_line(2) + 4, 0, 2, burst=1),
           Beat(1, HT_BUSY, addr_in_line(2) + 4, 0, 2, burst=1),
           Beat(1, HT_SEQ, addr_in_line(2) + 4, 0, 2, burst=1),
           idle_beat(sel=1)]
    bad = await _q3_case(env, seq, "idle/busy")
    await finish(env, bad)


@cocotb.test()
async def a1_q4_addr_phase_during_other_slave_wait(dut):
    """Another slave inserts wait states; meanwhile the master presents a read
    to the QSPI slave (not yet accepted: HREADY=0). The read must still
    return its own data exactly once."""
    env = Env(dut)
    await env.start(clk_div=1)
    bad = []
    for w in (2, 9, 15, 700, 1000):
        dut.DFLT_WAIT.value = w
        seq = [Beat(0, HT_NONSEQ, 0x3F0000, 0, 2), _R(addr_in_line(20, 2)),
               Beat(0, HT_NONSEQ, 0x3F0000, 0, 2), _R(addr_in_line(21, 1))]
        bad += await _q3_case(env, seq, f"other-wait{w}")
    dut.DFLT_WAIT.value = 0
    await finish(env, bad)


# ==========================================================================
# Q1/Q2  handshakes: APB commands (frame + SCLK counts), APB read data with
# the driver's BUSY-set/BUSY-clear sequence, CLK_DIV sweep.
# ==========================================================================
async def apb_cmd(env, word, poll="driver", timeout=200000):
    """Two-write strobe like sw/qspi_driver.c, then wait. Returns status."""
    apb = env.apb
    await apb.write(REG_CMD, word & ~0x100)
    await apb.write(REG_CMD, word | 0x100)
    if poll == "driver":
        # qspi_wait_idle(): BUSY set first (bounded), then BUSY clear
        n = 0
        while not (await apb.read(REG_STATUS)) & 1:
            n += 1
            if n > 2000:
                break
        n = 0
        while (await apb.read(REG_STATUS)) & 1:
            n += 1
            assert n < timeout, "BUSY never cleared"
    elif poll == "enable":
        # alternative software: wait for ENABLE auto-clear, then BUSY clear
        n = 0
        while (await apb.read(REG_CMD)) & 0x100:
            n += 1
            assert n < timeout, "ENABLE never auto-cleared"
        n = 0
        while (await apb.read(REG_STATUS)) & 1:
            n += 1
            assert n < timeout, "BUSY never cleared"
    await apb.write(REG_STATUS, 0x100)       # IRQ clear


def _spi_read_word(nbytes=16, dummy=8, op=0x0B):
    return op | (1 << 9) | (1 << 11) | (dummy << 12) | ((nbytes - 1) << 16)


@cocotb.test()
async def a1_q1_apb_frames_and_clocks(dut):
    """Every APB command must produce exactly ONE nCS frame with exactly the
    expected number of SCLK cycles, at every CLK_DIV. Catches a lost or late
    acknowledge (re-issue: extra clocks / extra frame) and a lost enable."""
    env = Env(dut)
    await env.start(clk_div=1)
    await env.xip_off()
    pins = QspiPinMonitor(dut).start()
    bad = []
    for div in (1, 2, 3, 4, 7, 15, 31):
        await env.apb.write(REG_CLKDIV, div)
        await ClockCycles(dut.HCLK, 4 * div + 10)
        pins.take()
        cases = [
            ("SPI WREN 0x06", 0x06, 8),
            ("SPI WRDI 0x04", 0x04, 8),
            ("SPI JEDEC 0x9F 3B", 0x9F | (1 << 9) | (2 << 16), 8 + 24),
            ("SPI FAST_READ 16B", _spi_read_word(), 8 + 24 + 8 + 128),
            ("SPI FAST_READ 4B", _spi_read_word(4), 8 + 24 + 8 + 32),
        ]
        for name, word, clocks in cases:
            await apb_cmd(env, word)
            await ClockCycles(dut.HCLK, 4 * div + 10)
            fr = pins.take()
            if fr != [clocks]:
                bad.append(f"div{div} {name}: frames(SCLK counts)={fr}, "
                           f"expected [{clocks}]")
    # QPI command-only (2 SCLK) after EQIO, then RSTQIO back to SPI
    for div in (1, 2, 4, 15):
        await env.apb.write(REG_CLKDIV, div)
        await apb_cmd(env, 0x38)                       # EQIO (SPI framing)
        await env.apb.write(REG_CTRL, 1)               # QIO_MODE=1
        await ClockCycles(dut.HCLK, 4 * div + 10)
        pins.take()
        for name, word, clocks in [("QPI WREN 0x06", 0x06, 2),
                                   ("QPI JEDEC 0xAF 3B", 0xAF | (1 << 9) | (2 << 12) | (2 << 16), 2 + 2 + 6)]:
            await apb_cmd(env, word)
            await ClockCycles(dut.HCLK, 4 * div + 10)
            fr = pins.take()
            if fr != [clocks]:
                bad.append(f"div{div} {name}: frames(SCLK counts)={fr}, "
                           f"expected [{clocks}]")
        await apb_cmd(env, 0xFF)                       # RSTQIO
        await env.apb.write(REG_CTRL, 0)
        await ClockCycles(dut.HCLK, 4 * div + 10)
        pins.take()
    for b in bad:
        env.log.warning(b)
    env.bad_frames = bad
    await env.xip_on(1)
    await finish(env, bad)


@cocotb.test()
async def a1_q1_apb_read_data_sweep(dut):
    """APB-mode FAST_READ of 16 bytes at random addresses across CLK_DIV,
    with both software completion idioms. RDATA0-3 must match the flash."""
    env = Env(dut)
    await env.start(clk_div=1)
    await env.xip_off()
    rnd = random.Random(SEED + 3)
    bad = []
    for div in (1, 2, 3, 5, 8, 31):
        await env.apb.write(REG_CLKDIV, div)
        for poll in ("driver", "enable"):
            for _ in range(2):
                a = REGION + 16 * rnd.randrange(REGION_LEN // 16)
                await env.apb.write(REG_ADDR, a)
                await apb_cmd(env, _spi_read_word(), poll=poll)
                got = [await env.apb.read(REG_RDATA0 + 4 * i) for i in range(4)]
                exp = [env.lane(a + 4 * i) for i in range(4)]
                if got != exp:
                    bad.append(f"div{div} poll={poll} @0x{a:06x}: got "
                               f"{[hex(x) for x in got]} exp {[hex(x) for x in exp]}")
    await env.xip_on(1)
    await finish(env, bad)


@cocotb.test()
async def a1_q1_xip_clkdiv_sweep(dut):
    """XiP reads (isolated and back-to-back-free pairs) at every CLK_DIV
    1..31: the AHB enable/ack/BUSY handshake must neither hang nor return
    wrong data, and the H1 ordering probe must stay clean."""
    env = Env(dut)
    await env.start(clk_div=1)
    rnd = random.Random(SEED + 4)
    bad = []
    for div in list(range(1, 9)) + [12, 16, 23, 31]:
        await env.apb.write(REG_CLKDIV, div)
        for _ in range(3):
            a = REGION + 4 * rnd.randrange(REGION_LEN // 4)
            bad += env.score(await env.xip_read_isolated(a), label=f"div{div} ")
    await finish(env, bad)


@cocotb.test()
async def a1_q1_xip_mode_switching(dut):
    """Back-to-back mode changes: XiP on/off toggles with no gap, APB command
    between XiP reads, XiP read immediately after XIP_ACTIVE=1, CLK_DIV
    change between XiP reads."""
    env = Env(dut)
    await env.start(clk_div=1)
    rnd = random.Random(SEED + 5)
    bad = []
    for it in range(12):
        div = rnd.choice([1, 2, 3, 5])
        await env.apb.write(REG_CLKDIV, div)
        # rapid toggles
        for _ in range(rnd.randrange(1, 4)):
            await env.apb.write(REG_CTRL, 0)
            await env.apb.write(REG_CTRL, XIP_ACTIVE)
        a = REGION + 4 * rnd.randrange(REGION_LEN // 4)
        bad += env.score(await env.xip_read_isolated(a), label=f"it{it} xip ")
        # to APB mode, one APB read, back to XiP, read immediately
        await env.xip_off()
        b = REGION + 16 * rnd.randrange(REGION_LEN // 16)
        await env.apb.write(REG_ADDR, b)
        await apb_cmd(env, _spi_read_word())
        got = [await env.apb.read(REG_RDATA0 + 4 * i) for i in range(4)]
        if got != [env.lane(b + 4 * i) for i in range(4)]:
            bad.append(f"it{it} APB read @0x{b:06x} wrong: {[hex(x) for x in got]}")
        await env.apb.write(REG_CTRL, XIP_ACTIVE)
        c = REGION + 4 * rnd.randrange(REGION_LEN // 4)
        bad += env.score(await env.xip_read_isolated(c), label=f"it{it} xip2 ")
    await finish(env, bad)


@cocotb.test()
async def a1_q1_reset_mid_transfer(dut):
    """HRESETn asserted at a random point inside an XiP read (WAIT_READ) or an
    APB command; after reset + re-init the next transfers must be correct and
    the checker must see no protocol violation."""
    env = Env(dut)
    await env.start(clk_div=1)
    rnd = random.Random(SEED + 6)
    bad = []
    for it in range(10):
        div = rnd.choice([1, 2, 3])
        await env.xip_on(div)
        a = REGION + 4 * rnd.randrange(REGION_LEN // 4)
        if it % 2 == 0:
            task = cocotb.start_soon(env.ahb.run([_R(a)]))
        else:
            await env.xip_off()
            await env.apb.write(REG_ADDR, a & ~0xF)
            task = cocotb.start_soon(apb_cmd(env, _spi_read_word()))
        await ClockCycles(dut.HCLK, rnd.randrange(3, 120 * div))
        task.cancel()
        env.chk.completions.clear()
        env.chk.accepted = 0
        env.ahb._drive(idle_beat())
        dut.PSEL.value = 0
        dut.PENABLE.value = 0
        await env.hard_reset(rnd.randrange(1, 6))
        # AHB-Lite: the slave must come out of reset ready (HREADYOUT=1,
        # OKAY), whatever transfer it was in when reset hit.
        for _ in range(3):
            await FallingEdge(dut.HCLK)
            if not (_int(dut.S_HREADYOUT) == 1 and _int(dut.S_HRESP) == 0):
                bad.append(f"it{it}: after reset S_HREADYOUT={dut.S_HREADYOUT.value} "
                           f"S_HRESP={dut.S_HRESP.value} (must be 1/0)")
        await ClockCycles(dut.HCLK, 40)
        await env.xip_on(div)
        for _ in range(2):
            b = REGION + 4 * rnd.randrange(REGION_LEN // 4)
            bad += env.score(await env.xip_read_isolated(b), label=f"it{it} post-reset ")
    await finish(env, bad)


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def a1_q1_xip_off_mid_read_watchdog(dut):
    """XIP_ACTIVE cleared while an XiP read waits: the AHB ack/BUSY are forced
    (ack=0, BUSY=1), so the watchdog must end the read with a 2-cycle ERROR
    (no hang), pulse SOFT_RESET, and the next XiP read must be correct."""
    env = Env(dut)
    await env.start(clk_div=1)
    bad = []
    for div in (1, 3):
        await env.xip_on(div)
        a = addr_in_line(30)
        n0 = len(env.chk.completions)
        task = cocotb.start_soon(env.ahb.run([_R(a)]))
        await ClockCycles(dut.HCLK, 3)
        await env.apb.write(REG_CTRL, 0)
        await task
        comps = env.chk.completions[n0:]
        env.log.info("xip-off-mid-read div%d: %r", div, comps)
        if not comps or comps[0].resp not in (0, 1):
            bad.append(f"div{div}: no completion")
        elif comps[0].resp == 0:
            bad += env.score(comps, label=f"div{div} xip-off-mid ")
        await ClockCycles(dut.HCLK, 300 * div)
        await env.xip_on(div)
        bad += env.score(await env.xip_read_isolated(addr_in_line(31, 2)),
                         label=f"div{div} recovery ")
    await finish(env, bad)
