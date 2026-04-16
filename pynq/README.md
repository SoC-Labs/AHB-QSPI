# AHB QSPI Subsystem - PYNQ-Z2 Overlay

PYNQ overlay package for running the existing cocotb test suite from
[verif/cocotb/](../verif/cocotb/) against a real PYNQ-Z2 board with a
Diligent **PmodSF3** (Micron N25Q256A / MT25QL256, 32 MB) connected to
**PMODA**.

## Hardware setup

```
PYNQ-Z2  PMODA          PmodSF3
JA1 -- Y18 ---->  Pin 1 (CS#)
JA2 -- Y19 <-->   Pin 2 (DQ0 / MOSI)
JA3 -- Y16 <-->   Pin 3 (DQ1 / MISO)
JA4 -- Y17 ---->  Pin 4 (SCK)
JA7 -- U18 <-->   Pin 7 (DQ2 / WP#)
JA8 -- U19 <-->   Pin 8 (DQ3 / HOLD#)
GND  ----------   Pin 5
3V3  ----------   Pin 6
```

PMODA is the right-hand PMOD on the PYNQ-Z2 board (looking from the front
with the HDMI port at the top). PMODB is also functional but is *not* what
this overlay targets - re-route in the XDC if you wire PmodSF3 to PMODB
instead.

## Files

| File | Purpose |
|---|---|
| [qspi.bit](qspi.bit) | Bitstream (built by `make build_design` upstream) |
| [qspi.hwh](qspi.hwh) | Hardware handoff metadata (IP-XACT flat) - PYNQ overlay loader requires it |
| [qspi_overlay.py](qspi_overlay.py) | `QspiOverlay` class - exposes `.apb` and `.ahb` MMIO regions |
| [qspi_ahb_shim.py](qspi_ahb_shim.py) | `MmioAhbShim` - drop-in replacement for `cocotbext.ahb.AHBLiteMaster`; `HwTB` and hardware-friendly `poll_busy_clear` / `wait_for_irq` |
| [cocotb_stubs.py](cocotb_stubs.py) | Minimal cocotb / cocotbext.ahb stubs so the simulation test files import without cocotb installed |
| [N25Q256A.py](N25Q256A.py) | Micron-specific overrides for the JEDEC ID + QPI mode entry / exit opcodes |
| [tests/run_tests.py](tests/run_tests.py) | Test runner - imports `verif/cocotb/ahb_qspi_tests.py` and runs each `@cocotb.test` against the overlay |

## Build and deploy from host

From the repo root on your build machine:

```bash
source set_env.sh
cd fpga
make build_design          # produces imp/fpga/output/pynq-z2/qspi.{bit,hwh}
make deploy PYNQ_HOST=xilinx@pynq.local
```

This SCPs the bitstream, .hwh, and the entire `pynq/` directory to
`/home/xilinx/qspi_overlay/` on the board.

## Running on the PYNQ board

```bash
ssh xilinx@pynq.local
cd /home/xilinx/qspi_overlay
sudo python3 tests/run_tests.py                   # run all tests
sudo python3 tests/run_tests.py APB_reg_tests     # one test
sudo python3 tests/run_tests.py -k QSPI -v        # filter + verbose
```

The runner does the following before launching tests:

1. Loads `qspi.bit` via the PYNQ overlay loader
2. Reads `PIDR0` (expect `0x59`) and `CIDR0` (expect `0x50`) over APB to verify the AXI -> APB path
3. Imports `verif/cocotb/ahb_qspi_tests.py` after monkey-patching `cocotb` and `cocotbext.ahb` to use the stub modules
4. Substitutes `TB` with `HwTB` so each test gets `MmioAhbShim`-backed `config_ahb_master` / `data_ahb_master`
5. Substitutes `SST26VF064B.poll_busy_clear` / `wait_for_irq` with the hardware versions (poll the BUSY bit instead of poking DUT signals)

## Block design address map

| Region | PS Address | Size | What |
|---|---|---|---|
| APB regs | `0x4200_0000` | 64 KB | QSPI control registers (PADDR[15:0]); CG092 cache regs at `+0x1000` |
| AHB XiP  | `0x4000_0000` | 16 MB | Read-only flash window (covers full SPI_ADDR[21:0]) |

## Known caveats

* **Flash part mismatch.** The cocotb tests target `SST26VF064B`. The PmodSF3 is `N25Q256A`/`MT25QL256`. JEDEC ID and QPI mode opcodes differ — see [N25Q256A.py](N25Q256A.py) for the deltas. Tests that hard-code `0xBF2643` as the expected ID will fail; either skip them or import from `N25Q256A` instead of `SST26VF064B`.
* **No true reset.** `cycle_reset` writes idle values to all writeable registers but the only true reset is reloading the bitstream. If a test leaves the controller in a wedged state, reload the overlay.
* **Hierarchical signal pokes.** A handful of regression tests in [verif/cocotb/ahb_qspi_tests.py](../verif/cocotb/ahb_qspi_tests.py) (the `test_bug*` series) write to internal DUT nets. These become no-ops on hardware (the `HwDut` proxy swallows the assignments) and the test will likely fail an assertion downstream. Run them with the `-k` filter excluded for the first bring-up pass.
* **CDC margin.** Default `CLK_DIV=5` (HCLK/10 -> 5 MHz QSPI_SCLK at 50 MHz HCLK) matches the cocotb default and gives plenty of margin for the synchronisers. Don't drop it below 2 without verifying the CDC paths in [logical/qspi_controller/logical/qspi_controller.sv](../logical/qspi_controller/logical/qspi_controller.sv).
* **4-byte addressing not enabled.** The N25Q256 needs 4-byte addressing to access the upper 16 MB. The hardware tests so far only exercise the low 16 MB (matches `SPI_ADDR[21:0]` width).

## Quick interactive smoke test

```python
from qspi_overlay import QspiOverlay
ol = QspiOverlay()

# CoreSight peripheral / component IDs (synthesised constants)
print(f"PIDR = 0x{ol.read_pidr():016x}")     # expect ...001516 59
print(f"CIDR = 0x{ol.read_cidr():08x}")      # expect 0x534c5150 = 'SLQP'

# Reset to safe defaults
ol.reset_controller()

# JEDEC ID read in SPI mode (RDID = 0x9F, 3 bytes addr/dummy + 3 bytes read)
ol.apb.write(0x34, 5)               # CLK_DIV = 5 -> QSPI_SCLK = HCLK/10
ol.apb.write(0x00, 0)               # CTRL = SPI mode, no XiP
ol.apb.write(0x08, 0x0002009F)      # READ=1, N_RW_BYTES=3, CMD=0x9F
ol.apb.write(0x08, 0x0002039F)      # +ENABLE
# wait for completion
import time
while ol.apb.read(0x04) & 1:
    time.sleep(0.001)
print(f"JEDEC = 0x{ol.apb.read(0x10):08x}")   # expect 0x?? ?? BA 20 (Micron)
```
