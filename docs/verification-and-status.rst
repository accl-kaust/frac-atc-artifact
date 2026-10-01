Verification and Implementation Status
======================================

Test Environment
----------------

The simulation tests use Python, cocotb, cocotb-test, cocotbext-axi, pytest, and
Verilator. The repository does not currently contain a pinned Python requirements
file for these tests, so a release should record the exact package and Verilator
versions used.

Controller Unit Tests
---------------------

Run the controller-only cocotb suite from the standalone repository root:

.. code:: sh

   make -C kernels/user_krnl/reconfctrl/tb

Enable FST wave generation with:

.. code:: sh

   make -C kernels/user_krnl/reconfctrl/tb WAVES=1

This testbench compiles ``reconfctrl.v`` directly and models HBM and the ICAP
stream. It does not compile the physical ``ICAPE3`` wrapper. The checked-in suite
covers:

-  A 96-byte HBM write and final-byte strobes.
-  A 64-byte HBM read.
-  A ten-word ICAP transfer.
-  A 16-beat ICAP burst followed by a tail burst.
-  Unaligned address rejection.
-  Selected-slot decoupling.
-  Waiting for ``PRDONE``.
-  ``PRERROR`` reporting.
-  Invalid slot rejection.
-  Idle status query.
-  Status query after successful reconfiguration.

The checked-in ``results.xml`` records 11 passing tests for this suite.

Network Integration Tests
-------------------------

Run the reassembly and controller integration suite with:

.. code:: sh

   make -C kernels/user_krnl/reassembly/tb

The suite compiles the request dispatcher, scheduler, slot routing, controller,
simulation ICAP wrapper, and simulated slot cells. Controller-related coverage
includes:

-  Routing workload ``0x00ab`` to the controller.
-  HBM write and read requests over the network request path.
-  Command size controlling the number of meaningful write bytes.
-  Ignoring padded bytes after a write.
-  Returning exactly one response per request.
-  Repeated controller requests over a connection.
-  Draining excess request packet data after a controller response.

The checked-in ``results.xml`` records 18 passing tests for the complete integration
suite. It does not issue an integrated ``QUERY_STATUS`` request; ``test_slots``
below issues an integrated ``RECONF_ICAP``.

The same run includes ``test_multiclient``, which drives several connections at
once through a model of the TOE's shared RX FIFO and checks that every response
comes back whole, exactly once, on its own connection, announced with its own
length:

-  One-segment requests from one, four, and sixteen clients, the last with two
   requests in flight each, and single-line requests back to back with
   multi-line ones.
-  Requests framed as ``sw/app`` frames them, a header segment and then the
   data, from two and four clients.
-  A TX side that refuses requests for want of window or for a closed
   connection.
-  The same with the stack's answers delayed 0 to 40 cycles and the TX
   metadata stalled a third of the time, so the answer to a request issued
   ahead lands at every point of the response before it, its last beat
   included; each way of going on from a response must occur.
-  The concurrent-request limit below, as an expected failure.

And ``test_throughput``: back-to-back 4 KB echoes from 16 connections against a
cycle-level TOE whose status comes 18 cycles after the request and at most one
per 8 cycles, as measured in xsim on the TOE's HLS RTL and the network
kernel's FIFOs. It requires every response intact and at least 0.97 beats of
TX data a cycle; ``pkt_sender`` reaches 0.985 (the scheduler's re-grant is the
cycle left), where waiting out the round trip for each response gave 0.736.
It runs once with every request to C00 and once with four connections to each
of the four slots, which the output switch takes in turn: 0.985 both times.

And ``test_slots``, on the four slots and their credit links (in the bench C00
and C02 echo, C01 and C03 OR every line with all ones, and each cell counts the
request beats it is sent):

-  Workloads 0 to 3 reach C00 to C03 and any other reaches C00.
-  Eight connections over the four slots with up to eight requests in flight
   each, while the stack takes response data a quarter of the time: every
   slot's request and response links run out of credits for thousands of
   cycles, and every response comes back whole, once, on its own connection.
-  ``RECONF_ICAP`` of slot 2 from a 32 KB stand-in bitstream: while it is
   decoupled C02 is held in reset and sent nothing, C00 keeps answering and a
   request for C02 waits; afterwards that request is answered, and C02 takes
   4 KB requests, which need all 64 credits, back to back.

An additional direct SystemVerilog HBM-write test is available:

.. code:: sh

   make -C kernels/user_krnl/reassembly/tb sv-write-hbm

Missing Verification
--------------------

The following cases are not covered by the current automated tests:

-  Unknown opcode and every validation-error priority combination.
-  Zero size, reads larger than 64 bytes, and ICAP sizes not divisible by four.
-  Addresses above the implemented range, end-address overflow, and HBM-capacity
   overflow.
-  AXI ``BRESP``, ``RRESP``, and ``RLAST`` fault paths in network integration.
-  Bursts beginning near a 4 KiB boundary.
-  Sustained HBM or ICAP backpressure and FIFO-full behavior.
-  ``AVAIL=0`` behavior.
-  Missing, simultaneous, or delayed ``PRDONE`` and ``PRERROR``.
-  Reset during HBM upload or ICAP reconfiguration.
-  Every supported module/slot combination.
-  A request already in a slot or its pipeline when decoupling is asserted.
-  ICAP bit and byte ordering against the physical U280 configuration engine.
-  Very large partial bitstreams.
-  Go command serialization and status decoding.
-  Authentication, artifact compatibility, digest failure, and replay handling.

Current Implementation Limitations
----------------------------------

Reconfiguration Safety
~~~~~~~~~~~~~~~~~~~~~~

-  The target slot is decoupled immediately. No busy/idle handshake proves that
   in-flight accelerator work or the surrounding pipeline has drained.
-  The controller has no per-slot reset output. The slot's boundary logic
   (``slot_boundary.v``) holds the cell in reset while the slot is decoupled, so
   a newly loaded module starts empty, and a request on its way to the cell or
   a response not yet taken when the slot is decoupled is lost.
-  ``PRERROR`` clears the selected decouple bit, reconnecting a potentially invalid
   module.
-  There is no timeout while waiting for ``PRDONE`` or ``PRERROR``.
-  ICAP ``AVAIL`` is observable but does not gate stream transmission.

Error-State Consistency
~~~~~~~~~~~~~~~~~~~~~~~

HBM read errors during the reconfiguration stream generate a status response
without using the normal reconfiguration-finalization path. In that path,
``reconf_active`` and the decouple bit can remain asserted even after the FSM
returns to ``IDLE``. This behavior needs a dedicated regression and a single
failure-cleanup path.

Status Visibility
~~~~~~~~~~~~~~~~~

-  Commands are accepted only in ``IDLE``, so a healthy in-progress operation
   cannot be queried through the same controller.
-  The query response does not include the active slot, FSM state, decouple mask,
   HBM progress, or remaining ICAP words.
-  The Go client does not decode the structured query response.
-  ``last_error`` can describe a non-PR command while ``last_slot_id`` and cycle count
   still describe an earlier PR operation.

Addressing and AXI
~~~~~~~~~~~~~~~~~~

-  The 33-bit controller range is larger than the configured 4 GiB HBM capacity.
-  ``address + size`` is not checked for overflow or memory bounds.
-  Reconfiguration bursts are not shortened to avoid crossing a 4 KiB boundary.
-  The HBM staging region is a client convention, not a hardware-enforced
   allocation.
-  Command and payload ``tkeep``/``tlast`` are ignored.

Concurrent Requests
~~~~~~~~~~~~~~~~~~~

-  A request that spans several TCP segments holds one of the scheduler's four
   queues (``QUEUE_NUM``) and one of the dispatcher's eight contexts
   (``CTX_NUM``) until its last segment arrives. The TOE hands every
   connection's segments over in one in-order stream, so one more multi-segment
   request while all queues are held stalls the receive path for good: the
   segments that would finish the others are behind it. A request written in
   one piece and no longer than the TOE's MSS takes no queue, however many
   clients send them.
-  A request must start at a TCP segment boundary; two requests coalesced into
   one segment are not separated.
-  At most one request is issued ahead of the response being sent, and only
   behind its final piece, so the stack's round trip is hidden for responses of
   about 1.4 KB and up; shorter ones still wait out part of it.

DFX Build
~~~~~~~~~

-  The regular Make flow does not apply the PR XDC or insert RM checkpoints.
-  The YAML manifests have no checked-in orchestration command.
-  Checked-in floorplan descriptions disagree for C02.
-  The experimental bit-generation script does not generate all slots and module
   variants.
-  Existing full and partial artifacts do not have a compatibility manifest.
-  Archived timing reports in the wider workspace show negative slack and are not
   evidence of a timing-clean release.

Security
~~~~~~~~

-  Network clients can write HBM and invoke ICAP without authentication.
-  The controller does not restrict HBM ranges by operation or client.
-  No digest, signature, artifact ID, static-image ID, or anti-replay field is
   present.
-  The controller cannot reject a partial image intended for another slot or
   static image before sending it to ICAP.

Intended Safety Sequence
------------------------

The controller should ultimately implement and verify this sequence:

1.  Authenticate and validate the command and artifact metadata.
2.  Stop dispatching new requests to the selected slot.
3.  Wait for the slot and all boundary pipelines to report idle.
4.  Assert slot reset and input/output decoupling.
5.  Verify ICAP availability and the permitted HBM range.
6.  Stream a size- and digest-validated image with bounded AXI transactions.
7.  Wait for ``PRDONE`` or a bounded timeout; treat ``PRERROR`` as failure.
8.  On success, initialize the module, release reset and decoupling, and resume
    dispatch.
9.  On failure, keep the slot isolated and expose a recovery/status interface.
10. Record slot, artifact, result, timing, and error information.

Release Checklist
-----------------

A controller and partial image should not be described as deployable until:

-  Static and reconfigurable checkpoints are built by a reproducible command.
-  The full image and partial image share the same locked static implementation.
-  The artifact manifest identifies the slot, module, floorplan, tool version,
   size, and digest.
-  DFX verification and full DRC pass.
-  Static and all reconfigurable configurations meet timing.
-  ICAP format and word ordering are verified on hardware.
-  HBM upload, successful PR, post-PR workload behavior, ``PRERROR``, timeout, and
   recovery are tested on the U280.
-  In-flight request behavior is tested and matches the documented safety
   contract.
-  All slots and supported module combinations are covered.
-  The network control path is deployed only within its documented trust model.
