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
        self.config_ahb_master = AHBLiteMaster(AHBBus.from_prefix(dut,"config", optional_signals = {"hsel":"HSEL", "hready_in":"HREADY_IN", "hburst":"HBURST"}), dut.HCLK, dut.HRESETn)
        self.data_ahb_master = AHBLiteMaster(AHBBus.from_prefix(dut,"data", optional_signals = {"hsel":"HSEL", "hready_in":"HREADY_IN", "hburst":"HBURST"}), dut.HCLK, dut.HRESETn)

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

async def SPI_RESET(dut,tb):
    await tb.config_ahb_master.write(0x08, 0x00000066)
    await tb.config_ahb_master.write(0x08, 0x00000166)

    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,2)
        data = await tb.config_ahb_master.read(0x04,4)
    
    await tb.config_ahb_master.write(0x08, 0x00000099)
    await tb.config_ahb_master.write(0x08, 0x00000199)
    
    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,2)
        data = await tb.config_ahb_master.read(0x04,4)
            
async def SPI_READ_JEDIC(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x0002009F)
    await tb.config_ahb_master.write(0x08, 0x0002039F)
    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,10)
        data = await tb.config_ahb_master.read(0x04,4)
    ID = await tb.config_ahb_master.read(0x10,4)
    return int(ID[0]['data'],16)

async def SET_QPI_MODE(dut,tb):
    await tb.config_ahb_master.write(0x08, 0x00000038)
    await tb.config_ahb_master.write(0x08, 0x00000138)

    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,2)
        data = await tb.config_ahb_master.read(0x04,4)

async def LEAVE_QPI_MODE(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x000000FF)
    await tb.config_ahb_master.write(0x08, 0x000001FF)

    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,2)
        data = await tb.config_ahb_master.read(0x04,4)

async def QPI_READ_JEDIC(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x000220AF)
    await tb.config_ahb_master.write(0x08, 0x000223AF)
    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,10)
        data = await tb.config_ahb_master.read(0x04,4)
    ID = await tb.config_ahb_master.read(0x10,4)
    return int(ID[0]['data'],16) 
      
async def SPI_WRITE_ENABLE(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x00000006)
    await tb.config_ahb_master.write(0x08, 0x00000106)

    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,2)
        data = await tb.config_ahb_master.read(0x04,4)
 
async def SPI_WRITE_DISABLE(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x00000004)
    await tb.config_ahb_master.write(0x08, 0x00000104)

    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,2)
        data = await tb.config_ahb_master.read(0x04,4)
       
async def SPI_CLR_PROTECTION(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x00000098)
    await tb.config_ahb_master.write(0x08, 0x00000198)

    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,2)
        data = await tb.config_ahb_master.read(0x04,4)
   
async def SPI_CHIP_ERASE(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x000000C7)
    await tb.config_ahb_master.write(0x08, 0x000001C7)

    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,2)
        data = await tb.config_ahb_master.read(0x04,4)

async def SPI_BLOCK_ERASE(dut, tb):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, 0x000000)
    
    await tb.config_ahb_master.write(0x08, 0x000008D8)
    await tb.config_ahb_master.write(0x08, 0x000009D8)

    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,2)
        data = await tb.config_ahb_master.read(0x04,4)
    SPI_STAT = await SPI_READ_STAT_REG(dut, tb)
    while(SPI_STAT&(1<<24)):
        SPI_STAT = await SPI_READ_STAT_REG(dut, tb)
        await Timer(time=1, units='ms')
   
async def SPI_READ_STAT_REG(dut,tb):
    await tb.config_ahb_master.write(0x08, 0x00002005)
    await tb.config_ahb_master.write(0x08, 0x00002305)
    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,10)
        data = await tb.config_ahb_master.read(0x04,4)
    data = await tb.config_ahb_master.read(0x10,4)
    return (int(data[0]['data'],16))

async def QPI_READ_STAT_REG(dut,tb):
    await tb.config_ahb_master.write(0x08, 0x00002005)
    await tb.config_ahb_master.write(0x08, 0x00002305)
    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,10)
        data = await tb.config_ahb_master.read(0x04,4)
    data = await tb.config_ahb_master.read(0x10,4)
    return (int(data[0]['data'],16))


async def SPI_READ_SLOW(dut, tb):
    # Write Adress
    await tb.config_ahb_master.write(0x0C, 0x000000)
    
    await tb.config_ahb_master.write(0x08, 0x00001003)
    await tb.config_ahb_master.write(0x08, 0x00001303)
    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,10)
        data = await tb.config_ahb_master.read(0x04,4)
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
    
    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,10)
        data = await tb.config_ahb_master.read(0x04,4)
        
    apb_r_addrs=[0x10, 0x14, 0x18, 0x1C]
    rData = []
    for i in range(0,n_words):
        rData_temp = await tb.config_ahb_master.read(apb_r_addrs[i],4)
        rData.append(int(rData_temp[0]['data'],16))
    return rData
    
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
    
    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,10)
        data = await tb.config_ahb_master.read(0x04,4)
    SPI_STAT = await QPI_READ_STAT_REG(dut, tb)
    while(SPI_STAT&(1<<24)):
        SPI_STAT = await QPI_READ_STAT_REG(dut, tb)
        await Timer(time=1, units='us')




@cocotb.test()
async def QSPI_TESTS(dut):  
    tb = TB(dut)
    await tb.cycle_reset()
    
    tb.log.info("Reset SPI")
    await SPI_RESET(dut, tb)
    
    tb.log.info("Reading JEDIC in SPI mode")
    ID = 0x4326BF00
    rID = await SPI_READ_JEDIC(dut, tb)
    print(rID)
    assert rID == ID
    
    tb.log.info("Setting QPI mode")
    await SET_QPI_MODE(dut, tb)
    await tb.config_ahb_master.write(0x00,0x1)
    
    tb.log.info("Reading JEDIC in QPI mode")
    rID = await QPI_READ_JEDIC(dut, tb)
    print(rID)
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

    tb.log.info("Exit QPI MODE")
    await LEAVE_QPI_MODE(dut, tb)
    await tb.config_ahb_master.write(0x00,0x1)

    


@cocotb.test()
async def QSPI_READ_TESTS(dut):  
    n_reads = 64


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
    
    tb.log.info("Reading JEDIC in QPI mode")
    rID = await QPI_READ_JEDIC(dut, tb)
    assert rID == ID
    
    await SPI_WRITE_ENABLE(dut, tb)
    tb.log.info("Clear Protection and enable Write")
    await SPI_CLR_PROTECTION(dut, tb)
    await SPI_WRITE_ENABLE(dut, tb)
    SPI_STAT = await QPI_READ_STAT_REG(dut, tb)
    WEL = SPI_STAT & (1<<25)
    assert WEL != 0
    
    tb.log.info("Page program 512x 16-bytes")
    data = [0x13243546, 0x97867564, 0x89ABCDEF, 0x01234567]
    for i in range(0,n_reads):
        addr = i*16
        await QPI_PAGE_PROGRAM(dut, tb, addr=addr, words=data, n_words=4)
        await SPI_WRITE_ENABLE(dut, tb)
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
        addr = i*16
        rDATA = await QPI_READ_WORDS(dut, tb, addr=addr, n_words=4, cont_read=True)
        assert rDATA==data
        tb.log.info("Read %d words", i)

    end_time = cocotb.utils.get_sim_time(units='ns')
    dt= end_time-start_time

    
    tb.log.info("Set AHB Mode")
    QSPI_CTRL_REG = await tb.config_ahb_master.read(0x00,4)
    QSPI_CTRL_REG = int(QSPI_CTRL_REG[0]['data'],16)
    QSPI_CTRL_REG = QSPI_CTRL_REG | (1<<8)
    await tb.config_ahb_master.write(0x00, QSPI_CTRL_REG)

    tb.log.info("Configure Cache")
    CACHE_STATUS_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x04,4)
    CACHE_STATUS = int(CACHE_STATUS_tmp[0]['data'],16)
    assert CACHE_STATUS==0  
    
    await tb.config_ahb_master.write(CACHE_CONFIG_ADDR, 0x21)

    CACHE_STATUS_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x04,4)
    CACHE_STATUS = int(CACHE_STATUS_tmp[0]['data'],16)
    while((CACHE_STATUS&(0x3))!=2):
        CACHE_STATUS_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x00,4)
        CACHE_STATUS_tmp = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x04,4)
        CACHE_STATUS = int(CACHE_STATUS_tmp[0]['data'],16)
        await Timer(time=10, units='us')
        print(CACHE_STATUS)
    print(CACHE_STATUS) 

    
    
    tb.log.info("Read %d x 16-bytes over AHB (uncached)",n_reads)
    start_time_uncached = cocotb.utils.get_sim_time(units='ns')
    for i in range(0,n_reads*4):
        data = await tb.data_ahb_master.read(i*4,4)
    end_time_uncached = cocotb.utils.get_sim_time(units='ns')
    dt_uncached = end_time_uncached - start_time_uncached
    await Timer(time=10, units='us')
    
    tb.log.info("Read 512x 16-bytes over AHB (cached)")
    start_time_cached = cocotb.utils.get_sim_time(units='ns')
    for i in range(0,n_reads*4):
        data = await tb.data_ahb_master.read(i*4,4)
    end_time_cached = cocotb.utils.get_sim_time(units='ns')
    dt_cached = end_time_cached - start_time_cached


    await tb.config_ahb_master.write(0x00, 0x01)

    await tb.config_ahb_master.write(0x08, 0x0FF)
    await tb.config_ahb_master.write(0x08, 0x1FF)
    await tb.config_ahb_master.write(0x08, 0x0FF)
    await tb.config_ahb_master.write(0x08, 0x1FF)
    tb.log.info("Time taken = %f", dt)
    BW = n_reads*4/(dt*1e-3)
    BW_uncached = n_reads*4/(dt_uncached*1e-3)
    BW_cached = n_reads*4/(dt_cached*1e-3)

    tb.log.info("dt APB: %f ns", dt)
    tb.log.info("dt caching: %f ns", dt_uncached)
    tb.log.info("dt cached: %f ns", dt_cached)


    tb.log.info("Bandwidth APB: %f MB/s", BW)
    tb.log.info("Bandwidth caching: %f MB/s", BW_uncached)
    tb.log.info("Bandwidth cached: %f MB/s", BW_cached)


@cocotb.test()
async def CACHE_CONFIG(dut):
    tb = TB(dut)
    await tb.cycle_reset()
    data = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR,4)
    # After reset CCR register should = 0x40
    assert int(data[0]['data'],16) == 0x40
    data = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x20,4)
    print(data)
