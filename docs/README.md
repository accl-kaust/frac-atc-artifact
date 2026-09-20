# fRAC Standalone Documentation

This directory documents the network-driven partial-reconfiguration path in the
standalone fRAC implementation.

## Documents

- [Reconfiguration controller](reconfiguration-controller.md): motivation,
  architecture, controller sequence, HBM and ICAP datapaths, decoupling, and
  status management.
- [Network protocol](protocol.md): request framing, command and response
  formats, opcodes, validation rules, and error codes.
- [Build and deployment](build-and-deployment.md): static and reconfigurable
  build artifacts, ICAP bitstream format, and board-client workflow.
- [Verification and implementation status](verification-and-status.md): test
  commands, current coverage, known limitations, and release criteria.

## Source Map

The principal implementation files are:

| Area | Path |
| --- | --- |
| Reconfiguration controller | `kernels/user_krnl/reconfctrl/rtl/reconfctrl.v` |
| ICAP wrapper | `kernels/user_krnl/reconfctrl/rtl/icap_ctrl.v` |
| AXI-Stream decoupler | `kernels/user_krnl/reconfctrl/rtl/axis_dfx_decoupler.sv` |
| Reconfigurable-cell shell | `kernels/user_krnl/reconfctrl/rtl/cell_bbx.sv` |
| Network and slot integration | `kernels/user_krnl/reassembly/rtl/pkt_logic.v` |
| Request dispatcher | `kernels/user_krnl/reassembly/rtl/dispatcher.v` |
| HBM integration | `frac/rtl/frac_hbm.v` |
| Board-side PR client | `sw/pr/main.go` |
| Controller tests | `kernels/user_krnl/reconfctrl/tb/` |

## Documentation Contract

These documents distinguish among:

- **Implemented behavior**: behavior directly represented by the checked-in RTL
  and software.
- **Intended behavior**: the safety and deployment contract the controller is
  expected to provide.
- **Build gap**: a required DFX step for which a complete, reproducible command
  is not currently checked in.

This distinction is important because the runtime controller is implemented and
tested, while the source-to-partial-bitstream flow is not yet connected into one
reproducible build target.
