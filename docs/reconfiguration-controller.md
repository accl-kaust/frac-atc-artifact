# Network-Driven Reconfiguration Controller

## Motivation

fRAC is the motivating case study for this controller. It exposes FPGA
accelerators to remote clients through a 100 Gb/s network datapath. The set of
accelerators needed by a deployment can change over time, while the FPGA has
limited area for resident accelerators. Partial reconfiguration (PR) allows an
accelerator slot to be replaced without rebuilding or stopping the complete
network design.

The contribution is not PR by itself. Instead of relying on a host CPU to stage
and initiate reconfiguration, fRAC carries the control operation over the
network. A remote client uploads a partial bitstream into FPGA-attached HBM and
then sends a command that causes a hardware controller to isolate the selected
slot, fetch the bitstream, stream it through ICAP, and report completion or
failure over the same TCP connection.

This makes reconfiguration part of the network service control plane:

```text
remote client
    |
    | TCP requests on port 2888
    v
100 GbE + TCP stack
    |
    +--> normal workload --> accelerator slots --> response
    |
    +--> workload 0x00ab --> reconfiguration controller
                              |              |
                              v              v
                           HBM AXI         ICAPE3
                              |              |
                              +-- bitstream -+
```

## Scope

The current standalone integration targets a Xilinx Alveo U280
(`xcu280-fsvh2892-2L-e`) and uses a 200 MHz controller, HBM, and ICAP clock. The
integrated controller has three reconfigurable slots. The RTL module defaults to
two slots, but `pkt_logic.v` overrides `SLOT_COUNT` to three.

| Slot ID | Static cell | Normal workload route |
| ---: | --- | --- |
| 0 | `c00_bbx_inst` | `0x0000` and the current default route |
| 1 | `c01_bbx_inst` | `0x0001` |
| 2 | `c02_bbx_inst` | `0x0002` |

Workload `0x00ab` is reserved for reconfiguration-controller requests and does
not pass through the normal accelerator scheduler.

## Module Architecture

The runtime path is composed of four main blocks:

| Module | Responsibility |
| --- | --- |
| `reconfctrl` | Parses commands, performs HBM reads and writes, controls slot isolation, streams ICAP data, and generates status responses. |
| `icap_ctrl` | Connects the controller's 32-bit stream to the Xilinx `ICAPE3` primitive. |
| `axis_dfx_decoupler` | Blocks traffic and clamps slot-boundary outputs while a slot is isolated. |
| `cell_bbx` | Empty static shell replaced by an out-of-context reconfigurable-module checkpoint during a DFX build. |

The controller interfaces are:

```text
                       +----------------------+
512-bit command AXIS ->|                      |-> 512-bit response AXIS
                       |      reconfctrl      |
ICAP status ---------->|                      |-> slot_decouple[2:0]
                       |                      |-> 32-bit ICAP AXIS
                       +----------+-----------+
                                  |
                                  v
                           256-bit HBM AXI
                             HBM port 01
```

The integrated widths are fixed in several internal data slices even though
they are module parameters:

| Interface | Integrated width |
| --- | ---: |
| Command and response AXI Stream | 512 bits / 64 bytes |
| HBM AXI data | 256 bits / 32 bytes |
| HBM address | 33 bits |
| ICAP stream | 32 bits / 4 bytes |
| Slot count | 3 |

## Runtime Reconfiguration Sequence

The implemented sequence for `RECONF_ICAP` is:

1. The dispatcher recognizes workload `0x00ab` and forwards the 64-byte command
   line to `reconfctrl`.
2. The controller validates the opcode, HBM address, size, and slot ID.
3. On command acceptance, the controller records the active slot, clears the
   previous `PRDONE`/`PRERROR` observations, resets the cycle counter, and
   immediately asserts `slot_decouple[slot_id]`.
4. The controller issues HBM reads in bursts of up to 16 256-bit beats, or 512
   bytes per burst.
5. Returned HBM beats enter a 16-entry FIFO. Each beat is serialized low-word
   first into eight 32-bit ICAP words.
6. The last requested 32-bit word is marked with `tlast`. The controller then
   stops streaming and waits for `PRDONE` or `PRERROR`.
7. `PRERROR` has priority if completion and error are observed together.
8. The controller stores the result and elapsed cycle count, clears the selected
   decouple bit, and sends one 64-byte status response.

At 200 MHz, each reported cycle corresponds nominally to 5 ns. The count covers
HBM access, ICAP streaming, and the wait for completion.

```text
IDLE
  |
  | valid RECONF_ICAP command
  v
assert selected decoupler
  |
  v
RECONF_ADDR ---- issue HBM burst
  |
  v
RECONF_STREAM -- buffer 256-bit beats -- emit 32-bit ICAP words
  |
  | final ICAP word accepted
  v
RECONF_WAIT_DONE
  |                 |
  | PRDONE          | PRERROR
  v                 v
status 0          status 9
  |                 |
  +------ clear selected decoupler
                       |
                       v
                  SEND_STATUS -> IDLE
```

## Decoupling

Each slot has an input and output `axis_dfx_decoupler`. When its `decouple`
input is high, the module:

- Drives upstream `tready` low, preventing new traffic from entering the
  boundary.
- Drives downstream `tvalid` low.
- Clamps downstream data, byte qualifiers, metadata, and `tlast` to zero.

When `decouple` is low, the decoupler is a combinational pass-through.

### Implemented Versus Intended Isolation

The intended safety contract is to stop new dispatches, drain in-flight work,
isolate and reset the target partition, perform PR, and reconnect the slot only
after a successful configuration.

The current implementation provides AXI-Stream isolation but does not implement
the complete contract:

| Concern | Intended contract | Current RTL |
| --- | --- | --- |
| New traffic | Stop dispatch to selected slot | Decoupler backpressure blocks the boundary. |
| In-flight traffic | Wait for slot and boundary pipelines to become idle | No slot-idle or drain handshake is present; decoupling is immediate. |
| Slot reset | Hold the RM in a defined reset state | No per-slot reset is driven by the controller. `RESET_AFTER_RECONFIG` depends on the DFX constraint flow. |
| Successful PR | Reconnect after `PRDONE` | Implemented. |
| Failed PR | Keep the slot isolated until recovery | Current `PRERROR` handling clears the decouple bit before returning error 9. |
| Completion timeout | Fail safely after a bounded interval | No hardware timeout is implemented. |

The distinction must be preserved in evaluations and paper claims: boundary
decoupling is implemented, but draining in-flight work is not established by the
current RTL.

## HBM Operations

The controller's 256-bit AXI master is connected directly to HBM port 01. AXI
addresses are byte addresses; all operations use 32-byte beats and incrementing
bursts.

### Write HBM

`WRITE_HBM` stages request payload bytes in memory:

- A 512-bit network line is split into low and high 256-bit halves.
- Each half is written as an independent one-beat AXI transaction.
- Byte strobes limit the final partial half to the command's requested size.
- The low half is written before the high half.
- Additional 64-byte payload lines are accepted until the requested byte count
  has been written.

The command size, not AXI-Stream `tkeep` or `tlast`, determines completion.
Insufficient payload therefore leaves the controller waiting for more data.

### Read HBM

`READ_HBM` is a diagnostic operation:

- It accepts sizes from 1 through 64 bytes.
- It performs one or two single-beat HBM reads.
- Unrequested bytes are zero-filled.
- Success returns raw data in one 64-byte response, not a status byte followed
  by data.

### Reconfiguration Read Path

`RECONF_ICAP` interprets the requested size as a count of 32-bit words. The size
must therefore be nonzero and divisible by four. HBM is read in bursts of up to
16 beats. A partial final HBM beat may be fetched, but only the requested number
of 32-bit words is sent to ICAP.

The controller does not currently check:

- `address + size` overflow or the configured 4 GiB HBM capacity.
- Whether an AXI burst crosses a 4 KiB boundary.
- A maximum partial-bitstream size.
- Whether the selected memory range overlaps another HBM user.

Deployments must reserve a safe HBM range and enforce these constraints in the
control software until they are enforced in hardware.

## ICAP Interface

`icap_ctrl.v` instantiates `ICAPE3` in write mode:

- `CSIB` is the inverse of stream `tvalid`.
- `RDWRB` is tied low.
- The 32-bit stream word is connected directly to `ICAPE3.I`.
- Stream `tready` is always high.
- `AVAIL` is reported but does not gate transmission.
- Hardware `tkeep` and `tlast` do not connect to `ICAPE3`; `tlast` is used by
  the simulation model to generate `PRDONE`.

There is no byte swap or bit reversal between HBM and `ICAPE3.I`. The uploaded
file must already be generated in the ICAP-compatible format described in
[Build and deployment](build-and-deployment.md#icap-partial-bitstream-format).

## Status Management

The controller tracks:

- Whether reconfiguration is active.
- The active and most recently completed slot IDs.
- The current and last reconfiguration cycle counts.
- The most recent controller error.
- Whether `PRDONE` or `PRERROR` was observed during the current operation.
- The current ICAP `AVAIL` input.

`PRDONE` and `PRERROR` are latched while reconfiguration is active so a short
pulse cannot be missed while the FSM moves into its completion state. The full
query-response layout is specified in [Network protocol](protocol.md#query-status-response).

Only the `IDLE` state accepts a new command. A healthy active reconfiguration
therefore cannot be queried through the same controller path; the original
`RECONF_ICAP` request remains pending until completion. The active fields are
primarily internal observability signals in the current architecture.

## Reset Behavior

Synchronous active-high reset returns the controller to `IDLE`, clears AXI and
AXI-Stream valid signals, clears all decouple bits, empties the reconfiguration
FIFO, and resets status and cycle counters. The hardware `ICAPE3` instance does
not have a controller-driven reset input.

## Trust Boundary

The current protocol permits a network client to write HBM and initiate ICAP
reconfiguration without authentication, authorization, integrity checking, or
bitstream compatibility checking. It must only be exposed on a trusted and
isolated network. A production control plane should authenticate commands,
authorize slots and HBM ranges, verify an artifact manifest and digest, and
provide a bounded recovery path for failed reconfiguration.
