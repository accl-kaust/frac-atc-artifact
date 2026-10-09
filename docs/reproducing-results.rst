Reproducing Results
===================

This guide explains how to reproduce the paper's evaluation (Section 5,
Figures 13 to 18) with the prebuilt bitstreams in ``example/``. Each
experiment is one command to measure and one to plot:

.. list-table::
   :header-rows: 1
   :widths: 14 22 22 14 28

   * - Figure
     - Experiment
     - Testbed
     - Time
     - Results on disk
   * - 13
     - ``latency_throughput``
     - kw61160
     - 32 min
     - 1 MB
   * - 14
     - ``mixed_workload``
     - acclnode14
     - 10 min
     - < 1 MB
   * - 15
     - ``reassembly``
     - acclnode14
     - 9 min
     - < 1 MB
   * - 16, 17
     - ``scalability``
     - acclnode14
     - 22 min
     - 5 GB
   * - 16 (CPU)
     - ``scalability_cpu``
     - acclnode14 and a server machine
     - 32 min
     - 1 GB
   * - 18
     - ``azure_trace``
     - acclnode14
     - 62 min
     - 8 MB

The times are ``eval/run.py``'s own estimates, which ``--dry-run`` prints; the
runs need no attention while they last. ``eval/run.py`` writes every run to a
new directory under ``eval/<experiment>/results/`` and points
``results/latest`` at it. ``eval/plot.py`` plots that newest run and writes
the figure, such as ``latency_throughput_fig_13.pdf``, into the run's
directory, next to its logs. Pass ``--run <directory>`` to plot an older run,
and ``--out <directory>`` to put the figure somewhere else.

Testbeds
--------

We provide access to two testbeds. In the latency and throughput experiment
(Figure 13), the CPU host and the FPGA are wired directly, without a switch.
To access this machine:

.. code-block:: sh

   $ ssh atcae@kw61160.tailef7cee.ts.net

The remaining experiments use a testbed with a network switch. To access this
machine:

.. code-block:: sh

   $ ssh atcae@acclnode14.tailef7cee.ts.net

Both are set up as in :doc:`quick-start`, with the repository checked out in
``~/frac-atc-artifact``.

Before You Start
----------------

kw61160 and acclnode14 each have their own checkout, so do these steps twice:
once on kw61160, before Figure 13, and once on acclnode14, before Figures 14
to 18.

Install the Python Packages (Skip to the next section)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The packages are already installed on our testbeds. Elsewhere, Ubuntu 24.04
refuses ``pip install`` into the system Python, so use a virtual environment:

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ python3 -m venv ~/frac-venv
  $ . ~/frac-venv/bin/activate
  $ python3 -m pip install -r eval/requirements.txt

After every new login, activate it again with ``. ~/frac-venv/bin/activate``
before running ``eval/run.py`` or ``eval/plot.py``. ``eval/run.py`` needs only
PyYAML; ``eval/plot.py`` and the figure scripts need the rest. To plot on
another machine, copy the run's directory to a checkout of this repository
there and pass its path with ``--run``.

Set the Network Interface
~~~~~~~~~~~~~~~~~~~~~~~~~

Set the interface that faces the FPGA in ``eval/testbed.yaml``. On kw61160:

.. code-block:: sh

  $ NIC=enp33s0f0np0
  $ sed -i -E 's/^(nic:[[:space:]]*)"[^"]*"/\1"'"$NIC"'"/' eval/testbed.yaml && grep -n '^nic:' eval/testbed.yaml

On acclnode14:

.. code-block:: sh

  $ NIC=enp33s0f1np1
  $ sed -i -E 's/^(nic:[[:space:]]*)"[^"]*"/\1"'"$NIC"'"/' eval/testbed.yaml && grep -n '^nic:' eval/testbed.yaml

``eval/testbed.yaml`` also holds the FPGA's address, the JTAG target, and where
``tpa`` and ``fperf`` are; the defaults suit a host set up as in
:doc:`quick-start`.

Each experiment's ``--dry-run`` prints every command it would run and its
time estimate, and touches nothing:

.. code-block:: sh

  $ python3 eval/run.py latency_throughput --dry-run

.. note::

   ``eval/run.py`` reprograms the FPGA over JTAG and loads partial bitstreams,
   so it replaces whatever the FPGA was running; it refuses to start while
   another ``eval/run.py`` or ``scripts/checkfuncs.sh`` uses the testbed.
   fperf needs root for DPDK, so ``eval/run.py`` asks for your sudo password
   once and keeps sudo's timestamp fresh until the sweep ends. A run that is
   interrupted can be finished with ``--resume``, which keeps its complete
   logs.

Latency vs Throughput (Figure 13)
---------------------------------

On kw61160:

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ python3 eval/run.py latency_throughput
  $ python3 eval/plot.py latency_throughput

Two images answer 4 KB requests from 1 to 28 clients, 30 seconds per point:
the baseline without fRAC (``example/bypass/frac.bit``), whose TCP stack
echoes each request itself, and fRAC with ``pattern_slot`` echoing in slot 0.
The FPGA is programmed again before every run.

Expected: fRAC's latency is within about 0.3 µs of the baseline's at every
load, both reach about 91 Gb/s from 24 clients on, and the median latency
stays below 10 µs.

A shorter run with 1 and 22 clients, about 8 minutes, checks the setup first:

.. code-block:: sh

  $ python3 eval/run.py latency_throughput -c smoke.yaml
  $ python3 eval/plot.py latency_throughput -c smoke.yaml

Mixed Workload (Figure 14)
--------------------------

On acclnode14:

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ python3 eval/run.py mixed_workload
  $ python3 eval/plot.py mixed_workload

Top-K, Logit, Norm and the CNN each get a slot. Each first runs alone with one
client, then all four run at once, 30 seconds each.

Expected: each function's latency is nearly the same alone and in the mix;
about 7.7 µs for Top-K (8.2 µs in the mix), 9.3 µs for Logit and Norm, and
8.6 ms for the CNN.

Reassembly (Figure 15)
----------------------

On acclnode14:

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ python3 eval/run.py reassembly
  $ python3 eval/plot.py reassembly

One client sends Top-K, Logit and Norm requests of 1, 2 and 4 KB, each written
1 KB at a time, so a request arrives in 1, 2 or 4 pieces that fRAC reassembles.
The "Without Reassembly (emu)" bars are not measured: the figure script takes
the one-piece latency times the number of pieces.

Expected: latency grows less than linearly with the number of pieces, so
every measured bar stays well below its emulated one.

Scalability and Tail Latency (Figures 16 and 17)
------------------------------------------------

On acclnode14:

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ python3 eval/run.py scalability
  $ python3 eval/plot.py scalability

Top-K is loaded into all four slots. 1 to 28 clients send 1 KB and 4 KB
requests to 1, 2 or 4 of them, with the clients split evenly. Every request's
latency is kept, which is where the 5 GB go. ``plot.py`` draws both
figures: Figure 16 from every point, Figure 17 from the 4 KB points with 28
clients.

Expected: fRAC's latency stays nearly flat up to 28 clients, from about 7.7
to 8.7 µs for 1 KB requests and from 8.4 µs to 10 to 12 µs for 4 KB requests;
at 28 clients the 99th percentile stays within about 1 µs of the median.

Figure 16's CPU curves come from the next experiment, whose newest run
``plot.py`` adds when there is one. The paper's DPU curves are not part of
this artifact.

CPU Baseline (Figure 16)
------------------------

On acclnode14, with a second machine as the server:

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ python3 eval/run.py scalability_cpu
  $ python3 eval/plot.py scalability

The requests of the scalability experiment, 1 KB and 4 KB from 1 to 28
clients, go to a CPU server instead of the FPGA: fperf's own server, which
computes Top-K in software (``qsort`` in libtpa's ``app/fperf/offrac.c``),
answers with the same 64 bytes, and runs its threads on 1, 2 or 4 cores.
``eval/run.py`` starts a fresh server on the server machine over ssh before
each point and stops it after. ``eval/plot.py scalability`` draws Figure 16
from the newest run of both experiments; ``eval/plot.py scalability_cpu``
draws the same figure.

First set up the server in ``eval/testbed.yaml``, from the ``server`` section
of ``eval/testbed.example.yaml``:

.. code-block:: yaml

  server:
    host: atcae@<server machine>    # TODO(authors)
    addr: <its port's address>      # TODO(authors)
    nic: <that port>                # TODO(authors)

The server machine needs libtpa built as in :doc:`quick-start`, its port on
the same switch with an MTU of 9000, 8 GB of hugepages and about 20 GB of
free memory besides (fperf's server never frees most of its request buffers;
a machine that swaps would slow the CPU curves down), a key-based ssh login
from acclnode14, and sudo without a password, since ``eval/run.py`` starts
and stops the server without a terminal. ``--dry-run`` prints the server's
commands too.

Expected: the CPU's latency grows with the number of clients, and more cores
only slow that growth, staying well above fRAC's. In the paper's runs, the
median at 28 clients was about 146 µs on one core and 41 µs on four for 1 KB
requests (14 µs with one client), and 625 µs and 162 µs for 4 KB requests
(30 µs with one client).

Azure Trace (Figure 18)
-----------------------

On acclnode14:

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ python3 eval/run.py azure_trace
  $ python3 eval/plot.py azure_trace

Top-K, Logit, the CNN and Norm are loaded into slots 0 to 3, and one client
replays ``eval/azure_trace/processed_trace.csv``, the busiest hour of the
Azure Functions trace, one request at a time; the replay takes as long as the
trace, about an hour. ``eval/azure_trace/experiment.yaml`` describes how the
trace was derived.

Expected: Top-K, Logit and Norm requests complete within a few tens of
microseconds and the CNN's at about 8.6 ms, with every curve rising steeply.
The right panel follows the CNN: it starts just below the fastest CNN
request.

