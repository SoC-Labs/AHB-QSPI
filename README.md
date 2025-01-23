# AHB QSPI with XiP
Basic QSPI controller with AHB and APB interfaces, uses Arm Corelink AHB Flash Cache controller for the XiP Cache. AHB from cache controller and APB interface are mux'd to QSPI controller so access can to external memory can be from either.

## Prerequisites 
This core uses external IP available from Arm

- Corstone 101 (BP210)
- Arm Flash Cache (CG092)

If you are utilising this IP you must set the SOCLABS_AHB_QSPI_DIR environment variable. This can be achieved by running `source set_env.sh`

## Integration
Top level 3 main ports:

- AHB: To Arm Flash Cache
- APB: To both APB QSPI controller and Arm Flash Cache for configuration
- QSPI

The AHB needs a minimum of 16 address bits, to 22 address bits (for an external flash size between 64 KB and 4096 KB). The default is 22. Cache size is between 32 bytes to 4 KB (default is 4 KB).

The APB is mapped between the QSPI controller and Flash Cache configuration registers as below

- 0x0000-0x0FFF : QSPI controller
- 0x1000-0x1FFF : Flash Cache

## Simulation
The AHB QSPI includes a cocoTB simulation environment. This can be run using the `make run_cocotb` command

## Statistics
Read bandwidth with 4 KB cache for 512x 32 bit reads, and system clock of 200 MHz + SPI clock 100 MHz:

- Using APB: 5.8 MB/s
- Using AHB(uncached, prefetch enabled): 32 MB/s
- Using AHB(cached): 400 MB/s

## ToDo
- Add programmable clock divider for QSPI
- Add programmable op codes for AHB interface
- Improve writing method over APB? (see below)
- Add interrupts for QSPI finish

## Writing over APB
Currently the method for writing over APB to the flash is to write up to 4x 32 bit words to the APB registers and then tell the QSPI controller to write. However as there is a long latency after writing over QSPI for the flash to finish, this is not optimal. 

The flash device we are targeting is a SST26VF064B device which allows up to 256 bytes to be written in a single SPI transaction (currently only writing 16 bytes per transaction). So proposals for improving this are as follows

1. Just simply add an extra 240 bytes of registers to the APB controller. This is the simplest to do but I think that this will inflate the overall area of the IP by too much, however this makes the software side fairly simple. (i.e. write 256 bytes to APB-> send command to QSPI controller-> wait for QSPI transaction to finish-> poll QSPI status until write is complete)
2. Add write fifo. This will be a lot smaller in terms of area. But will have to keep track of how many bytes get written over QSPI to limit to 256. This requires a bit of an overhaul in how the write transaction works but it means we can fully utilise the page program command. Software then becomes a little more complicated (i.e. write N bytes to APB-> send command to QSPI controller-> check if FIFO not full and send more data-> repeat last step 256/N times-> QSPI checks if FIFO is empty whilst the happens and stops transaction when empty-> poll QSPI status until write is complete). 

