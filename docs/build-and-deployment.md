# Build and Deployment

## Build Status

The repository currently contains two related but separate flows:

1. The Make/Vivado flow builds HLS dependencies and a conventional full FPGA
   image.
2. The DFX manifests, partition constraints, and experimental Tcl scripts
   describe parts of a partial-reconfiguration flow.

They are not connected into one reproducible source-to-partial-bitstream target.
In particular, the normal Make flow does not load reconfigurable-module
checkpoints or include `frac/xdc/pr_frac.xdc`.

The standalone README declares Xilinx 2021.2 as the tested tool version, while
preserved implementation reports and bitstream artifacts in the wider workspace
were generated with Vivado 2022.2. A release must select and record one validated
tool version.

## Conventional Build

Run these commands from the standalone repository root.

```sh
make ip
make synth
make frac
```

The nominal combined command is:

```sh
make all
```

Expected conventional-build outputs include:

```text
frac_top.xpr
frac_top.runs/synth_1/frac_top.dcp
frac_top.runs/impl_1/frac_top_routed.dcp
frac_top.runs/impl_1/frac_top.bit
frac_top.runs/impl_1/frac_top.bin
frac_top.runs/impl_1/frac_top.ltx
frac_top.xsa
```

This is not currently a documented functional DFX build. The source list uses
empty `cell_bbx` partition shells, and the Make constraint list contains
`floorplan.xdc` rather than `pr_frac.xdc`.

### Known Make-Flow Issues

- `hls.mk` prefixes `CMAKE_ARGS` with an extra hyphen, causing the first option
  to expand as `--DFDEV_NAME=...` in a clean build.
- `make frac` has no explicit dependency on `make ip`; parallel `make all`
  may race IP generation and Vivado project creation.
- The checked-in defaults set `TCP_STACK_EN=0`, despite the controller's TCP
  deployment path.
- The source list includes both `network_types.svh` and its `.in` template.

These items should be resolved and the build rerun from a clean checkout before
the conventional commands are treated as release instructions.

## DFX Inputs

The checked-in DFX-related inputs are:

| File | Intended role |
| --- | --- |
| `static.yaml` | Static shell source and IP manifest |
| `spin.yaml` | Reconfigurable-module units (`pattern_slot` and `or_slot`) |
| `spinhdl.yaml` | Three cells, slot IDs, regions, and permitted modules |
| `frac/xdc/pr_frac.xdc` | Pblocks and `HD.RECONFIGURABLE` properties |
| `kernels/user_krnl/reconfctrl/rtl/cell_bbx.sv` | Static partition boundary shell |
| `kernels/user_krnl/apps/*/unit.yaml` | Per-module synthesis manifests |

No checked-in executable or Make target consumes all three YAML files. The
orchestrator, schema version, command line, and output contract are therefore a
build gap.

The C02 region in `spinhdl.yaml` does not match the C02 region in
`frac/xdc/pr_frac.xdc`. An authoritative floorplan must be chosen before
partial images are produced.

## Required DFX Artifact Stages

A reproducible DFX build must implement these stages:

1. Build all required network-stack and Xilinx IP.
2. Synthesize the static design while preserving C00, C01, and C02 as
   reconfigurable partitions.
3. Synthesize every reconfigurable module out of context with interface
   parameters matching `cell_bbx`.
4. Apply one authoritative PR pblock constraint set.
5. Insert an explicit initial module checkpoint into every cell.
6. Optimize, place, and route the initial configuration.
7. Lock or preserve the routed static design.
8. Build every supported cell/module configuration against that same static
   implementation.
9. Run DFX compatibility verification, DRC, and timing checks.
10. Generate a full image for initial programming and one partial image per
    supported cell/module pair.
11. Convert each partial image into the ICAP-compatible binary format.

The wider workspace contains experimental `bit_est/run_route.tcl` and
`bit_est/run_bitgen.tcl` scripts that illustrate checkpoint insertion and
artifact generation. They are not standalone build commands: they require
missing `static_synth.dcp`, RM checkpoints, `cell_paths.tcl`, and routed alternate
configurations, and they do not generate every slot/module combination.

## ICAP Partial-Bitstream Format

The runtime client and RTL copy file bytes unchanged into HBM and then onto the
32-bit ICAP input. The deployment input must therefore be an ICAP-prepared
partial binary, not a raw `.bit` file and not a PCAP-formatted binary.

The experimental bit-generation flow uses this conversion:

```tcl
write_bitstream -force -cell ${cell_path} module_partial.bit
write_cfgmem -force -format BIN -interface SMAPx32 \
    -loadbit "up 0x0 module_partial.bit" module_icap_part.bin
```

The ICAP form intentionally does not use `-disablebitswap`. The experimental
PCAP form adds `-disablebitswap` and is a different artifact.

The controller streams the file in this order:

```text
HBM beat bits  31:0   -> first ICAP word
HBM beat bits  63:32  -> second ICAP word
...
HBM beat bits 255:224 -> eighth ICAP word
```

There is no conversion in the Go client or RTL. Supplying the wrong artifact
format can cause `PRERROR` or leave the controller waiting indefinitely.

## Artifact Manifest

Each deployable partial image should be accompanied by a manifest containing:

| Field | Purpose |
| --- | --- |
| Static image ID and digest | Binds the partial image to its routed static design |
| Slot ID and hierarchical cell path | Prevents loading into an incompatible partition |
| Reconfigurable module name and source revision | Identifies accelerator behavior |
| Part and board | Records `xcu280-fsvh2892-2L-e` / U280 compatibility |
| Pblock/XDC revision | Binds the image to the partition floorplan |
| Vivado/Vitis versions | Makes implementation reproducible |
| Artifact format | Distinguishes JTAG `.bit`, ICAP `.bin`, and PCAP `.bin` |
| Byte length and SHA-256 digest | Detects truncation or corruption |
| DFX verification, DRC, and timing results | Records release qualification |

The current controller does not validate such a manifest. Validation must occur
in trusted deployment software.

## Initial Programming

The initial full image must contain the static network design and one compatible
module in each partition. The exact board-programming command and authoritative
initial slot composition are not currently checked in and remain `TBD`.

Do not assume the conventional `frac_top.bit` and a preserved partial binary
are compatible. Full and partial images must originate from the same routed
static implementation.

## Runtime Deployment

The current client is `sw/pr/main.go`. It uses only the Go standard library and
can be run from the standalone repository root:

```sh
go run ./sw/pr/main.go \
    -addr 172.24.1.52:2888 \
    -hbm-addr 0x4000 \
    -chunk-size 64 \
    -query-status \
    -post-probe \
    path/to/c00_module_icap_part.bin
```

The client performs this sequence:

1. Read the selected binary and pad it to a four-byte boundary.
2. Upload it to HBM with one or more `WRITE_HBM` commands.
3. Pad each network payload to a 64-byte boundary while preserving the actual
   chunk size in the command.
4. Send `RECONF_ICAP` for the uploaded address and padded file size.
5. Wait for the final 64-byte status response.
6. Optionally issue `QUERY_STATUS` and probe workload `0x0000`.

Current defaults and restrictions are:

| Setting | Value |
| --- | --- |
| TCP endpoint | `172.24.1.52:2888` |
| HBM staging address | `0x4000` |
| Upload chunk | 64 bytes; configurable in 64-byte increments through 256 |
| Socket timeout | 10 seconds |
| Selected slot | C00 / slot 0, hard-coded by the current CLI |

Although the command ABI supports slots 0 through 2, the client does not expose
a slot-selection flag. It also accepts any input filename and does not verify
that it is an ICAP image paired with the running static image.

`QUERY_STATUS` is currently used only as an acceptance check. The client does
not decode or print the status payload described in
[Network protocol](protocol.md#query-status-response).

## Recovery

If the host times out waiting for `RECONF_ICAP`, the hardware may still be
active and the selected slot may remain decoupled. There is no independent
status channel or abort command while the controller is busy. Recovery currently
requires diagnosing ICAP/HBM state through hardware debug or resetting and
reprogramming the complete FPGA image.

Because current `PRERROR` handling reconnects the slot, software must not assume
that an error leaves the failed partition safely isolated.
