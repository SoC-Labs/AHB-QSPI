# AHB QSPI Controller -- UVM Verification Plan

## 1. Overview

This verification plan covers the UVM-based functional verification of the AHB QSPI controller IP (`ahb_qspi`). The IP provides dual-path access to external quad SPI flash:
- **APB register path**: Full programmatic control of SPI/QPI transactions
- **AHB XIP path**: Read-only execute-in-place through a 2-way 4KB cache

### DUT Hierarchy Under Test
| Module | File | Description |
|--------|------|-------------|
| `qspi_controller` | `logical/qspi_controller/logical/qspi_controller.sv` | QSPI protocol engine and FSM |
| `apb_qspi_regs` | `logical/apb_qspi_regs/logical/apb_qspi_regs.v` | APB register bank |
| `ahb_qspi_interface` | `logical/ahb_qspi_interface/logical/ahb_qspi_interface.sv` | AHB-to-QSPI read-only interface |
| `qspi_controller_mux` | `logical/qspi_controller/logical/qspi_controller_mux.v` | APB/AHB mux to QSPI controller |
| `qspi_clock_div` | `logical/qspi_controller/logical/qspi_clock_div.v` | Programmable SCLK clock divider |
| `cache_subsystem` | `logical/cache_subsytem/logical/cache_subsystem.v` | Flash cache wrapper (Arm CG092) |
| `top_ahb_qspi` | `logical/top_ahb_qspi/logical/top_ahb_qspi.v` | Top-level integration |

### Testbench Architecture
- **Top module**: `test_top` (`uvm/ahb_qspi/tb/top.sv`)
- **DUT wrapper**: `ahb_qspi_pads` (pad-level wrapper with tri-state QSPI IO)
- **Flash model**: SST26VF064B (Microchip 64Mb SPI flash, timing parameters reduced for simulation)
- **Clock**: 100 MHz (10 ns period)
- **UVM Environment** (`ahb_qspi_env`):
  - **APB Master Agent** (`apb_master_agent`): Driver, monitor, sequencer for APB register access
  - **QSPI Monitor** (`qspi_monitor`): Passive monitor on QSPI SCLK/nCS/IO signals
  - **Scoreboard** (`ahb_qspi_scoreboard`): Dual-port analysis (APB + QSPI), shadow register model, check counters
  - **Coverage** (`ahb_qspi_coverage`): Functional covergroups sampled from APB transactions
- **AHB Data Interface** (`ahb_data_if`): Directly driven by test-level helper tasks for XIP reads/writes
- **Interfaces**:
  - `apb_master_if` -- APB signals with driver and monitor modports
  - `ahb_data_if` -- AHB slave port signals with master modport and clocking block
  - `qspi_monitor_if` -- QSPI bus signals (SCLK, nCS, IO[3:0])

---

## 2. Register Map

| Offset | Name | Bits | Access | Description |
|--------|------|------|--------|-------------|
| 0x00 | REG0 (Control) | [0] QIO_MODE, [8] XIP_ACTIVE, [23:16] MODE_CODE, [24] CONT_READ, [25] NO_CMD | R/W | Configuration |
| 0x04 | REG1 (Status) | [0] BUSY (RO), [8] IRQ_CLR (W1C) | R/W | Status and IRQ clear |
| 0x08 | REG2 (Command) | [7:0] CMD, [8] ENABLE, [9] READ, [10] WRITE, [11] ADDR_EN, [15:12] DUMMY_CYCLES, [19:16] N_RW_BYTES | R/W | QSPI command descriptor |
| 0x0C | REG3 (Address) | [21:0] ADDR | R/W | QSPI address |
| 0x10-0x1C | REG4-7 (RDATA) | [31:0] | RO | Read data (4x32-bit) |
| 0x20-0x2C | REG8-11 (WDATA) | [31:0] | R/W | Write data (4x32-bit) |
| 0x30 | REG12 (AHB Setup) | [7:0] AHB_CMD, [15:12] AHB_DUMMY_CYCLES | R/W | AHB XIP command config |
| 0x34 | REG13 (CLK Div) | [4:0] CLK_DIV | R/W | SCLK clock divider (reset=0x01) |
| 0xFD0-0xFEC | PIDR4-PIDR3 | [7:0] | RO | Peripheral ID registers |
| 0xFE0-0xFEC | PIDR0-PIDR3 | [7:0] | RO | Peripheral ID registers |
| 0xFF0-0xFFC | CIDR0-CIDR3 | [7:0] | RO | Component ID registers |

### Expected ID Values

| Register | Value |
|----------|-------|
| PIDR0 | 0x59 |
| PIDR1 | 0x16 |
| PIDR2 | 0x15 |
| PIDR3 | 0x00 |
| PIDR4 | 0x00 |
| CIDR0 | 0x50 |
| CIDR1 | 0x51 |
| CIDR2 | 0x4C |
| CIDR3 | 0x53 |

---

## 3. Implemented Tests

### 3.1 ahb_qspi_register_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_register_test.sv` |
| **Feature** | Register reset values, read/write, PID/CID identification, reserved addresses |
| **Description** | Verifies all register reset values (CTRL, STATUS, SPI_CMD, ADDR, AHB_SETUP, CLK_DIV). Reads and verifies all 9 PID/CID registers against expected constants. Tests write/readback on CTRL, CLK_DIV (max value 0x1F), and ADDR (max value 0x3FFFFF). Performs a walking-1 test on WDATA0 (all 32 bits). Reads unmapped addresses (0x0040, 0x0100) and verifies they return 0xDEADCAFE. |
| **Assertions/Checks** | 6 reset value checks, 9 PID/CID checks, 3 R/W checks, 32 walking-1 checks, 2 reserved address checks (52 total) |
| **FSM States** | N/A (register access only) |
| **Coverage** | Register read/write access to all addresses, ID verification, reserved address behavior |

### 3.2 ahb_qspi_spi_cmd_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_spi_cmd_test.sv` |
| **Feature** | SPI mode commands: JEDEC ID, status register read, page program, fast read, write enable/disable |
| **Description** | Initialises flash (RSTEN + RST + WREN + ULBPR). Reads JEDEC ID (3 bytes, cmd 0x9F) and verifies against expected value 0x4326BF00. Reads status register (cmd 0x05). Performs a page program (cmd 0x02) at address 0x000000 with 4 bytes of data (0xDEADBEEF), polls flash BUSY via RDSR. Reads back with standard read (cmd 0x03, 0 dummy cycles) and fast read (cmd 0x0B, 8 dummy cycles). Issues WRDI to disable writes. |
| **Assertions/Checks** | 1 JEDEC ID verification via scoreboard |
| **FSM States** | IDLE, OP, ADDR, DATA_O, DATA_I, DUMMY |
| **Coverage** | SPI opcodes (0x9F, 0x05, 0x06, 0x02, 0x03, 0x0B, 0x04), read/write data paths |

### 3.3 ahb_qspi_qpi_cmd_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_qpi_cmd_test.sv` |
| **Feature** | QPI mode: enter QPI, JEDEC ID in quad mode, fast read, exit QPI, verify SPI still works |
| **Description** | Initialises flash with QPI mode enabled (EQIO 0x38 + QIO_MODE bit). Reads QPI JEDEC ID (cmd 0xAF, 3 bytes) and verifies. Performs QPI fast read at address 0x0 with 4 dummy cycles. Exits QPI mode (RSTQIO 0xFF), clears QIO_MODE bit, then verifies SPI JEDEC ID (cmd 0x9F) still works correctly. |
| **Assertions/Checks** | 2 JEDEC ID verifications (QPI mode + SPI after QPI exit) |
| **FSM States** | IDLE, OP, ADDR, DUMMY, DATA_I |
| **Coverage** | QPI mode entry/exit, QIO_MODE register bit, quad JEDEC ID opcode |

### 3.4 ahb_qspi_xip_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_xip_test.sv` |
| **Feature** | AHB XIP memory-mapped reads |
| **Description** | Initialises flash and programs 16 bytes at address 0 with a known pattern (0xAABBCCDD, 0x11223344, 0x55667788, 0x99AABBCC). Configures AHB_SETUP with fast read (0x0B) and 8 dummy cycles. Enables XIP mode via CTRL[8]. Performs 8 sequential AHB word reads at addresses 0x00-0x1C using the `ahb_read` helper task. Disables XIP after reads. |
| **Assertions/Checks** | Informational read-data logging (no explicit scoreboard checks in test body) |
| **FSM States** | All states via XIP path (IDLE, OP, ADDR, DUMMY, DATA_I) |
| **Coverage** | XIP_ACTIVE enable/disable, AHB_SETUP configuration, AHB read transactions |

### 3.5 ahb_qspi_error_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_error_test.sv` |
| **Feature** | Error paths: AHB write rejection in XIP mode, AHB read without XIP, APB BUSY during XIP |
| **Description** | Enables XIP mode, then attempts an AHB write transaction and verifies HRESP=1 (ERROR). Disables XIP, then attempts an AHB read without XIP active and verifies HRESP=1. Re-enables XIP and reads STATUS register to verify BUSY is forced high during XIP (blocking APB commands). |
| **Assertions/Checks** | 2 HRESP error checks (write rejection + read without XIP), 1 STATUS BUSY observation |
| **FSM States** | IDLE, ERR (AHB error response states) |
| **Coverage** | AHB write rejection, AHB read error without XIP, APB BUSY during XIP |

### 3.6 ahb_qspi_clkdiv_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_clkdiv_test.sv` |
| **Feature** | Clock divider correctness across full range |
| **Description** | Initialises flash, then runs the `clkdiv_sweep_sequence` which sweeps CLK_DIV from 1 to 31 (all valid non-bypass values). At each divider setting, issues a JEDEC ID read and verifies the returned data matches the expected value 0x4326BF00. Restores default divider value after sweep. |
| **Assertions/Checks** | 31 JEDEC ID data comparisons (one per divider value) |
| **FSM States** | IDLE, OP, DATA_I (JEDEC ID read path) |
| **Coverage** | Full CLK_DIV range (1-31), clock divider functional correctness |

### 3.7 ahb_qspi_irq_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_irq_test.sv` |
| **Feature** | Interrupt lifecycle: assertion on completion, clear via IRQ_CLR, multiple cycles |
| **Description** | Verifies IRQ is initially low after reset. Issues a JEDEC ID command manually (two-phase setup/enable, without auto IRQ clear) and polls BUSY until command completes. Checks IRQ_QSPI_FINISHED is asserted after completion. Writes IRQ_CLR bit (STATUS[8]) and verifies IRQ deasserts. Runs 5 additional JEDEC ID commands via `qspi_cmd_sequence` (which auto-clears IRQ) to verify IRQ cycles reliably. |
| **Assertions/Checks** | 1 IRQ-low check, 1 IRQ-asserted check, 1 IRQ-cleared check, 5 command cycle completions |
| **FSM States** | IDLE, OP, DATA_I |
| **Coverage** | IRQ assertion, IRQ_CLR mechanism, IRQ lifecycle across multiple commands |

### 3.8 ahb_qspi_arb_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_arb_test.sv` |
| **Feature** | XIP/APB arbitration: XIP toggle while idle, APB after XIP disable, interleaved access |
| **Description** | Rapidly toggles XIP_ACTIVE on and off 10 times while QSPI is idle to stress the mux. Enables then disables XIP, then issues a JEDEC ID command via APB to verify the APB path works correctly after XIP mode. Interleaves 5 APB JEDEC ID commands with brief XIP enable/disable cycles (20 clock settle time) to verify no corruption. |
| **Assertions/Checks** | 1 JEDEC ID verification after XIP toggle, implicit completion checks on all 5 interleaved commands |
| **FSM States** | IDLE, OP, DATA_I |
| **Coverage** | XIP_ACTIVE toggling, APB/AHB mux arbitration, post-XIP APB operability |

### 3.9 ahb_qspi_reset_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_reset_test.sv` |
| **Feature** | Register modification and software-level restore to defaults |
| **Description** | Writes non-default values to CTRL, ADDR, CLK_DIV, and AHB_SETUP registers and verifies the write took effect. Restores all registers to their reset default values via APB writes. Verifies CTRL, CLK_DIV, and AHB_SETUP return to defaults. Re-initialises flash and issues a JEDEC ID command to verify the controller FSM is still functional. |
| **Assertions/Checks** | 1 pre-restore verification, 3 post-restore register checks, 1 JEDEC ID verification |
| **FSM States** | IDLE, OP, DATA_I |
| **Coverage** | Register restore to defaults, post-restore operational verification |

### 3.10 ahb_qspi_stress_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_stress_test.sv` |
| **Feature** | Multi-phase stress: register storm, clock divider sweep, dummy cycle walk, mode switching frenzy |
| **Description** | **Phase 1**: Initialises flash with block protection cleared. **Phase 2**: Runs `reg_storm_sequence` with 200 randomised APB transactions targeting all R/W registers with random data, then verifies JEDEC ID still works (with flash re-init via RSTEN+RST). **Phase 3**: Runs `clkdiv_sweep_sequence` sweeping CLK_DIV 1-31 with JEDEC ID verification at each value. **Phase 4**: Runs `dummy_sweep_sequence` sweeping DUMMY_CYCLES 0-15 with fast reads. **Phase 5**: Runs `mode_switch_sequence` with 20 rapid SPI/QPI mode switches, issuing JEDEC ID in each mode. |
| **Assertions/Checks** | 1 post-storm JEDEC check, 31 CLK_DIV sweep checks, 16 dummy sweep reads, 40 mode switch JEDEC reads |
| **FSM States** | All states (IDLE, OP, ADDR, DUMMY, DATA_I, DATA_O, MODE) |
| **Coverage** | Register stress, full CLK_DIV range, full DUMMY_CYCLES range, SPI/QPI mode switching |

### 3.11 ahb_qspi_data_integrity_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_data_integrity_test.sv` |
| **Feature** | Data pattern sweep, multi-word program sizes, cross-mode (SPI vs QPI) consistency |
| **Description** | **Phase 1**: Flash init with block protection cleared. **Phase 2**: `data_pattern_sequence` in SPI mode -- programs and verifies 8 patterns at different addresses: all-zeros, all-ones, alternating 0xAA, alternating 0x55, walking-1, walking-0, byte-ramp, nibble-swap. **Phase 3**: `multiword_program_sequence` in SPI mode -- programs and verifies 1, 2, 3, and 4 word writes independently at different addresses. **Phase 4**: `cross_mode_verify_sequence` -- programs data in SPI mode, reads back in SPI and QPI, compares all 4 words between modes. **Phase 5**: `data_pattern_sequence` repeated in QPI mode. |
| **Assertions/Checks** | 32 pattern checks (8 patterns x 4 words), 10 multi-word checks (1+2+3+4 words), 12 cross-mode checks (4 words x 3 comparisons), 32 QPI pattern checks (86 total) |
| **FSM States** | IDLE, OP, ADDR, DATA_O, DATA_I, DUMMY |
| **Coverage** | Bit-level data integrity, nibble/byte ordering, N_RW_BYTES write sizes, SPI vs QPI data path consistency |

### 3.12 ahb_qspi_corner_case_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_corner_case_test.sv` |
| **Feature** | N_RW_BYTES sweep, simultaneous R+W bits, back-to-back commands, address boundaries, continuous read mode |
| **Description** | **Phase 1**: Flash init. **Phase 2**: `n_rw_bytes_sweep_sequence` -- exercises all 16 N_RW_BYTES values (0-15, encoding 1-16 bytes) with fast reads at address 0. **Phase 3**: `simultaneous_rw_sequence` -- sets both READ and WRITE bits simultaneously and verifies the controller does not hang. **Phase 4**: `back_to_back_cmd_sequence` -- issues 50 consecutive JEDEC ID reads without extra delay, verifying data each time. **Phase 5**: `addr_boundary_sequence` -- reads at address 0x000000 and near-max address 0x3FFF00 to test 22-bit address field boundaries. **Phase 6**: `continuous_read_sequence` -- enters QPI with CONT_READ and MODE_CODE=0xA0, performs initial read to set last_QSPI_ADDR, enables NO_CMD, reads same address (NO_FETCH path), reads different address (ADDR path), then cleans up. |
| **Assertions/Checks** | 16 N_RW reads, 1 simultaneous R+W completion, 50 back-to-back JEDEC checks, 2 address boundary reads, 2 continuous read path completions |
| **FSM States** | All states including NO_FETCH, MODE |
| **Coverage** | Full N_RW_BYTES range, invalid R+W config, ENABLE_ACK handshake stress, address boundaries, CONT_READ + NO_CMD paths |

### 3.13 ahb_qspi_rdata_readonly_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_rdata_readonly_test.sv` |
| **Feature** | RDATA register (REG4-7) write protection |
| **Description** | **Phase 1**: Verifies all 4 RDATA registers are zero after reset. **Phase 2**: Attempts to write 0xDEADBEEF to each RDATA register. **Phase 3**: Reads back and verifies all RDATA registers remain zero (write had no effect). **Phase 4**: Performs a real JEDEC ID read to populate RDATA0, verifies RDATA0 is non-zero (updated by QSPI controller), then attempts to overwrite RDATA0 with 0xFFFFFFFF and verifies the overwrite did not take effect. |
| **Assertions/Checks** | 4 reset-zero checks, 4 write-protection checks, 1 RDATA update check, 1 post-read overwrite check (10 total) |
| **FSM States** | IDLE, OP, DATA_I |
| **Coverage** | Read-only register enforcement, RDATA update from QSPI controller |

### 3.14 ahb_qspi_xip_stress_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_xip_stress_test.sv` |
| **Feature** | XIP multi-address reads, cache thrashing, reverse-order re-reads, write rejection, post-XIP APB verify |
| **Description** | **Phase 1**: Programs 4 pages at addresses 0x000, 0x100, 0x200, 0x300 with unique patterns (16 bytes each), polling flash BUSY after each program. **Phase 2**: Enables XIP mode and reads all 16 words (4 pages x 4 words) via AHB, verifying each against expected data. **Phase 3**: Re-reads first word of each page in reverse order (page 3, 2, 1, 0) to exercise cache miss/hit patterns. **Phase 4**: Attempts AHB write in XIP mode and verifies HRESP=1 error. **Phase 5**: Disables XIP and verifies APB JEDEC ID command still works correctly. |
| **Assertions/Checks** | 16 forward XIP read checks, 4 reverse re-read checks, 1 AHB write rejection check, 1 JEDEC post-XIP check (22 total) |
| **FSM States** | All states via XIP path |
| **Coverage** | XIP multi-address access, cache thrash patterns, XIP write rejection, post-XIP APB operability |

### 3.15 ahb_qspi_reset_recovery_test

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `tests/ahb_qspi_reset_recovery_test.sv` |
| **Feature** | Software-level reset recovery from configured state, multi-cycle restore and verify |
| **Description** | **Phase 1**: Initialises flash, programs 16 bytes at address 0, polls flash BUSY, then modifies CLK_DIV (0x0F) and AHB_SETUP (0x800B) to non-default values. **Phase 2**: Restores all registers (CTRL, SPI_CMD, ADDR, CLK_DIV, AHB_SETUP) to their reset default values via APB writes. Verifies CLK_DIV and AHB_SETUP match expected reset values. **Phase 3**: Re-initialises flash and issues JEDEC ID read to verify the controller is operational post-restore. **Phase 4**: Runs 3 additional restore cycles -- each cycle sets CLK_DIV to a non-default value, restores to default, verifies CLK_DIV, re-initialises flash, and verifies JEDEC ID. |
| **Assertions/Checks** | 2 post-restore register checks, 1 JEDEC post-restore check, 3 CLK_DIV cycle checks, 3 JEDEC cycle checks (9 total) |
| **FSM States** | IDLE, OP, ADDR, DATA_O, DATA_I |
| **Coverage** | Register restore to defaults, multi-cycle recovery, post-restore operational verification |

---

## 4. Sequences

### 4.1 Primitive Sequences

| Sequence | File | Description |
|----------|------|-------------|
| `apb_read_sequence` | `sequences/apb_read_sequence.sv` | Single APB read transaction. Takes `addr`, returns `rdata` after completion. |
| `apb_write_sequence` | `sequences/apb_write_sequence.sv` | Single APB write transaction. Takes `addr` and `wdata`. |

### 4.2 Command Sequences

| Sequence | File | Description |
|----------|------|-------------|
| `qspi_cmd_sequence` | `sequences/qspi_cmd_sequence.sv` | Generic QSPI command via APB registers. Implements the two-phase protocol (setup with ENABLE=0, then trigger with ENABLE=1). Configurable: opcode, do_read, do_write, addr_en, dummy_cycles, n_rw_bytes, flash_addr, wdata[4]. Polls BUSY for completion. Reads back RDATA[0-3] if do_read=1. Auto-clears IRQ. N_RW_BYTES encoding: value N means (N+1) bytes transferred. |
| `qspi_init_sequence` | `sequences/qspi_init_sequence.sv` | Flash initialisation: sets CLK_DIV=5, issues RSTEN+RST. Optionally clears block protection (WREN + ULBPR) and/or enters QPI mode (EQIO + QIO_MODE bit). |

### 4.3 XIP Sequences

| Sequence | File | Description |
|----------|------|-------------|
| `qspi_xip_enable_sequence` | `sequences/qspi_xip_sequence.sv` | Configures AHB_SETUP register (opcode + dummy cycles) and enables XIP mode via CTRL[8]. Configurable: `ahb_cmd` (default 0x0B), `ahb_dummy` (default 8). |
| `qspi_xip_disable_sequence` | `sequences/qspi_xip_sequence.sv` | Disables XIP mode by writing 0 to CTRL register. |

### 4.4 Stress Sequences

| Sequence | File | Description |
|----------|------|-------------|
| `reg_storm_sequence` | `sequences/qspi_stress_sequence.sv` | Randomised register storm: writes random data to random R/W registers (CTRL, SPI_CMD, ADDR, WDATA0-3, AHB_SETUP, CLK_DIV). Configurable `num_transactions` (50-500, default randomised). |
| `clkdiv_sweep_sequence` | `sequences/qspi_stress_sequence.sv` | Sweeps CLK_DIV from 1 to 31, issuing a JEDEC ID read at each value and checking the result against expected. |
| `dummy_sweep_sequence` | `sequences/qspi_stress_sequence.sv` | Sweeps DUMMY_CYCLES from 0 to 15 with fast reads at address 0, exercising all dummy cycle boundary values. |
| `mode_switch_sequence` | `sequences/qspi_stress_sequence.sv` | Rapidly alternates between SPI and QPI modes. Each iteration: EQIO, set QIO_MODE, QPI JEDEC read, RSTQIO, clear QIO_MODE, SPI JEDEC read. Configurable `num_switches` (10-50). |

### 4.5 Data Integrity Sequences

| Sequence | File | Description |
|----------|------|-------------|
| `page_program_verify_sequence` | `sequences/qspi_data_integrity_sequence.sv` | Programs N words (1-4) at a given flash address, polls flash BUSY, reads back with fast read, and compares each word. Supports both SPI and QPI modes (adjusts dummy cycles accordingly). |
| `data_pattern_sequence` | `sequences/qspi_data_integrity_sequence.sv` | Programs and verifies 8 data patterns: all-zeros, all-ones, alternating 0xAA, alternating 0x55, walking-1, walking-0, byte-ramp, nibble-swap. Each pattern written to a different address in the 0x010000 range. |
| `multiword_program_sequence` | `sequences/qspi_data_integrity_sequence.sv` | Tests 1, 2, 3, and 4 word program operations independently at different addresses in the 0x020000 range. |
| `cross_mode_verify_sequence` | `sequences/qspi_data_integrity_sequence.sv` | Programs data in SPI mode, reads back in SPI and QPI modes, compares all 4 words across both modes to verify data consistency. |

### 4.6 Corner Case Sequences

| Sequence | File | Description |
|----------|------|-------------|
| `n_rw_bytes_sweep_sequence` | `sequences/qspi_corner_case_sequence.sv` | Sweeps N_RW_BYTES from 0 to 15 (1-16 bytes) with fast reads at address 0. |
| `simultaneous_rw_sequence` | `sequences/qspi_corner_case_sequence.sv` | Sets both READ=1 and WRITE=1 simultaneously in SPI_CMD register, triggers the command, and polls for completion to verify the controller does not hang on invalid configuration. |
| `back_to_back_cmd_sequence` | `sequences/qspi_corner_case_sequence.sv` | Issues N consecutive JEDEC ID reads without extra delay, verifying data each time. Stresses the ENABLE/ENABLE_ACK handshake. Configurable `num_commands` (20-100). |
| `addr_boundary_sequence` | `sequences/qspi_corner_case_sequence.sv` | Reads at address 0x000000 and near-max address 0x3FFF00 to test 22-bit address field boundaries. |
| `continuous_read_sequence` | `sequences/qspi_corner_case_sequence.sv` | Enters QPI with CONT_READ and MODE_CODE=0xA0. Performs initial read to set last_QSPI_ADDR, enables NO_CMD, reads same address (NO_FETCH path), reads different address (ADDR path). Cleans up by disabling NO_CMD, exiting QPI. |

---

## 5. Coverage Strategy

### 5.1 Functional Coverage (UVM -- `ahb_qspi_coverage.sv`)

The `ahb_qspi_coverage` component is a `uvm_subscriber` that samples APB transactions from the APB monitor analysis port. It implements four covergroups:

#### `cg_apb_access` -- Register Access Coverage
| Coverpoint | Bins | Description |
|------------|------|-------------|
| `cp_addr` | ctrl, status, spi_cmd, addr_reg, rdata[4], wdata[4], ahb_setup, clk_div, pid[8], cid[4] | All register addresses accessed |
| `cp_rw` | read, write | Read vs write direction |
| `cx_addr_rw` | cross of cp_addr x cp_rw | Every register accessed in both read and write directions |

#### `cg_spi_command` -- SPI Command Coverage
| Coverpoint | Bins | Description |
|------------|------|-------------|
| `cp_opcode` | read, fast_read, rsten, rst, eqio, rstqio, rdsr, wren, wrdi, jedec_id, pp, se, be, ce, ulbpr, other | All SPI/QPI opcodes issued |
| `cp_qio` | spi_mode, quad_mode | Both SPI and QPI modes exercised |
| `cp_dummy` | zero, low(1-3), mid(4-7), high(8-15) | Dummy cycle ranges |
| `cp_n_rw` | zero, one, mid(2-8), max(9-15) | N_RW_BYTES ranges |
| `cx_opcode_mode` | cross of cp_opcode x cp_qio | Every opcode in both SPI and QPI modes |
| `cx_opcode_dummy` | cross of cp_opcode x cp_dummy | Every opcode with each dummy cycle range |

#### `cg_clk_div` -- Clock Divider Coverage
| Coverpoint | Bins | Description |
|------------|------|-------------|
| `cp_div` | bypass(0), div_1(1), div_low(2-7), div_mid(8-15), div_high(16-31) | Clock divider ranges |

#### `cg_xip` -- XIP Mode Coverage
| Coverpoint | Bins | Description |
|------------|------|-------------|
| `cp_xip` | 0, 1 | XIP mode enabled and disabled |

### 5.2 RTL Coverage (via VCS)

Code coverage is collected by VCS with the following metrics, scoped to the DUT hierarchy only:
- **Line coverage** (`-cm line`)
- **Condition coverage** (`-cm cond`)
- **Toggle coverage** (`-cm tgl`)
- **FSM coverage** (`-cm fsm`)
- **Branch coverage** (`-cm branch`)

RTL modules under coverage:
- `qspi_controller` -- QSPI protocol engine and FSM
- `apb_qspi_regs` -- APB register bank
- `ahb_qspi_interface` -- AHB-to-QSPI read-only interface
- `qspi_controller_mux` -- APB/AHB mux
- `qspi_clock_div` -- Programmable SCLK divider

Excluded from coverage (pre-verified external IP):
- `cache_subsystem` / `p_flash_cache_f0`
- `sst26vf064b` (flash memory model)

---

## 6. Test Execution

### 6.1 Compilation

```bash
cd uvm/ahb_qspi
make compile
```

This generates an expanded filelist (resolving environment variables), then compiles using VCS with UVM-1.2, SystemVerilog, xprop, and code coverage enabled.

### 6.2 Running Individual Tests

```bash
# Run a specific test (compiles first if needed)
make run TEST=ahb_qspi_register_test

# Run with a specific seed
make run TEST=ahb_qspi_spi_cmd_test SEED=12345

# Run with higher verbosity
make run TEST=ahb_qspi_irq_test VERBOSITY=UVM_HIGH

# Run with VCD waveform dumping
make waves TEST=ahb_qspi_xip_test
```

### 6.3 Running Full Regression

```bash
make run_all
```

This runs all 15 tests sequentially with automatic random seeds. Reports pass/fail count at completion. Each test log is saved as `sim_build/<test_name>.log`.

### 6.4 Available Tests

| Test Name | Description |
|-----------|-------------|
| `ahb_qspi_register_test` | Register reset values, read/write, PID/CID |
| `ahb_qspi_spi_cmd_test` | SPI mode: JEDEC ID, read, page program |
| `ahb_qspi_qpi_cmd_test` | QPI mode: enter/exit, JEDEC ID, fast read |
| `ahb_qspi_xip_test` | XIP memory-mapped reads via AHB |
| `ahb_qspi_error_test` | Error paths: write reject, no-XIP read |
| `ahb_qspi_clkdiv_test` | Clock divider sweep (1-31) |
| `ahb_qspi_irq_test` | Interrupt assert/clear |
| `ahb_qspi_arb_test` | XIP/APB arbitration |
| `ahb_qspi_reset_test` | Reset recovery |
| `ahb_qspi_stress_test` | Register storm, mode frenzy, dummy sweep |
| `ahb_qspi_data_integrity_test` | Data patterns, multi-word, cross-mode |
| `ahb_qspi_corner_case_test` | N_RW sweep, R+W bits, back-to-back, addr |
| `ahb_qspi_rdata_readonly_test` | RDATA register write protection |
| `ahb_qspi_xip_stress_test` | XIP multi-address, cache, verify |
| `ahb_qspi_reset_recovery_test` | Reset from configured state, multi-cycle |

### 6.5 Coverage Report Generation

```bash
# Generate merged coverage report after running tests
make coverage
```

This runs VCS `urg` to merge coverage databases from `sim_build/simv.vdb` and generates an HTML + text report in `coverage_report/`.

### 6.6 Cleanup

```bash
make clean
```

Removes `sim_build/`, `coverage_report/`, and all build artifacts.

### 6.7 Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TEST` | `ahb_qspi_register_test` | UVM test name to run |
| `SEED` | `random` | Random seed (integer or `random` for automatic) |
| `VERBOSITY` | `UVM_MEDIUM` | UVM verbosity level (`UVM_NONE` to `UVM_DEBUG`) |
