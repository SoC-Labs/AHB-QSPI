# Verification plan for AHB QSPI


## QSPI verification using APB Interface
First verification tasks is to verify the QSPI interface using the APB controller. This is verified using a verilog model of the Microchip SST26VF064B. 

Device instructions that have been verified as working:

Configuration

- [ ] (0x00) NOP
- [x] (0x66) RSTEN: Reset Enable
- [x] (0x99) RST: Reset memory
- [x] (0x38) EQIO: Enable quad io
- [ ] (0xFF) RSTQIO: Reset Quad IO
- [x] (0x05) RDSR: Read Status register
- [ ] (0x01) WRSR: Write Status register
- [ ] (0x35) RDCR: Read configuration Register

Read

- [ ] (0x03) Read Memory
- [x] (0x0B) High speed Read
- [ ] (0x6B) SQOR: SPI Quad Output Read
- [ ] (0xEB) SQIOR: SPI Quad I/O Read
- [ ] (0x3B) SDOR: SPI Dual Output Read
- [ ] (0xBB) SDIOR: SPI Dual I/O Read
- [ ] (0xC0) SB: Set Burst Length
- [ ] (0x0C) RBSQI: SQI Read Burst with Wrap
- [ ] (0xEC) RBSPI: SPI Read Burst with Wrap

Identification

- [x] (0x9F) JEDEC-ID Read 
- [x] (0xAF) Quad I/O JEDEC-ID Read
- [ ] (0x5A) SFDP: Serial Flash Discoverable Parameters

Write

- [x] (0x06) Write Enable
- [x] (0x04) Write Disable
- [ ] (0x20) SE: Erase 4 KBytes of memory array
- [ ] (0xD8) BE: Erase 64, 32, or 8 KBytes of memory array
- [ ] (0xC7) CE: Full chip erase
- [x] (0x02) PP: Page program
- [ ] (0x32) SPI Quad page program
- [ ] (0xB0) WRSU: Suspend program/erase
- [ ] (0x30) WRRE: Resume Program/erase

Protection

- [ ] (0x72) RBPR: Read Block-protection register
- [ ] (0x42) WBPR: Write Block-protection register
- [ ] (0x8D) LBPR: Lock down block-protection register
- [ ] (0xE8) nVWLDR: non-volatile write lock down register
- [ ] (0x98) ULBPR: Global block protection unlock
- [ ] (0x88) RSID: Read security ID
- [ ] (0xA5) PSID: Program user security ID Area
- [ ] (0x85) LSID: Lockout security ID Programming