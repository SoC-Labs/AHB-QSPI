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

class TB:
    def __init__(self,dut):
        self.dut = dut
        
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.HCLK, 10, units="ns").start())
        self.ahb_master = AHBLiteMaster(AHBBus.from_prefix(dut,"cocotb"), dut.HCLK, dut.HRESETn)
    async def cycle_reset(self):
        self.dut.HRESETn.setimmediatevalue(0)
        await ClockCycles(self.dut.HCLK,20)
        self.dut.HRESETn.setimmediatevalue(1)
        await ClockCycles(self.dut.HCLK,10)
            
@cocotb.test()
async def AHB_QSPI_1(dut):
    tb = TB(dut)
    await tb.cycle_reset()
    
    await tb.ahb_master.write(0x00,0x15)