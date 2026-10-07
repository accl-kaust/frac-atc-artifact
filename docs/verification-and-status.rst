Verification and Implementation Status
======================================

Test Environment
----------------

The simulation tests use Python, cocotb, cocotb-test, cocotbext-axi, pytest, and
Verilator. ``kernels/user_krnl/requirements.txt`` pins the Python packages at
the versions we ran the suites with, and we used Verilator 5.034:

.. code:: sh

   python3 -m pip install -r kernels/user_krnl/requirements.txt

Controller Unit Tests
---------------------

Run the controller-only cocotb suite from the standalone repository root:

.. code:: sh

   make -C kernels/user_krnl/reconfctrl/tb

Enable FST wave generation with:

.. code:: sh

   make -C kernels/user_krnl/reconfctrl/tb WAVES=1

This testbench compiles ``reconfctrl.v`` directly and models HBM and the ICAP
stream. It does not compile the physical ``ICAPE3`` wrapper. The suite covers:

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

Its 10 tests pass; cocotb writes their results to ``results.xml`` in the
testbench directory.

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

The complete integration suite has 41 tests, in ``test_reassembly``,
``test_multiclient``, ``test_throughput`` and ``test_slots``, and they pass. It
does not issue an integrated ``QUERY_STATUS`` request; ``test_slots`` below
issues an integrated ``RECONF_ICAP``.

The same run includes ``test_multiclient``, which drives several connections at
once through a model of the TOE's shared RX FIFO and checks that every response
comes back whole, exactly once, on its own connection, announced with its own
length:

-  One-segment requests from one, four, and sixteen clients, the last with two
   requests in flight each, and single-line requests back to back with
   multi-line ones.
-  Requests framed as a header segment and then the data, from two and four
   clients.
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

Accelerator Tests
-----------------

Each accelerator in ``kernels/user_krnl/apps`` has its own cocotb suite, run at
one of two levels:

.. code:: sh

   make -C kernels/user_krnl/apps/log/tb               # log_core alone
   make -C kernels/user_krnl/apps/log/tb LEVEL=slot    # the module in its slot

``LEVEL=core``, the default, drives ``<name>_core`` directly: every handshake,
the sideband and the cycle timing. ``LEVEL=slot`` builds the module as it goes
into a cell and drives it through the static side of its slot
(``reassembly/tb/tb_slot.sv``): ``slot_boundary``'s request source, response
sink and 16 register stages each way, with credit flow control. The boundary
carries no sideband, so the sideband checks run at ``LEVEL=core`` only.
``log`` and ``norm`` run against ``tb/fp_stubs.v``: invertible integer
operations at the floating-point cores' latencies, which pin the dataflow but
not the IEEE-754 arithmetic.

Beyond each response against a reference model, the suites check how long a
request takes. ``top_k`` takes a line every cycle and answers 19 cycles after
the request's last line, however long the request (10 for one line, 14 for
two). ``log`` streams a value every cycle and answers its first line 84 cycles
after taking it and the rest one every 16. ``norm`` scans a line every cycle
and answers 65 cycles after the last line, then one line every 16. A 4 KB
request is checked end to end in each. ``log`` and ``norm`` hold their
responses in an output FIFO and take no line they could not answer; the suites
stall the sink to check that, and reset each module with several lines in its
pipeline.

An additional direct SystemVerilog HBM-write test is available:

.. code:: sh

   make -C kernels/user_krnl/reassembly/tb sv-write-hbm

Hardware Correctness Check
--------------------------

``scripts/checkfuncs.sh`` checks the accelerators on the U280 itself. It loads
top_k, norm and log into every slot in turn, sends each slot requests of known
data with ``scripts/checkfuncs.go``, and compares every answer word with what
the host computes for it. norm must match bit for bit; log may differ in the
last place, because the Xilinx logarithm core does not round correctly.

.. code:: sh

   BIT=example/frac/jtag/frac.bit ICAP=example/frac/icap scripts/checkfuncs.sh

``BIT`` programs that full image first. Without it the script checks the image
already on the FPGA, which must come from the same build as the partials in
``ICAP``. The script takes the testbed lock that ``eval/run.py`` takes, and
leaves the slots holding the last unit it checked.

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
-  Every module/slot combination in simulation; on the U280,
   ``scripts/checkfuncs.sh`` covers top_k, norm and log in every slot.
-  A request already in a slot or its pipeline when decoupling is asserted.
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

-  ``spinhdl weave`` builds the full image and every partial bitstream of every
   cell from one static implementation, and the build in ``example/`` meets
   timing in every configuration. The bitstreams carry no manifest that binds
   a partial to its full image, though, so a partial from another build can
   be loaded, and the controller reports success even then.

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

Open Items
----------

The prototype covers what the paper evaluates: the full image and the partial
bitstreams come from one reproducible build, meet timing, and load and run on
the U280 in every slot. Before the reconfiguration path is used outside a
trusted testbed, these remain open:

-  A manifest that identifies each partial bitstream's slot, module, floorplan,
   tool version, size, digest and full image, checked before it is loaded.
-  Tests on the U280 of ``PRERROR``, timeouts and recovery.
-  Tests of requests in flight when a slot is decoupled, against the safety
   sequence above.
-  Authentication on the network control path, or deployment only on a trusted
   network.
