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

## License

fRAC is released under the [MIT License](LICENSE). This covers everything in
this repository except the third-party code listed below, which keeps its
original copyright notices and license. Where a file's header names a license,
that license applies to that file.

| Third-party code | Location | License |
| --- | --- | --- |
| Alex Forencich's [verilog-axis](https://github.com/alexforencich/verilog-axis) modules, taken from [Corundum](https://github.com/corundum/corundum) | `lib/axis/` (except `reset_gen.v`), `kernels/user_krnl/reassembly/rtl/axis_register.v`, `kernels/user_krnl/reassembly/rtl/axis_pipeline_register.v`; `vivado.mk` is adapted from his Vivado makefile | [MIT](https://spdx.org/licenses/MIT.html) |
| [Taxi](https://github.com/fpganinja/taxi) by FPGA Ninja, LLC | `lib/taxi/` | [CERN-OHL-S-2.0](https://spdx.org/licenses/CERN-OHL-S-2.0.html); `taxi_axis_if.sv` is MIT |
| [EasyNet](https://github.com/fpgasystems/Vitis_with_100Gbps_TCP-IP) by ETH Zurich Systems Group and Xilinx | `kernels/cmac_krnl/`, `kernels/network_krnl/`, `kernels/common/` | [BSD-3-Clause](https://spdx.org/licenses/BSD-3-Clause.html), per file header |
| [fpga-network-stack](https://github.com/fpgasystems/fpga-network-stack) by ETH Zurich Systems Group and Xilinx | `lib/fpga-network-stack/` | BSD-3-Clause, see its [LICENSE.md](lib/fpga-network-stack/LICENSE.md) |
| ETH Zurich Systems Group RTL; `nukv_fifogen.v` is from [Caribou](https://github.com/fpgasystems/caribou) | `kernels/user_krnl/reassembly/rtl/tcp_top_loopback.v`, `kernels/user_krnl/apps/cnn/src/rtl/nukv_fifogen.v` | [GPL-3.0-or-later](https://spdx.org/licenses/GPL-3.0-or-later.html) |
| AMD/Xilinx Vitis RTL-kernel and Vivado HLS generated files | `kernels/user_krnl/reassembly/rtl/user_krnl.v`, `kernels/network_krnl/rtl/network_krnl.sv`, `*_krnl_control_s_axi.*` and `package_*_krnl.tcl` under `kernels/` | AMD/Xilinx notice in each file |
| Microsoft's [Azure Functions invocation trace](https://github.com/Azure/AzurePublicDataset), cut to its busiest hour and preprocessed | `eval/azure_trace/processed_trace.csv` | [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) |

AMD/Xilinx IP cores, such as the 100G CMAC, the HBM controller, the
floating-point units and the AXI infrastructure, are not distributed here. The
Tcl scripts in `frac/ip/`, `kernels/*/ip/` and `kernels/user_krnl/apps/*/src/ip/`
only configure them; Vivado generates them under AMD's license terms, and the
CMAC also needs an UltraScale+ Integrated 100G Ethernet Subsystem license set
up in Vivado. The CNN core in `kernels/user_krnl/apps/cnn/src/ip/` is Vitis HLS
output generated from our hls4ml model, and its files keep the tool's
AMD/Xilinx banner.

The prebuilt bitstreams in `example/` are compiled from all of the above,
including the AMD/Xilinx IP, so each component's license applies to them.
`bin/spinhdl` is a prebuilt binary that includes Rust crates licensed under MIT
or Apache-2.0.

Taxi's CERN-OHL-S-2.0 is strongly reciprocal: anyone who distributes a design
or bitstream containing Taxi modules must make the complete source of that
design available under CERN-OHL-S-2.0. fRAC's own files can still be reused on
their own under MIT.

