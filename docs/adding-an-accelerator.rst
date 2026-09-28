Integrating Your Own Accelerator
================================

fRAC provides abstract shells that let developers integrate accelerators without rebuilding the entire stack. An accelerator needs little to no knowledge of the network.
This guide shows how to bring your own accelerator into fRAC. It covers where the accelerator connects, the interface it must implement, how to implement the hardware, and how a client sends it requests.

Please follow  `quick-start <https://accl-kaust.github.io/frac-atc-artifact/>`_ before proceeding.

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

        assign m_axis_tdata  = {s_axis_tdata[AXIS_DATA_W-1:512], s_axis_tdata[511:0] | {512{1'b1}}};
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

   $ ./bin/spinhdl spin test_app --shell build/frac/abstract_shell/ab_sh_c00_bbx_inst.dcp \
                    --cell C00 --out-dir out


Try It on Hardware
--------------------------

1. Program the FPGA with the full image

.. code-block:: sh

   $ ./scripts/programfpga.sh build/frac/bitstreams/jtag/frac.bit

2. Send a request just to check if fRAC is live

.. code-block:: sh

   $ go run ./scripts/testfuncs.go -slots 0,1 -counter

.. code-block:: output

  workload 0x0000 (slot 0):
  unrecognised; closest is or_slot (ff 00 00 .., 8-bit line) (1/16 words)   64B in 301.471095ms
  00000000  b9 aa aa aa 00 00 00 00  b7 aa aa aa b6 aa aa aa  |................|
  00000010  b5 aa aa aa b4 aa aa aa  b3 aa aa aa b2 aa aa aa  |................|
  00000020  b1 aa aa aa b0 aa aa aa  af aa aa aa ae aa aa aa  |................|
  00000030  ad aa aa aa ac aa aa aa  ab aa aa aa aa aa aa aa  |................|

  workload 0x0001 (slot 1):
  unrecognised; closest is or_slot (ff 00 00 .., 8-bit line) (1/16 words)   64B in 301.646634ms
  00000000  b9 aa aa aa 00 00 00 00  b7 aa aa aa b6 aa aa aa  |................|
  00000010  b5 aa aa aa b4 aa aa aa  b3 aa aa aa b2 aa aa aa  |................|
  00000020  b1 aa aa aa b0 aa aa aa  af aa aa aa ae aa aa aa  |................|
  00000030  ad aa aa aa ac aa aa aa  ab aa aa aa aa aa aa aa  |................|

3. Program your accelerator

.. code-block:: sh

   $ go run ./scripts/reconfslots.go -slot 0 -chunk-size 256 -hbm-addr 0x10004000 -query-status out/icap/c00_f08.bin

4. Send a request again to see the change

.. code-block:: sh

   $ go run ./scripts/testfuncs.go -slots 0,1 -counter

.. code-block:: output

  workload 0x0000 (slot 0):
  or_slot (payload | all-ones, wide line)  16/16 words   128B in 1.160003ms
  00000000  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000020  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000030  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000040  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000050  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000060  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000070  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|

  workload 0x0001 (slot 1):
  unrecognised; closest is or_slot (ff 00 00 .., 8-bit line) (1/16 words)   64B in 302.145387ms
  00000000  b9 aa aa aa 00 00 00 00  b7 aa aa aa b6 aa aa aa  |................|
  00000010  b5 aa aa aa b4 aa aa aa  b3 aa aa aa b2 aa aa aa  |................|
  00000020  b1 aa aa aa b0 aa aa aa  af aa aa aa ae aa aa aa  |................|
  00000030  ad aa aa aa ac aa aa aa  ab aa aa aa aa aa aa aa  |................|
