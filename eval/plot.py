#!/usr/bin/env python3
"""Plot one experiment's results with its figure scripts.

    eval/plot.py latency_throughput                           # the newest run
    eval/plot.py latency_throughput --run 2026-10-02T153012
    eval/plot.py latency_throughput --run DIR --out FIGDIR    # any directory of logs

The figure scripts are the paper's, copied unchanged from
github.com/accl-kaust/frac_evaluation_script.  Each reads its logs from
fixed paths such as data/latency_throughput under the directory it runs in.
plot.py runs each script in a scratch directory where the config's `data`
entries make those paths lead to the run's logs, to an empty directory, or
to another run, after applying the config's `set` entries to module
constants such as FILE_PREFIX.  A `merge` entry adds the newest run of
another experiment to such a path, such as a baseline measured on its own,
so that one figure shows both.  The figure lands next to the logs, or in
--out, together with what the script printed, saved as <script>.out.

plot.py needs numpy and matplotlib, which eval/run.py does not, so it can
run on another machine: copy the run directory there and pass it to --run.
"""
import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile

from common import (DEFAULT_CONFIG, EVAL_DIR, ConfigError, Experiment, abs_path,
                    find_experiment, log_complete, read_yaml, rel, trace_replayed)

FIGURE_TYPES = (".pdf", ".png", ".svg")


def run_params(exp, run_dir):
    """The params the run was measured with, from its manifest when it has one."""
    path = os.path.join(run_dir, "manifest.yaml")
    if os.path.isfile(path):
        params = read_yaml(path).get("params")
        if isinstance(params, dict):
            return {str(key): value for key, value in params.items()}
    return dict(exp.params)


def set_constant(source, name, value, script):
    """`source` with its top-level `name = ...` line assigning `value`, quoted
    when the original value is a string literal."""
    line = re.compile(r"^%s[ \t]*=[ \t]*(.*)$" % re.escape(name), re.M)
    found = line.findall(source)
    if len(found) != 1:
        raise ConfigError(f"{rel(script)}: expected one top-level line {name} = ..., "
                          f"found {len(found)}")
    literal = repr(value) if found[0].lstrip()[:1] in ("'", '"') else value
    return line.sub(lambda match: f"{name} = {literal}  # set by eval/plot.py", source, count=1)


def prepared_source(spec, params):
    """The figure script's source with the config's `set` entries applied."""
    try:
        with open(spec.script) as f:
            source = f.read()
    except OSError as e:
        raise ConfigError(f"cannot read {rel(spec.script)}: {e.strerror}")
    for name, template in spec.settings.items():
        try:
            value = template.format(**params)
        except (KeyError, IndexError, ValueError) as e:
            raise ConfigError(f"{rel(spec.script)}: set.{name} cannot be filled from "
                              f"the run's params: {e!r}")
        source = set_constant(source, name, value, spec.script)
    return source


def resolve_data(spec, run_dir):
    """Where each path the figure script reads leads, with directories checked."""
    resolved = {}
    for path, (kind, target) in spec.data.items():
        if kind == "dir":
            target = abs_path(target, run_dir)
            if not os.path.isdir(target):
                raise ConfigError(f"plot {os.path.basename(spec.script)}: data.{path}: "
                                  f"{target} is not a directory")
        resolved[path] = (kind, target)
    return resolved


def short_logs(directory, complete):
    """The .log files under `directory` that `complete` finds cut short."""
    return sorted(os.path.relpath(os.path.join(folder, name), directory)
                  for folder, _, names in os.walk(directory) for name in names
                  if name.endswith(".log") and not complete(os.path.join(folder, name)))


def resolve_merge(spec):
    """The runs each data path merges: {path: [(experiment, directory)]},
    the newest run of every experiment its merge entry names that has one."""
    script = os.path.basename(spec.script)
    merges = {}
    for path, names in spec.merge.items():
        merges[path] = []
        for name in names:
            latest = os.path.join(find_experiment(name), "results", "latest")
            if os.path.isdir(latest):
                merges[path].append((name, os.path.realpath(latest)))
            else:
                print(f"{script}: there is no {name} run yet to add to {path}")
    return merges


def overlay(dest, sources, skip=(), top=True):
    """Make `dest` a directory holding what all the `sources` directories
    hold: an entry of one source becomes a link to it, and a directory
    several hold a directory again, made the same way.  Of a file several
    hold, the first source's is taken, with a warning below the top level,
    where the runs' own files such as manifest.yaml are.  Names in `skip`
    are left out."""
    os.makedirs(dest, exist_ok=True)
    entries = {}
    for source in sources:
        for name in sorted(os.listdir(source)):
            if name not in skip:
                entries.setdefault(name, []).append(os.path.join(source, name))
    for name, paths in entries.items():
        folders = [path for path in paths if os.path.isdir(path)]
        if len(folders) > 1:
            overlay(os.path.join(dest, name), folders, top=False)
            continue
        if len(paths) > 1 and not top:
            print(f"warning: {len(paths)} runs hold {name}; the figure reads {paths[0]}")
        os.symlink((folders or paths)[0], os.path.join(dest, name))


def plot(spec, source, data, merges, run_dir, out_dir):
    """Run one figure script on `run_dir`; 0 if it wrote a figure, else 1."""
    script = os.path.basename(spec.script)
    stem = os.path.splitext(script)[0]
    printed = os.path.join(out_dir, stem + ".out")
    for name in spec.fresh:
        stale = os.path.join(run_dir, name)
        if os.path.isfile(stale):
            os.remove(stale)
    with tempfile.TemporaryDirectory(prefix="frac-plot-") as stage:
        with open(os.path.join(stage, script), "w") as f:
            f.write(source)
        shutil.copy(os.path.join(EVAL_DIR, "plot_fonts.py"), stage)
        fonts = os.path.join(EVAL_DIR, "fonts")
        if os.path.isdir(fonts):
            os.symlink(fonts, os.path.join(stage, "fonts"))
        for path, (kind, target) in data.items():
            link = os.path.join(stage, path)
            os.makedirs(os.path.dirname(link), exist_ok=True)
            others = [directory for _, directory in merges.get(path, [])]
            if others:
                # A real directory: what the script writes there, such as a
                # cache, stays out of every run, and fresh files from earlier
                # plots of any of them stay out of it.
                mine = {"run": [run_dir], "dir": [target]}.get(kind, [])
                overlay(link, mine + others, skip=spec.fresh)
            elif kind == "empty":
                os.makedirs(link, exist_ok=True)
            else:
                os.symlink(run_dir if kind == "run" else target, link)
        print(f"{script}: plotting {run_dir}", flush=True)
        for runs in merges.values():
            for name, directory in runs:
                print(f"{script}: with {name}'s run {directory}", flush=True)
        env = dict(os.environ, MPLBACKEND="Agg")
        with open(printed, "w") as out:
            for step in spec.prepare + [os.path.join(stage, script)]:
                proc = subprocess.Popen([sys.executable, step], cwd=stage, env=env,
                                        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, errors="replace")
                for line in proc.stdout:
                    sys.stdout.write(line)
                    out.write(line)
                rc = proc.wait()
                if rc != 0:
                    script = os.path.basename(step)
                    break
        figures = [name for name in sorted(os.listdir(stage))
                   if os.path.splitext(name)[1] in FIGURE_TYPES]
        for name in figures:
            shutil.move(os.path.join(stage, name), os.path.join(out_dir, name))
    if rc != 0:
        print(f"{script}: failed with status {rc}; its output is in {printed}")
        return 1
    if not figures:
        print(f"{script}: wrote no figure; its output above, also in {printed}, says why")
        return 1
    for name in figures:
        print(f"figure: {os.path.join(out_dir, name)}")
    print(f"output: {printed}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="eval/plot.py", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("experiment", help="a directory under eval/, such as latency_throughput")
    parser.add_argument("-c", "--config", default=DEFAULT_CONFIG, metavar="FILE",
                        help=f"config in the experiment directory (default {DEFAULT_CONFIG})")
    parser.add_argument("--run", metavar="RUN",
                        help="a run in results/, by default this config's newest, or any "
                             "directory of logs")
    parser.add_argument("--out", metavar="DIR",
                        help="where the figures go (default: the run directory)")
    args = parser.parse_args(argv)
    try:
        exp = Experiment(find_experiment(args.experiment), args.config)
        if not exp.plots:
            raise ConfigError(f"{rel(exp.config_path)} lists no figure script under plot")
        run_dir = exp.find_run(args.run)
        params = run_params(exp, run_dir)
        jobs = [(spec, prepared_source(spec, params), resolve_data(spec, run_dir),
                 resolve_merge(spec)) for spec in exp.plots]
        for spec in exp.plots:
            for step in spec.prepare:
                if not os.path.isfile(step):
                    raise ConfigError(f"{rel(step)} is missing")
    except ConfigError as e:
        sys.exit(f"plot.py: {e}")
    missing = [name for name in ("numpy", "matplotlib") if importlib.util.find_spec(name) is None]
    if missing:
        sys.exit(f"plot.py: {' and '.join(missing)} missing here; install them with "
                 "python3 -m pip install numpy matplotlib, or plot on another machine")
    if not any(name.endswith(".log") for _, _, names in os.walk(run_dir) for name in names):
        sys.exit(f"plot.py: no .log files in {run_dir}")
    seconds = params.get("d")
    complete = None
    if exp.trace:
        complete, end = trace_replayed, "the trace's last row"
    elif isinstance(seconds, int) and not isinstance(seconds, bool):
        complete, end = (lambda path: log_complete(path, seconds)), f"second {seconds - 1}"
    if complete:
        short = short_logs(run_dir, complete)
        if short:
            print(f"warning: {len(short)} logs end before {end}, so their points "
                  f"rest on fewer samples: {', '.join(short)}")
    # The runs merged in from other experiments may be unfinished, too.
    merged = sorted({directory for _, _, _, merges in jobs for runs in merges.values()
                     for _, directory in runs})
    for directory in merged:
        length = run_params(exp, directory).get("d")
        if isinstance(length, int) and not isinstance(length, bool):
            short = short_logs(directory, lambda path: log_complete(path, length))
            if short:
                print(f"warning: in {directory}, {len(short)} logs end before second "
                      f"{length - 1}, so their points rest on fewer samples: {', '.join(short)}")
    out_dir = os.path.abspath(args.out) if args.out else run_dir
    os.makedirs(out_dir, exist_ok=True)
    return max(plot(spec, source, data, merges, run_dir, out_dir)
               for spec, source, data, merges in jobs)


if __name__ == "__main__":
    sys.exit(main())
