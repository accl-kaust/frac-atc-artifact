## Directory

``` sh
├── kernels
│   ├── cmac_krnl # CMAC IP intialization
│   ├── common
│   ├── network_krnl # Binding Network stack
│   └── user_krnl # User logic ; currently just loopsback
├── lib
│   ├── axis # Some axis components
│   └── fpga-network-stack # TCP Stack
├── offrac
│   ├── ip
│   ├── rtl # Stitches the whole stack together
│   └── xdc
├── hls.mk # Builds TCP stack
├── Makefile
├── vivado.mk # Build OffRAC
└── README.md
```

## Build Instructions

### Building from scratch ?

``` sh
$ make all
```

### Seperating Builds

#### OffRAC uses [ETH's TCP stack](https://github.com/fpgasystems/Vitis_with_100Gbps_TCP-IP/tree/vitis_2020_1) and uses it as a library as well as few kernels. To build the library
``` sh
$ make ip
```

#### Finally to build OffRAC
``` sh
$ make offrac
```

## Prerequisites

Currently, the project is only tested with Xilinx 2021.2 tools.

### Libraries and Borrowed Code

Some code is borrowed from [Corundum](https://github.com/corundum/corundum) project.
