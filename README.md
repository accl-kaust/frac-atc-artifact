# fRAC

fRAC enables request-level, in-network invocation of FPGA accelerators. It
reassembles incoming request data, schedules requests to accelerators, and
supports swapping accelerators at runtime through partial reconfiguration.
By eliminating PCIe round trips and software overhead from the request path,
fRAC achieves low latency at 100G. fRAC is currently built on top of EasyNet, a TCP stack for FPGAs, but its design is transport agnostic.

## Directory Structure

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

Follow the [documentation](https://accl-kaust.github.io/frac-atc-artifact/) to set up and run fRAC.


## Prerequisites

fRAC has been tested with Vitis and Vivado 2022.2 on an Alveo U280 connected to a Mellanox ConnectX-6 Dx 100 Gb/s NIC. We use [libtpa](https://github.com/krish-iyer/libtpa/tree/frac_hdr_fmt) for performance measurements and have extended it to support FPGA measurements.

## Third-Party Code

Some code is borrowed from the [Corundum project](https://github.com/corundum/corundum).

