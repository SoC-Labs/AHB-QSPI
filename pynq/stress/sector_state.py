#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - Persistent sector rotation state for wear management
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# The N25Q256A is rated for ~100k erase cycles per sector. Without rotation
# a soak test would hammer sector 0 and burn through that budget in a few
# weekends of testing. This module persists the next-sector-to-erase index
# in a small file alongside the runner so successive runs spread wear
# evenly across the lower-16-MB / 256-sector address space.
#-----------------------------------------------------------------------------

import os

DEFAULT_STATE_PATH = os.path.expanduser('~/.qspi_stress_state')


class SectorRotator:
    """Iterates through flash sectors, persisting position across invocations.

    Each call to next() returns a (sector_index, byte_address) tuple and
    advances the persisted cursor. Wraps around at total_sectors.
    """

    def __init__(self, total_sectors=256, sector_size=64*1024,
                 state_path=DEFAULT_STATE_PATH):
        self.total_sectors = total_sectors
        self.sector_size   = sector_size
        self.state_path    = state_path
        self._cursor       = self._load()

    def _load(self):
        try:
            with open(self.state_path) as f:
                return int(f.read().strip()) % self.total_sectors
        except (FileNotFoundError, ValueError):
            return 0

    def _save(self, idx):
        try:
            with open(self.state_path, 'w') as f:
                f.write(str(idx))
        except OSError:
            # Non-fatal - we just lose rotation across runs
            pass

    def peek(self):
        return self._cursor

    def next(self):
        idx  = self._cursor
        addr = idx * self.sector_size
        self._cursor = (idx + 1) % self.total_sectors
        self._save(self._cursor)
        return idx, addr

    def reset(self):
        self._cursor = 0
        self._save(0)
