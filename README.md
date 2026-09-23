# fRAC

fRAC enables request-level, in-network invocation of FPGA accelerators. It
reassembles incoming request data, schedules requests to accelerators, and
supports swapping accelerators at runtime through partial reconfiguration.

## Directory

``` sh
├── kernels
│   ├── cmac_krnl # CMAC IP intialization
│   ├── common
│   ├── network_krnl # Binding Network stack
│   └── user_krnl # Request reassembly, accelerator slots, and PR control
├── lib
│   ├── axis # Some axis components
│   └── fpga-network-stack # TCP Stack
├── frac
│   ├── ip
│   ├── rtl # Stitches the whole stack together
│   └── xdc
├── hls.mk # Builds TCP stack
├── Makefile
├── vivado.mk # Build fRAC
└── README.md
```

## Documentation

Start with the [fRAC overview](docs/index.rst) for the network architecture,
request processing, runtime accelerator replacement, and design philosophy.
The detailed guides cover the reconfiguration controller, network command ABI,
ICAP bitstream format, build and deployment flow, verification coverage, and
current implementation limitations.

## Build Instructions

### Building from scratch ?

``` sh
$ make all
```

### Seperating Builds

#### fRAC uses [ETH's TCP stack](https://github.com/fpgasystems/Vitis_with_100Gbps_TCP-IP/tree/vitis_2020_1) and uses it as a library as well as few kernels. To build the library
``` sh
$ make ip
```

#### Finally to build fRAC
``` sh
$ make frac
```

## Prerequisites

Currently, the project is only tested with Xilinx 2021.2 tools.


### Libraries and Borrowed Code

Some code is borrowed from [Corundum](https://github.com/corundum/corundum) and [taxi](https://github.com/fpganinja/taxi) project.
