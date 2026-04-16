#!/usr/bin/env python3
"""Convert a Vivado .bit file to a byte-swapped .bin for Linux fpga_manager.

The Vivado .bit file format is:
    1. Variable-length ASCII header  (design name, part, date, ...)
    2. Sync word 0xAA995566 (big-endian in the file)
    3. Configuration packets (32-bit words, big-endian)

Linux's zynq-fpga driver (loaded via /sys/class/fpga_manager/fpga0/firmware)
wants only the post-sync configuration data, with each 32-bit word
byte-swapped to little-endian so the PCAP DMA engine can stream it directly.

Equivalent to Xilinx bootgen: bootgen -image x.bif -arch zynq
                              -process_bitstream bin

Usage:
    bit2bin.py <input.bit> <output.bin>
"""

import struct
import sys


SYNC = b"\xaa\x99\x55\x66"


def convert(bit_path, bin_path):
    with open(bit_path, "rb") as f:
        data = f.read()

    idx = data.find(SYNC)
    if idx < 0:
        raise SystemExit(f"ERROR: sync word {SYNC.hex()} not found in {bit_path}")

    raw = data[idx:]
    if len(raw) % 4:
        # Pad to a 4-byte boundary (shouldn't be needed for valid bitstreams)
        raw += b"\x00" * (4 - (len(raw) % 4))

    # Byte-swap each 32-bit word (>I read big-endian, <I write little-endian)
    swapped = bytearray(len(raw))
    for i in range(0, len(raw), 4):
        (word,) = struct.unpack_from(">I", raw, i)
        struct.pack_into("<I", swapped, i, word)

    with open(bin_path, "wb") as f:
        f.write(swapped)

    print(f"Wrote {bin_path}: {len(swapped)} bytes "
          f"(stripped {idx}-byte header from {bit_path})")


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    convert(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()
