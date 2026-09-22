Quick Start
===========

This guide connects a host to fRAC and runs a request-response test using
`libtpa <https://github.com/krish-iyer/libtpa/>`_. The example assumes a full FPGA
image with the ``pattern_slot`` accelerator loaded in slot 0 (C00).

Requirements
------------

Hardware
~~~~~~~~

1. Alveo U280.
2. ConnectX-6 Dx 100GbE adapter.
3. USB cable for JTAG.
4. 100G QSFP cable.

Software
~~~~~~~~

1. Ubuntu 22.04 LTS.
2. Vivado 2022.2.
3. `MLNX_OFED <https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/>`_.

Get the Software
----------------

On the host connected to the ConnectX-6 Dx, install Git and the C build tools,
then clone fRAC and libtpa into a common working directory:

.. code-block:: sh

   sudo apt update
   sudo apt install -y git build-essential

   mkdir -p frac-workspace
   cd frac-workspace
   export FRAC_WORKSPACE="$PWD"

   git clone https://github.com/krish-iyer/offrac.git
   git clone --branch tcp_bench --single-branch https://github.com/krish-iyer/libtpa.git

Use libtpa's ``tcp_bench`` branch for this example. It adds FPGA request framing
and the function, request-size, and response-size options used below.

Build libtpa
------------

Install the dependencies and build the library and its applications:

.. code-block:: sh

   cd "$FRAC_WORKSPACE/libtpa"
   sudo ./buildtools/install-dep.deb.sh --with-meson
   make
   sudo make install

The installation provides the ``tpa`` launcher, the ``swing`` connection tool,
and the ``tperf`` benchmark. MLNX_OFED must include the DPDK and userspace verbs
support described in the
`libtpa installation guide <https://github.com/krish-iyer/libtpa/blob/tcp_bench/doc/quick_start.rst>`_.

Allocate hugepages for libtpa's DPDK memory pools:

.. code-block:: sh

   sudo ./tools/scripts/hugepage-setup.sh
   sudo mkdir -p /dev/hugepages
   mountpoint -q /dev/hugepages || sudo mount -t hugetlbfs -o pagesize=2M none /dev/hugepages
   grep -E 'HugePages|Hugepagesize' /proc/meminfo

The helper reserves 1024 pages of 2 MiB each, or 2 GiB. Check that the allocation
succeeded before running a client; this setup may need to be repeated after a
reboot.

Connect the Hardware
--------------------

1. Install and power the Alveo U280 and the ConnectX-6 Dx in their host systems.
2. Connect the U280 port used by the design (``qsfp0``) to the ConnectX-6 Dx using
   the 100G QSFP cable.
3. Connect the U280's JTAG USB interface to the machine running Vivado.

The network client and Vivado can run on the same machine or on separate
machines.

Program the FPGA
----------------

Use a full U280 bitstream containing the fRAC network infrastructure and
``pattern_slot`` in C00. This example uses workload ID ``0`` to reach that slot.
See :doc:`build-and-deployment` for the FPGA build flow.

.. note::

   The Quick Start image's download location and release filename are still to
   be specified. ``<initial-frac-image.bit>`` below denotes that full image.

In Vivado 2022.2:

1. Open **Hardware Manager**.
2. Select **Open Target → Auto Connect** and locate the U280 FPGA.
3. Select **Program Device**.
4. Choose ``<initial-frac-image.bit>`` as the bitstream file. If using debug
   probes, select the ``.ltx`` file from the same build.
5. Program the device and wait for completion.

Configure the Host Network
--------------------------

The checked-in fRAC design uses FPGA address ``172.24.1.52`` and TCP port
``2888``. Configure the connected host interface with a different address in
the same subnet. The example uses ``172.24.1.10/24``.

Identify the ConnectX-6 Dx interface:

.. code-block:: sh

   ip -br link

Replace ``enp1s0f0`` below with the interface connected to the FPGA. Start with a
1500-byte MTU for the small request used in this guide:

.. code-block:: sh

   export FRAC_NETDEV=enp1s0f0
   sudo ip addr add 172.24.1.10/24 dev "$FRAC_NETDEV"
   sudo ip link set dev "$FRAC_NETDEV" mtu 1500 up
   ip -br addr show dev "$FRAC_NETDEV"
   ethtool "$FRAC_NETDEV"

Confirm that ``ethtool`` reports ``Link detected: yes`` and a speed of
``100000Mb/s``. These network settings apply to the current boot. If your FPGA
image uses another IP address, adjust the host subnet and client destination
accordingly.

Check the TCP Connection
------------------------

Use libtpa's ``swing`` application to check that the FPGA accepts a TCP
connection:

.. code-block:: sh

   sudo env TPA_ETH_DEV="$FRAC_NETDEV" TPA_ID=frac-connect \
       tpa run swing 172.24.1.52 2888

The launcher derives libtpa's network configuration from ``FRAC_NETDEV`` through
``TPA_ETH_DEV``. Keep the interface attached to its ``mlx5_core`` driver;
libtpa uses the Mellanox driver alongside the host network stack.

Wait for ``[connected]``, then press **Ctrl+C**. This checks the TCP connection;
the next step sends a framed fRAC request.

Run a Request-Response Test
--------------------------------

With ``pattern_slot`` in C00, run a five-second test with one connection and one
worker:

.. code-block:: sh

   sudo env TPA_ETH_DEV="$FRAC_NETDEV" TPA_ID=frac-test \
       tpa run tperf -c 172.24.1.52 -p 2888 -t rr \
       -Z 1 -F 0 -m 64 -X 64 -R 64 -n 1 -C 1 -d 5

The FPGA-specific options are implemented in the fork's
`tperf client <https://github.com/krish-iyer/libtpa/tree/tcp_bench/app/tperf>`_:

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - Option
     - Meaning
   * - ``-t rr``
     - Send a request and wait for its response before sending the next.
   * - ``-Z 1``
     - Encode the request for the FPGA.
   * - ``-F 0``
     - Select workload ID 0, routed to C00 in the current design.
   * - ``-m 64 -X 64``
     - Send one 64-byte message per request, including the fRAC request header.
   * - ``-R 64``
     - Wait for a 64-byte response.
   * - ``-n 1 -C 1 -d 5``
     - Use one worker and one connection for five seconds.

This minimal request consists of the header alone. The ``pattern_slot``
accelerator is an echo workload: it returns the 64-byte header unchanged, with
the request's TCP length and session ID as response metadata. A working exchange produces nonzero request
``count`` values and ``min``, ``avg``, and ``max`` latency statistics in the
``tperf`` output. This benchmark measures request completion and latency; its
current client does not verify the response payload.

If the connection succeeds but requests do not complete, check that C00 contains
``pattern_slot`` and that the expected response size is 64 bytes. Other
accelerators require their own request payload and response-size settings.

Replace an Accelerator
----------------------

After completing the initial test, stop the benchmark and follow
:ref:`Runtime deployment <build-and-deployment:Runtime Deployment>` to load a
replacement accelerator. Use an ICAP-compatible partial image built for the
selected slot and the same static design as the running full image.

When rerunning the libtpa client, select the workload ID routed to that slot and
set the request and response sizes for the replacement accelerator.
