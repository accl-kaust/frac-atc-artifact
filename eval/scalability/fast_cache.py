"""Compute the 1, 2 and 4 accelerator rows of processed_latency_cache.txt with
numpy, the way scalability_fig_16.py computes them, so that the figure script
finds its numbers cached and only draws.

The figure script parses every per-request latency in pure Python and reads
each file four times, which takes very long once every client's samples are
kept.  This follows its rules exactly:

  * the directories data/scalability/top_k_<k>_inst/rr_d_*_m_<m>_n_*_f_1_O_1,
    grouped by the n in their path, n times k being the clients;
  * in every *.txt file, the first quarter of the lines dropped;
  * latencies in ns divided by 1000, and the 25th, 50th, 75th, 90th, 95th and
    99th percentiles taken over every remaining sample of a group.

The CPU and DPU rows are left to the figure script: there are no such runs
here, so it finds nothing to read for them.  eval/plot.py runs this in the
same scratch directory as the figure script, just before it.
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
CONFIGS = (("1_accel", 1), ("2_accel", 2), ("4_accel", 4))
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


def rows(k, size):
    """(clients, p25, median, p75, p90, p95, p99) per client count."""
    groups = {}
    pattern = os.path.join(BASE, f"top_k_{k}_inst", f"rr_d_*_m_{size}_n_*_f_1_O_1")
    for directory in glob.glob(pattern):
        match = re.search(r"n_(\d+)", directory)
        groups.setdefault(int(match.group(1)) if match else 0, []).append(directory)
    found = []
    for threads, directories in sorted(groups.items()):
        parts = [part for part in map(directory_us, directories) if part is not None]
        if parts:
            values = np.concatenate(parts)
            found.append((threads * k,) + tuple(np.percentile(values, PERCENTILES)))
    return sorted(found)


def main():
    lines = ["# Cached latency data",
             "# Format: config_name,msg_size,clients,p25,median,p75,p90,p95,p99"]
    for name, k in CONFIGS:
        for size in SIZES:
            for clients, *values in rows(k, size):
                lines.append(f"{name},{size},{clients}," + ",".join(f"{v:.3f}" for v in values))
    path = os.path.join(BASE, "processed_latency_cache.txt")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"fast_cache.py: wrote {len(lines) - 2} accelerator rows to {path}")


if __name__ == "__main__":
    main()
