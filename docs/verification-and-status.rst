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
suite. It does not issue an integrated ``RECONF_ICAP`` or ``QUERY_STATUS`` request.

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
-  Integrated ICAP operation and post-reconfiguration slot traffic.
-  Every slot and every supported module/slot combination.
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
-  The controller has no per-slot reset output.
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
