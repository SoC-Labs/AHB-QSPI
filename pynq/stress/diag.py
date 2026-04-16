#!/usr/bin/env python3
"""Minimal QSPI write diagnostic — run on the PYNQ to pinpoint why
page programs silently fail (reads return 0xFF = erased state)."""

import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from bare_overlay import BareMMIO

apb = BareMMIO(0x42000000, 0x10000)

def wr(off, val): apb.write(off, val)
def rd(off): return apb.read(off)

def busy_wait(tag="", timeout=2.0):
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        s = rd(0x04)
        if not (s & 1):
            print(f"  [{tag}] BUSY cleared in {(time.monotonic()-t0)*1000:.1f} ms, STATUS=0x{s:08x}")
            wr(0x04, 0x100)  # IRQ CLR
            return s
    raise RuntimeError(f"  [{tag}] BUSY timeout!")

def spi_cmd(desc, cmd, read=0, write=0, addr_en=0, dummy=0, n_bytes=1):
    flags = (read<<9)|(write<<10)|(addr_en<<11)|(dummy<<12)|((n_bytes-1)<<16)
    base = (cmd & 0xFF) | flags
    wr(0x08, base)
    wr(0x08, base | (1<<8))
    busy_wait(desc)

print("=" * 60)
print("QSPI Write Diagnostic")
print("=" * 60)

# Reset
wr(0x00, 0); wr(0x04, 0x100); wr(0x08, 0); wr(0x0C, 0); wr(0x34, 5)
print(f"PIDR0=0x{rd(0xFE0)&0xFF:02x}  CIDR0=0x{rd(0xFF0)&0xFF:02x}")

# JEDEC ID
print("\n--- JEDEC ID ---")
spi_cmd("JEDEC", 0x9F, read=1, n_bytes=3)
rdata0 = rd(0x10)
print(f"  RDATA0 = 0x{rdata0:08x}")
print(f"  (MSB byte = 0x{(rdata0>>24)&0xFF:02x}, byte2 = 0x{(rdata0>>16)&0xFF:02x}, "
      f"byte1 = 0x{(rdata0>>8)&0xFF:02x}, LSB = 0x{rdata0&0xFF:02x})")

# Read Status Register (raw word)
print("\n--- Status Register (before WREN) ---")
spi_cmd("RDSR-pre", 0x05, read=1, n_bytes=3)
sr_word = rd(0x10)
print(f"  RDATA0 = 0x{sr_word:08x}")
sr = (sr_word >> 8) & 0xFF  # try byte 1 (LE skip-byte-0 model)
print(f"  SR (byte1) = 0x{sr:02x}  WIP={sr&1} WEL={(sr>>1)&1} BP={sr>>2:04b}")
sr_alt = (sr_word >> 24) & 0xFF  # try MSB (big-endian model)
print(f"  SR (MSB)   = 0x{sr_alt:02x}  WIP={sr_alt&1} WEL={(sr_alt>>1)&1}")

# WREN
print("\n--- WREN (0x06) ---")
spi_cmd("WREN", 0x06)
print("  WREN issued.")

# Read Status Register AFTER WREN
print("\n--- Status Register (after WREN) ---")
spi_cmd("RDSR-post", 0x05, read=1, n_bytes=3)
sr_word2 = rd(0x10)
print(f"  RDATA0 = 0x{sr_word2:08x}")
sr2 = (sr_word2 >> 8) & 0xFF
print(f"  SR (byte1) = 0x{sr2:02x}  WIP={sr2&1} WEL={(sr2>>1)&1}")
sr2_alt = (sr_word2 >> 24) & 0xFF
print(f"  SR (MSB)   = 0x{sr2_alt:02x}  WIP={sr2_alt&1} WEL={(sr2_alt>>1)&1}")
if not ((sr2 >> 1) & 1) and not ((sr2_alt >> 1) & 1):
    print("  *** WEL NOT SET — WREN FAILED ***")

# Sector erase at address 0xFE0000 (sector 254 — safe)
print("\n--- Sector Erase (0xFE0000) ---")
spi_cmd("WREN2", 0x06)
wr(0x0C, 0x0FE000)
spi_cmd("ERASE", 0xD8, addr_en=1)
print("  Erase command issued. Polling flash WIP...")
for i in range(200):
    spi_cmd("POLL", 0x05, read=1, n_bytes=3)
    sw = rd(0x10)
    wip = (sw >> 8) & 1
    wip_alt = (sw >> 24) & 1
    if not wip and not wip_alt:
        print(f"  Flash idle after {i+1} polls. RDATA0=0x{sw:08x}")
        break
    time.sleep(0.01)
else:
    print("  *** ERASE WIP TIMEOUT ***")

# Read 4 bytes at 0xFE0000 (should be 0xFF after erase)
print("\n--- Read after erase ---")
wr(0x0C, 0x0FE000)
spi_cmd("READ1", 0x0B, read=1, addr_en=1, dummy=8, n_bytes=4)
r0 = rd(0x10)
print(f"  RDATA0 = 0x{r0:08x} (expect 0xFFFFFFxx for erased flash)")

# Page program 4 bytes: [0xDE, 0xAD, 0xBE, 0xEF]
print("\n--- Page Program 4 bytes at 0xFE0000 ---")
spi_cmd("WREN3", 0x06)
spi_cmd("RDSR-pre-pp", 0x05, read=1, n_bytes=3)
sr_pre_pp = rd(0x10)
print(f"  SR before PP: RDATA0=0x{sr_pre_pp:08x}")

wr(0x0C, 0x0FE000)       # address

# Try WDATA with different byte packings to see which one takes effect
wr(0x20, 0xDEADBEEF)     # WDATA0 = literal 0xDEADBEEF
print(f"  WDATA0 written: 0x{rd(0x20):08x}")

spi_cmd("PP", 0x02, write=1, addr_en=1, n_bytes=4)
print("  Page program issued. Polling flash WIP...")
for i in range(200):
    spi_cmd("POLL-PP", 0x05, read=1, n_bytes=3)
    sw = rd(0x10)
    wip = (sw >> 8) & 1
    wip_alt = (sw >> 24) & 1
    if not wip and not wip_alt:
        print(f"  Flash idle after {i+1} polls. RDATA0=0x{sw:08x}")
        break
    time.sleep(0.005)
else:
    print("  *** PP WIP TIMEOUT ***")

# Read back
print("\n--- Read after program ---")
wr(0x0C, 0x0FE000)
spi_cmd("READ2", 0x0B, read=1, addr_en=1, dummy=8, n_bytes=4)
r1 = rd(0x10)
print(f"  RDATA0 = 0x{r1:08x}")
if r1 == r0:
    print("  *** NO CHANGE — page program had no effect ***")
else:
    print(f"  Data changed! Was 0x{r0:08x}, now 0x{r1:08x}")

# Also try reading with different byte counts
print("\n--- Read 16 bytes (N_RW=15) ---")
wr(0x0C, 0x0FE000)
spi_cmd("READ3", 0x0B, read=1, addr_en=1, dummy=8, n_bytes=16)
for i, off in enumerate([0x10, 0x14, 0x18, 0x1C]):
    print(f"  RDATA{i} = 0x{rd(off):08x}")

print("\n" + "=" * 60)
apb.close()
