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
        cocotb.start_soon(Clock(dut.HCLK, 4.166, units="ns").start())
        self.config_ahb_master = AHBLiteMaster(AHBBus.from_prefix(dut,"config", optional_signals = {"hsel":"HSEL", "hready_in":"HREADY_IN", "hburst":"HBURST", "hprot":"HPROT"}), dut.HCLK, dut.HRESETn)
        self.data_ahb_master = AHBLiteMaster(AHBBus.from_prefix(dut,"data", optional_signals = {"hsel":"HSEL", "hready_in":"HREADY_IN", "hburst":"HBURST", "hprot":"HPROT"}), dut.HCLK, dut.HRESETn)

    async def cycle_reset(self):
        self.dut.HRESETn.setimmediatevalue(0)
        await ClockCycles(self.dut.HCLK,20)
        self.dut.HRESETn.setimmediatevalue(1)
        await ClockCycles(self.dut.HCLK,10)
            

@cocotb.test()
async def CACHE_CONFIG(dut):
    tb = TB(dut)
    await tb.cycle_reset()
    data = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR,4)
    # After reset CCR register should = 0x40
    assert int(data[0]['data'],16) == 0x40
    data = await tb.config_ahb_master.read(CACHE_CONFIG_ADDR+0x20,4)
    print(data)
    
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

async def SET_QPI_MODE(dut,tb):
    await tb.config_ahb_master.write(0x08, 0x00000038)
    await tb.config_ahb_master.write(0x08, 0x00000138)

    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,2)
        data = await tb.config_ahb_master.read(0x04,4)

async def QPI_READ_JEDIC(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x000210AF)
    await tb.config_ahb_master.write(0x08, 0x000213AF)
    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,10)
        data = await tb.config_ahb_master.read(0x04,4)
        
async def SPI_WRITE_ENABLE(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x00000006)
    await tb.config_ahb_master.write(0x08, 0x00000106)

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
   

async def SPI_BLOCK_ERASE(dut, tb):
    await tb.config_ahb_master.write(0x08, 0x000008D8)
    await tb.config_ahb_master.write(0x08, 0x000009D8)

    data = await tb.config_ahb_master.read(0x04,4)
    while(int(data[0]['data'],16)&1):
        await ClockCycles(dut.HCLK,2)
        data = await tb.config_ahb_master.read(0x04,4)
   


@cocotb.test()
async def QSPI_TESTS(dut):  
    tb = TB(dut)
    await tb.cycle_reset()
    await SPI_RESET(dut, tb)
    await SPI_READ_JEDIC(dut, tb)
    await SET_QPI_MODE(dut, tb)
    await tb.config_ahb_master.write(0x00,0x1)
    await QPI_READ_JEDIC(dut, tb)
    await SPI_WRITE_ENABLE(dut, tb)
    await SPI_CLR_PROTECTION(dut, tb)
    await SPI_CHIP_ERASE(dut, tb)

    
    