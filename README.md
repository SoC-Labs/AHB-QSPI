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

