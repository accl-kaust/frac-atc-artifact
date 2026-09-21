fRAC
====

fRAC enables request-level, in-network invocation of FPGA accelerators. Remote
clients send application requests over the network, and fRAC reassembles the
request data, schedules requests to accelerators, and returns their results.
Accelerators can be swapped at runtime through partial reconfiguration, allowing
the FPGA to serve different workloads as requirements change.

.. toctree::
   :maxdepth: 2
   :hidden:

   quick-start
   reconfiguration-controller
   protocol
   build-and-deployment
   verification-and-status

Request-Level Acceleration
--------------------------

An accelerator invocation operates on an application request, which may span
multiple network packets. fRAC adds request framing, reassembly, and scheduling
above the transport layer so that accelerator invocation follows request
boundaries.

The request header identifies the workload and carries the information needed
to track request completion. The reassembly logic associates incoming data with
its request, and the scheduler coordinates delivery to the accelerator slots.
Results pass back through the network stack to the requesting client.

Network Architecture
--------------------

fRAC uses `EasyNet <https://github.com/fpgasystems/Vitis_with_100Gbps_TCP-IP>`_
for its TCP transport layer. EasyNet provides the foundation for the project's
100 Gb/s network stack; fRAC builds request reassembly and accelerator scheduling
on top of that transport.

Parts of the EasyNet networking infrastructure below TCP have been replaced
with components from `Corundum <https://github.com/corundum/corundum>`_. The
resulting stack places EasyNet’s TCP functionality between Corundum’s lower-layer
components and fRAC’s request-processing logic.

.. figure:: figures/frac-architecture.*
   :alt: fRAC architecture showing the network stack, dispatcher, reassembly
         buffers, selector, accelerator slots, response path, and a
         reconfiguration controller that loads bitstreams from DRAM.
   :align: center
   :width: 100%

   fRAC architecture (Figure 10 from the fRAC paper). The dispatcher routes
   request fragments into reassembly buffers, and the selector forwards
   assembled requests to accelerator slots. Responses return through the network
   stack, while the reconfiguration controller manages accelerator replacement.

Runtime Accelerator Replacement
--------------------------------

Accelerators occupy reconfigurable slots. Partial reconfiguration replaces the
accelerator in a selected slot while keeping the static network and request
infrastructure configured.

fRAC also exposes reconfiguration through the network. A client uploads a partial
bitstream into FPGA-attached memory and sends a reconfiguration command. The
hardware controller isolates the selected slot, streams the bitstream into the
FPGA's internal configuration port, and reports the result. See
:doc:`reconfiguration-controller` for the controller architecture and
:doc:`build-and-deployment` for the current bitstream-generation workflow.

Design Philosophy and Influences
---------------------------------

`Corundum <https://github.com/corundum/corundum>`_ and
`Taxi <https://github.com/fpganinja/taxi>`_ have strongly influenced how fRAC is
organized and developed. Following their example, the project aims to minimize
dependence on vendor IP, favor reusable RTL components, and use cocotb for
simulation and verification.

These choices make the design easier to inspect, modify, and exercise in
simulation. Vendor IP remains part of the implementation where needed for the
target FPGA. The :doc:`verification-and-status` page describes the existing
cocotb suites and their coverage.
