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

async def SPI_RESET(dut,tb):
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

    await tb.config_ahb_master.write(0x08, 0x00000066)
    await tb.config_ahb_master.write(0x08, 0x00000166)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)

    await tb.config_ahb_master.write(0x08, 0x00000099)
    await tb.config_ahb_master.write(0x08, 0x00000199)

    await wait_for_irq(dut,tb)
    await poll_busy_clear(dut, tb)
            
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



