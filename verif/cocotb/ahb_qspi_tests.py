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
        self.config_ahb_master = AHBLiteMaster(AHBBus.from_prefix(dut,"config", optional_signals = {"hsel":"HSEL", "hready_in":"HREADY_IN", "hburst":"HBURST"}), dut.HCLK, dut.HRESETn, 500)
        self.data_ahb_master = AHBLiteMaster(AHBBus.from_prefix(dut,"data", optional_signals = {"hsel":"HSEL", "hready_in":"HREADY_IN", "hburst":"HBURST"}), dut.HCLK, dut.HRESETn, 500)

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

    tb.log.info("Exit QPI MODE")
    await LEAVE_QPI_MODE(dut, tb)
    await tb.config_ahb_master.write(0x00,0x1)

    


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
    
    tb.log.info("Reading JEDIC in QPI mode")
    rID = await QPI_READ_JEDIC(dut, tb)
    assert rID == ID
    
    await SPI_WRITE_ENABLE(dut, tb)
    tb.log.info("Clear Protection and enable Write")
    await SPI_CLR_PROTECTION(dut, tb)
    
    tb.log.info("Page program 512x 16-bytes")
    data = [0x13243546, 0x97867564, 0x89ABCDEF, 0x01234567]
    for i in range(0,n_reads):
        addr = i*16 + base_addr
        await SPI_WRITE_ENABLE(dut, tb)
        SPI_STAT = await QPI_READ_STAT_REG(dut, tb)
        WEL = SPI_STAT & (1<<25)
        assert WEL != 0
        await QPI_PAGE_PROGRAM(dut, tb, addr=addr, words=data, n_words=4)
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
        assert rDATA==data
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
    
    tb.log.info("Read %d x 16-bytes over AHB (uncached)",n_reads)
    start_time_uncached = cocotb.utils.get_sim_time(units='ns')
    for i in range(0,n_reads*4):
        rdata = await tb.data_ahb_master.read(i*4 + base_addr,4)
        assert int(rdata[0]['data'],16)==data[i%4]
    end_time_uncached = cocotb.utils.get_sim_time(units='ns')
    dt_uncached = end_time_uncached - start_time_uncached
    await Timer(time=10, units='us')
    
    tb.log.info("Read 512x 16-bytes over AHB (cached)")
    start_time_cached = cocotb.utils.get_sim_time(units='ns')
    for i in range(0,n_reads*4):
        rdata = await tb.data_ahb_master.read(i*4+ base_addr,4)
        assert int(rdata[0]['data'],16)==data[i%4]
    end_time_cached = cocotb.utils.get_sim_time(units='ns')
    dt_cached = end_time_cached - start_time_cached

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


    tb.log.info("Read 512x 16-bytes over AHB (uncached)")
    start_time_slow = cocotb.utils.get_sim_time(units='ns')
    for i in range(0,n_reads*4):
        rdata = await tb.data_ahb_master.read(i*4+ base_addr,4)
        assert int(rdata[0]['data'],16)==data[i%4]
    end_time_slow = cocotb.utils.get_sim_time(units='ns')
    dt_slow = end_time_slow - start_time_slow


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