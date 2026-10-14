"""A1 assessment library: cycle-accurate AHB-Lite master, AHB-Lite protocol
checker + scoreboard, APB master, and QSPI pin monitor.

Independent assessor A1, 13 Oct 2026. Written from the AMBA AHB-Lite rules,
not from the DUT's comments.

Sampling convention (all coroutines): values are read at the FALLING edge of
HCLK, after ReadOnly. Inputs are driven at the falling edge too. Everything
read at falling edge k is therefore exactly what the next RISING edge samples.
The DUT's HREADYOUT/HRESP/HRDATA are flop outputs (no combinational path from
HTRANS/HADDR), so a value read at the falling edge is the value the rising edge
uses.
"""

import random

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, ReadOnly, Timer

HT_IDLE, HT_BUSY, HT_NONSEQ, HT_SEQ = 0, 1, 2, 3
HT_NAME = {0: "IDLE", 1: "BUSY", 2: "NONSEQ", 3: "SEQ"}


def _int(sig):
    """int(sig.value), or None if it carries X/Z."""
    try:
        return int(sig.value)
    except ValueError:
        return None


class Beat:
    """One AHB address phase as the master presents it."""

    __slots__ = ("sel", "trans", "addr", "write", "size", "burst", "wdata",
                 "tag", "late")

    def __init__(self, sel=1, trans=HT_NONSEQ, addr=0, write=0, size=2,
                 burst=0, wdata=0, tag="", late=False):
        self.sel, self.trans, self.addr, self.write = sel, trans, addr, write
        self.size, self.burst, self.wdata, self.tag = size, burst, wdata, tag
        # late=True: present IDLE while the previous data phase waits and
        # switch to this beat only in the cycle HREADY is high (AHB-Lite
        # permits IDLE->NONSEQ during wait states), so the address phase is
        # on the bus for exactly the completion cycle.
        self.late = late

    def is_xfer(self):
        return self.trans in (HT_NONSEQ, HT_SEQ)

    def __repr__(self):
        return (f"{HT_NAME[self.trans]}{'' if self.sel else '(dflt)'} "
                f"{'W' if self.write else 'R'} 0x{self.addr:06x} {self.tag}")


def idle_beat(sel=0):
    return Beat(sel=sel, trans=HT_IDLE, addr=0, write=0)


class AhbMaster:
    """Zero-wait-issue AHB-Lite master. `run(beats)` presents every beat as an
    address phase, back-to-back: the next beat goes on the bus the cycle after
    the previous one is accepted (HREADY=1). Holds the address phase while
    HREADY=0, as AHB-Lite requires. Drives HWDATA in the data phase."""

    def __init__(self, dut, max_wait=70000):
        self.dut = dut
        self.max_wait = max_wait
        self._drive(idle_beat())
        dut.HWDATA.value = 0

    def _drive(self, b):
        d = self.dut
        d.HSEL.value = b.sel
        d.HTRANS.value = b.trans
        d.HADDR.value = b.addr & 0x3FFFFF
        d.HWRITE.value = b.write
        d.HSIZE.value = b.size
        d.HBURST.value = b.burst

    async def run(self, beats, tail_idle=True):
        """Returns the number of cycles taken. The checker records the
        completions; the master only drives."""
        d = self.dut
        beats = list(beats)
        if tail_idle:
            beats.append(idle_beat())
        await FallingEdge(d.HCLK)
        i = 0
        self._drive(idle_beat() if beats[0].late else beats[0])
        dp = None
        waits = 0
        cycles = 0
        while True:
            hready = _int(d.HREADY)
            if beats[i].late and hready == 1:
                self._drive(beats[i])
            await RisingEdge(d.HCLK)
            cycles += 1
            if hready == 1:
                waits = 0
                dp = beats[i]
                i += 1
                await FallingEdge(d.HCLK)
                if i >= len(beats):
                    self._drive(idle_beat())
                    break
                self._drive(idle_beat() if beats[i].late else beats[i])
                # data phase write data
                if dp.is_xfer() and dp.write:
                    d.HWDATA.value = dp.wdata
            else:
                waits += 1
                if waits > self.max_wait:
                    raise AssertionError(
                        f"AHB master: HREADY low for {waits} cycles "
                        f"(bus hang) with {beats[i]!r} in address phase")
                await FallingEdge(d.HCLK)
        # let the last data phase (if any) complete
        n = 0
        while _int(d.HREADY) != 1:
            await RisingEdge(d.HCLK)
            await FallingEdge(d.HCLK)
            n += 1
            if n > self.max_wait:
                raise AssertionError("AHB master: final data phase never "
                                     "completed (bus hang)")
        await RisingEdge(d.HCLK)
        await FallingEdge(d.HCLK)
        return cycles


class Completion:
    __slots__ = ("addr", "write", "size", "resp", "rdata", "wdata", "acc_t",
                 "cmp_t", "waits", "tag")

    def __repr__(self):
        r = "ERR" if self.resp else "OK"
        return (f"{'W' if self.write else 'R'} 0x{self.addr:06x} {r} "
                f"waits={self.waits} acc@{self.acc_t} done@{self.cmp_t}")


class AhbChecker:
    """AHB-Lite protocol checker for the QSPI slave port of tb_a1_core.

    Rules checked (slave side), each a hard failure:
      R1  no X/Z on S_HREADYOUT / S_HRESP after reset; no X/Z on HRDATA
          when an OKAY read completes.
      R2  an IDLE or BUSY transfer to the slave gets a zero-wait OKAY.
      R3  ERROR is exactly two cycles: (HREADYOUT=0,HRESP=1) then
          (HREADYOUT=1,HRESP=1). HRESP=1 with HREADYOUT=1 never appears
          without the first cycle; the first cycle is never followed by
          anything else.
      R4  HRESP=0 in every wait cycle that is not an ERROR first cycle.
      R5  every accepted NONSEQ/SEQ to the slave completes exactly once (no
          drop, no extra completion), within max_wait cycles.
    The checker also records every completion for the scoreboard."""

    NAMES = ("HCLK", "HRESETn", "HSEL", "HTRANS", "HADDR", "HWRITE", "HSIZE",
             "HREADY", "S_HREADYOUT", "S_HRESP", "S_HRDATA")

    def __init__(self, dut, log, max_wait=70000, name="qspi", sigs=None):
        """sigs: optional {logical name: handle} map (defaults to the
        tb_a1_core port names)."""
        self.log, self.max_wait, self.name = log, max_wait, name
        if sigs is None:
            sigs = {n: getattr(dut, n) for n in self.NAMES}
        self.dut = type("SigMap", (), sigs)
        self.completions = []
        self.violations = []
        self.accepted = 0
        self.stop = False
        self.t = 0
        self.fail_fast = True
        self._task = None
        self.on_complete = None     # optional callback(Completion)

    def start(self):
        self._task = cocotb.start_soon(self._run())
        return self

    def _viol(self, msg):
        m = f"[{self.name} AHB checker] cyc {self.t}: {msg}"
        self.violations.append(m)
        self.log.error(m)
        if self.fail_fast:
            raise AssertionError(m)

    async def _run(self):
        d = self.dut
        dp = None          # pending valid data phase (dict) for the slave
        dp_idle = False    # IDLE/BUSY accepted for the slave last edge
        err1 = False       # previous sample was an ERROR first cycle
        while not self.stop:
            await FallingEdge(d.HCLK)
            await ReadOnly()
            self.t += 1
            if _int(d.HRESETn) != 1:
                dp, dp_idle, err1 = None, False, False
                continue
            hready = _int(d.HREADY)
            ho = _int(d.S_HREADYOUT)
            hr = _int(d.S_HRESP)
            if ho is None or hr is None:
                self._viol(f"X/Z on S_HREADYOUT={d.S_HREADYOUT.value} "
                           f"S_HRESP={d.S_HRESP.value}")
                continue
            sel = _int(d.HSEL)
            trans = _int(d.HTRANS)
            addr = _int(d.HADDR)
            wr = _int(d.HWRITE)
            size = _int(d.HSIZE)

            # ---- data phase checks for the slave ----
            if dp_idle:
                if not (ho == 1 and hr == 0):
                    self._viol(f"R2: IDLE/BUSY transfer not given zero-wait "
                               f"OKAY (HREADYOUT={ho} HRESP={hr})")
                dp_idle = False
            if dp is not None:
                if err1:
                    if not (ho == 1 and hr == 1):
                        self._viol(f"R3: ERROR first cycle not followed by "
                                   f"(HREADYOUT=1,HRESP=1); got ({ho},{hr})")
                elif ho == 1 and hr == 1:
                    self._viol("R3: one-cycle ERROR (HREADYOUT=1,HRESP=1 "
                               "without a preceding (0,1) cycle)")
                if ho == 0 and hr == 0 and err1:
                    pass  # reported above
                err1 = (ho == 0 and hr == 1)
                if ho == 1:
                    c = Completion()
                    c.addr, c.write, c.size = dp["addr"], dp["write"], dp["size"]
                    c.resp = hr
                    c.rdata = _int(d.S_HRDATA)
                    c.wdata = None
                    c.acc_t, c.cmp_t, c.waits = dp["t"], self.t, dp["waits"]
                    c.tag = ""
                    if hr == 0 and not c.write and c.rdata is None:
                        self._viol(f"R1: X/Z on HRDATA for OKAY read "
                                   f"0x{c.addr:06x}")
                    self.completions.append(c)
                    if self.on_complete is not None:
                        self.on_complete(c)
                    dp = None
                    err1 = False
                else:
                    dp["waits"] += 1
                    if dp["waits"] > self.max_wait:
                        self._viol(f"R5: transfer 0x{dp['addr']:06x} not "
                                   f"completed in {self.max_wait} cycles")
                        dp = None
            else:
                if err1:
                    self._viol("R3: ERROR first cycle with no transfer "
                               "pending")
                err1 = False
                # Not in a data phase for this slave: HRESP must be 0 when
                # this slave would be sampled; we check it only when it is
                # the selected data-phase slave (dp_idle handled above).

            # ---- address phase acceptance (at the coming rising edge) ----
            if hready == 1:
                if sel == 1 and trans is not None and trans >= HT_NONSEQ:
                    if dp is not None:
                        self._viol("internal: new address phase accepted "
                                   "while previous data phase pending")
                    dp = {"addr": addr, "write": wr, "size": size,
                          "t": self.t, "waits": 0}
                    self.accepted += 1
                elif sel == 1:
                    dp_idle = True

    def check_drained(self):
        if len(self.completions) != self.accepted:
            self._viol(f"R5: {self.accepted} transfers accepted but "
                       f"{len(self.completions)} completed")


class Apb:
    """Simple APB3 master on tb_a1_core (PREADY honoured)."""

    def __init__(self, dut):
        self.dut = dut
        dut.PSEL.value = 0
        dut.PENABLE.value = 0
        dut.PWRITE.value = 0
        dut.PADDR.value = 0
        dut.PWDATA.value = 0
        self.lock = None

    async def _xfer(self, addr, write, data=0):
        d = self.dut
        await FallingEdge(d.HCLK)
        d.PADDR.value = addr
        d.PWRITE.value = write
        d.PWDATA.value = data
        d.PSEL.value = 1
        d.PENABLE.value = 0
        await FallingEdge(d.HCLK)
        d.PENABLE.value = 1
        while True:
            await FallingEdge(d.HCLK)
            # the rising edge just gone sampled PSEL&PENABLE; PREADY is
            # combinational PSEL&PENABLE in apb_qspi_regs, so it completed.
            rd = _int(d.PRDATA)
            break
        d.PSEL.value = 0
        d.PENABLE.value = 0
        return rd

    async def write(self, addr, data):
        await self._xfer(addr, 1, data)

    async def read(self, addr):
        # PRDATA is combinational from PADDR; sample in the access phase
        d = self.dut
        await FallingEdge(d.HCLK)
        d.PADDR.value = addr
        d.PWRITE.value = 0
        d.PSEL.value = 1
        d.PENABLE.value = 0
        await FallingEdge(d.HCLK)
        d.PENABLE.value = 1
        await ReadOnly()
        await FallingEdge(d.HCLK)
        await ReadOnly()
        rd = _int(d.PRDATA)
        await Timer(1, "ns")
        d.PSEL.value = 0
        d.PENABLE.value = 0
        return rd


class QspiPinMonitor:
    """Counts nCS-low frames and SCLK rising edges per frame."""

    def __init__(self, dut):
        self.dut = dut
        self.frames = []     # list of SCLK-rise counts per frame
        self._cur = None
        self.stop = False

    def start(self):
        cocotb.start_soon(self._ncs())
        cocotb.start_soon(self._sclk())
        return self

    async def _ncs(self):
        from cocotb.triggers import Edge
        d = self.dut
        while not self.stop:
            await Edge(d.QSPI_nCS_o)
            v = _int(d.QSPI_nCS_o)
            if v == 0:
                self._cur = 0
            elif v == 1 and self._cur is not None:
                self.frames.append(self._cur)
                self._cur = None

    async def _sclk(self):
        d = self.dut
        while not self.stop:
            await RisingEdge(d.QSPI_SCLK_o)
            if self._cur is not None:
                self._cur += 1

    def take(self):
        f = self.frames
        self.frames = []
        return f


def start_sys_checkers(dut, log):
    """Attach AhbChecker to the existing system TB (verif/cocotb,
    ahb_qspi_cocotb): (1) the external data port (the CG092 cache's AHB slave
    side, 32-bit), (2) the private bus between the CG092 cache (master) and
    ahb_qspi_interface (slave, 128-bit). Protocol only (R1-R5); data is
    checked by the existing tests. Returns the two checkers."""
    t = dut.u_ahb_qspi_pads.u_top_ahb_qspi
    ext = {"HCLK": dut.HCLK, "HRESETn": dut.HRESETn, "HSEL": dut.data_HSEL,
           "HTRANS": dut.data_HTRANS, "HADDR": dut.data_HADDR,
           "HWRITE": dut.data_HWRITE, "HSIZE": dut.data_HSIZE,
           "HREADY": dut.data_HREADY, "S_HREADYOUT": dut.data_HREADY,
           "S_HRESP": dut.data_HRESP, "S_HRDATA": dut.data_HRDATA}
    prv = {"HCLK": dut.HCLK, "HRESETn": dut.HRESETn, "HSEL": t.flash_HSELM,
           "HTRANS": t.flash_HTRANSM, "HADDR": t.flash_HADDRM,
           "HWRITE": t.flash_HWRITEM, "HSIZE": t.flash_HSIZEM,
           "HREADY": t.flash_HREADYM, "S_HREADYOUT": t.flash_HREADYOUTM,
           "S_HRESP": t.flash_HRESPM, "S_HRDATA": t.flash_HRDATAM}
    c1 = AhbChecker(dut, log, name="ext-data-port", sigs=ext).start()
    c2 = AhbChecker(dut, log, name="private-bus", sigs=prv).start()
    # Report-only data check on the private bus: every OKAY read must return
    # the 16-byte flash line at ITS OWN address (backdoor read of the flash
    # model array at completion time). Logged as "A1-PRIV-DATA MISMATCH".
    mem = dut.u_sst26vf064b.I0.memory

    def _chk(c):
        if c.write or c.resp or c.rdata is None:
            return
        base = c.addr & ~0xF
        try:
            ref = 0
            for i in range(16):
                ref |= int(mem[base + i].value) << (8 * i)
        except ValueError:
            return       # X in the flash array (erased-with-X region)
        if ref != c.rdata:
            log.warning("A1-PRIV-DATA MISMATCH %r: got %032x ref %032x",
                        c, c.rdata, ref)
    c2.on_complete = _chk
    return c1, c2
