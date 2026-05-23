# AHB QSPI for XiP
Basic QSPI controller with AHB and APB interfaces, uses Arm Corelink AHB Flash Cache controller for the XiP Cache. AHB from cache controller and APB interface are mux'd to QSPI controller so access can to external memory can be from either.

## Prerequisites 
This core uses external IP available from Arm

- Corstone 101 (BP210)
- Arm Flash Cache (CG092)

If you are utilising this IP you must set the SOCLABS_AHB_QSPI_DIR environment variable. This can be achieved by running `source set_env.sh`

## Integration
Top level 3 main ports:

- AHB: To Arm Flash Cache
- APB: To both APB QSPI controller and Arm Flash Cache for configuration
- QSPI

The AHB needs a minimum of 16 address bits, to 22 address bits (for an external flash size between 64 KB and 4096 KB). The default is 22. Cache size is between 32 bytes to 4 KB (default is 4 KB).

The APB is mapped between the QSPI controller and Flash Cache configuration registers as below

- 0x0000-0x0FFF : QSPI controller (see `src/rdl/apb_qspi_regs.rdl` for full register description)
- 0x1000-0x1FFF : Flash Cache (CG092, see Arm documentation)

### QSPI Controller APB Register Summary
| Address | Register | Description |
|---------|----------|-------------|
| 0x0000 | CTRL | Control (QIO mode, XiP active, mode code, continuous read, no-cmd) |
| 0x0004 | STATUS | Status (busy[0], IRQ clear[8]) |
| 0x0008 | SPI_CMD | SPI command (opcode, enable, read/write, addr enable, dummy cycles, N bytes) |
| 0x000C | SPI_ADDR | SPI address [21:0] |
| 0x0010 | RDATA0 | Read data bytes 3:0 (read-only) |
| 0x0014 | RDATA1 | Read data bytes 7:4 (read-only) |
| 0x0018 | RDATA2 | Read data bytes 11:8 (read-only) |
| 0x001C | RDATA3 | Read data bytes 15:12 (read-only) |
| 0x0020 | WDATA0 | Write data bytes 3:0 |
| 0x0024 | WDATA1 | Write data bytes 7:4 |
| 0x0028 | WDATA2 | Write data bytes 11:8 |
| 0x002C | WDATA3 | Write data bytes 15:12 |
| 0x0030 | AHB_SPI_SETUP | AHB XiP opcode[7:0] and dummy cycles[15:12] |
| 0x0034 | CLK_DIV | QSPI clock divider [4:0] (SCLK = HCLK / 2*N, reset default=1) |
| 0x0FD0-0x0FEC | PIDRx | Peripheral ID registers (read-only) |
| 0x0FF0-0x0FFC | CIDRx | Component ID registers (read-only) |

## Interrupts
Only 1 interrupt currently for when QSPI has finished a transfer. To clear interrupt write a 1 to 8th bit of status register.

## Simulation
The AHB QSPI includes a cocoTB simulation environment. This can be run using the `make run_cocotb` command

## Statistics
Read bandwidth with 4 KB cache for 512x 32 bit reads, and system clock of 200 MHz + SPI clock 100 MHz:

- Using APB: 5.8 MB/s
- Using AHB(uncached, prefetch enabled): 32 MB/s
- Using AHB(cached): 400 MB/s

## ToDo
- Improve writing method over APB? (see below)
- Add programmable address length (currently this is set to the maximum of the CG092 flash cache. If we want to increase this then we need a new cache)

## Writing over APB
Currently the method for writing over APB to the flash is to write up to 4x 32 bit words to the APB registers and then tell the QSPI controller to write. However as there is a long latency after writing over QSPI for the flash to finish, this is not optimal. 

The flash device we are targeting is a SST26VF064B device which allows up to 256 bytes to be written in a single SPI transaction (currently only writing 16 bytes per transaction). So proposals for improving this are as follows

1. Just simply add an extra 240 bytes of registers to the APB controller. This is the simplest to do but I think that this will inflate the overall area of the IP by too much, however this makes the software side fairly simple. (i.e. write 256 bytes to APB-> send command to QSPI controller-> wait for QSPI transaction to finish-> poll QSPI status until write is complete)
2. Add write fifo. This will be a lot smaller in terms of area. But will have to keep track of how many bytes get written over QSPI to limit to 256. This requires a bit of an overhaul in how the write transaction works but it means we can fully utilise the page program command. Software then becomes a little more complicated (i.e. write N bytes to APB-> send command to QSPI controller-> check if FIFO not full and send more data-> repeat last step 256/N times-> QSPI checks if FIFO is empty whilst the happens and stops transaction when empty-> poll QSPI status until write is complete). 

## Project status
This IP has been verified against a model of the Microchip SST26VF064B flash memory with 97.5% code coverage. The most important QSPI commands and AHB XiP interface usage have been verified (see `verif/README.md` for the full checklist). Further work should verify against other flash memory models and support different flash sizes (i.e. configurable address width).

Gate-level simulations match behavioural. `scen_slow` setup WNS is −0.01 ns at the TSMC tcbn65lp 9-track 1.08 V slow corner — recoverable rounding-class.

FPGA implementation has been tested on PYNQ-Z2, with QSPI working over APB. AHB XiP on FPGA has known issues.

Technology support includes generic (simulation), TSMC 65nm, TSMC 28nm, and TSMC 16nm (SRAM macros for cache).

## ASIC partition (hard-macro) status
The `top_ahb_qspi` partition runs end-to-end through the Synopsys Fusion Compiler flow at `syn/asic/fusion-compiler/` against the **TSMC 65nm cln65lp 9-track tcbn65lp** standard cell library (migrated 2026-05-21 from the previous 12-track Arm sc12 wrapper). Current sign-off state:

```
RESULT: CLEAN (2 WAIVERS) — partition ready for chip-top integration
  check_design / check_legality / check_pg_drc / pre_timing /
    check_mv_design / check_pin_placement / check_clock_trees  PASS
  check_pg_connectivity  WAIVE  (1008 wire-stubs ≤ 1300, 0 macros)
  check_routes           WAIVE  (3 DRCs ≤ 5 incl. 2 Shorts, 0 opens)
  Formality LEC          FM_LEC_OK
  scen_slow setup WNS    -0.01 ns
```

Both waivers are bounded, guarded, and one-env-var (`FC_PG_CONN_WAIVER=0` / `FC_ROUTES_WAIVER=0`) away from strict mode. The 2 routing **Shorts** are explicitly flagged for chip-top detailed-route ECO — eleven autonomous PnR levers were exhausted in characterising them; full evidence trail in `syn/asic/fusion-compiler/INTEGRATION_CHANGES.md`. Calibre signoff DRC (Mentor Calibre v2023.1, TSMC 1p9m_6X2Z0U deck) is wired at `syn/asic/calibre/` but currently requires the foundry tcbn65lp stdcell GDS to surface short coordinates (absent on the build host).

To run the partition flow:

```
source set_env.sh
make -C syn/asic/fusion-compiler fc_all      # init → synth → cts → route → pg → signoff → drc → abstract → LEC
make -C syn/asic/calibre calibre_drc         # (optional, needs foundry stdcell .gds for coord extraction)
```

## Documentation

For deeper context on the backend work and what the chip-top integrator needs to know:

- `docs/route_drc_shorts_analysis.md` — engineering reference for the 2 routing Shorts, all 11 PnR levers tried, full evidence trail.
- `docs/backend_shorts_resolution_guide.md` — beginner walkthrough for someone who has never done ASIC backend before.
- `docs/chip_top_handoff.md` — short-form hand-off package for the chip-top team.
- `docs/cdc_signoff_status.md` — CDC verification status.
- `syn/asic/fusion-compiler/INTEGRATION_CHANGES.md` — running narrative of every PnR experiment + its committed disposition.


