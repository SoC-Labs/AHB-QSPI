# AHB QSPI Controller — Cocotb Verification Plan

## 1. Overview

This verification plan covers the cocotb-based functional verification of the AHB QSPI controller IP (`ahb_qspi`). The IP provides dual-path access to external quad SPI flash:
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
- **Testbench wrapper**: `verif/cocotb/ahb_qspi_cocotb.v`
- **Flash model**: SST26VF064B (Microchip 64Mb SPI flash)
- **AHB BFM**: `cocotbext.ahb.AHBLiteMaster` (two instances: config + data)
- **Bridge**: `cmsdk_ahb_to_apb` (config AHB → APB)
- **Clock**: 100 MHz (10 ns period)

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
| 0x34 | REG13 (CLK Div) | [4:0] CLK_DIV | R/W | SCLK clock divider |
| 0xFD0-0xFFC | PID/CID | [7:0] | RO | Peripheral/Component ID |

---

## 3. Implemented Tests

### 3.1 APB_reg_tests

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `ahb_qspi_tests.py:48-92` |
| **Feature** | APB register identification and basic read/write |
| **Description** | Verifies PIDR0-7 and CIDR0-3 identification registers return expected values. Tests write/readback of REG0, REG1, REG2, REG3, REG12. |
| **Assertions** | 8 register value checks |
| **FSM States** | N/A (register access only) |
| **Coverage** | Register read, register write, ID verification |

### 3.2 QSPI_TESTS

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `ahb_qspi_tests.py:94-244` |
| **Feature** | Comprehensive SPI/QPI functional test |
| **Description** | Tests SPI reset sequence (RSTEN + RST), JEDEC ID read in SPI and QPI modes, write enable/disable, block protection clear, page programming with 1-4 words, byte-level reads (1-15 bytes), status register write, FSM state transitions (MODE→DATA_I, MODE→DATA_O, DUMMY→DATA_O, ADDR→IDLE, DUMMY→IDLE, MODE→IDLE) in both SPI and QPI modes, clock divider changes (0x02, 0x1F), slow SPI reads. |
| **Assertions** | ~20 data verification assertions |
| **FSM States** | IDLE, OP, ADDR, MODE, DUMMY, DATA_I, DATA_O |
| **Coverage** | SPI mode, QPI mode, mode switching, variable data sizes, clock scaling, state transitions |

### 3.3 QSPI_READ_TESTS

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `ahb_qspi_tests.py:249-419` |
| **Feature** | Bulk programming, AHB XIP, cache, performance |
| **Description** | Programs 64x16-byte blocks with random data. Measures APB continuous read bandwidth. Configures AHB XIP mode (fast read 0x0B, 4 dummy cycles). Enables/disables flash cache, measures uncached vs cached AHB read bandwidth. Sweeps full 16MB address range. Tests AHB write error response. Tests slow clock (divider=5). |
| **Assertions** | 6 data correctness assertions |
| **FSM States** | All states via XIP path |
| **Coverage** | Bulk data, cache enable/disable, XIP mode, bandwidth measurement, full address range, error handling |

### 3.4 CACHE_CONFIG

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `ahb_qspi_tests.py:422-430` |
| **Feature** | Cache configuration register reset value |
| **Description** | Reads cache config register (0x1000) after reset, verifies default value is 0x40. |
| **Assertions** | 1 |
| **FSM States** | N/A |
| **Coverage** | Cache register defaults |

### 3.5 AHB_BAD_BEHAVIOUR

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `ahb_qspi_tests.py:432-443` |
| **Feature** | AHB error response handling |
| **Description** | Attempts AHB write (should fail with ERROR). Attempts AHB read when not in XIP mode (should fail). Asserts HRESP=ERROR for both. |
| **Assertions** | 2 (write error + read error) |
| **FSM States** | IDLE, ERR |
| **Coverage** | AHB write rejection, AHB read without XIP |

### 3.6 test_bug1_rdata_latch

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `ahb_qspi_tests.py:446-512` |
| **Feature** | QSPI_RDATA combinational output correctness |
| **Bug Targeted** | BUG-1: QSPI_RDATA latch in `always_comb` (missing else branch when `QSPI_nCS=0`) |
| **Description** | Verifies QSPI_RDATA is zero after reset. Programs data at two addresses with different sizes (1 word and 2 words). Performs three sequential reads: 1-word read, 2-word read, then re-reads 1-word address. Verifies RDATA updates correctly each time, confirming no stale latched values persist. |
| **Assertions** | 4 (reset value + 3 read comparisons) |
| **FSM States** | IDLE, OP, ADDR, DUMMY, DATA_I |
| **Coverage** | RDATA update across different N_RW_BYTES, reset behavior |

### 3.7 test_bug2_enable_ack_latch

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `ahb_qspi_tests.py:515-601` |
| **Feature** | QSPI_ENABLE_ACK behavior during all FSM states |
| **Bug Targeted** | BUG-2: QSPI_ENABLE_ACK not assigned in MODE, DUMMY, DATA_O, DATA_I states |
| **Description** | Exercises transactions that traverse MODE, DUMMY, and DATA states: (1) QPI fast read with 6 dummy cycles (DUMMY→DATA_I), (2) continuous read with mode byte (MODE→DUMMY→DATA_I), (3) MODE→DATA_I transition, (4) DUMMY→DATA_O transition. After each transaction, verifies the controller is no longer busy (proving ENABLE_ACK was handled correctly through those states). |
| **Assertions** | 5 (1 data check + 4 busy=0 checks) |
| **FSM States** | MODE, DUMMY, DATA_I, DATA_O |
| **Coverage** | ENABLE_ACK behavior in all FSM states |

### 3.8 test_bug3_no_cmd_last_addr

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **File** | `ahb_qspi_tests.py:604-697` |
| **Feature** | NO_CMD / NO_FETCH FSM path and `last_QSPI_ADDR` tracking |
| **Bug Targeted** | BUG-3: `last_QSPI_ADDR` assigned in `always_comb` (latch) |
| **Description** | Programs data at addresses A (0x3000) and B (0x3100). Performs a normal read to A (sets `last_QSPI_ADDR`). Enables NO_CMD mode (bit 25 of REG0). Reads same address A (expects NO_FETCH path). Reads different address B (expects ADDR path). Reads B again (expects NO_FETCH). Returns to A (expects ADDR). Verifies correct data at every step. |
| **Assertions** | 6 data comparisons |
| **FSM States** | IDLE, OP, ADDR, NO_FETCH, MODE, DUMMY, DATA_I |
| **Coverage** | NO_CMD mode, NO_FETCH path, last address comparison, address update |

### 3.9 test_register_reset_values

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | Register reset defaults |
| **Description** | After reset, verifies all 10 registers (REG0-3, REG8-11, REG12-13) return expected defaults. Notably verifies REG13 (CLK_DIV) resets to 0x01. |
| **Assertions** | 10 |
| **Coverage** | All register reset values |

### 3.10 test_register_bit_masking

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | Register field isolation |
| **Description** | Writes 0xFFFFFFFF to REG3, REG13, REG1 and verifies only valid bits stored. REG13 masks to 5 bits (0x1F), REG1[0] is read-only. |
| **Assertions** | 3 |
| **Coverage** | Bit masking, read-only fields |

### 3.11 test_wdata_regs_readback

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | Write data register access |
| **Description** | Writes unique patterns to REG8-11, reads back, verifies data integrity. |
| **Assertions** | 4 |
| **Coverage** | Write data register R/W |

### 3.12 test_enable_auto_clear

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | REG2[8] ENABLE auto-clear |
| **Description** | Writes a command with ENABLE bit set, waits for completion, verifies bit auto-clears. |
| **Assertions** | 1 |
| **Coverage** | ENABLE_ACK handshake clearing REG2[8] |

### 3.13 test_irq_lifecycle

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | Interrupt assert, clear, no-spurious |
| **Description** | Verifies IRQ is 0 after reset, asserts after transaction completes, clears when REG1[8]=1 written, stays deasserted for 100 cycles. |
| **Assertions** | 4 (reset=0, assert, clear, no-spurious) |
| **Coverage** | IRQ lifecycle |

### 3.14 test_spi_write_and_read

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | SPI mode page program and readback |
| **Description** | Programs 4 words in SPI mode (not QPI) using cmd 0x02, reads back with fast read 0x0B. Verifies data integrity in SPI mode. |
| **Assertions** | 1 data comparison |
| **FSM States** | IDLE, OP, ADDR, DATA_O, DATA_I, DUMMY |
| **Coverage** | SPI mode write, SPI mode read |

### 3.15 test_spi_standard_read

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | Standard SPI read (cmd 0x03) vs fast read (0x0B) |
| **Description** | Reads same data with standard read (0 dummy cycles) and fast read (8 dummy cycles), verifies both return identical data. |
| **Assertions** | 3 |
| **FSM States** | All read states |
| **Coverage** | Standard read cmd, fast read cmd, result comparison |

### 3.16 test_clock_divider_sweep

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | Clock divider correctness across values |
| **Description** | Programs data, reads back at 7 different CLK_DIV values (0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F). Verifies data integrity at each speed. |
| **Assertions** | 7 data comparisons |
| **Coverage** | Full CLK_DIV range |

### 3.17 test_vary_n_rw_bytes

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | All N_RW_BYTES values |
| **Description** | Tests byte-level reads (1-15 bytes) and word-level reads (1-4 words). Verifies correct data count and content. |
| **Assertions** | 19 (15 byte + 4 word) |
| **Coverage** | All QSPI_N_RW_BYTES mux paths |

### 3.18 test_op_only_command

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | Command-only transactions (OP->IDLE) |
| **Description** | Sends WREN and WRDI (no addr/dummy/data), verifies clean return to idle. |
| **Assertions** | 2 busy=0 checks |
| **FSM States** | OP, IDLE |
| **Coverage** | OP->IDLE path |

### 3.19 test_reset_during_idle

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | Reset recovery |
| **Description** | Operates the controller, resets, verifies all registers at defaults, then verifies the controller still works (JEDEC ID read). |
| **Assertions** | 4 |
| **Coverage** | Reset recovery, post-reset operation |

### 3.20 test_ahb_xip_read

| Field | Value |
|-------|-------|
| **Status** | Implemented |
| **Feature** | AHB XIP read path end-to-end |
| **Description** | Programs data, enables XIP mode and cache, reads 4 words via AHB data bus, reads again (cached), verifies write returns ERROR in XIP mode. |
| **Assertions** | 9 (4 uncached + 4 cached + 1 write error) |
| **FSM States** | All (via XIP path) |
| **Coverage** | AHB XIP, cache hit, cache miss, XIP write rejection |

---

## 4. Proposed Tests (Not Yet Implemented)

### 4.1 Remaining Register Tests

#### test_rdata_regs_readonly
| Field | Value |
|-------|-------|
| **Priority** | Medium |
| **Feature** | Read data register write protection |
| **Description** | Attempt to write to REG4-7, verify they are unaffected (read-only). |

### 4.2 Remaining QSPI Protocol Tests

#### test_vary_dummy_cycles
| Field | Value |
|-------|-------|
| **Priority** | Medium |
| **Feature** | Dummy cycle sweep |
| **Description** | Sweep QSPI_DUMMY_CYCLES from 1-15 with read operations, verify correct protocol timing and data. |

#### test_spi_continuous_read
| Field | Value |
|-------|-------|
| **Priority** | Medium |
| **Feature** | SPI mode continuous read |
| **Description** | Currently MODE state in SPI mode immediately exits to IDLE (line 178-179 of qspi_controller.sv). Verify this behavior and that data can still be read. |

### 4.3 Remaining AHB/Cache Tests

#### test_ahb_cache_coherency
| Field | Value |
|-------|-------|
| **Priority** | Medium |
| **Feature** | Cache coherency |
| **Description** | Write flash via APB, read via AHB cached, invalidate cache, write new data via APB, read again, verify updated data. |

#### test_ahb_sequential_reads
| Field | Value |
|-------|-------|
| **Priority** | Low |
| **Feature** | Cache line fill |
| **Description** | Verify sequential AHB reads to adjacent addresses exploit cache line fill (128-bit line = 4 words). |

#### test_ahb_addr_alignment
| Field | Value |
|-------|-------|
| **Priority** | Medium |
| **Feature** | Address alignment |
| **Description** | Read from non-16B-aligned addresses via AHB, verify correct word selection from 128-bit cache line. |

### 4.4 Error / Corner Case Tests

#### test_simultaneous_rw_bits
| Field | Value |
|-------|-------|
| **Priority** | Low |
| **Feature** | Invalid R+W configuration |
| **Description** | Set both QSPI_READ=1 and QSPI_WRITE=1 simultaneously. Verify the controller handles it without hanging. |

#### test_xip_switch_while_busy
| Field | Value |
|-------|-------|
| **Priority** | Medium |
| **Feature** | XIP mode switch safety |
| **Description** | Toggle XIP_ACTIVE while a QSPI transaction is in progress. Verify the system recovers cleanly. |

#### test_enable_while_busy
| Field | Value |
|-------|-------|
| **Priority** | Medium |
| **Feature** | Double-enable protection |
| **Description** | Assert QSPI_ENABLE while the controller is already running a transaction. Verify no corruption. |

#### test_reset_during_transaction
| Field | Value |
|-------|-------|
| **Priority** | Medium |
| **Feature** | Reset recovery |
| **Description** | Assert reset mid-transaction. Verify FSM returns to IDLE and QSPI bus is clean after reset release. |

#### test_zero_byte_transfer
| Field | Value |
|-------|-------|
| **Priority** | Low |
| **Feature** | Minimum data size |
| **Description** | Set N_RW_BYTES=0 with read enabled. Verify 1-byte read completes correctly. |

---

## 5. Coverage Strategy

### RTL Coverage (via simulator)
- **Line/Branch/Condition/Toggle coverage** measured on:
  - `qspi_controller`
  - `ahb_qspi_interface`
  - `apb_qspi_regs`
  - `qspi_controller_mux`
  - `qspi_clock_div`
- **Excluded from coverage** (pre-verified external IP):
  - `cache_subsystem` / `p_flash_cache_f0`
  - `cmsdk_ahb_to_apb`
  - `sst26vf064b` (flash model)

### Functional Coverage (proposed — not yet implemented)
| Coverpoint | Description |
|------------|-------------|
| FSM state | All 8 states visited: IDLE, NO_FETCH, OP, ADDR, MODE, DUMMY, DATA_O, DATA_I |
| FSM transitions | All valid state transitions exercised |
| QIO_MODE | Both SPI (0) and QPI (1) modes tested |
| N_RW_BYTES | All 16 values (0-15) exercised |
| DUMMY_CYCLES | Values 0, 1, 4, 6, 8, 15 exercised |
| CLK_DIV | Values 0, 1, 2, 5, 0x1F exercised |
| NO_CMD | Both 0 and 1 tested |
| CONT_READ | Both 0 and 1 tested |
| XIP_ACTIVE | Both 0 and 1 tested |
| AHB HRESP | Both OK and ERROR responses observed |
| Cache state | Enabled and disabled tested |

---

## 6. Bug Regression Tests

| Bug ID | Test | RTL File | Line(s) | Issue | Fix |
|--------|------|----------|---------|-------|-----|
| BUG-1 | `test_bug1_rdata_latch` | `qspi_controller.sv` | 374-399 | 128-bit RDATA latch in `always_comb` (missing else) | Removed `HRESETn`/`QSPI_nCS` gating, made purely combinational |
| BUG-2 | `test_bug2_enable_ack_latch` | `qspi_controller.sv` | 78-248 | `QSPI_ENABLE_ACK` not assigned in MODE/DUMMY/DATA states | Added default `QSPI_ENABLE_ACK = 1'b0` at top of `always_comb` |
| BUG-3 | `test_bug3_no_cmd_last_addr` | `qspi_controller.sv` | 138 | `last_QSPI_ADDR` latch in combinational block | Moved to sequential posedge block with reset |

---

## 7. Test Execution

```bash
# Run all tests (Questa)
cd verif/cocotb && make SIM=questa

# Run specific test
cd verif/cocotb && make SIM=questa TESTCASE=test_bug1_rdata_latch

# Run with VCS + coverage
cd verif/cocotb && make SIM=vcs
```

### Supported Simulators
| Simulator | Status | Coverage |
|-----------|--------|----------|
| Questa | Primary | Line, toggle, branch |
| VCS | Supported | Line, toggle, FSM, branch, condition |
| Icarus | Supported | FST waveforms only |
| Verilator | Supported | FST waveforms only |
