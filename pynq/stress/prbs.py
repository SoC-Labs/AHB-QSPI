#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - PRBS / LFSR helpers for stress tests
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Address-keyed deterministic byte streams. Lets stress tests verify any
# byte they later read back without storing 16 MB of expected data.
#
# The PRBS uses xorshift32 (Marsaglia, 2003): full 2^32 - 1 period, fast in
# pure Python, and the sequence depends only on the seed - so two tests
# can independently regenerate the expected bytes for any address.
#
# Convention:
#   expected_for(addr, n)   -> bytes that should be at flash[addr : addr+n]
#-----------------------------------------------------------------------------

PRBS_KEY = 0xA5A50000


class XorShift32:
    """Marsaglia xorshift32 PRBS. Period 2^32 - 1. State 0 is illegal."""

    def __init__(self, seed):
        s = seed & 0xFFFFFFFF
        if s == 0:
            s = 0xDEADBEEF
        self.state = s

    def next_word(self):
        x = self.state
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= (x >> 17)
        x ^= (x << 5)  & 0xFFFFFFFF
        self.state = x & 0xFFFFFFFF
        return self.state

    def next_bytes(self, n):
        out = bytearray()
        while len(out) < n:
            out.extend(self.next_word().to_bytes(4, 'little'))
        return bytes(out[:n])


def expected_for(addr, n_bytes):
    """Deterministic bytes for `addr..addr+n_bytes` independent of prior calls.

    CRITICAL CONTRACT: the byte at any given flash address X must be
    the same regardless of which query range asked for it. Callers
    rely on this when they page-program with one range and verify
    with another (e.g. programs the whole 256-byte page, then reads
    random 4-byte chunks from it).

    Implementation: seed the PRBS PER 4-BYTE BLOCK so the byte at
    address X is fully determined by (X & ~0x3 | PRBS_KEY) and the
    offset within that block. This means any query that touches X
    will produce the same byte there.
    """
    word_addr = addr & ~0x3
    byte_off  = addr & 0x3

    out          = bytearray()
    total_needed = byte_off + n_bytes
    current_word = word_addr
    while len(out) < total_needed:
        rng = XorShift32(current_word | PRBS_KEY)
        out.extend(rng.next_bytes(4))
        current_word += 4
    return bytes(out[byte_off:byte_off + n_bytes])
