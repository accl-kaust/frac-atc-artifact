"""Compute the rows of processed_latency_cache.txt with numpy, the way
scalability_fig_16.py computes them, so that the figure script finds its
numbers cached and only draws.

The figure script parses every per-request latency in pure Python and reads
each file four times, which takes very long once every client's samples are
kept.  This follows its rules exactly:

  * the directories data/scalability/top_k_<k>_inst/rr_d_*_m_<m>_n_*_f_1_O_<O>,
    O being 1 for fRAC, 2 for the CPU and 3 for the DPU, grouped by the n in
    their path.  For fRAC n is the clients of one accelerator, so there are n
    times k in all; for the CPU and the DPU n is every client;
  * in every *.txt file, the first quarter of the lines dropped;
  * latencies in ns divided by 1000, and the 25th, 50th, 75th, 90th, 95th and
    99th percentiles taken over every remaining sample of a group.

The fRAC rows come from the scalability experiment, and the CPU rows from
scalability_cpu, whose newest run eval/plot.py merges in.  There are no DPU
runs here: their rows stay out, and the figure script, looking for them
itself, finds nothing either.  eval/plot.py runs this in the same scratch
directory as the figure script, just before it.
"""
import glob
import os
import re

import numpy as np

try:
    import pandas as pd
except ImportError:
    pd = None

BASE = "data/scalability"
CONFIGS = (("1_accel", 1, 1), ("2_accel", 2, 1), ("4_accel", 4, 1),     # name, k, O
           ("1_cpu", 1, 2), ("2_cpu", 2, 2), ("4_cpu", 4, 2),
           ("1_dpu", 1, 3), ("2_dpu", 2, 3), ("4_dpu", 4, 3))
SIZES = (1024, 4096)
PERCENTILES = (25, 50, 75, 90, 95, 99)


def read_ns(path):
    """One latency file: a number of nanoseconds per line."""
    if pd is not None:
        try:
            return pd.read_csv(path, header=None, dtype=np.float64, engine="c").iloc[:, 0].to_numpy()
        except pd.errors.EmptyDataError:
            return np.empty(0)
    return np.fromfile(path, dtype=np.float64, sep=" ")


def directory_us(directory):
    """A directory's latencies in µs as the figure script keeps them, or None."""
    kept = []
    for path in glob.glob(os.path.join(directory, "*.txt")):
        values = read_ns(path)
        kept.append(values[len(values) // 4:])
    if not kept:
        return None
    values = np.concatenate(kept)
    return values / 1000.0 if values.size else None


def rows(k, machine, size):
    """(clients, p25, median, p75, p90, p95, p99) per client count."""
    groups = {}
    pattern = os.path.join(BASE, f"top_k_{k}_inst", f"rr_d_*_m_{size}_n_*_f_1_O_{machine}")
    for directory in glob.glob(pattern):
        match = re.search(r"n_(\d+)", directory)
        groups.setdefault(int(match.group(1)) if match else 0, []).append(directory)
    found = []
    for threads, directories in sorted(groups.items()):
        parts = [part for part in map(directory_us, directories) if part is not None]
        if parts:
            values = np.concatenate(parts)
            clients = threads * k if machine == 1 else threads
            found.append((clients,) + tuple(np.percentile(values, PERCENTILES)))
    return sorted(found)


def main():
    lines = ["# Cached latency data",
             "# Format: config_name,msg_size,clients,p25,median,p75,p90,p95,p99"]
    for name, k, machine in CONFIGS:
        for size in SIZES:
            for clients, *values in rows(k, machine, size):
                lines.append(f"{name},{size},{clients}," + ",".join(f"{v:.3f}" for v in values))
    path = os.path.join(BASE, "processed_latency_cache.txt")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"fast_cache.py: wrote {len(lines) - 2} rows to {path}")


if __name__ == "__main__":
    main()
