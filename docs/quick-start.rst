Quick Start
===========

fRAC includes an Ethernet and TCP stack and few accelerators, all implemented on the FPGA.
A TCP client can send application requests over TCP and receive responses with low latency.
Accelerators are placed in a slot which are reconfigurable through partial reconfiguration.
We use libtpa, a DPDK based TCP stack to measure latency and throughput.

Requirements
------------

Hardware
~~~~~~~~

1. Alveo U280.
2. ConnectX-6 Dx 100GbE NIC.
3. USB cable for JTAG.
4. 100G QSFP cable.

Software
~~~~~~~~

1. Ubuntu 22.04 LTS.
2. Vivado 2022.2.
3. `MLNX_OFED <https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/>`_.
4. `Go <https://go.dev/doc/install>`_ compiler
5. Cmake >= 3.5

If you don't have access to hardware, you can request access to our infrastructure by contacting us.

Generating bitstream
--------------------
.. code-block:: sh

   $ git clone --branch main \
                --single-branch https://github.com/accl-kaust/frac-atc-artifact.git
   $ cd frac-atc-artifact
   $ make ip CMAKE=/usr/bin/cmake
   $ ./bin/spinhdl --parallel 8 weave spinhdl.yaml \
                    --units spin.yaml \
                    --static static.yaml \
                    --run all
   $ cd ~

.. note::
   You can skip this section and use our bitstreams instead under ``example/``


Setting up the NIC
----------------

Make sure you have a ConnectX-6 Dx, other NICs might also work but we haven't tested anything else yet.

Download `MLNX_OFED <https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/>`_.

.. code-block:: sh

   $ tar -xvf MLNX_OFED_LINUX-24.07-0.6.1.0-ubuntu22.04-x86_64.tgz
   $ cd MLNX_OFED_LINUX-24.07-0.6.1.0-ubuntu22.04-x86_64
   $ sudo ./mlnxofedinstall --dpdk --upstream-libs
   $ cd ~

Building libtpa
---------------

.. code-block:: sh

   # export or add to ~/.bashrc or ~/.zshrc
   $ export DPDK_VERSION=v22.11
   $ git clone --branch frac_hdr_fmt
                --single-branch https://github.com/krish-iyer/libtpa.git
   $ cd libtpa
   $ sudo ./buildtools/install-dep.deb.sh --with-meson
   $ make
   $ make install

Allocate hugepages for libtpa's DPDK memory pools. Please adjust the number of pages according to available DRAM

.. code-block:: sh

   # allocating 2000 hugepages each 2MB
   # please allocate more if required
   $ sudo sed -i.bak 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="default_hugepagesz=2M hugepagesz=2M hugepages=2000"|' \
              /etc/default/grub
   $ sudo update-grub
   $ sudo reboot

Connect the Hardware
--------------------

1. Connect (``qsfp0``) (port 0) of U280 to the ConnectX-6 Dx with 100G QSFP cable.
2. Connect the U280's JTAG USB interface to the machine.

Program the FPGA
----------------

Program the Alveo U280 FPGA with the generated bitstream. We have a shell script to this. The full bitstreams come with default accelerators with ID:0 in ``spinhdl.yaml``.

.. code-block:: sh

   $ cd frac-atc-artifact
   $ ./scripts/programfpga.sh example/jtag/frac.bit

.. code-block:: output

   programming ~/frac-atc-artifact/example/jtag/frac.bit
   PROGRAM_OK: xcu280_u55c_0

.. note::

   Wait a few seconds after flashing the FPGA before sending it any packets
   or requests.

Configure the Host Network
--------------------------

The checked-in fRAC design uses FPGA address ``172.24.1.52`` and TCP port
``2888``. Configure the connected host interface with a different address in
the same subnet. The example uses ``172.24.1.2/24``.

You will need the ConnectX-6 Dx interface connected to the Alveo U280 by a QSFP cable. We prefer configuring network interface through netplan.

.. code-block:: sh

   $ sudo vim /etc/netplan/01-network-manager-all.yaml

.. code-block:: yaml

    network:
      version: 2
      renderer: NetworkManager
      ethernets:
        enp33s0f0np0: # ConnectX-6 Dx Intf to U280
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

If ping is sucessfull then your machine can reach FPGA and possibly fRAC.

You can also send some test packets to fRAC accelerators and see if they are live.

.. code-block:: sh

   $ cd frac-atc-artifact
   $ go run ./scripts/testfuncs.go -slots 0,1 -counter

You will get a response something like this.

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

Try reconfiguring with any acclerator

.. code-block:: sh

   $ go run ./scripts/reconfslots.go -slot 1 -chunk-size 256 \
            -hbm-addr 0x10004000 -query-status example/icap/c01_f03.bin

Then try sending packets and it should change the response.

Finally, program with echo for the next step

.. code-block:: sh

   $ go run ./scripts/reconfslots.go -slot 1 -chunk-size 256 \
            -hbm-addr 0x10004000 -query-status example/icap/c01_f09.bin


.. code-block:: sh

   $ go run patprobe.go -slots 0,1

.. code-block:: output

  workload 0x0000 (slot 0):
  echo_slot (data returned unchanged)  16/16 words   128B in 1.143403ms
  00000000  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000020  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
  00000030  ff ff ff ff ff ff ff ff  80 00 00 00 fd ff 00 00  |................|
  00000040  aa aa aa aa aa aa aa aa  aa aa aa aa aa aa aa aa  |................|
  00000050  aa aa aa aa aa aa aa aa  aa aa aa aa aa aa aa aa  |................|
  00000060  aa aa aa aa aa aa aa aa  aa aa aa aa aa aa aa aa  |................|
  00000070  aa aa aa aa aa aa aa aa  aa aa aa aa aa aa aa aa  |................|

  workload 0x0001 (slot 1):
  unrecognised; closest is echo_slot (data returned unchanged) (15/16 words)   64B in 301.595283ms
  00000000  aa aa aa aa 00 00 00 00  aa aa aa aa aa aa aa aa  |................|
  00000010  aa aa aa aa aa aa aa aa  aa aa aa aa aa aa aa aa  |................|
  00000020  aa aa aa aa aa aa aa aa  aa aa aa aa aa aa aa aa  |................|
  00000030  aa aa aa aa aa aa aa aa  aa aa aa aa aa aa aa aa  |................|

Performance Measurements
------------------------

.. note::

   Before proceeding, make sure the ``pattern`` function is loaded into at
   least one slot. It echoes requests back to the client.


We measure performance with our libtpa based perf tool.

.. note::
   Change ``-n`` according to number of cores your machine has. fperf allocates each client to an individual core, if you need more client per core use ``-C``

.. code-block:: sh

   # set TPA_ETH_DEV to ConnectX-6 Dx interface connected to Alveo U280
   $ cd libtpa
   $ sudo TPA_ID=client TPA_ETH_DEV=<> \
          TPA_CFG="tcp {tso = 0; } \
          dpdk { socket-mem = 8192; mbuf_mem_size = 6GB; }" \
          ~/.local/bin/tpa run build/bin/app/fperf -c 171.24.1.52 -p 2888 \
          -t rr -d 5 -n 28 -S 0 -m 4096 -X 4096 -R 4096  -Z 1 -K 0

.. code-block:: output

    2 RR .0 min=6.91us avg=7.83us max=842.24us read(Gbits/sec)=4.130 write(Gbits/sec)=4.130 count=126025
    ...
    2 RR Total-Throughput read(Gbits/sec)=90.868 write(Gbits/sec)=90.868

    3 RR .0 min=6.66us avg=7.82us max=46.85us read(Gbits/sec)=4.132 write(Gbits/sec)=4.132 count=126109
    ...
    3 RR Total-Throughput read(Gbits/sec)=90.872 write(Gbits/sec)=90.872
