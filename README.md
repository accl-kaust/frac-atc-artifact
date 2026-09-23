# fRAC

fRAC enables request-level, in-network invocation of FPGA accelerators. It
reassembles incoming request data, schedules requests to accelerators, and
supports swapping accelerators at runtime through partial reconfiguration.

## Directory

```sh
├── bin
│   └── spinhdl      # DFX build orchestrator, see Build Instructions
├── kernels
│   ├── cmac_krnl    # CMAC IP intialization
│   ├── common
│   ├── network_krnl # Binding Network stack
│   └── user_krnl    # Request reassembly, accelerator slots, PR control, apps
├── lib
│   ├── axis         # Some axis components
│   └── fpga-network-stack # TCP Stack
├── frac
│   ├── ip
│   ├── rtl          # Stitches the whole stack together
│   └── xdc
├── static.yaml      # spinhdl manifest: the static shell
├── spin.yaml        # spinhdl manifest: the reconfigurable-module units
├── spinhdl.yaml     # spinhdl manifest: cells, regions and slot IDs
├── hls.mk           # Builds the TCP stack IP into build/lib
├── vivado.mk        # Legacy Make/Vivado flow (full image, no PR)
├── Makefile
└── README.md
```



## Documentation

Start with the [fRAC overview](docs/index.rst) for the network architecture,
request processing, runtime accelerator replacement, and design philosophy.
The detailed guides cover the reconfiguration controller, network command ABI,
ICAP bitstream format, build and deployment flow, verification coverage, and
current implementation limitations.

## Build Instructions

Requires Vivado 2022.2 on `PATH` (plus Vitis HLS 2022.2 and CMake for step 1).
Run both commands from the repository root.

1. Build the HLS network-stack IP into `build/lib`:

```sh
make ip
```

1. Build fRAC with `spinhdl` (shipped in `bin/`). It reads `static.yaml`,
  `spin.yaml` and `spinhdl.yaml`, and produces the static shell, the
   reconfigurable modules, the full image and the partial bitstreams under
   `build/`:

```sh
./bin/spinhdl weave --parallel
```



## Libraries and Borrowed Code

fRAC uses [ETH's TCP stack](https://github.com/fpgasystems/Vitis_with_100Gbps_TCP-IP/tree/vitis_2020_1)
as a library as well as a few kernels. Some code is borrowed from
[Corundum](https://github.com/corundum/corundum) and
[taxi](https://github.com/fpganinja/taxi).