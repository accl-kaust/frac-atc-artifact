# fRAC

fRAC enables request-level, in-network invocation of FPGA accelerators. It
reassembles incoming request data, schedules requests to accelerators, and
supports swapping accelerators at runtime through partial reconfiguration.

## Directory

``` sh
├── kernels
│   ├── cmac_krnl # CMAC IP initialization
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

## Prerequisites

### Hardware

The current design targets the Xilinx Alveo U280 FPGA accelerator card
(`xcu280-fsvh2892-2L-e`). The documented setup uses:

- An Alveo U280
- A host with a ConnectX-6 Dx 100GbE NIC
- A 100G QSFP cable connecting the U280's `qsfp0` port to the NIC.
- A USB cable connecting the U280's JTAG interface to the machine running Vivado
  for initial FPGA programming.

The network client and Vivado can run on the same machine or separate machines.
See the [quick-start guide](docs/quick-start.rst) for hardware connections, host
software setup, FPGA programming, and a request-response test.

### Software

Currently, the project is only tested with Vivado 2022.2 tools.

## Build Instructions

### Build from scratch

``` sh
$ make all
```

### Separate builds

fRAC uses [ETH's TCP stack](https://github.com/fpgasystems/Vitis_with_100Gbps_TCP-IP/tree/vitis_2020_1)
as a library along with several kernels. Build the library first:

``` sh
$ make ip
```

Then build fRAC:

``` sh
$ make frac
```

## Libraries and Borrowed Code

Some code is borrowed from the [Corundum](https://github.com/corundum/corundum)
and [taxi](https://github.com/fpganinja/taxi) projects.
