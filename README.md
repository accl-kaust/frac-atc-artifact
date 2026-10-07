# fRAC: Remote Accelerator Calls on FPGAs

This repository is the artifact of the ACM ATC '26 paper **fRAC: Remote
Accelerator Calls on FPGAs**.

fRAC enables request-level, in-network invocation of FPGA accelerators. It
reassembles incoming request data, schedules requests to accelerators, and
supports swapping accelerators at runtime through partial reconfiguration.
By eliminating PCIe round trips and software overhead from the request path,
fRAC achieves low latency at 100G. fRAC is currently built on top of EasyNet, a TCP stack for FPGAs, but its design is transport agnostic.

- Documentation: <https://accl-kaust.github.io/frac-atc-artifact/>, built
  from `docs/` (see [Documentation](#documentation)).
- Archived artifact: TODO(authors): Zenodo DOI.

```bibtex
@inproceedings{frac-atc26,
  title     = {{fRAC}: Remote Accelerator Calls on {FPGAs}},
  author    = {TODO(authors)},
  booktitle = {ACM ATC '26},
  year      = {2026},
}
```

## Contents

| Path | What it is | Paper |
| --- | --- | --- |
| `kernels/user_krnl/reassembly/` | fRAC's request path: dispatcher, reassembly buffers, single-fragment buffer, scheduler, slot boundaries with credit flow control and the response path, with cocotb testbenches in `tb/` | §3, §4, Fig. 10 |
| `kernels/user_krnl/reconfctrl/` | Reconfiguration controller: bitstream upload into HBM, streaming into ICAP, slot decoupling | §4 (partial reconfiguration) |
| `kernels/user_krnl/apps/` | Accelerators: `top_k` (A1, Top-K), `log` (A2, Logit), `norm` (A3, Min-Max Normalization) and `cnn` (A4). `or_slot` and `pattern_slot` are test units. | §4 (accelerators), Tables 1 and 6 |
| `kernels/cmac_krnl/`, `kernels/network_krnl/`, `kernels/common/`, `lib/fpga-network-stack/` | 100G Ethernet (CMAC) and the TCP/IP stack, from EasyNet and fpga-network-stack | §4 (network stack), Table 3 |
| `lib/axis/`, `lib/taxi/` | AXI-Stream building blocks (verilog-axis, Taxi) | |
| `frac/` | Top level (`rtl/`), AMD IP configuration (`ip/`), constraints and floorplan (`xdc/`) | §4 |
| `spinhdl.yaml`, `spin.yaml`, `static.yaml`, `bin/spinhdl` | The partial-reconfiguration build: the four cells and the accelerators each can hold, the accelerator catalogue, the static design, and the tool that builds them | §4 |
| `Makefile`, `hls.mk`, `vivado.mk` | `make ip` builds the TCP/IP stack's HLS cores | |
| `example/` | Prebuilt bitstreams: the full image, partial bitstreams for every cell and accelerator, and the baseline without fRAC ([example/README.md](example/README.md)) | §5 |
| `eval/` | One directory per experiment, with its configuration and the paper's figure script; `run.py` measures and `plot.py` plots | §5, Figs. 13–18 |
| `scripts/` | Programming the FPGA (`programfpga.sh`, `flashfpga.sh`), loading a slot (`reconfslots.go`), probing slots (`testfuncs.go`), checking accelerator results on the FPGA (`checkfuncs.sh`, `checkfuncs.go`) | |
| `docs/` | Documentation | |

## Claims and Experiments

| Paper | Claim | Reproduce with | Time |
| --- | --- | --- | --- |
| Fig. 13 | fRAC adds little latency over echoing in the TCP stack, up to line rate | `latency_throughput` | 32 min |
| Fig. 14 | Requests to different accelerators are isolated: each one's latency is the same alone and in a mix | `mixed_workload` | 10 min |
| Fig. 15 | With reassembly, latency grows sub-linearly with the number of fragments | `reassembly` | 9 min |
| Figs. 16, 17 | fRAC's latency stays low and nearly flat as clients grow, with 1, 2 or 4 Top-K instances, and its tail is short | `scalability` | 22 min |
| Fig. 18 | Latency stays stable while replaying the busiest hour of the Azure Functions trace | `azure_trace` | 62 min |
| Correctness | Top-K, Logit and Norm compute correct results in every slot after partial reconfiguration | `scripts/checkfuncs.sh` | |

Each experiment is measured with `python3 eval/run.py <experiment>` and drawn
with `python3 eval/plot.py <experiment>`, which writes the figure as a PDF next
to the run's logs. [docs/reproducing-results.rst](docs/reproducing-results.rst)
gives each figure's testbed, what it measures and the result to expect. The
times are `eval/run.py`'s own estimates; the runs need no attention while they
last.

## Tested Environment

**Paper measurements (§5).** Clients ran on an AMD EPYC 7763 (64 cores) with
512 GB of DDR4, an NVIDIA ConnectX-6 NIC and Ubuntu 20.04, one client per
hardware thread on the NIC's NUMA node. fRAC ran on an AMD Alveo U280. Both
were connected through an EdgeCore DCS810 switch at 100 Gb/s, with an MTU of
9000.

**Evaluation testbeds.**

- kw61160, for Fig. 13: 64 hardware threads, 500 GB of RAM, Ubuntu 24.04,
  20000 × 2 MB hugepages. A ConnectX-6 Dx is cabled directly to the U280's
  QSFP0, and the U280 is programmed over JTAG.
- acclnode14, for Figs. 14–18: AMD EPYC 9355, Ubuntu 24.04. The host and the
  U280 are connected through a 100 Gb/s switch. TODO(authors): RAM, NIC and
  switch model.

| Software | Version |
| --- | --- |
| Vivado and Vitis HLS | 2022.2 |
| MLNX_OFED | 24.07-0.6.1.0 |
| libtpa, our fork with the fperf client | [accl-kaust/libtpa](https://github.com/accl-kaust/libtpa), branch `frac_hdr_fmt`, commit `2f81dd4` |
| DPDK, built by libtpa | v22.11 |
| [spinHDL](https://github.com/krish-iyer/spinHDL), as `bin/spinhdl` | commit `943f5bc`; the binary needs glibc 2.34 or newer |
| Go | 1.22 |
| Python | 3.12, with [eval/requirements.txt](eval/requirements.txt) |
| Simulation | cocotb 1.9.2 with [kernels/user_krnl/requirements.txt](kernels/user_krnl/requirements.txt), Verilator 5.034 |

Running the experiments needs no Vivado license: the bitstreams in `example/`
are prebuilt, and Vivado's hardware manager programs them. Building bitstreams
needs Vivado and Vitis HLS licensed for the U280 and for the UltraScale+
Integrated 100G Ethernet Subsystem (CMAC).

## Getting Started

This takes about 30 minutes, most of it waiting for the short run in step 4.

1. Log in to the testbed with the `ssh` command in
   [docs/quick-start.rst](docs/quick-start.rst#testbed), or set up your own
   host as described there.
2. Get the artifact and its Python packages. Skip this step on our testbeds:
   the clone is already in `~/frac-atc-artifact` and the packages are
   installed.

   ```sh
   git clone --branch artifact-eval https://github.com/accl-kaust/frac-atc-artifact.git ~/frac-atc-artifact
   cd ~/frac-atc-artifact
   python3 -m venv ~/frac-venv && . ~/frac-venv/bin/activate
   python3 -m pip install -r eval/requirements.txt
   ```

3. Program the FPGA and check that its slots answer:

   ```sh
   cd ~/frac-atc-artifact
   ./scripts/programfpga.sh example/frac/jtag/frac.bit
   ping -c 3 172.24.1.52
   go run ./scripts/testfuncs.go -slots 0,1 -counter
   ```

   `testfuncs` reports both slots as "unrecognised" after about 300 ms. They
   hold Top-K, whose answer it does not recognise. The quick start explains the
   output and how to load another accelerator into a slot.

4. On kw61160, do the steps in
   [Before You Start](docs/reproducing-results.rst#before-you-start). Then run
   the short latency-throughput check, 1 and 22 clients in about 8 minutes,
   and plot it:

   ```sh
   python3 eval/run.py latency_throughput -c smoke.yaml
   python3 eval/plot.py latency_throughput -c smoke.yaml
   ```

   The figure is `eval/latency_throughput/results/latest-smoke/latency_throughput_fig_13.pdf`.

## Reproducing the Paper's Results

For each experiment in [Claims and Experiments](#claims-and-experiments), on
the testbed that
[docs/reproducing-results.rst](docs/reproducing-results.rst) names for it:

```sh
python3 eval/run.py <experiment> --dry-run   # the commands it would run, and its time
python3 eval/run.py <experiment>             # measure
python3 eval/plot.py <experiment>            # draw the figure into the run's directory
```

Each run goes to a new directory under `eval/<experiment>/results/`, with
`latest` pointing at it. `manifest.yaml` there records the configuration, the
testbed and the sha256 of every bitstream loaded. An interrupted run continues
with `--resume`. To plot elsewhere, copy the run's directory and pass it to
`eval/plot.py --run`.

## Expected Resource Use

| Experiment | Time | Results on disk |
| --- | --- | --- |
| `latency_throughput` | 32 min (`-c smoke.yaml`: 8 min) | 1 MB |
| `mixed_workload` | 10 min | < 1 MB |
| `reassembly` | 9 min | < 1 MB |
| `scalability` | 22 min | 5 GB, every request's latency |
| `azure_trace` | 62 min | 8 MB |

- **CPU:** fperf pins one client thread per core, up to 28.
- **Memory:** each fperf process takes 8 GB of 2 MB hugepages, and
  `mixed_workload` and `scalability` run four at once. Our testbeds reserve
  20000 pages (40 GB).
- **Temporary space:** fperf records every request's latency in `/tmp` during
  a run, up to about 500 MB for the runs with 28 clients.
- **Building the bitstreams:** 3.5 hours on 48 cores with 192 GB of memory
  allotted. The flat baseline image takes 66 minutes on 16 cores.

## Building from Source

```sh
make ip CMAKE=/usr/bin/cmake
./bin/spinhdl --parallel 8 weave spinhdl.yaml --units spin.yaml --static static.yaml
```

The bitstreams land in `build/frac/bitstreams/` and each cell's abstract shell
in `build/frac/abstract_shell/`.
[docs/build-and-deployment.rst](docs/build-and-deployment.rst) describes the
flow, and [docs/adding-an-accelerator.rst](docs/adding-an-accelerator.rst)
shows how to build a new accelerator against an abstract shell without
rebuilding fRAC. The baseline image `example/bypass/frac.bit` is a flat
(non-PR) build of branch `frac-bypass`, commit `243eb1b`.

Without Vivado, the design can still be exercised in simulation with cocotb
and Verilator. In the accelerator testbenches, `fp_stubs.v` stands in for
the Xilinx floating-point cores:

```sh
python3 -m pip install -r kernels/user_krnl/requirements.txt
make -C kernels/user_krnl/reassembly/tb      # request path and controller, 41 tests
make -C kernels/user_krnl/reconfctrl/tb      # reconfiguration controller, 10 tests
```

[docs/verification-and-status.rst](docs/verification-and-status.rst) lists the
suites, what they cover and the known limitations.

## Warnings

- `scripts/programfpga.sh` and `scripts/flashfpga.sh` reconfigure the FPGA. If
  the U280 is up on PCIe, for example running the XRT shell, its link goes
  down, and some servers answer that with a reset. Take the card off the bus
  and disable its link first; `scripts/flashfpga.sh --help` shows the commands.
- `scripts/flashfpga.sh` overwrites the image the U280 boots from its flash,
  the XRT shell as shipped. The card's golden image stays as the fallback.
- `eval/run.py` reprograms the FPGA, replacing what it runs. It runs fperf as
  root through `sudo` and keeps sudo's credentials fresh for the length of a
  sweep. `eval/scalability/four_topk.sh`, when interrupted, stops every process
  running its fperf binary with `sudo pkill`.
- The host setup in [docs/quick-start.rst](docs/quick-start.rst) installs
  MLNX_OFED, which replaces the distribution's RDMA and NIC drivers. It also
  reserves hugepages and changes the kernel command line and the netplan
  configuration.
- fRAC's control path has no authentication. Any host that reaches the FPGA's
  TCP port can write its HBM and reconfigure its slots, so keep it on a
  private network.

## Known Behavior and Deviations

- A partial bitstream works only on the full image of its own build. One from
  another build can report a successful load and leave the slot unchanged.
- fperf's first second is not meaningful. The figure scripts drop the first
  seconds of the fixed-length runs.

## Third-Party Code and Changes

The [License](#license) table lists the third-party code in this repository.
What we changed:

- The EasyNet kernels in `kernels/` were adapted to fRAC. Parts of the
  networking infrastructure below TCP were replaced with verilog-axis modules
  from `lib/axis/`. This repository's history records the changes.
  `lib/fpga-network-stack/` was imported in one commit, `63d7da7`, and has not
  changed since.
- [libtpa](https://github.com/accl-kaust/libtpa) is our fork of ByteDance's
  libtpa. Our changes are on branch `frac_hdr_fmt`: the fperf client, adapted
  from libtpa's tperf, with the fRAC request header and trace replay.
- The figure scripts in `eval/` are the paper's, copied from
  [frac_evaluation_script](https://github.com/accl-kaust/frac_evaluation_script)
  at the commit each `experiment.yaml` names. `mixed_workload_fig_14.py` is
  the one exception: it drops the first 2 seconds of the isolated runs instead
  of 10.
- `eval/azure_trace/processed_trace.csv` is derived from Microsoft's Azure
  Functions Invocation Trace 2021. `eval/azure_trace/experiment.yaml`
  describes how.

## Documentation

The documentation is published at
<https://accl-kaust.github.io/frac-atc-artifact/>. To build it from `docs/`:

```sh
python3 -m pip install sphinx sphinx-rtd-theme
make -C docs html      # docs/_build/html/index.html
```

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
`bin/spinhdl` is a prebuilt binary of [spinHDL](https://github.com/krish-iyer/spinHDL),
which is licensed under GPL-3.0-only, and it includes Rust crates licensed
under MIT or Apache-2.0.

Taxi's CERN-OHL-S-2.0 is strongly reciprocal: anyone who distributes a design
or bitstream containing Taxi modules must make the complete source of that
design available under CERN-OHL-S-2.0. fRAC's own files can still be reused on
their own under MIT.
