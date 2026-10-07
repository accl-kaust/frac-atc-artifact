Build and Deployment
====================

This page describes how the bitstreams in ``example/`` are built, what a build
produces, and how bitstreams are loaded at runtime. Building is optional: the
experiments in :doc:`reproducing-results` run on the prebuilt bitstreams.

Requirements
------------

- Vitis HLS and Vivado 2022.2, licensed for the Alveo U280 part
  (``xcu280-fsvh2892-2L-e``) and for the UltraScale+ Integrated 100G Ethernet
  Subsystem (CMAC).
- CMake 3.5 or newer.
- ``bin/spinhdl``, a prebuilt x86-64 Linux binary (glibc 2.34 or newer) of
  `spinHDL <https://github.com/krish-iyer/spinHDL>`_, which drives the
  partial-reconfiguration flow. The bitstreams in ``example/`` were built with
  spinHDL commit ``943f5bc``.
- Time and memory. The build of the bitstreams in ``example/`` took 3.5 hours
  on 48 cores with 192 GB of memory allotted. The flat baseline image in
  ``example/bypass/`` took 66 minutes on 16 cores.

Building
--------

Run these commands from the repository root:

.. code:: sh

   make ip CMAKE=/usr/bin/cmake
   ./bin/spinhdl --parallel 8 weave spinhdl.yaml --units spin.yaml --static static.yaml

``make ip`` builds the TCP/IP stack's HLS cores, from
``lib/fpga-network-stack``, into ``build/lib``. ``spinhdl weave`` then reads
three manifests:

================== ===============================================================
``static.yaml``    The static design: its RTL, the Tcl that configures the AMD IP,
                   and its constraints, including ``frac/xdc/floorplan.xdc``
``spin.yaml``      The catalogue of accelerators (units) and their sources
``spinhdl.yaml``   The four cells, the region of the device each one occupies, and
                   the units each one can hold, with their ids
================== ===============================================================

It synthesizes the static design and every unit, implements the initial
configuration, with the first unit listed for each cell (top_k), and writes an
abstract shell for every cell. It then implements every other unit of every
cell against that cell's shell and writes the bitstreams:

========================================================= ==========================================
``build/frac/bitstreams/jtag/frac.bit``                   The full image, programmed over JTAG
``build/frac/bitstreams/jtag/c<cell>_f<id>.bit``          Partial bitstreams, for JTAG
``build/frac/bitstreams/icap/c<cell>_f<id>.bin``          Partial bitstreams for the reconfiguration
                                                          controller
``build/frac/bitstreams/pcap/c<cell>_f<id>.bin``          The same without ICAP's bit swap; unused
``build/frac/abstract_shell/ab_sh_c0<n>_bbx_inst.dcp``    Each cell's abstract shell, for building
                                                          new accelerators (:doc:`adding-an-accelerator`)
========================================================= ==========================================

``<cell>`` is the cell's number and ``<id>`` the unit's id in
``spinhdl.yaml``, both two digits, so ``c02_f20`` is the CNN in cell C02;
``example/README.md`` lists them all. The regions in ``spinhdl.yaml`` and the
static pblock in ``frac/xdc/floorplan.xdc`` describe the same floorplan; change
them together.

The Makefile's other targets (``synth``, ``frac``) drive a conventional
single-image Vivado project. They are not used for the bitstreams in
``example/``.

Build options
~~~~~~~~~~~~~

The TCP stack's maximum segment size is set in the Makefile
(``TCP_STACK_MSS``, 8192 bytes). The host's network must carry 8232-byte
frames for it, an MTU of 9000 in our setup. On a network with a 1500-byte MTU,
build the IP with ``make ip TCP_STACK_MSS=1408`` in a fresh ``build/``.

Loading Bitstreams
------------------

Full image
~~~~~~~~~~

``scripts/programfpga.sh <file.bit>`` programs a full image over JTAG with the
Vivado hardware manager. ``VIVADO_ROOT`` selects the Vivado installation and
``HW_TARGET`` the JTAG cable, if the host has more than one.

``scripts/flashfpga.sh <file.bit>`` instead writes the image into the U280's
configuration flash, at the address where the card keeps the image its golden
image boots, so that the card starts fRAC at power-up. This overwrites the
image the card shipped with, such as the XRT shell; the golden image stays as
the fallback. The write takes 10 to 30 minutes, and the image runs after the
next power cycle.

.. warning::

   Both scripts reconfigure the FPGA. If the card is up on PCIe, for example
   running the XRT shell, its link goes down, and some servers answer that
   with a reset. Take the card off the bus and disable its link first;
   ``scripts/flashfpga.sh --help`` shows the commands.

Partial bitstreams
~~~~~~~~~~~~~~~~~~

``scripts/reconfslots.go`` loads a partial bitstream into a slot over the
network, through the reconfiguration controller:

.. code:: sh

   go run ./scripts/reconfslots.go -slot 1 -chunk-size 256 \
       -hbm-addr 0x10004000 -query-status example/frac/icap/c01_f09.bin

It reads the file, pads it to a four-byte boundary, and uploads it into the
FPGA's HBM with ``WRITE_HBM`` commands of at most ``-chunk-size`` bytes. It
then sends ``RECONF_ICAP`` for the slot and waits for the controller's status
response. With ``-query-status`` it also sends ``QUERY_STATUS``, and with
``-post-probe`` it sends the slot a request afterwards. ``-query-only``,
``-read-hbm`` and ``-no-reconf`` query the controller, read HBM back, or stop
after the upload. :doc:`protocol` describes the commands.

================= ==============================================================
Option            Default
================= ==============================================================
``-addr``         ``172.24.1.52:2888``
``-slot``         ``0``; slot N is cell C0N, from 0 to 3
``-hbm-addr``     ``0x4000``; the experiments use ``0x10004000``
``-chunk-size``   ``64``; the experiments use ``256``
``-timeout``      ``10s`` per connection and request
================= ==============================================================

A partial bitstream works only on the full image of its own build. The
controller cannot tell: a partial from another build can report a successful
load and still leave the slot's old function in place.

ICAP Partial-Bitstream Format
-----------------------------

The runtime client and RTL copy file bytes unchanged into HBM and then onto the
32-bit ICAP input. The deployment input must therefore be an ICAP-prepared
partial binary, not a raw ``.bit`` file and not a PCAP-formatted binary. The
``icap/`` files are written with this conversion; the ``.prm`` file beside
each one records it:

.. code:: tcl

   write_cfgmem -force -format BIN -interface SMAPx32 \
       -loadbit "up 0x0 module_partial.bit" module_icap_part.bin

The ICAP form intentionally does not use ``-disablebitswap``; the ``pcap/``
files add it and are a different artifact.

The controller streams the file in this order:

.. code:: text

   HBM beat bits  31:0   -> first ICAP word
   HBM beat bits  63:32  -> second ICAP word
   ...
   HBM beat bits 255:224 -> eighth ICAP word

There is no conversion in the Go client or RTL. Supplying the wrong artifact
format can cause ``PRERROR`` or leave the controller waiting indefinitely.

Recovery
--------

If the host times out waiting for ``RECONF_ICAP``, the hardware may still be
active and the selected slot may remain decoupled. There is no independent
status channel or abort command while the controller is busy. Recovery currently
requires diagnosing ICAP/HBM state through hardware debug or resetting and
reprogramming the complete FPGA image.

Because current ``PRERROR`` handling reconnects the slot, software must not assume
that an error leaves the failed partition safely isolated.
