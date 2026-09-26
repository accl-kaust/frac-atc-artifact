Integrating Your Own Accelerator
================================

Six steps take an accelerator from an empty directory to serving requests on
the FPGA. ``kernels/user_krnl/apps/top_k/`` is the reference throughout: copy
it and edit.

.. This guide explains how to bring your own accelerator into fRAC: where it plugs
.. in, what interface it must present, how to write the hardware, and how a client
.. formats the requests that reach it.

Where an Accelerator Plugs In
-----------------------------

fRAC receives TCP payload from the network stack, reassembles it into
requests, and hands each request to one of three accelerator slots. The
response from the slot is sent back on the same TCP connection.

.. code:: text

   TCP stack ──> pkt_receiver ──> dispatcher ──> scheduler ──> per-slot FIFO ──┐
                                                                               │
                                                     ┌── slot boundary ────────┤
                                                     │   your accelerator      │
                                                     └── slot boundary ────────┤
                                                                               │
   TCP stack <── pkt_sender <── slot_tx_axis_switch <──────────────────────────┘

Your accelerator is the module inside the slot boundary. Everything outside it
(header parsing, request reassembly, slot selection, response return) already
exists and is shared by all accelerators. You do not touch the network stack,
the dispatcher, or the scheduler.

Existing accelerators to learn from
   .. list-table::
      :header-rows: 1
      :widths: 22 78

      * - Module
        - Summary
      * - ``pattern_slot``, ``or_slot``
        - Pass-through modules that return a constant pattern. The minimum
          legal module and a loopback test.
      * - ``top_k``
        - Native RTL. Skips the header, reads a parameter from it, returns one
          response line.
      * - ``log``
        - Streaming kernel built on Xilinx floating-point IP. One response line
          per input line.
      * - ``norm``
        - Two-pass kernel that buffers the whole request before answering.
      * - ``mm``
        - CNN inference around an hls4ml-generated IP, with its own packet
          parser and FIFOs; ``mm.v`` adapts it to the slot interface.

Step 1: Create the Module Directory
-----------------------------------

Create ``kernels/user_krnl/apps/<name>/`` with this layout. Copying
``apps/top_k/`` gives you all of it.

``src/rtl/``: Your RTL.

``src/ip/`` or ``src/xci/``: Vivado IP generation scripts or ``.xci`` files, only if the module uses IP.

``tb/``: cocotb testbench (Step 3).

``unit.yaml``: The module's build manifest (Step 4).

Step 2: Write the Top-Level Module
----------------------------------

Give the top module exactly this port list. It must match the slot boundary in
``kernels/user_krnl/reconfctrl/rtl/cell_bbx.sv``; the static design
instantiates it with the parameter values in the Width column.

.. list-table::
   :header-rows: 1
   :widths: 22 14 64

   * - Port
     - Width
     - Notes
   * - ``clk``, ``rst``
     - 1
     - Static-side clock and synchronous, active-high reset.
   * - ``s_axis_tdata``
     - ``AXIS_DATA_W`` = 512
     - One 64-byte line of the request per beat.
   * - ``s_axis_tkeep``, ``s_axis_tstrb``
     - 64
     - Always all-ones on input. Every request beat is a full 64-byte line.
   * - ``s_axis_tvalid``, ``s_axis_tready``
     - 1
     - Standard AXI-Stream handshake. You may hold ``tready`` low while busy,
       a FIFO ahead of the slot absorbs the back-pressure.
   * - ``s_axis_tlast``
     - 1
     - Set on the final beat of a request.
   * - ``s_axis_tdest``, ``s_axis_tid``, ``s_axis_tuser``
     - ``TDEST_W`` = 1, ``TID_W`` = 1, ``USER_W`` = 1
     - Driven to zero. Carry no information. Echo them or drive zero.
   * - ``m_axis_*``
     - as above
     - The response stream. Same signal set, same widths.

Start from this skeleton (the structure of ``top_k.v``):

.. code:: verilog

   (* DONT_TOUCH = "yes" *)
   module my_acc #(
       parameter integer AXIS_DATA_W = 512,
       parameter integer KEEP_W      = AXIS_DATA_W/8,
       parameter integer TDEST_W     = 1,
       parameter integer TID_W       = 1,
       parameter integer USER_W      = 1
   ) (
       input  wire                   clk,
       input  wire                   rst,
       // request in
       input  wire [AXIS_DATA_W-1:0] s_axis_tdata,
       input  wire [KEEP_W-1:0]      s_axis_tkeep,
       input  wire [KEEP_W-1:0]      s_axis_tstrb,
       input  wire                   s_axis_tvalid,
       output wire                   s_axis_tready,
       input  wire                   s_axis_tlast,
       input  wire [TDEST_W-1:0]     s_axis_tdest,
       input  wire [TID_W-1:0]       s_axis_tid,
       input  wire [USER_W-1:0]      s_axis_tuser,
       // response out
       output wire [AXIS_DATA_W-1:0] m_axis_tdata,
       output wire [KEEP_W-1:0]      m_axis_tkeep,
       output wire [KEEP_W-1:0]      m_axis_tstrb,
       output wire                   m_axis_tvalid,
       input  wire                   m_axis_tready,
       output wire                   m_axis_tlast,
       output wire [TDEST_W-1:0]     m_axis_tdest,
       output wire [TID_W-1:0]       m_axis_tid,
       output wire [USER_W-1:0]      m_axis_tuser
   );
       wire is_header = (s_axis_tdata[447:0] == {448{1'b1}});
       wire rx_fire   = s_axis_tvalid && s_axis_tready;

       reg frame_active;   // a request is in progress
       reg resp_valid;     // response line is ready
       reg [AXIS_DATA_W-1:0] resp_data;

       assign s_axis_tready = !resp_valid;   // one request at a time

       always @(posedge clk) begin
           if (rst) begin
               frame_active <= 1'b0;
               resp_valid   <= 1'b0;
           end else begin
               if (rx_fire) begin
                   frame_active <= !s_axis_tlast;
                   if (!frame_active && is_header) begin
                       // read per-request parameters from tdata[495:482]
                   end else begin
                       // feed s_axis_tdata to the kernel
                   end
                   if (s_axis_tlast) resp_valid <= 1'b1;
               end
               if (resp_valid && m_axis_tready) resp_valid <= 1'b0;
           end
       end

       assign m_axis_tdata  = resp_data;
       assign m_axis_tvalid = resp_valid;
       assign m_axis_tlast  = 1'b1;
       assign m_axis_tkeep  = {KEEP_W{1'b1}};
       assign m_axis_tstrb  = {KEEP_W{1'b1}};
       assign m_axis_tdest  = {TDEST_W{1'b0}};
       assign m_axis_tid    = {TID_W{1'b0}};
       assign m_axis_tuser  = {USER_W{1'b0}};
   endmodule

Then check the module against this list:

-  Skip the header beat. It is the first beat of every request and has bytes
   0-55 all ``0xff``. Per-request parameters are in ``tdata[495:482]``.
-  Return exactly one response per request, ending in ``m_axis_tlast``.
-  Make every response beat a full 64-byte line, pad short results.
-  Make the response the same number of bytes as the request's TCP packet,
   header included.
-  Hold ``s_axis_tready`` low while busy. Never drop beats.
-  Keep a single request under 512 beats (32 KiB). If you buffer the whole
   request, make the buffer depth a parameter.
-  Keep ``(* DONT_TOUCH = "yes" *)`` on the top module. Use no I/O, clocking
   primitives, or hard blocks.
-  Initialise all state in the ``rst`` branch.

.. Points that are easy to get wrong:

.. -  If the kernel needs several cycles per beat, hold ``s_axis_tready`` low
..    rather than dropping beats. The slot FIFO provides the elasticity.
.. -  If the kernel needs the whole request before producing output (as ``norm``
..    does), the buffer depth defines the largest request you accept. Make it a
..    parameter and document it.

.. Rules the static side imposes:

.. Requests arrive whole and in order
..    The scheduler does not forward a request until every TCP packet of it has
..    arrived, so your module sees the beats of one request back to back, ending
..    in ``tlast``. Beats of two different requests are never interleaved on one
..    slot.

.. The header beat is delivered to you
..    The first beat of every request is the 64-byte fRAC request header (format
..    below). The dispatcher reads the workload ID and size from it but does not
..    remove it. Your module must recognise and skip it, or treat it as data on
..    purpose. ``top_k.v`` recognises it by testing whether bytes 0-55 are all
..    ``0xff``:

..    .. code:: verilog

..       wire is_header = (s_axis_tdata[447:0] == {448{1'b1}});

.. Responses are 64-byte lines
..    Your ``m_axis_tkeep`` is not connected on the static side. Every response
..    beat is transmitted as a full 64 bytes, so pad short results to a line.

.. Exactly one response per request
..    The static side captures one metadata entry per request when its first beat
..    enters the slot FIFO, and releases it when your response's ``tlast`` passes
..    the output switch. A request with no response leaks a metadata entry and
..    eventually stalls the slot. Two responses to one request corrupt the pairing
..    for all later requests on that slot.

.. Response length is taken from the request
..    ``pkt_sender.v`` passes the request's TCP metadata (payload length and
..    session ID) to the TCP stack unchanged as the response metadata. The stack
..    therefore expects the response to be as long as the request's TCP packet.
..    For a single-packet request the safe design is a response with the same
..    number of bytes as that packet, header included. If your response size
..    must differ, check ``pkt_sender.v`` and the TCP transmit path before
..    relying on it; this is a known limitation of the current static design,
..    not a property of the protocol.

.. Request size is bounded by the slot FIFO
..    ``pkt_logic.v`` places a request FIFO of ``SLOT_RX_FIFO_DEPTH`` beats
..    (currently 512, so 32 KiB) ahead of each slot. A single request larger than
..    that cannot be absorbed and deadlocks the slot. Raising the constant is a
..    static-design change.

.. Constraints that come from PR slot boundaries
..    The module is delivered as a partial bitstream into a fixed region of the
..    FPGA, so its resources must fit the slot's clock regions listed in
..    ``spinhdl.yaml``, and it is built once per slot it may occupy. Keep a
..    ``(* DONT_TOUCH = "yes" *)`` attribute on the top module so trivial logic is
..    not optimised away, and do not use I/O, clocking primitives, or hard blocks
..    outside the region. The module's registers are not reset by the static side
..    after a reconfiguration; initialise your state in the ``rst`` branch.

.. What the Accelerator Sees
.. -------------------------

.. A request is a sequence of 64-byte lines. Line 0 is the header; lines 1 to N
.. are the payload exactly as the client sent it.

.. .. list-table::
..    :header-rows: 1
..    :widths: 12 10 78

..    * - Bytes
..      - Bits
..      - Field
..    * - 0-55
..      - 447:0
..      - Prefix, ``0xff`` in every byte. Use it to recognise the header line.
..    * - 56-59
..      - 479:448
..      - Declared request size, little-endian, in bytes, **including** this
..        header. Consumed by the dispatcher; informational to you.
..    * - 60-61
..      - 495:480
..      - Configuration word. Bits 1:0 are the framing flags ``FIRST`` and
..        ``LAST`` and belong to the dispatcher. Bits 15:2 are free for
..        per-request accelerator parameters; ``top_k`` uses this word as its
..        result mask.
..    * - 62-63
..      - 511:496
..      - Workload ID. Selects the slot; already acted on before you see it.

.. Byte ``n`` of a line is at ``tdata[8n+7:8n]``. Existing accelerators treat the
.. payload as 16 little-endian 32-bit words per line, word ``i`` at
.. ``tdata[32i+31:32i]``, but that is a convention, not a requirement.

Wrapping an existing core
~~~~~~~~~~~~~~~~~~~~~~~~~

Keep the core unchanged and add an adapter module at the top that maps the
slot ports onto it. ``kernels/user_krnl/apps/mm/`` is the example:
``CNN_workload.v`` is untouched and ``mm.v`` is the adapter. Declare any
Vivado IP the core needs in ``unit.yaml`` (``xci`` for ``.xci`` files, ``ip``
for a ``gen_ip.tcl``).

.. If the kernel already exists with its own interface, keep it unchanged and
.. add an adapter at the top. ``kernels/user_krnl/apps/mm/`` is the example: the
.. CNN accelerator (``CNN_workload.v`` with its packet parser, FIFOs, and the
.. hls4ml IP ``myproject_1``) is untouched, and ``mm.v`` only maps the slot
.. ports onto it.
.. Vivado IP the core depends on is declared in ``unit.yaml`` (``xci`` for
.. ``.xci`` files, ``ip`` for a ``gen_ip.tcl``) so the per-module synthesis can
.. regenerate it.

Step 3: Simulate
----------------

Unit test
   Copy ``kernels/user_krnl/apps/top_k/tb/`` into your ``tb/`` and point its
   ``Makefile`` at your RTL. It runs cocotb under Verilator or Icarus.
   ``test_top_k.py`` has a ``header_line()`` helper that builds a valid header
   beat and an AXI-Stream source/sink pair from ``cocotbext-axi``. Drive
   header-only, single-line, multi-line, and back-to-back requests, and insert
   random ``tready`` stalls on the response side.

Integration test
   Swap ``cell_bbx_pattern_sim.sv`` for your module and run
   ``make -C kernels/user_krnl/reassembly/tb``. This drives the dispatcher,
   scheduler, and slot routing over a modelled TCP interface and checks the
   header skip, request reassembly across TCP packets, and the
   one-response-per-request rule together.

Step 4: Register with the Build
-------------------------------

Add the module to all three manifests.

``kernels/user_krnl/apps/<name>/unit.yaml``
   The module's own manifest: ``name``, ``top``, ``moduletype: recon``, the
   target part, and the RTL, XDC, XCI, and IP file lists. Copy
   ``apps/top_k/unit.yaml`` and edit.

``spin.yaml`` (repository root)
   Append a unit entry with the same fields plus a ``utilization`` estimate.
   Run an out-of-context synthesis first and record the numbers, as the
   existing entries do.

``spinhdl.yaml`` (repository root)
   Under each slot (``C00``, ``C01``, ``C02``) that may host your module, add a
   ``component`` naming the unit. Component ``id`` values are unique across
   the whole file; the next free value is 15. The module is only built for the
   slots you list it under.

Then run the DFX build as in :doc:`build-and-deployment`. It produces a full
image for initial programming and one ICAP partial ``.bin`` per (module, slot)
pair; Step 6 loads them.

.. The DFX build then produces one partial bitstream per (module, slot) pair. How
.. to run that flow and load the result is covered in :doc:`build-and-deployment`
.. and :doc:`reconfiguration-controller`; it is the same for every accelerator
.. and needs nothing module-specific beyond these manifests.

Step 5: Send a Request
----------------------

Open a raw TCP connection to port 2888 (address ``172.24.1.52`` in the
checked-in design). Send the 64-byte header followed by the payload, then read
the response as raw bytes. There is no response header, so the client must
know how many bytes to expect.

Header layout
~~~~~~~~~~~~~

.. list-table::
   :header-rows: 1
   :widths: 12 10 78

   * - Bytes
     - Size
     - Value
   * - 0-55
     - 56
     - ``0xff`` repeated. Required: accelerators use it to recognise the
       header line.
   * - 56-59
     - 4
     - Total request size in bytes, little-endian, **including** these 64
       header bytes. A header-only request declares 64.
   * - 60-61
     - 2
     - Configuration word, little-endian. Bit 0 = ``FIRST``, bit 1 = ``LAST``;
       set both (``0x3``) for an ordinary single request. Bits 15:2 are passed
       to the accelerator as parameters; use ``0xffff`` masked with the flags
       when the accelerator has none.
   * - 62-63
     - 2
     - Workload ID, little-endian: the slot your accelerator is loaded in.

The size rule differs for the reconfiguration controller (its declared size
excludes the header; see :ref:`protocol:fRAC Request Header`). For
accelerators, count the header.

Workload ID
~~~~~~~~~~~

The workload ID selects the slot. The mapping is fixed in
``kernels/user_krnl/reassembly/rtl/pkt_logic.v``:

.. list-table::
   :header-rows: 1
   :widths: 25 25 50

   * - Workload ID
     - Parameter
     - Destination
   * - ``0x0000``
     - ``PATTERN_APP``
     - Slot C00
   * - ``0x0001``
     - ``OR_APP``
     - Slot C01
   * - ``0x0002``
     - ``C02_APP``
     - Slot C02
   * - ``0x00ab``
     - ``RECONF_APP``
     - Reconfiguration controller, not an accelerator slot
   * - anything else
     -
     - Falls through to slot C00

.. -  Giving an accelerator a stable ID independent of slot is a static-design
..    change: add a parameter and a routing case in ``pkt_logic.v``, then rebuild
..    the static design and every partial bitstream.

Ready-made clients
~~~~~~~~~~~~~~~~~~

The Go client in ``sw/pr/main.go`` builds the header in ``buildHeader`` and is
a convenient starting point for a Go tool. For load testing, the libtpa
``tperf`` fork used in :doc:`quick-start` encodes the header with ``-Z 1``,
selects the workload with ``-F``, and sets request and response sizes with
``-m``/``-X`` and ``-R``.

.. Example
.. ~~~~~~~

.. A Python client sending 32 little-endian 32-bit values to the accelerator in
.. slot C01 and reading back one 64-byte line:

.. .. code:: python

..    import socket, struct

..    FIRST, LAST = 0x1, 0x2
..    values = list(range(32))                       # 2 lines of 16 words
..    payload = b"".join(struct.pack("<I", v) for v in values)
..    assert len(payload) % 64 == 0

..    total  = 64 + len(payload)                     # header included
..    config = (0xffff & ~0x3) | FIRST | LAST        # no parameters
..    header = (bytes([0xff]) * 56
..              + struct.pack("<I", total)
..              + struct.pack("<H", config)
..              + struct.pack("<H", 0x0001))         # slot C01

..    s = socket.create_connection(("172.24.1.52", 2888))
..    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
..    s.sendall(header + payload)                    # 192 bytes, one segment
..    response = s.recv(64)

Step 6: Try It on Hardware
--------------------------

#. Program the FPGA with the full image from the same DFX build as your partial
   bitstream, using Vivado Hardware Manager (:ref:`quick-start:Program the FPGA`).
#. Give the host interface connected to the U280 an address on the FPGA's
   subnet, for example ``172.24.1.10/24``
   (:ref:`quick-start:Configure the Host Network`).
#. Check that the FPGA accepts a TCP connection:

   .. code:: sh

      sudo env TPA_ETH_DEV="$FRAC_NETDEV" TPA_ID=frac-connect \
          tpa run swing 172.24.1.52 2888

   Wait for ``[connected]``, then press Ctrl+C.
#. Load your partial bitstream into the slot with the reconfiguration client:

   .. code:: sh

      go run ./sw/pr/main.go -addr 172.24.1.52:2888 -hbm-addr 0x4000 \
          -chunk-size 64 -query-status -post-probe \
          path/to/<slot>_<module>_icap_part.bin

   Use the ICAP-formatted ``.bin``, not the ``.bit``. 
#. Send a header-only request to your slot's workload ID (Step 5) and confirm
   a response arrives. For instance, for slot C00, workload ID ``0``:

   .. code:: sh

      sudo env TPA_ETH_DEV="$FRAC_NETDEV" TPA_ID=frac-test \
          tpa run tperf -c 172.24.1.52 -p 2888 -t rr \
          -Z 1 -F 0 -m 64 -X 64 -R 64 -n 1 -C 1 -d 5

   A nonzero request ``count`` in the output means the exchange works.
#. Send real payloads: set ``-m``/``-X`` to the full request size, header
   included, and ``-R`` to your response size.

.. #. Send a header-only request (declared size 64) and confirm one 64-byte
..    response arrives.
.. #. Send real payloads.
.. #. If responses stop arriving after a while, look for a request shape that
..    gets no response or two responses.
