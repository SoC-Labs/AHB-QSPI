import itertools
import logging
import os
from numpy import random
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ClockCycles
from cocotb.regression import TestFactory

from cocotbext.ahb import AHBLiteMaster, AHBBus


from SST26VF064B import *

FREQ = 240

QSPI_CONFIG_ADDR = 0x0
CACHE_CONFIG_ADDR = 0x1000

class TB:
    def __init__(self,dut):
        self.dut = dut
        
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        self.dut.HRESETn.setimmediatevalue(0)
        cocotb.start_soon(Clock(dut.HCLK, 10, units="ns").start())
        self.config_ahb_master = AHBLiteMaster(AHBBus.from_prefix(dut,"config", optional_signals = {"hsel":"HSEL", "hready_in":"HREADY_IN", "hburst":"HBURST"}), dut.HCLK, dut.HRESETn, 5000)
        self.data_ahb_master = AHBLiteMaster(AHBBus.from_prefix(dut,"data", optional_signals = {"hsel":"HSEL", "hready_in":"HREADY_IN", "hburst":"HBURST"}), dut.HCLK, dut.HRESETn, 5000)

    async def cycle_reset(self):
        await ClockCycles(self.dut.HCLK,1)
        await Timer(time=4.5, units='ns')
        self.dut.HRESETn.setimmediatevalue(0)
        await ClockCycles(self.dut.HCLK,40)
        await Timer(time=4.5, units='ns')
        self.dut.HRESETn.setimmediatevalue(1)
        await ClockCycles(self.dut.HCLK,10)
            

    
async def CACHE_READ(dut,tb):
    data = await tb.data_ahb_master.read(0x00,4)
    return int(data[0]['data'],16)   

@cocotb.test()
async def APB_reg_tests(dut):
    tb = TB(dut)
    await tb.cycle_reset()
    
    tb.log.info("Read ID of QSPI Core")
    PIDR=[0x00, 0x00, 0x00, 0x00, 0x59, 0x16, 0x15, 0x00]
    for i in range(0,8):
        PIDr_temp = await tb.config_ahb_master.read(0xFD0 + i*4,4)
        tb.log.info("PIDR %d = %x",i,int(PIDr_temp[0]['data'],16))
        assert int(PIDr_temp[0]['data'],16) == PIDR[i]
    CIDR=[0x50, 0x51, 0x4C, 0x53]
    for i in range(0,4):
        CIDR_temp = await tb.config_ahb_master.read(0xFF0 + i*4,4)
        tb.log.info("CIDR %d = %x",i,int(CIDR_temp[0]['data'],16))
        assert int(CIDR_temp[0]['data'],16) == CIDR[i]

    tb.log.info("Test REG12")
    await tb.config_ahb_master.write(0x30,0xFFFFFFFF)
    reg12 = await tb.config_ahb_master.read(0x30,4)
    assert int(reg12[0]['data'],16) == 0xFFFFFFFF

    tb.log.info("Test REG0")
    await tb.config_ahb_master.write(0x00,0xFFFFFFFF)
    reg0 = await tb.config_ahb_master.read(0x00,4)
    assert int(reg0[0]['data'],16) == 0xFFFFFFFF

    tb.log.info("Test REG1")
    await tb.config_ahb_master.write(0x04,0xFFFFFFFF)
    reg1 = await tb.config_ahb_master.read(0x04,4)
    reg1 =int(reg1[0]['data'],16)
    reg1 = reg1 | 1
    reg1 = reg1 | (1<<8)
    assert reg1 == 0xFFFFFFFF

    tb.log.info("Test REG2")
    await tb.config_ahb_master.write(0x08,0xFFFFFFFF)
    reg2 = await tb.config_ahb_master.read(0x08,4)
    assert int(reg2[0]['data'],16) == 0xFFFFFFFF

    tb.log.info("Test REG3")
    await tb.config_ahb_master.write(0x0C,0xFFFFFFFF)
    reg3 = await tb.config_ahb_master.read(0x0C,4)
    assert int(reg3[0]['data'],16) == 0xFFFFFFFF


@cocotb.test()
async def QSPI_TESTS(dut):  
    tb = TB(dut)
    await tb.cycle_reset()    
    
    tb.log.info("Reset SPI")
    await SPI_RESET(dut, tb)
    
    tb.log.info("Reading JEDIC in SPI mode")
    
    rID = await SPI_READ_JEDIC(dut, tb)
    tb.log.info("Read ID: 0x%x",rID)
    assert rID == ID
    
    tb.log.info("Setting QPI mode")
    await SET_QPI_MODE(dut, tb)
    await tb.config_ahb_master.write(0x00,0x1)
    
    tb.log.info("Reading JEDIC in QPI mode")
    rID = await QPI_READ_JEDIC(dut, tb)
    tb.log.info("Read ID: 0x%x",rID)
    assert rID == ID

    tb.log.info("Enable Write")
    await SPI_WRITE_ENABLE(dut, tb)
    SPI_STAT = await QPI_READ_STAT_REG(dut, tb)
    WEL = SPI_STAT & (1<<25)
    assert WEL != 0
    
    tb.log.info("Clear Protection and enable Write")
    await SPI_CLR_PROTECTION(dut, tb)
    await SPI_WRITE_ENABLE(dut, tb)
    SPI_STAT = await QPI_READ_STAT_REG(dut, tb)
    WEL = SPI_STAT & (1<<25)
    assert WEL != 0
    
    # Write and read 32-bit word
    tb.log.info("Page program 4x bytes")
    data = [0x18273456]
    await QPI_PAGE_PROGRAM(dut, tb, words=data, n_words=1)
    
    tb.log.info("Read 4x bytes")

    await SPI_WRITE_DISABLE(dut,tb)
    rdata = await QPI_READ_WORDS(dut, tb, n_words=1)
    assert rdata == data
        
    # Write and read 2x 32=bit words
    tb.log.info("Page program 8x bytes")
    data = [0x01234567, 0x89ABCDEF]
    await SPI_WRITE_ENABLE(dut, tb)
    await QPI_PAGE_PROGRAM(dut, tb, addr=0x100, words=data, n_words=2)
    
    tb.log.info("Read 8x bytes")
    await SPI_WRITE_DISABLE(dut,tb)
    rdata = await QPI_READ_WORDS(dut, tb, addr=0x100, n_words=2)
    assert rdata == data

    # Write and read 3x 32=bit words
    tb.log.info("Page program 12x bytes")
    data = [0x13243546, 0x97867564, 0x01234567]
    await SPI_WRITE_ENABLE(dut, tb)
    await QPI_PAGE_PROGRAM(dut, tb, addr=0x200, words=data, n_words=3)
    
    await SPI_WRITE_DISABLE(dut,tb)
    tb.log.info("Read 12x bytes")
    rdata = await QPI_READ_WORDS(dut, tb, addr=0x200, n_words=3)
    assert rdata == data

    # Write and read 4x 32=bit words
    tb.log.info("Page program 16x bytes")
    data = [0x13243546, 0x97867564, 0x89ABCDEF, 0x01234567]
    await SPI_WRITE_ENABLE(dut, tb)
    await QPI_PAGE_PROGRAM(dut, tb, addr=0x300, words=data, n_words=4)
    
    tb.log.info("Read 16x bytes")
    await SPI_WRITE_DISABLE(dut,tb)
    rdata = await QPI_READ_WORDS(dut, tb, addr=0x300, n_words=4)
    assert rdata == data
    
    for i in range(1,16):
        tb.log.info("Read %d bytes",i)
        rdata = await QPI_READ_BYTES(dut,tb,addr=0x300,n_bytes=i)

    tb.log.info("SPI write STATUS register")
    await SPI_WRITE_STATUS(dut, tb)

    # Test untested transitions in QPI
    tb.log.info("Test MODE to DATA_I transition")
    await SPI_MODE_TO_DATA(dut,tb,write=0,read=1)

    tb.log.info("Test MODE to DATA_O transition")
    await SPI_MODE_TO_DATA(dut,tb,write=1,read=0)

    tb.log.info("Test DUMMY to DATA_O transition")
    await SPI_DUMMY_TO_DATAO(dut,tb)

    tb.log.info("Test address to IDLE transition")
    await SPI_ADDR_TO_IDLE(dut, tb, addr=0xFFFFFF)

    tb.log.info("Test DUMMY to IDLE transition")
    await SPI_DUMMY_TO_IDLE(dut, tb)
    
    tb.log.info("Test MODE to IDLE transition")
    await SPI_MODE_TO_IDLE(dut, tb)

    tb.log.info("Exit QPI MODE")
    await LEAVE_QPI_MODE(dut, tb)
    await tb.config_ahb_master.write(0x00,0x0)
    
    tb.log.info("Read 16x bytes (SPI)")
    rdata = await SPI_READ_WORDS(dut, tb, addr=0x300, n_words=4)
    assert rdata == data
    
    await tb.config_ahb_master.write(0x34, 0x02)
    tb.log.info("Clock divider changed")

    tb.log.info("Read 16x bytes (SPI) Slow")
    rdata = await SPI_READ_WORDS_SLOW(dut, tb, addr=0x300, n_words=4)
    assert rdata == data
    
    tb.log.info("SPI write STATUS register")
    await SPI_WRITE_STATUS(dut, tb)

    # Test untested transitions in SPI
    tb.log.info("Test MODE to DATA_I transition")
    await SPI_MODE_TO_DATA(dut,tb,write=0,read=1)

    tb.log.info("Test MODE to DATA_O transition")
    await SPI_MODE_TO_DATA(dut,tb,write=1,read=0)

    tb.log.info("Test DUMMY to DATA_O transition")
    await SPI_DUMMY_TO_DATAO(dut,tb)

    tb.log.info("Test address to IDLE transition")
    await SPI_ADDR_TO_IDLE(dut, tb, addr=0xFFFFFF)

    tb.log.info("Test DUMMY to IDLE transition")
    await SPI_DUMMY_TO_IDLE(dut, tb)
    
    tb.log.info("Test MODE to IDLE transition")
    await SPI_MODE_TO_IDLE(dut, tb)



    await tb.config_ahb_master.write(0x34, 0x1F)
    tb.log.info("Clock divider changed")

    tb.log.info("Read 16x bytes (SPI) Very Slow")
    rdata = await SPI_READ_WORDS_SLOW(dut, tb, addr=0x300, n_words=4)
    assert rdata == data

    


@cocotb.test()
async def QSPI_READ_TESTS(dut):  
    n_reads = 64
    base_addr = 0x400

    tb = TB(dut)
    await tb.cycle_reset()
    
    tb.log.info("Reset SPI")
    await SPI_RESET(dut, tb)
    
    tb.log.info("Reading JEDIC in SPI mode")
    ID = 0x4326BF00
    rID = await SPI_READ_JEDIC(dut, tb)
    assert rID == ID
    
    tb.log.info("Setting QPI mode")
    await SET_QPI_MODE(dut, tb)
    await tb.config_ahb_master.write(0x00,0x1)
    
    await tb.config_ahb_master.write(0x34, 0x00)
    tb.log.info("Clock divider changed CLK=100MHz")

    tb.log.info("Reading JEDIC in QPI mode")
    rID = await QPI_READ_JEDIC(dut, tb)
    assert rID == ID
    
    await SPI_WRITE_ENABLE(dut, tb)
    tb.log.info("Clear Protection and enable Write")
    await SPI_CLR_PROTECTION(dut, tb)
    
    tb.log.info("Page program 512x 16-bytes")
    data = random.randint(4294967295, size=4*n_reads)
    data = data.tolist()
    for i in range(0,n_reads):
        addr = i*16 + base_addr
        await SPI_WRITE_ENABLE(dut, tb)
        SPI_STAT = await QPI_READ_STAT_REG(dut, tb)
        WEL = SPI_STAT & (1<<25)
        assert WEL != 0
        await QPI_PAGE_PROGRAM(dut, tb, addr=addr, words=data[(i*4):(i*4+4)], n_words=4)
        await SPI_WRITE_DISABLE(dut,tb)
        tb.log.info("Programmed %d words", i)
    
    await SPI_WRITE_DISABLE(dut,tb)

    tb.log.info("Read 16x bytes over APB")
    rDATA = await QPI_READ_WORDS(dut, tb, addr=0x10000, n_words=4, cont_read=True)
    
    tb.log.info("Set Continuous Read mode")
    QSPI_CTRL_REG = await tb.config_ahb_master.read(0x00,4)
    QSPI_CTRL_REG = int(QSPI_CTRL_REG[0]['data'],16)
    QSPI_CTRL_REG = QSPI_CTRL_REG | (1<<25)
    await tb.config_ahb_master.write(0x00, QSPI_CTRL_REG)    
    
    tb.log.info("Read %d x 16-bytes over APB in continous read mode",n_reads)
    start_time = cocotb.utils.get_sim_time(units='ns')
    for i in range(0,n_reads):
        addr = i*16 + base_addr
        rDATA = await QPI_READ_WORDS(dut, tb, addr=addr, n_words=4, cont_read=True)
        assert rDATA==data[(i*4):(i*4+4)]
        tb.log.info("Read %d words", i)

    end_time = cocotb.utils.get_sim_time(units='ns')
    dt= end_time-start_time

    
    tb.log.info("Set AHB Mode")
    QSPI_CTRL_REG = await tb.config_ahb_master.read(0x00,4)
    QSPI_CTRL_REG = int(QSPI_CTRL_REG[0]['data'],16)
    QSPI_CTRL_REG = QSPI_CTRL_REG | (1<<8)
    await tb.config_ahb_master.write(0x00, QSPI_CTRL_REG)

    QSPI_AHB_CMD_REG = (4<<12) + 0x0B
    await tb.config_ahb_master.write(0x30, QSPI_AHB_CMD_REG)


    tb.log.info("Configure Cache")
    CACHE_STATUS_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x04,4)
    CACHE_STATUS = int(CACHE_STATUS_tmp[0]['data'],16)
    assert CACHE_STATUS==0  
    
    await tb.config_ahb_master.write(CACHE_CONFIG_ADDR, 0x1)

    CACHE_CONFIG_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR,4)
    CACHE_CONFIG = int(CACHE_CONFIG_tmp[0]['data'],16)
    assert CACHE_CONFIG == 0x1

    CACHE_STATUS_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x04,4)
    CACHE_STATUS = int(CACHE_STATUS_tmp[0]['data'],16)
    while((CACHE_STATUS&(0x3))!=2):
        CACHE_STATUS_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x00,4)
        CACHE_STATUS_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x04,4)
        CACHE_STATUS = int(CACHE_STATUS_tmp[0]['data'],16)
        await Timer(time=10, units='us')
    
    tb.log.info("Read %d x bytes over AHB (uncached)",n_reads*16)
    start_time_uncached = cocotb.utils.get_sim_time(units='ns')
    for i in range(0,n_reads*4):
        rdata = await tb.data_ahb_master.read(i*4 + base_addr,4)
        assert int(rdata[0]['data'],16)==data[i]
    end_time_uncached = cocotb.utils.get_sim_time(units='ns')
    dt_uncached = end_time_uncached - start_time_uncached
    await Timer(time=10, units='us')
    rdata = await tb.data_ahb_master.read(base_addr,4)
    
    tb.log.info("Read %d x bytes over AHB (cached)",n_reads*16)
    start_time_cached = cocotb.utils.get_sim_time(units='ns')
    for i in range(0,n_reads*4):
        rdata = await tb.data_ahb_master.read(i*4 + base_addr,4)
        assert int(rdata[0]['data'],16)==data[i]
    end_time_cached = cocotb.utils.get_sim_time(units='ns')
    dt_cached = end_time_cached - start_time_cached

    tb.log.info("Read over AHB full address range (cached)")
    for i in range(0, 0xFFFFFF, 0x1000):
        rdata = await tb.data_ahb_master.read(i, 4)

    await tb.config_ahb_master.write(0x34, 0x05)
    tb.log.info("Clock divider changed")

    await tb.config_ahb_master.write(CACHE_CONFIG_ADDR, 0x0)
    tb.log.info("Disable Cache")
    CACHE_CONFIG_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR,4)
    CACHE_CONFIG = int(CACHE_CONFIG_tmp[0]['data'],16)
    assert CACHE_CONFIG == 0x0

    CACHE_STATUS_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x04,4)
    CACHE_STATUS = int(CACHE_STATUS_tmp[0]['data'],16)
    while((CACHE_STATUS&(0x3))!=0):
        CACHE_STATUS_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x00,4)
        CACHE_STATUS_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x04,4)
        CACHE_STATUS = int(CACHE_STATUS_tmp[0]['data'],16)
        await Timer(time=10, units='us')

    rdata = await tb.data_ahb_master.read(base_addr,4)

    tb.log.info("Read 512x 16-bytes over AHB (uncached)")
    start_time_slow = cocotb.utils.get_sim_time(units='ns')
    for i in range(0,n_reads*4):
        rdata = await tb.data_ahb_master.read(i*4+ base_addr,4)
        assert int(rdata[0]['data'],16)==data[i]
    end_time_slow = cocotb.utils.get_sim_time(units='ns')
    dt_slow = end_time_slow - start_time_slow

    tb.log.info("Try write over AHB, expect ERROR")
    resp = await tb.data_ahb_master.write(0x000,0xFFFFFFFF)
    tb.log.info(resp[0]['resp'])

    await tb.config_ahb_master.write(0x00, 0x01)

    await tb.config_ahb_master.write(0x08, 0x0FF)
    await tb.config_ahb_master.write(0x08, 0x1FF)
    await tb.config_ahb_master.write(0x08, 0x0FF)
    await tb.config_ahb_master.write(0x08, 0x1FF)
    tb.log.info("Time taken = %f", dt)
    BW = n_reads*4/(dt*1e-3)
    BW_uncached = n_reads*4/(dt_uncached*1e-3)
    BW_cached = n_reads*4/(dt_cached*1e-3)
    BW_slow = n_reads*4/(dt_slow*1e-3)
    
    tb.log.info("dt APB: %f ns", dt)
    tb.log.info("dt caching: %f ns", dt_uncached)
    tb.log.info("dt cached: %f ns", dt_cached)
    tb.log.info("dt slow: %f ns", dt_slow)


    tb.log.info("Bandwidth APB: %f MB/s", BW)
    tb.log.info("Bandwidth caching: %f MB/s", BW_uncached)
    tb.log.info("Bandwidth cached: %f MB/s", BW_cached)
    tb.log.info("Bandwidth slow: %f MB/s", BW_slow)


@cocotb.test()
async def CACHE_CONFIG(dut):
    tb = TB(dut)
    await tb.cycle_reset()
    data = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR,4)
    # After reset CCR register should = 0x40
    assert int(data[0]['data'],16) == 0x40
    data = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x20,4)
    print(data)

@cocotb.test()
async def AHB_BAD_BEHAVIOUR(dut):
    tb = TB(dut)
    await tb.cycle_reset()

    tb.log.info("Try write over AHB, expect ERROR")
    resp = await tb.data_ahb_master.write(0x000,0xCAFECAFE)
    tb.log.info(resp[0]['resp'])

    tb.log.info("Try read over AHB when in APB mode, expect ERROR")
    data = await tb.data_ahb_master.read(0x100,4)
    tb.log.info(data[0]['resp'])


@cocotb.test()
async def test_bug1_rdata_latch(dut):
    """Test BUG-1: QSPI_RDATA latch in always_comb.

    The QSPI_RDATA combinational block has no else clause when HRESETn=1
    and QSPI_nCS=0, causing QSPI_RDATA to latch its previous value.
    This test performs two reads with different data sizes and values,
    verifying QSPI_RDATA updates correctly each time and is zero after reset.
    """
    tb = TB(dut)
    await tb.cycle_reset()

    # After reset, QSPI_RDATA should be 0
    rdata_reg0 = await tb.config_ahb_master.read(0x10, 4)
    rdata_val = int(rdata_reg0[0]['data'], 16)
    tb.log.info("QSPI_RDATA word0 after reset: 0x%08x", rdata_val)
    assert rdata_val == 0, f"QSPI_RDATA should be 0 after reset, got 0x{rdata_val:08x}"

    # Initialize flash
    tb.log.info("Reset SPI")
    await SPI_RESET(dut, tb)

    tb.log.info("Setting QPI mode")
    await SET_QPI_MODE(dut, tb)
    await tb.config_ahb_master.write(0x00, 0x1)

    tb.log.info("Enable Write")
    await SPI_WRITE_ENABLE(dut, tb)

    tb.log.info("Clear Protection")
    await SPI_CLR_PROTECTION(dut, tb)

    # Write known data to two different addresses with different sizes
    # Address 0x1000: 1 word (4 bytes)
    data_a = [0xDEADBEEF]
    await SPI_WRITE_ENABLE(dut, tb)
    await QPI_PAGE_PROGRAM(dut, tb, addr=0x1000, words=data_a, n_words=1)
    tb.log.info("Programmed 0x%08x at address 0x1000", data_a[0])

    # Address 0x1100: 2 words (8 bytes)
    data_b = [0x12345678, 0xCAFEBABE]
    await SPI_WRITE_ENABLE(dut, tb)
    await QPI_PAGE_PROGRAM(dut, tb, addr=0x1100, words=data_b, n_words=2)
    tb.log.info("Programmed 0x%08x 0x%08x at address 0x1100", data_b[0], data_b[1])

    # First read: 1 word from address 0x1000
    await SPI_WRITE_DISABLE(dut, tb)
    tb.log.info("Read 1 word from address 0x1000")
    rdata1 = await QPI_READ_WORDS(dut, tb, addr=0x1000, n_words=1)
    tb.log.info("Read data 1: 0x%08x (expected 0x%08x)", rdata1[0], data_a[0])
    assert rdata1 == data_a, f"First read mismatch: got {rdata1}, expected {data_a}"

    # Second read: 2 words from address 0x1100 (different byte count exercises
    # the QSPI_RDATA mux with a different QSPI_N_RW_BYTES value)
    tb.log.info("Read 2 words from address 0x1100")
    rdata2 = await QPI_READ_WORDS(dut, tb, addr=0x1100, n_words=2)
    tb.log.info("Read data 2: 0x%08x 0x%08x (expected 0x%08x 0x%08x)",
                rdata2[0], rdata2[1], data_b[0], data_b[1])
    assert rdata2 == data_b, f"Second read mismatch: got {rdata2}, expected {data_b}"

    # Third read: re-read address 0x1000 to confirm RDATA updates back
    tb.log.info("Re-read 1 word from address 0x1000")
    rdata3 = await QPI_READ_WORDS(dut, tb, addr=0x1000, n_words=1)
    tb.log.info("Read data 3: 0x%08x (expected 0x%08x)", rdata3[0], data_a[0])
    assert rdata3 == data_a, f"Third read mismatch: got {rdata3}, expected {data_a}"

    tb.log.info("BUG-1 test PASSED: QSPI_RDATA updates correctly across reads")


@cocotb.test()
async def test_bug2_enable_ack_latch(dut):
    """Test BUG-2: QSPI_ENABLE_ACK not assigned in all FSM states.

    QSPI_ENABLE_ACK is only assigned in IDLE (else branch), NO_FETCH, OP,
    and ADDR states. It is NOT assigned in MODE, DUMMY, DATA_O, DATA_I,
    creating a latch. This test exercises transactions that pass through
    MODE, DUMMY, and DATA_I states and verifies QSPI_ENABLE_ACK behaves
    correctly (deasserts to allow reg2[8] to clear so the controller
    completes properly).
    """
    tb = TB(dut)
    await tb.cycle_reset()

    # Initialize flash
    tb.log.info("Reset SPI")
    await SPI_RESET(dut, tb)

    tb.log.info("Setting QPI mode")
    await SET_QPI_MODE(dut, tb)
    await tb.config_ahb_master.write(0x00, 0x1)

    tb.log.info("Enable Write and Clear Protection")
    await SPI_WRITE_ENABLE(dut, tb)
    await SPI_CLR_PROTECTION(dut, tb)

    # Program test data
    data = [0xA5A5A5A5, 0x5A5A5A5A, 0x12345678, 0x9ABCDEF0]
    await SPI_WRITE_ENABLE(dut, tb)
    await QPI_PAGE_PROGRAM(dut, tb, addr=0x2000, words=data, n_words=4)
    tb.log.info("Programmed 4 words at address 0x2000")

    await SPI_WRITE_DISABLE(dut, tb)

    # Test 1: Read with dummy cycles (exercises DUMMY and DATA_I states)
    # Standard QPI fast read (0x0B) with 6 dummy cycles, 4 words
    tb.log.info("Test read with dummy cycles (DUMMY -> DATA_I path)")
    rdata = await QPI_READ_WORDS(dut, tb, addr=0x2000, n_words=4)
    tb.log.info("Read data: %s", [hex(x) for x in rdata])
    assert rdata == data, f"Read with dummy cycles failed: got {rdata}, expected {data}"

    # After transaction completes, verify QSPI is no longer busy
    # (QSPI_ENABLE_ACK must have been properly handled)
    status = await tb.config_ahb_master.read(0x04, 4)
    busy = int(status[0]['data'], 16) & 1
    tb.log.info("QSPI busy after dummy-cycle read: %d", busy)
    assert busy == 0, "QSPI should not be busy after transaction completes"

    # Test 2: Read with continuous read mode (exercises MODE -> DUMMY -> DATA_I)
    # Enable continuous read mode with mode code 0xA0
    tb.log.info("Test read with continuous read mode (MODE -> DUMMY -> DATA_I path)")
    QSPI_CTRL_REG = await tb.config_ahb_master.read(0x00, 4)
    QSPI_CTRL_REG = int(QSPI_CTRL_REG[0]['data'], 16)
    QSPI_CTRL_REG = QSPI_CTRL_REG | ((0xA0 << 16) + (1 << 24))
    await tb.config_ahb_master.write(0x00, QSPI_CTRL_REG)

    rdata2 = await QPI_READ_WORDS(dut, tb, addr=0x2000, n_words=4, cont_read=True)
    tb.log.info("Read data (cont): %s", [hex(x) for x in rdata2])
    assert rdata2 == data, f"Continuous read failed: got {rdata2}, expected {data}"

    # Check busy flag cleared
    status = await tb.config_ahb_master.read(0x04, 4)
    busy = int(status[0]['data'], 16) & 1
    tb.log.info("QSPI busy after continuous read: %d", busy)
    assert busy == 0, "QSPI should not be busy after continuous read completes"

    # Test 3: MODE -> DATA_I transition (no dummy cycles, with mode code)
    tb.log.info("Test MODE -> DATA_I transition")
    await SPI_MODE_TO_DATA(dut, tb, write=0, read=1)

    # Check busy flag cleared
    status = await tb.config_ahb_master.read(0x04, 4)
    busy = int(status[0]['data'], 16) & 1
    tb.log.info("QSPI busy after MODE->DATA_I: %d", busy)
    assert busy == 0, "QSPI should not be busy after MODE->DATA_I completes"

    # Test 4: DUMMY -> DATA_O transition
    tb.log.info("Test DUMMY -> DATA_O transition")
    await SPI_DUMMY_TO_DATAO(dut, tb)

    # Check busy flag cleared
    status = await tb.config_ahb_master.read(0x04, 4)
    busy = int(status[0]['data'], 16) & 1
    tb.log.info("QSPI busy after DUMMY->DATA_O: %d", busy)
    assert busy == 0, "QSPI should not be busy after DUMMY->DATA_O completes"

    tb.log.info("BUG-2 test PASSED: QSPI_ENABLE_ACK handled correctly through MODE/DUMMY/DATA states")


@cocotb.test()
async def test_bug3_no_cmd_last_addr(dut):
    """Test BUG-3: last_QSPI_ADDR stateful assignment in always_comb.

    last_QSPI_ADDR is assigned with a blocking assignment in the always_comb
    FSM block (ADDR state), creating a latch. This variable is used by the
    NO_CMD optimization: when QSPI_NO_CMD=1 and the address matches
    last_QSPI_ADDR, the FSM skips to NO_FETCH instead of ADDR.

    Test sequence:
    1. Normal QPI read to address A (sets last_QSPI_ADDR = A)
    2. Enable NO_CMD mode
    3. Read same address A -> should use NO_FETCH path
    4. Read different address B -> should use ADDR path
    5. Verify correct data in all cases
    """
    tb = TB(dut)
    await tb.cycle_reset()

    # Initialize flash
    tb.log.info("Reset SPI")
    await SPI_RESET(dut, tb)

    tb.log.info("Setting QPI mode")
    await SET_QPI_MODE(dut, tb)
    await tb.config_ahb_master.write(0x00, 0x1)

    tb.log.info("Enable Write and Clear Protection")
    await SPI_WRITE_ENABLE(dut, tb)
    await SPI_CLR_PROTECTION(dut, tb)

    # Program data at two different addresses
    addr_a = 0x3000
    addr_b = 0x3100
    data_a = [0x11223344, 0x55667788, 0x99AABBCC, 0xDDEEFF00]
    data_b = [0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC, 0xDDDDDDDD]

    await SPI_WRITE_ENABLE(dut, tb)
    await QPI_PAGE_PROGRAM(dut, tb, addr=addr_a, words=data_a, n_words=4)
    tb.log.info("Programmed 4 words at address 0x%06x", addr_a)

    await SPI_WRITE_ENABLE(dut, tb)
    await QPI_PAGE_PROGRAM(dut, tb, addr=addr_b, words=data_b, n_words=4)
    tb.log.info("Programmed 4 words at address 0x%06x", addr_b)

    await SPI_WRITE_DISABLE(dut, tb)

    # Step 1: Normal QPI read to address A (this sets last_QSPI_ADDR = A)
    # Use continuous read mode so the controller goes through MODE state
    # and sets up for NO_CMD usage
    tb.log.info("Step 1: Normal QPI read to address 0x%06x (sets last_QSPI_ADDR)", addr_a)
    rdata1 = await QPI_READ_WORDS(dut, tb, addr=addr_a, n_words=4, cont_read=True)
    tb.log.info("Read data: %s", [hex(x) for x in rdata1])
    assert rdata1 == data_a, f"Step 1 read mismatch: got {rdata1}, expected {data_a}"

    # Step 2: Enable NO_CMD mode (bit 25 of reg0)
    tb.log.info("Step 2: Enable NO_CMD mode")
    QSPI_CTRL_REG = await tb.config_ahb_master.read(0x00, 4)
    QSPI_CTRL_REG = int(QSPI_CTRL_REG[0]['data'], 16)
    QSPI_CTRL_REG = QSPI_CTRL_REG | (1 << 25)
    await tb.config_ahb_master.write(0x00, QSPI_CTRL_REG)
    tb.log.info("reg0 = 0x%08x (NO_CMD enabled)", QSPI_CTRL_REG)

    # Step 3: Read same address A with NO_CMD -> should use NO_FETCH path
    tb.log.info("Step 3: Read same address 0x%06x with NO_CMD (expect NO_FETCH path)", addr_a)
    rdata2 = await QPI_READ_WORDS(dut, tb, addr=addr_a, n_words=4, cont_read=True)
    tb.log.info("Read data (same addr, NO_CMD): %s", [hex(x) for x in rdata2])
    assert rdata2 == data_a, f"Step 3 read mismatch (NO_FETCH path): got {rdata2}, expected {data_a}"

    # Step 4: Read different address B with NO_CMD -> should use ADDR path
    tb.log.info("Step 4: Read different address 0x%06x with NO_CMD (expect ADDR path)", addr_b)
    rdata3 = await QPI_READ_WORDS(dut, tb, addr=addr_b, n_words=4, cont_read=True)
    tb.log.info("Read data (diff addr, NO_CMD): %s", [hex(x) for x in rdata3])
    assert rdata3 == data_b, f"Step 4 read mismatch (ADDR path): got {rdata3}, expected {data_b}"

    # Step 5: Read address B again with NO_CMD -> should use NO_FETCH again
    # (last_QSPI_ADDR should now be B)
    tb.log.info("Step 5: Read same address 0x%06x again with NO_CMD (expect NO_FETCH)", addr_b)
    rdata4 = await QPI_READ_WORDS(dut, tb, addr=addr_b, n_words=4, cont_read=True)
    tb.log.info("Read data (same addr B, NO_CMD): %s", [hex(x) for x in rdata4])
    assert rdata4 == data_b, f"Step 5 read mismatch: got {rdata4}, expected {data_b}"

    # Step 6: Go back to address A with NO_CMD -> should use ADDR path
    tb.log.info("Step 6: Read address 0x%06x with NO_CMD (expect ADDR path)", addr_a)
    rdata5 = await QPI_READ_WORDS(dut, tb, addr=addr_a, n_words=4, cont_read=True)
    tb.log.info("Read data (back to addr A, NO_CMD): %s", [hex(x) for x in rdata5])
    assert rdata5 == data_a, f"Step 6 read mismatch: got {rdata5}, expected {data_a}"

    # Disable NO_CMD mode
    QSPI_CTRL_REG = QSPI_CTRL_REG & ~(1 << 25)
    await tb.config_ahb_master.write(0x00, QSPI_CTRL_REG)
    tb.log.info("NO_CMD mode disabled")

    tb.log.info("BUG-3 test PASSED: last_QSPI_ADDR and NO_CMD/NO_FETCH work correctly")