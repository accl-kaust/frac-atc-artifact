Reproducing Results
===================

This guide explains how to reproduce results comparable to those presented in
the paper. We provide access to two test setups. In the latency and throughput
experiments, the CPU host and FPGA are wired directly, without a switch. The
remaining experiments use a switch between them.

Each experiment below is measured with ``eval/run.py`` and plotted with
``eval/plot.py``. ``run.py`` writes every run to a new directory under
``eval/<experiment>/results/`` and points ``results/latest`` at it.
``plot.py`` plots that newest run and writes the figure, such as
``latency_throughput_fig_13.pdf``, into the run's directory, next to its logs.
Pass ``--run <directory>`` to plot an older run, and ``--out <directory>`` to
put the figure somewhere else.

The figure scripts need numpy, matplotlib, pandas and scipy:

.. code-block:: sh

  $ python3 -m pip install numpy matplotlib pandas scipy

To plot on another machine, copy the run's directory to a checkout of this
repository there and pass its path with ``--run``.

Testbed
-------

The latency–throughput experiment uses a testbed without a network switch.
To access the testbed machine:

.. code-block:: sh

   $ ssh atcae@kw61160.tailef7cee.ts.net


Latency Throughput (Figure 13)
------------------------------

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ NIC=enp33s0f0np0
  $ sed -i -E 's/^(nic:[[:space:]]*)"[^"]*"/\1"'"$NIC"'"/' eval/testbed.yaml && grep -n '^nic:' eval/testbed.yaml
  $ python3 eval/run.py latency_throughput
  $ python3 eval/plot.py latency_throughput


The remaining experiments use a testbed with a network switch. To access this machine:

.. code-block:: sh

   $ ssh atcae@acclnode14.tailef7cee.ts.net


Mixed Workload (Figure 14)
--------------------------

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ NIC=enp33s0f1np1
  $ sed -i -E 's/^(nic:[[:space:]]*)"[^"]*"/\1"'"$NIC"'"/' eval/testbed.yaml && grep -n '^nic:' eval/testbed.yaml
  $ python3 eval/run.py mixed_workload
  $ python3 eval/plot.py mixed_workload


Reassembly (Figure 15)
----------------------

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ NIC=enp33s0f1np1
  $ sed -i -E 's/^(nic:[[:space:]]*)"[^"]*"/\1"'"$NIC"'"/' eval/testbed.yaml && grep -n '^nic:' eval/testbed.yaml
  $ python3 eval/run.py reassembly
  $ python3 eval/plot.py reassembly


Scalability (Figure 16)
-----------------------

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ NIC=enp33s0f1np1
  $ sed -i -E 's/^(nic:[[:space:]]*)"[^"]*"/\1"'"$NIC"'"/' eval/testbed.yaml && grep -n '^nic:' eval/testbed.yaml
  $ python3 eval/run.py scalability
  $ python3 eval/plot.py scalability


Azure Trace (Figure 17)
------------------------

.. code-block:: sh

  $ cd ~/frac-atc-artifact
  $ NIC=enp33s0f1np1
  $ sed -i -E 's/^(nic:[[:space:]]*)"[^"]*"/\1"'"$NIC"'"/' eval/testbed.yaml && grep -n '^nic:' eval/testbed.yaml
  $ python3 eval/run.py azure_trace
  $ python3 eval/plot.py azure_trace









