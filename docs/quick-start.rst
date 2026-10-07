Quick Start
===========

fRAC includes an Ethernet and TCP stack and a few accelerators, all implemented on the FPGA.
A TCP client can send application requests over TCP and receive responses with low latency.
Accelerators sit in slots, which can be swapped at runtime through partial reconfiguration.
We use libtpa, a DPDK-based TCP stack, to measure latency and throughput.

.. note:: Artifact evaluators using the provided testbed

   The FPGA, host network, and required software are already configured.
   Skip the **Setting up the NIC**, **Building libtpa**, **Setup Hugepages**,
   **Connect the Hardware**, and **Configure the Host Network** sections.

Requirements
------------

Hardware
~~~~~~~~

1. Alveo U280.
2. ConnectX-6 Dx 100GbE NIC.
3. USB cable for JTAG.
4. 100G QSFP cable.
5. A host with at least 28 cores to spare: the experiments pin up to 28 client
   threads, one per core.

Software
~~~~~~~~

1. Ubuntu. The paper's measurements ran on 20.04, and the evaluation testbeds
   run 24.04.
2. Vivado 2022.2, whose hardware manager programs the FPGA over JTAG. Building
   bitstreams also needs Vitis HLS 2022.2 and a license for the UltraScale+
   Integrated 100G Ethernet Subsystem (CMAC).
3. `MLNX_OFED <https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/>`_;
   we used 24.07-0.6.1.0.
4. `Go <https://go.dev/doc/install>`_ compiler; we used 1.22.
5. CMake >= 3.5, for building bitstreams.
6. Python 3 with the packages in ``eval/requirements.txt``, for the experiments
   (see :doc:`reproducing-results`).

If you don't have access to hardware, you can request access to our infrastructure by contacting us.

.. warning::

   Programming the U280 over JTAG takes it off PCIe if it was up there, for
   example running the XRT shell from its flash. Some servers treat that
   surprise link-down as a fatal error and reset. Take the card off the bus
   and disable its link first (``scripts/flashfpga.sh --help`` shows the
   commands), or use a host on which the card is not enumerated.

Testbed
-------

If you have access to our testbed, follow this step before proceeding

.. code-block:: sh

   $ ssh atcae@kw61160.tailef7cee.ts.net

Generating bitstream
--------------------
.. code-block:: sh

   $ cd ~
   $ git clone --branch artifact-eval \
                --single-branch https://github.com/accl-kaust/frac-atc-artifact.git
   $ cd frac-atc-artifact
   $ make ip CMAKE=/usr/bin/cmake
   $ ./bin/spinhdl --parallel 8 weave spinhdl.yaml \
                    --units spin.yaml \
                    --static static.yaml

.. note::
   You can skip this section and use our bitstreams instead under ``example/``.
   From this point on, we use the provided bitstreams. If you built fRAC yourself, you can find the bitstreams under ``~/frac-atc-artifact/build/frac/bitstreams``.


Setting up the NIC (Skip to the next section)
---------------------------------------------

Make sure you have a ConnectX-6 Dx; other NICs might also work, but we haven't tested them.

Download `MLNX_OFED <https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/>`_
for your Ubuntu release. The commands below are for version 24.07-0.6.1.0 on
Ubuntu 22.04; change the file names to match yours.

.. warning::

   ``mlnxofedinstall`` replaces the distribution's RDMA and NIC driver
   packages with its own.

.. code-block:: sh

   $ cd ~
   $ tar -xvf MLNX_OFED_LINUX-24.07-0.6.1.0-ubuntu22.04-x86_64.tgz
   $ cd MLNX_OFED_LINUX-24.07-0.6.1.0-ubuntu22.04-x86_64
   $ sudo ./mlnxofedinstall --dpdk --upstream-libs

Building libtpa (Skip to the next section)
------------------------------------------

The client we measure with, fperf, is part of our libtpa fork. Clone it and
install its build dependencies:

.. code-block:: sh

   $ cd ~
   $ git clone --branch frac_hdr_fmt \
                --single-branch https://github.com/accl-kaust/libtpa.git
   $ cd libtpa
   $ git checkout 2f81dd4    # the commit this artifact was tested with
   $ sudo ./buildtools/install-dep.deb.sh --with-meson

Then build and install it:

.. code-block:: sh

   # export or add to ~/.bashrc or ~/.zshrc
   $ export DPDK_VERSION=v22.11
   $ make
   $ make install

Setup Hugepages  (Skip to the next section)
-------------------------------------------

Allocate hugepages for libtpa's DPDK memory pools. Please adjust the number of
pages according to available DRAM. Each fperf process takes 8 GB of them
(``socket-mem = 8192`` in ``TPA_CFG``), and the mixed-workload and scalability
experiments run four at once, so we allocate 20000 pages (40 GB).

.. code-block:: sh

   # allocating 20000 hugepages each 2MB, after the kernel parameters already there
   # please allocate more if required
   $ sudo sed -i.bak 's|^GRUB_CMDLINE_LINUX="\(.*\)"|GRUB_CMDLINE_LINUX="\1 default_hugepagesz=2M hugepagesz=2M hugepages=20000"|' \
              /etc/default/grub
   $ sudo update-grub
   $ sudo reboot

Connect the Hardware  (Skip to the next section)
------------------------------------------------

1. Connect (``qsfp0``) (port 0) of U280 to the ConnectX-6 Dx with 100G QSFP cable.
2. Connect the U280's JTAG USB interface to the machine.

Program the FPGA
----------------

Program the Alveo U280 FPGA with the full image. We have a shell script for
this. The full image starts with top_k, the first accelerator listed for each
cell in ``spinhdl.yaml``, in every slot.

.. code-block:: sh

   $ cd ~/frac-atc-artifact
   $ ./scripts/programfpga.sh example/frac/jtag/frac.bit

.. code-block:: output

   programming ~/frac-atc-artifact/example/frac/jtag/frac.bit
   PROGRAM_OK: xcu280_u55c_0

``programfpga.sh`` uses the Vivado in ``/tools/Xilinx/Vivado/2022.2``. Set
``VIVADO_ROOT`` if yours is elsewhere, and ``HW_TARGET`` if the host has more
than one JTAG cable; ``--help`` lists the options.

.. note::

   Wait a few seconds after programming the FPGA before sending it any packets
   or requests.

Configure the Host Network  (Skip to the next section)
------------------------------------------------------

The checked-in fRAC design uses FPGA address ``172.24.1.52`` and TCP port
``2888``. Configure the connected host interface with a different address in
the same subnet. The example uses ``172.24.1.2/24``. The MTU must be at least
8232, because fRAC's TCP stack sends 8192-byte segments; we use 9000.

You will need the ConnectX-6 Dx interface connected to the Alveo U280 by a
QSFP cable. We configure it through netplan; add it to your netplan file and
keep what is already there.

.. code-block:: sh

   $ sudo vim /etc/netplan/01-network-manager-all.yaml

.. code-block:: yaml

    network:
      version: 2
      renderer: NetworkManager
      ethernets:
        enp33s0f0np0: # ConnectX-6 Dx interface cabled to the U280
          dhcp4: no
          addresses: [172.24.1.2/24]
          mtu: 9000

Now apply network settings

.. code-block:: sh

   $ sudo netplan apply


Check the TCP Connection
------------------------

Just try ping-ing FPGA.

.. code-block:: sh

   $ ping 172.24.1.52

If ping succeeds, your machine can reach the FPGA and possibly fRAC.

You can also send some test packets to fRAC accelerators and see if they are live.

.. code-block:: sh

   $ cd ~/frac-atc-artifact
   $ go run ./scripts/testfuncs.go -slots 0,1 -counter

You will get a response something like this. Both slots hold top_k, which
answers with a single line that ``testfuncs`` does not recognise; the 300 ms is
``testfuncs`` waiting for further lines that do not come. Both are expected.

.. code-block:: output

  workload 0x0000 (slot 0):
  unrecognised; closest is or_slot (ff 00 00 .., 8-bit line) (1/16 words)   64B in 301.58273ms
  00000000  b9 aa aa aa 00 00 00 00  b7 aa aa aa b6 aa aa aa  |................|
  00000010  b5 aa aa aa b4 aa aa aa  b3 aa aa aa b2 aa aa aa  |................|
  00000020  b1 aa aa aa b0 aa aa aa  af aa aa aa ae aa aa aa  |................|
  00000030  ad aa aa aa ac aa aa aa  ab aa aa aa aa aa aa aa  |................|

  workload 0x0001 (slot 1):
  unrecognised; closest is or_slot (ff 00 00 .., 8-bit line) (1/16 words)   64B in 301.57862ms
  00000000  b9 aa aa aa 00 00 00 00  b7 aa aa aa b6 aa aa aa  |................|
  00000010  b5 aa aa aa b4 aa aa aa  b3 aa aa aa b2 aa aa aa  |................|
  00000020  b1 aa aa aa b0 aa aa aa  af aa aa aa ae aa aa aa  |................|
  00000030  ad aa aa aa ac aa aa aa  ab aa aa aa aa aa aa aa  |................|

Reconfigure with an Accelerator
-------------------------------

Try reconfiguring with any accelerator

.. code-block:: sh

   $ cd ~/frac-atc-artifact
   $ go run ./scripts/reconfslots.go -slot 1 -chunk-size 256 \
            -hbm-addr 0x10004000 -query-status example/frac/icap/c01_f09.bin

Then try sending packets and it should change the response.

Finally, program with echo for the next step

.. code-block:: sh

   $ go run ./scripts/reconfslots.go -slot 1 -chunk-size 256 \
            -hbm-addr 0x10004000 -query-status example/frac/icap/c01_f09.bin


.. code-block:: sh

   $ go run ./scripts/testfuncs.go -slots 0,1 -counter

.. code-block:: output

  workload 0x0000 (slot 0):
  unrecognised; closest is or_slot (ff 00 00 .., 8-bit line) (1/16 words)   64B in 302.053461ms
  00000000  b9 aa aa aa 00 00 00 00  b7 aa aa aa b6 aa aa aa  |................|
  00000010  b5 aa aa aa b4 aa aa aa  b3 aa aa aa b2 aa aa aa  |................|
  00000020  b1 aa aa aa b0 aa aa aa  af aa aa aa ae aa aa aa  |................|
  00000030  ad aa aa aa ac aa aa aa  ab aa aa aa aa aa aa aa  |................|

  workload 0x0001 (slot 1):
  echo_slot (data returned unchanged)  16/16 words   128B in 1.17679ms
  00000000  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000020  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000030  ff ff ff ff ff ff ff ff  80 00 00 00 fd ff 01 00  |................|
  00000040  aa aa aa aa ab aa aa aa  ac aa aa aa ad aa aa aa  |................|
  00000050  ae aa aa aa af aa aa aa  b0 aa aa aa b1 aa aa aa  |................|
  00000060  b2 aa aa aa b3 aa aa aa  b4 aa aa aa b5 aa aa aa  |................|
  00000070  b6 aa aa aa b7 aa aa aa  b8 aa aa aa b9 aa aa aa  |................|

Performance Measurements
------------------------

.. note::

   Before proceeding, make sure the ``pattern`` function is loaded into at
   least one slot. It echoes requests back to the client. The command below
   sends to slot 1 (``-K 1``), which the previous step loaded.


We measure performance with our libtpa based perf tool.

.. note::
   Change ``-n`` according to number of cores your machine has. fperf allocates each client to an individual core, if you need more client per core use ``-C``

.. code-block:: sh

   # set TPA_ETH_DEV to ConnectX-6 Dx interface connected to Alveo U280
   $ cd ~/libtpa

   $ sudo TPA_ID=client TPA_ETH_DEV=enp33s0f0np0 TPA_CFG="tcp {tso = 0; } dpdk { socket-mem = 8192; mbuf_mem_size = 6GB; }" ~/.local/bin/tpa run build/bin/app/fperf -c 172.24.1.52 -p 2888 -t rr -d 5 -n 22 -S 0 -m 4096 -X 4096 -R 4096  -Z 1 -K 1

Each line reports one client's latency and throughput for one second, and the
``Total-Throughput`` lines the sum over all clients. The first second's
numbers are not meaningful; ignore them.

.. code-block:: output

    2 RR .0 min=6.91us avg=7.83us max=842.24us read(Gbits/sec)=4.130 write(Gbits/sec)=4.130 count=126025
    ...
    2 RR Total-Throughput read(Gbits/sec)=90.868 write(Gbits/sec)=90.868

    3 RR .0 min=6.66us avg=7.82us max=46.85us read(Gbits/sec)=4.132 write(Gbits/sec)=4.132 count=126109
    ...
    3 RR Total-Throughput read(Gbits/sec)=90.872 write(Gbits/sec)=90.872
