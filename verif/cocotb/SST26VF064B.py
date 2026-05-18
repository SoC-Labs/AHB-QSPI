from cocotb.triggers import Timer, ClockCycles

ID = 0x4326BF00

# Default timeout for polling loops (in clock cycles)
POLL_TIMEOUT_CYCLES = 50000

async def poll_busy_clear(dut, tb, timeout=POLL_TIMEOUT_CYCLES):
    """Poll status register until QSPI_BUSY (bit 0) clears. Raises AssertionError on timeout."""
    for _ in range(timeout):
        data = await tb.config_ahb_master.read(0x04, 4)
        if not (int(data[0]['data'], 16) & 1):
            return
        await ClockCycles(dut.HCLK, 2)
    raise AssertionError(f"QSPI_BUSY did not clear within {timeout} cycles")

async def poll_busy_set(dut, tb, timeout=POLL_TIMEOUT_CYCLES):
    """Poll status register until QSPI_BUSY (bit 0) sets. Raises AssertionError on timeout."""
    for _ in range(timeout):
        data = await tb.config_ahb_master.read(0x04, 4)
        if int(data[0]['data'], 16) & 1:
            return
        await ClockCycles(dut.HCLK, 2)
    raise AssertionError(f"QSPI_BUSY did not set within {timeout} cycles")

async def wait_for_irq(dut, tb, timeout=POLL_TIMEOUT_CYCLES):
    tb.log.info("Wait for IRQ")
    for _ in range(timeout):
        if dut.IRQ_QSPI_FINISHED.value == 1:
            break
        await ClockCycles(dut.HCLK, 1)
    else:
        raise AssertionError(f"IRQ_QSPI_FINISHED did not assert within {timeout} cycles")
    await tb.config_ahb_master.write(0x04, 0x00000100)
    await ClockCycles(dut.HCLK, 2)
    assert dut.IRQ_QSPI_FINISHED.value == 0
    data = await tb.config_ahb_master.read(0x04, 4)
    assert int(data[0]['data'], 16) == 0

async def _flash_cmd_byte(dut, tb, cmd):
    """Issue a single command-only flash transaction (no address, no data).

    The 0x08 (Command) register low byte is the opcode; bit 8 is the
    start/strobe.  Both writes plus the IRQ/BUSY handshake mirror every
    other command helper in this file, so nCS is guaranteed to cycle
    high between commands (the SST26VF064B model only advances its
    command FSM on posedge CEb).
    """
    op = cmd & 0xFF
    await tb.config_ahb_master.write(0x08, op)
    await tb.config_ahb_master.write(0x08, 0x100 | op)
    await wait_for_irq(dut, tb)
    await poll_busy_clear(dut, tb)


async def SPI_RESET(dut, tb):
    """Robustly return the SST26VF064B to a known SPI / non-continuous-read
    state regardless of what mode a *previous* test left it in.

    Why a single QPI RSTQIO is not enough (root cause of the full-suite
    `test_xip_plain_spi_no_flash_write` X/Z failure).  The cocotb suite
    runs every test in one shared simulation with no flash reset between
    tests.  `cycle_reset()` only resets the RTL (HRESETn) — it does NOT
    reset the flash model.  When a predecessor (e.g. test_xip_qpi_no_nocmd)
    leaves the flash in QPI *continuous-read* mode the model has
    `Mode_Configuration[7:4] === 4'hA`.  In that state the SST26VF064B SQI
    command interpreter (verif/VIP/SST26VF064B.v ~line 686) special-cases
    `sqi_count === 0`: it force-aborts the command loop (`sqi_count = 8`)
    and re-triggers `SQI_HS_READ_trg` — i.e. the very next transaction is
    consumed as a *read continuation*, NOT decoded as a command.  So a
    lone RSTQIO (0xFF) is swallowed: it never reaches the RSTQIO decode,
    `SQI_SPI_mode` stays True, and subsequent SPI-framed RSTEN/RST are
    mis-parsed by the still-active QPI interpreter — the model never
    fires its `reset` event, the flash stays desynced and drives 'z' onto
    the IO bus, which propagates to the AHB read as X/Z.

    The recovery below is deliberately order-independent and idempotent:

      1. Safe CLK_DIV so the CDC-synced BUSY flag is observed reliably.
      2. RSTQIO (0xFF) in QPI framing, issued *twice* with nCS toggling
         between.  The 1st absorbs any continuous-read trap — the model
         takes the continuation branch which executes
         `Mode_Configuration = 8'hFF`, clearing continuous-read.  The 2nd
         is now decoded as a genuine SQI_RSTQIO → `SQI_SPI_mode = False`.
         If the flash was already in SPI mode these are harmless no-ops.
      3. RSTEN(0x66)+RST(0x99) in QPI framing — belt-and-braces: if the
         flash is somehow still in QPI, this is the SQI RSTEN/RST decode
         path that fires the model `reset` event.
      4. Switch controller to SPI framing, then RSTEN(0x66)+RST(0x99) in
         SPI framing — the definitive reset once we are guaranteed back
         in SPI mode.  The model `reset` event clears *all* flash state:
         `SQI_SPI_mode=False`, `Mode_Configuration=8'hFF`, every active
         read/program loop disabled.

    Net effect: no test can inherit a desynced / wrong-mode / mid-frame
    flash from its predecessor, so the suite is order-independent.
    """
    # Set clock divider to safe value before any flash commands.
    # Default CLK_DIV=1 (HCLK/2) is too fast: commands complete before the
    # CDC-synchronised BUSY flag propagates, so poll_busy_clear returns
    # prematurely and the next command can overlap, preventing nCS from
    # cycling high between transactions.  The SST26VF064B flash model
    # blocks inside its RST handler waiting for posedge CEb; if that edge
    # never arrives, no subsequent command is processed and read data
    # stays at 'z'/'x'.  CLK_DIV=5 (HCLK/10) matches the UVM testbench
    # and gives enough margin for the synchronisers.
    await tb.config_ahb_master.write(0x34, 0x00000005)

    # --- Step 2: RSTQIO x2 in QPI framing ---------------------------------
    # QIO_MODE=1 so the controller encodes the byte as QPI nibbles.  Also
    # clear CONT_READ / NO_CMD / XIP so this is a clean command-only frame
    # even if a prior test left those CTRL bits set.
    await tb.config_ahb_master.write(0x00, 0x00000001)  # QIO_MODE=1 only
    await _flash_cmd_byte(dut, tb, 0xFF)  # absorbs any continuous-read trap
    await _flash_cmd_byte(dut, tb, 0xFF)  # now decoded as real RSTQIO

    # --- Step 3: RSTEN + RST while still in QPI framing --------------------
    # Harmless if already back in SPI; if still in QPI this is the SQI
    # RSTEN/RST decode that triggers the model's full `reset` event.
    await _flash_cmd_byte(dut, tb, 0x66)  # RSTEN
    await _flash_cmd_byte(dut, tb, 0x99)  # RST

    # --- Step 4: RSTEN + RST in SPI framing (definitive) ------------------
    # Switch controller to SPI framing (clears QIO_MODE/CONT_READ/NO_CMD).
    await tb.config_ahb_master.write(0x00, 0x00000000)
    await _flash_cmd_byte(dut, tb, 0x66)  # RSTEN
    await _flash_cmd_byte(dut, tb, 0x99)  # RST
            
async def SPI_READ_JEDIC(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x0002009F)
    await tb.config_ahb_master.write(0x08, 0x0002039F)
    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    ID = await tb.config_ahb_master.read(0x10,4)
    return int(ID[0]['data'],16)

async def SET_QPI_MODE(dut,tb):
    await tb.config_ahb_master.write(0x08, 0x00000038)
    await tb.config_ahb_master.write(0x08, 0x00000138)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)

async def LEAVE_QPI_MODE(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x000000FF)
    await tb.config_ahb_master.write(0x08, 0x000001FF)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)

async def QPI_READ_JEDIC(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x000220AF)
    await tb.config_ahb_master.write(0x08, 0x000223AF)
    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    ID = await tb.config_ahb_master.read(0x10,4)
    return int(ID[0]['data'],16)
      
async def SPI_WRITE_ENABLE(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x00000006)
    await tb.config_ahb_master.write(0x08, 0x00000106)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
 
async def SPI_WRITE_DISABLE(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x00000004)
    await tb.config_ahb_master.write(0x08, 0x00000104)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
       
async def SPI_CLR_PROTECTION(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x00000098)
    await tb.config_ahb_master.write(0x08, 0x00000198)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
   
async def SPI_CHIP_ERASE(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x000000C7)
    await tb.config_ahb_master.write(0x08, 0x000001C7)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)

async def SPI_BLOCK_ERASE(dut, tb):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, 0x000000)

    await tb.config_ahb_master.write(0x08, 0x000008D8)
    await tb.config_ahb_master.write(0x08, 0x000009D8)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    for _ in range(1000):
        SPI_STAT = await SPI_READ_STAT_REG(dut, tb)
        if not (SPI_STAT & (1 << 24)):
            break
        await Timer(time=1, units='ms')
    else:
        raise AssertionError("Block erase did not complete")
   
async def SPI_READ_STAT_REG(dut,tb):
    await tb.config_ahb_master.write(0x08, 0x00002005)
    await tb.config_ahb_master.write(0x08, 0x00002305)
    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    data = await tb.config_ahb_master.read(0x10,4)
    return (int(data[0]['data'],16))


async def SPI_SECTOR_ERASE(dut, tb, addr=0):
    """Erase the 4 KiB SST26VF064B sector containing `addr` (SPI 0x20).

    Self-contained test-isolation primitive: issues WREN, sends Sector
    Erase, then spins on the status BUSY bit until the model finishes.

    NOR flash page-program can only clear bits (1->0); it can never
    restore a 1.  Because the cocotb suite runs every test in ONE shared
    simulation with no flash reset, any test that programs a fixed flash
    address and a later test that reads the same address expecting the
    erased (0xFF) pattern collide — the second test reads the stale
    programmed bits AND-ed with its own (e.g. test_bug1_rdata_latch
    leaves 0xDEADBEEF at 0x1000; test_xip_plain_spi_no_flash_write then
    reads 0x1000 expecting 0xFFFFFFFF).  A true erase-before-use is the
    general, order-independent cure.

    This is only affordable because the testbench wrapper
    (verif/cocotb/ahb_qspi_cocotb.v) overrides the model erase times via
    `defparam u_sst26vf064b.I0.Tse = 1_000;` (and Tbe/Tsce/Tpp/Tws), so a
    sector erase costs ~1 us of sim time instead of the datasheet 25 ms
    (~25000x).  Without that defparam this would blow the cocotb timeout
    and erase-before-use would be impractical (see findings doc FINAL).
    """
    # Global Block-Protection Unlock first: the SST26VF064B powers up
    # with every block write/erase-protected, and the model's reset
    # event does NOT restore protection — so this only matters if no
    # earlier test happened to unlock, but doing it here makes the
    # primitive self-sufficient and order-independent (a protected
    # sector erase is silently aborted by the model => stale data).
    await SPI_WRITE_ENABLE(dut, tb)
    await SPI_CLR_PROTECTION(dut, tb)
    await SPI_WRITE_ENABLE(dut, tb)
    # 24-bit sector address; the model masks it to the 4 KiB boundary.
    await tb.config_ahb_master.write(0x0C, addr & 0xFFFFFF)
    # 0x20 = Sector Erase opcode, bit 11 (0x800) = ADDR_EN.
    await tb.config_ahb_master.write(0x08, 0x00000820)
    await tb.config_ahb_master.write(0x08, 0x00000920)
    await wait_for_irq(dut, tb)
    await poll_busy_clear(dut, tb)
    # Spin on the flash status BUSY bit (same framing as SPI_BLOCK_ERASE).
    # Tse=1 us via defparam, so a 2 us poll quantum settles in 1-2 reads;
    # the generous iteration budget keeps it robust if Tse is retuned.
    for _ in range(2000):
        if not (await SPI_READ_STAT_REG(dut, tb) & (1 << 24)):
            break
        await Timer(time=2, units='us')
    else:
        raise AssertionError("Sector erase did not complete (flash busy)")

async def QPI_READ_STAT_REG(dut,tb):
    await tb.config_ahb_master.write(0x08, 0x00002005)
    await tb.config_ahb_master.write(0x08, 0x00002305)
    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    data = await tb.config_ahb_master.read(0x10,4)
    return (int(data[0]['data'],16))


async def SPI_READ_SLOW(dut, tb):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, 0x000000)

    await tb.config_ahb_master.write(0x08, 0x00001003)
    await tb.config_ahb_master.write(0x08, 0x00001303)
    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    rData = await tb.config_ahb_master.read(0x10,4)
    print(rData)

async def QPI_READ_WORDS(dut,tb, addr =0, n_words=1, cont_read = False):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, addr)

    if(cont_read==True):
        QSPI_CTRL_REG = await tb.config_ahb_master.read(0x00,4)
        QSPI_CTRL_REG = int(QSPI_CTRL_REG[0]['data'],16)
        QSPI_CTRL_REG = QSPI_CTRL_REG | ((0xA0<<16) + (1<<24))
        await tb.config_ahb_master.write(0x00, QSPI_CTRL_REG)
        QSPI_DUMMY_CYCLES = 4
    else:
        QSPI_DUMMY_CYCLES = 6


    QSPI_CMD  = 0x0B
    QSPI_READ = 1
    QSPI_WRITE = 0
    QSPI_ADDR_EN = 1
    QSPI_N_RW_BYTES = n_words*4 - 1
    
    QSPI_INSTR = QSPI_CMD
    QSPI_INSTR += QSPI_READ<<9
    QSPI_INSTR += QSPI_WRITE<<10
    QSPI_INSTR += QSPI_ADDR_EN<<11
    QSPI_INSTR += QSPI_DUMMY_CYCLES<<12
    QSPI_INSTR += QSPI_N_RW_BYTES << 16

    await tb.config_ahb_master.write(0x08, QSPI_INSTR)
    QSPI_INSTR = QSPI_INSTR ^ (1<<8)
    await tb.config_ahb_master.write(0x08, QSPI_INSTR)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)

    apb_r_addrs=[0x10, 0x14, 0x18, 0x1C]
    rData = []
    for i in range(0,n_words):
        rData_temp = await tb.config_ahb_master.read(apb_r_addrs[i],4)
        rData.append(int(rData_temp[0]['data'],16))
    return rData

async def QPI_READ_BYTES(dut,tb, addr =0, n_bytes=1, cont_read = False):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, addr)

    if(cont_read==True):
        QSPI_CTRL_REG = await tb.config_ahb_master.read(0x00,4)
        QSPI_CTRL_REG = int(QSPI_CTRL_REG[0]['data'],16)
        QSPI_CTRL_REG = QSPI_CTRL_REG | ((0xA0<<16) + (1<<24))
        await tb.config_ahb_master.write(0x00, QSPI_CTRL_REG)
        QSPI_DUMMY_CYCLES = 4
    else:
        QSPI_DUMMY_CYCLES = 6


    QSPI_CMD  = 0x0B
    QSPI_READ = 1
    QSPI_WRITE = 0
    QSPI_ADDR_EN = 1
    QSPI_N_RW_BYTES = n_bytes - 1
    
    QSPI_INSTR = QSPI_CMD
    QSPI_INSTR += QSPI_READ<<9
    QSPI_INSTR += QSPI_WRITE<<10
    QSPI_INSTR += QSPI_ADDR_EN<<11
    QSPI_INSTR += QSPI_DUMMY_CYCLES<<12
    QSPI_INSTR += QSPI_N_RW_BYTES << 16

    await tb.config_ahb_master.write(0x08, QSPI_INSTR)
    QSPI_INSTR = QSPI_INSTR ^ (1<<8)
    await tb.config_ahb_master.write(0x08, QSPI_INSTR)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)

    rData = []
    for i in range(0,n_bytes):
        rData_temp = await tb.config_ahb_master.read(0x10+i,1)
        rData.append(int(rData_temp[0]['data'],16))
    return rData

async def SPI_READ_WORDS(dut,tb, addr =0, n_words=1):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, addr)

    QSPI_DUMMY_CYCLES = 8


    QSPI_CMD  = 0x0B
    QSPI_READ = 1
    QSPI_WRITE = 0
    QSPI_ADDR_EN = 1
    QSPI_N_RW_BYTES = n_words*4 - 1
    
    QSPI_INSTR = QSPI_CMD
    QSPI_INSTR += QSPI_READ<<9
    QSPI_INSTR += QSPI_WRITE<<10
    QSPI_INSTR += QSPI_ADDR_EN<<11
    QSPI_INSTR += QSPI_DUMMY_CYCLES<<12
    QSPI_INSTR += QSPI_N_RW_BYTES << 16

    await tb.config_ahb_master.write(0x08, QSPI_INSTR)
    QSPI_INSTR = QSPI_INSTR ^ (1<<8)
    await tb.config_ahb_master.write(0x08, QSPI_INSTR)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)

    apb_r_addrs=[0x10, 0x14, 0x18, 0x1C]
    rData = []
    for i in range(0,n_words):
        rData_temp = await tb.config_ahb_master.read(apb_r_addrs[i],4)
        rData.append(int(rData_temp[0]['data'],16))
    return rData

async def SPI_READ_WORDS_SLOW(dut,tb, addr =0, n_words=1):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, addr)

    QSPI_DUMMY_CYCLES = 0


    QSPI_CMD  = 0x03
    QSPI_READ = 1
    QSPI_WRITE = 0
    QSPI_ADDR_EN = 1
    QSPI_N_RW_BYTES = n_words*4 - 1
    
    QSPI_INSTR = QSPI_CMD
    QSPI_INSTR += QSPI_READ<<9
    QSPI_INSTR += QSPI_WRITE<<10
    QSPI_INSTR += QSPI_ADDR_EN<<11
    QSPI_INSTR += QSPI_DUMMY_CYCLES<<12
    QSPI_INSTR += QSPI_N_RW_BYTES << 16

    await tb.config_ahb_master.write(0x08, QSPI_INSTR)
    QSPI_INSTR = QSPI_INSTR ^ (1<<8)
    await tb.config_ahb_master.write(0x08, QSPI_INSTR)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)

    apb_r_addrs=[0x10, 0x14, 0x18, 0x1C]
    rData = []
    for i in range(0,n_words):
        rData_temp = await tb.config_ahb_master.read(apb_r_addrs[i],4)
        rData.append(int(rData_temp[0]['data'],16))
    return rData

async def SPI_ADDR_TO_IDLE(dut,tb, addr =0, n_words=1):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, addr)

    QSPI_DUMMY_CYCLES = 0


    QSPI_CMD  = 0x03
    QSPI_READ = 0
    QSPI_WRITE = 0
    QSPI_ADDR_EN = 1
    QSPI_N_RW_BYTES = n_words*4 - 1
    
    QSPI_INSTR = QSPI_CMD
    QSPI_INSTR += QSPI_READ<<9
    QSPI_INSTR += QSPI_WRITE<<10
    QSPI_INSTR += QSPI_ADDR_EN<<11
    QSPI_INSTR += QSPI_DUMMY_CYCLES<<12
    QSPI_INSTR += QSPI_N_RW_BYTES << 16

    await tb.config_ahb_master.write(0x08, QSPI_INSTR)
    QSPI_INSTR = QSPI_INSTR ^ (1<<8)
    await tb.config_ahb_master.write(0x08, QSPI_INSTR)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    return

async def SPI_DUMMY_TO_IDLE(dut,tb, addr =0, n_words=1):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, addr)

    QSPI_DUMMY_CYCLES = 4


    QSPI_CMD  = 0x03
    QSPI_READ = 0
    QSPI_WRITE = 0
    QSPI_ADDR_EN = 1
    QSPI_N_RW_BYTES = n_words*4 - 1
    
    QSPI_INSTR = QSPI_CMD
    QSPI_INSTR += QSPI_READ<<9
    QSPI_INSTR += QSPI_WRITE<<10
    QSPI_INSTR += QSPI_ADDR_EN<<11
    QSPI_INSTR += QSPI_DUMMY_CYCLES<<12
    QSPI_INSTR += QSPI_N_RW_BYTES << 16

    await tb.config_ahb_master.write(0x08, QSPI_INSTR)
    QSPI_INSTR = QSPI_INSTR ^ (1<<8)
    await tb.config_ahb_master.write(0x08, QSPI_INSTR)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    return

async def SPI_DUMMY_TO_DATAO(dut,tb, addr =0, n_words=1):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, addr)

    QSPI_DUMMY_CYCLES = 4


    QSPI_CMD  = 0x03
    QSPI_READ = 0
    QSPI_WRITE = 1
    QSPI_ADDR_EN = 1
    QSPI_N_RW_BYTES = n_words*4 - 1
    
    QSPI_INSTR = QSPI_CMD
    QSPI_INSTR += QSPI_READ<<9
    QSPI_INSTR += QSPI_WRITE<<10
    QSPI_INSTR += QSPI_ADDR_EN<<11
    QSPI_INSTR += QSPI_DUMMY_CYCLES<<12
    QSPI_INSTR += QSPI_N_RW_BYTES << 16

    await tb.config_ahb_master.write(0x08, QSPI_INSTR)
    QSPI_INSTR = QSPI_INSTR ^ (1<<8)
    await tb.config_ahb_master.write(0x08, QSPI_INSTR)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    return


async def SPI_WRITE_STATUS(dut,tb):

    QSPI_DUMMY_CYCLES = 0


    QSPI_CMD  = 0x01
    QSPI_READ = 0
    QSPI_WRITE = 1
    QSPI_ADDR_EN = 0
    QSPI_N_RW_BYTES = 1
    
    QSPI_INSTR = QSPI_CMD
    QSPI_INSTR += QSPI_READ<<9
    QSPI_INSTR += QSPI_WRITE<<10
    QSPI_INSTR += QSPI_ADDR_EN<<11
    QSPI_INSTR += QSPI_DUMMY_CYCLES<<12
    QSPI_INSTR += QSPI_N_RW_BYTES << 16

    await tb.config_ahb_master.write(0x08, QSPI_INSTR)
    QSPI_INSTR = QSPI_INSTR ^ (1<<8)
    await tb.config_ahb_master.write(0x08, QSPI_INSTR)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    return

async def SPI_MODE_TO_IDLE(dut,tb, addr =0, n_words=1):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, addr)

    QSPI_DUMMY_CYCLES = 0
    QSPI_CTRL_REG = await tb.config_ahb_master.read(0x00,4)
    QSPI_CTRL_REG = int(QSPI_CTRL_REG[0]['data'],16)
    QSPI_CTRL_REG = QSPI_CTRL_REG | ((0xA0<<16) + (1<<24))
    await tb.config_ahb_master.write(0x00, QSPI_CTRL_REG)


    QSPI_CMD  = 0x03
    QSPI_READ = 0
    QSPI_WRITE = 0
    QSPI_ADDR_EN = 1
    QSPI_N_RW_BYTES = n_words*4 - 1
    
    QSPI_INSTR = QSPI_CMD
    QSPI_INSTR += QSPI_READ<<9
    QSPI_INSTR += QSPI_WRITE<<10
    QSPI_INSTR += QSPI_ADDR_EN<<11
    QSPI_INSTR += QSPI_DUMMY_CYCLES<<12
    QSPI_INSTR += QSPI_N_RW_BYTES << 16

    await tb.config_ahb_master.write(0x08, QSPI_INSTR)
    QSPI_INSTR = QSPI_INSTR ^ (1<<8)
    await tb.config_ahb_master.write(0x08, QSPI_INSTR)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    return

async def SPI_MODE_TO_DATA(dut,tb, addr =0, write=1, read=0):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, addr)

    QSPI_DUMMY_CYCLES = 0
    QSPI_CTRL_REG = await tb.config_ahb_master.read(0x00,4)
    QSPI_CTRL_REG = int(QSPI_CTRL_REG[0]['data'],16)
    QSPI_CTRL_REG = QSPI_CTRL_REG | ((0xA0<<16) + (1<<24))
    await tb.config_ahb_master.write(0x00, QSPI_CTRL_REG)


    QSPI_CMD  = 0x03
    QSPI_READ = read
    QSPI_WRITE = write
    QSPI_ADDR_EN = 1
    QSPI_N_RW_BYTES = 3
    
    QSPI_INSTR = QSPI_CMD
    QSPI_INSTR += QSPI_READ<<9
    QSPI_INSTR += QSPI_WRITE<<10
    QSPI_INSTR += QSPI_ADDR_EN<<11
    QSPI_INSTR += QSPI_DUMMY_CYCLES<<12
    QSPI_INSTR += QSPI_N_RW_BYTES << 16

    await tb.config_ahb_master.write(0x08, QSPI_INSTR)
    QSPI_INSTR = QSPI_INSTR ^ (1<<8)
    await tb.config_ahb_master.write(0x08, QSPI_INSTR)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    return

async def QPI_PAGE_PROGRAM(dut, tb, addr = 0, words=0, n_words = 1):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, addr)
    # Write Data
    
    apb_addrs = [0x20, 0x24, 0x28, 0x2C]
    
    for i in range(0,n_words):
        await tb.config_ahb_master.write(apb_addrs[i], words[i])

    QSPI_CMD  = 0x02
    QSPI_READ = 0
    QSPI_WRITE = 1
    QSPI_ADDR_EN = 1
    QSPI_DUMMY_CYCLES = 0
    QSPI_N_RW_BYTES = n_words*4 - 1
    
    QSPI_INSTR = QSPI_CMD
    QSPI_INSTR += QSPI_READ<<9
    QSPI_INSTR += QSPI_WRITE<<10
    QSPI_INSTR += QSPI_ADDR_EN<<11
    QSPI_INSTR += QSPI_DUMMY_CYCLES<<12
    QSPI_INSTR += QSPI_N_RW_BYTES << 16

    await tb.config_ahb_master.write(0x08, QSPI_INSTR)
    QSPI_INSTR = QSPI_INSTR ^ (1<<8)
    await tb.config_ahb_master.write(0x08, QSPI_INSTR)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
    for _ in range(10000):
        SPI_STAT = await QPI_READ_STAT_REG(dut, tb)
        if not (SPI_STAT & (1 << 24)):
            break
        await Timer(time=1, units='us')
    else:
        raise AssertionError("Page program did not complete (flash busy)")



