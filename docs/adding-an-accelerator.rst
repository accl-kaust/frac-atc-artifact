Integrating Your Own Accelerator
================================

fRAC provides abstract shells that let developers integrate accelerators without rebuilding the entire stack. An accelerator needs little to no knowledge of the network.
This guide shows how to bring your own accelerator into fRAC. It covers where the accelerator connects, the interface it must implement, how to implement the hardware, and how a client sends it requests.

Creating files
--------------

fRAC expects a specific directory layout and set of files.

.. code-block:: sh

   $ cd ~/frac-atc-artifact
   $ mkdir -p kernels/user_krnl/apps/<name>/src/{rtl,ip,xci,tb}
   $ touch kernels/user_krnl/apps/<name>/unit.yaml

Write an Accelerator
--------------------

Give the top module exactly this port list. It must match the slot boundary in
``kernels/user_krnl/reconfctrl/rtl/cell_bbx.sv``; the static design
instantiates it with the parameter values in the Width column.


.. list-table::
   :header-rows: 1
   :widths: 32 18 50

   * - Port
     - Width
     - Notes
   * - ``clk``, ``rst``
     - 1
     - Static-side clock and synchronous, active-high reset.
   * - ``s_axis_tdata`` / ``m_axis_tdata``
     - ``AXIS_DATA_W`` = 512
     - Request input and response output, with a 64-byte data bus per beat.
   * - | ``s_axis_tkeep`` / ``m_axis_tkeep``,
       | ``s_axis_tstrb`` / ``m_axis_tstrb``
     - 64
     - Always all-ones on input. Every request beat is a full 64-byte line.
   * - | ``s_axis_tvalid`` / ``m_axis_tvalid``,
       | ``s_axis_tready`` / ``m_axis_tready``
     - 1
     - Standard AXI-Stream handshakes. You may hold ``s_axis_tready`` low
       while busy; a FIFO ahead of the slot absorbs the back-pressure.
   * - ``s_axis_tlast`` / ``m_axis_tlast``
     - 1
     - Set on the final beat of a request or response, respectively.
   * - | ``s_axis_tdest`` / ``m_axis_tdest``,
       | ``s_axis_tid`` / ``m_axis_tid``,
       | ``s_axis_tuser`` / ``m_axis_tuser``
     - | ``TDEST_W`` = 1,
       | ``TID_W`` = 1,
       | ``USER_W`` = 1
     - Driven to zero on input. They carry no information; echo them or
       drive zero on output.


Your accelerator might require registers at input and output port so we recommemd.




Start from this template.


.. code-block:: verilog
   :caption: kernels/user_krnl/apps/<name>/src/rtl/<name>.v


    (* DONT_TOUCH = "yes" *)
    module <name> #(
        parameter integer AXIS_DATA_W = 512 + 1 + 32,
        parameter integer KEEP_W      = 1,
        parameter integer TDEST_W     = 1,
        parameter integer TID_W       = 1,
        parameter integer USER_W      = 1
    ) (
        input  wire                   clk,
        input  wire                   rst,

        input  wire [AXIS_DATA_W-1:0] s_axis_tdata,
        input  wire [KEEP_W-1:0]      s_axis_tkeep,
        input  wire [KEEP_W-1:0]      s_axis_tstrb,
        input  wire                   s_axis_tvalid,
        output wire                   s_axis_tready,
        input  wire                   s_axis_tlast,
        input  wire [TDEST_W-1:0]     s_axis_tdest,
        input  wire [TID_W-1:0]       s_axis_tid,
        input  wire [USER_W-1:0]      s_axis_tuser,

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

        reg rst_q = 1'b1;
        always @(posedge clk) rst_q <= rst;

        // request: boundary -> req_reg_inst -> core
        wire [AXIS_DATA_W-1:0] req_tdata;
        wire                   req_tvalid, req_tready, req_tlast;
        wire [TDEST_W-1:0]     req_tdest;
        wire [TID_W-1:0]       req_tid;
        wire [USER_W-1:0]      req_tuser;

        // response: core -> resp_reg_inst -> boundary
        wire [AXIS_DATA_W-1:0] resp_tdata;
        wire                   resp_tvalid, resp_tready, resp_tlast;
        wire [TDEST_W-1:0]     resp_tdest;
        wire [TID_W-1:0]       resp_tid;
        wire [USER_W-1:0]      resp_tuser;

        axis_register #(
            .DATA_WIDTH (AXIS_DATA_W),
            .KEEP_ENABLE(0),
            .KEEP_WIDTH (1),
            .LAST_ENABLE(1),
            .ID_ENABLE  (1),
            .ID_WIDTH   (TID_W),
            .DEST_ENABLE(1),
            .DEST_WIDTH (TDEST_W),
            .USER_ENABLE(1),
            .USER_WIDTH (USER_W),
            .REG_TYPE   (2)
        ) req_reg_inst (
            .clk          (clk),
            .rst          (rst_q),
            .s_axis_tdata (s_axis_tdata),
            .s_axis_tkeep (1'b1),
            .s_axis_tvalid(s_axis_tvalid),
            .s_axis_tready(s_axis_tready),
            .s_axis_tlast (s_axis_tlast),
            .s_axis_tid   (s_axis_tid),
            .s_axis_tdest (s_axis_tdest),
            .s_axis_tuser (s_axis_tuser),
            .m_axis_tdata (req_tdata),
            .m_axis_tkeep (),
            .m_axis_tvalid(req_tvalid),
            .m_axis_tready(req_tready),
            .m_axis_tlast (req_tlast),
            .m_axis_tid   (req_tid),
            .m_axis_tdest (req_tdest),
            .m_axis_tuser (req_tuser)
        );

        // Please don't forget to change with the app name here
        <name>_core #(
            .AXIS_DATA_W(AXIS_DATA_W),
            .KEEP_W     (KEEP_W),
            .TDEST_W    (TDEST_W),
            .TID_W      (TID_W),
            .USER_W     (USER_W)
        ) core_inst (
            .clk          (clk),
            .rst          (rst_q),
            .s_axis_tdata (req_tdata),
            .s_axis_tkeep ({KEEP_W{1'b1}}),
            .s_axis_tstrb ({KEEP_W{1'b1}}),
            .s_axis_tvalid(req_tvalid),
            .s_axis_tready(req_tready),
            .s_axis_tlast (req_tlast),
            .s_axis_tdest (req_tdest),
            .s_axis_tid   (req_tid),
            .s_axis_tuser (req_tuser),
            .m_axis_tdata (resp_tdata),
            .m_axis_tkeep (),
            .m_axis_tstrb (),
            .m_axis_tvalid(resp_tvalid),
            .m_axis_tready(resp_tready),
            .m_axis_tlast (resp_tlast),
            .m_axis_tdest (resp_tdest),
            .m_axis_tid   (resp_tid),
            .m_axis_tuser (resp_tuser)
        );

        axis_register #(
            .DATA_WIDTH (AXIS_DATA_W),
            .KEEP_ENABLE(0),
            .KEEP_WIDTH (1),
            .LAST_ENABLE(1),
            .ID_ENABLE  (1),
            .ID_WIDTH   (TID_W),
            .DEST_ENABLE(1),
            .DEST_WIDTH (TDEST_W),
            .USER_ENABLE(1),
            .USER_WIDTH (USER_W),
            .REG_TYPE   (2)
        ) resp_reg_inst (
            .clk          (clk),
            .rst          (rst_q),
            .s_axis_tdata (resp_tdata),
            .s_axis_tkeep (1'b1),
            .s_axis_tvalid(resp_tvalid),
            .s_axis_tready(resp_tready),
            .s_axis_tlast (resp_tlast),
            .s_axis_tid   (resp_tid),
            .s_axis_tdest (resp_tdest),
            .s_axis_tuser (resp_tuser),
            .m_axis_tdata (m_axis_tdata),
            .m_axis_tkeep (),
            .m_axis_tvalid(m_axis_tvalid),
            .m_axis_tready(m_axis_tready),
            .m_axis_tlast (m_axis_tlast),
            .m_axis_tid   (m_axis_tid),
            .m_axis_tdest (m_axis_tdest),
            .m_axis_tuser (m_axis_tuser)
        );

        assign m_axis_tkeep = {KEEP_W{1'b1}};
        assign m_axis_tstrb = {KEEP_W{1'b1}};

    endmodule

    `resetall


.. code-block:: verilog
   :caption: kernels/user_krnl/apps/<name>/src/rtl/<name>_core.v

    module <name>_core #(
        parameter integer AXIS_DATA_W = 512 + 1 + 32,
        parameter integer KEEP_W      = 1,
        parameter integer TDEST_W     = 1,
        parameter integer TID_W       = 1,
        parameter integer USER_W      = 1
    ) (
        input  wire                   clk,
        input  wire                   rst,

        input  wire [AXIS_DATA_W-1:0] s_axis_tdata,
        input  wire [KEEP_W-1:0]      s_axis_tkeep,
        input  wire [KEEP_W-1:0]      s_axis_tstrb,
        input  wire                   s_axis_tvalid,
        output wire                   s_axis_tready,
        input  wire                   s_axis_tlast,
        input  wire [TDEST_W-1:0]     s_axis_tdest,
        input  wire [TID_W-1:0]       s_axis_tid,
        input  wire [USER_W-1:0]      s_axis_tuser,

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

        assign s_axis_tready = m_axis_tready;
        assign m_axis_tvalid = s_axis_tvalid;

        // change tdata accordingly, for example here we are
        // OR'ing on the data we receive

        assign m_axis_tdata  = s_axis_tdata | {AXIS_DATA_W {1'b1}};
        assign m_axis_tkeep  = s_axis_tkeep;
        assign m_axis_tstrb  = s_axis_tstrb;
        assign m_axis_tlast  = s_axis_tlast;
        assign m_axis_tdest  = s_axis_tdest;
        assign m_axis_tid    = s_axis_tid;
        assign m_axis_tuser  = s_axis_tuser;

    endmodule

    `resetall


Check if your files and directory looks like this

.. code-block:: sh

   $ tree kernels/user_krnl/apps/<name>/

.. code-block:: output

    kernels/user_krnl/apps/<name>/
    ├── src
    │   ├── ip
    │   ├── rtl
    │   │   ├── <name>.v
    │   │   └── <name>_core.v
    │   ├── tb
    │   └── xci
    └── unit.yaml


Now, unit.yaml

.. code-block:: yaml
   :caption: kernels/user_krnl/apps/<name>/unit.yaml

    name: <name>
    moduletype: recon
    top: <name>
    build: synth
    build_dir: build
    version: 0.1.0
    part: xcu280-fsvh2892-2L-e
    arch: ultraplus

    rtl:
      dir: "src/rtl"
      files:
        - <name>.v
        - <name>_core.v
        - ../../../../reassembly/rtl/axis_register.v

    xdc:
      dir: "src/xdc"
      files:

    xci:
      dir: "src/xci"
      files:

    ip:
      dir: "src/ip"
      files:

Add your accelerator to database.

.. code-block:: yaml
   :caption: spin.yaml

    - name: <name>
      path: kernels/user_krnl/apps/<name>
      moduletype: recon
      top: <name>
      build: synth
      build_dir: build
      rtl:
        dir: src/rtl
        files:
        - <name>.v
        - <name>_core.v
        - ../../../../reassembly/rtl/axis_register.v
      xdc:
        dir: src/xdc
        files: null
      xci:
        dir: src/xci
        files: null
      ip:
        dir: src/ip
        files: null
      # you can add dummy numbers here.
      utilization:
        slices: 142
        ramb36: 0
        dsp: 0


.. code-block:: yaml
   :caption: spinhdl.yaml

    - name: C00
      id: 0
      slot_id: 0
      region:
      ...
      components:
      ...
      - name: test_app
        id: 8
        unit: test_app


Now just build with a abstract shell.

.. code-block:: sh

   $  ./bin/spinhdl spin test_app --shell build/frac/abstract_shell/ab_sh_c00_bbx_inst.dcp \
                    --cell C00 --out-dir out

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
