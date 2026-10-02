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
constants such as FILE_PREFIX.  The figure lands next to the logs, or in
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
                    find_experiment, log_complete, read_yaml, rel)

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


def plot(spec, source, data, run_dir, out_dir):
    """Run one figure script on `run_dir`; 0 if it wrote a figure, else 1."""
    script = os.path.basename(spec.script)
    stem = os.path.splitext(script)[0]
    printed = os.path.join(out_dir, stem + ".out")
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
            if kind == "empty":
                os.makedirs(link, exist_ok=True)
            else:
                os.symlink(run_dir if kind == "run" else target, link)
        print(f"{script}: plotting {run_dir}", flush=True)
        env = dict(os.environ, MPLBACKEND="Agg")
        with open(printed, "w") as out:
            proc = subprocess.Popen([sys.executable, script], cwd=stage, env=env,
                                    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, errors="replace")
            for line in proc.stdout:
                sys.stdout.write(line)
                out.write(line)
            rc = proc.wait()
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
        jobs = [(spec, prepared_source(spec, params), resolve_data(spec, run_dir))
                for spec in exp.plots]
    except ConfigError as e:
        sys.exit(f"plot.py: {e}")
    missing = [name for name in ("numpy", "matplotlib") if importlib.util.find_spec(name) is None]
    if missing:
        sys.exit(f"plot.py: {' and '.join(missing)} missing here; install them with "
                 "python3 -m pip install numpy matplotlib, or plot on another machine")
    if not any(name.endswith(".log") for _, _, names in os.walk(run_dir) for name in names):
        sys.exit(f"plot.py: no .log files in {run_dir}")
    seconds = params.get("d")
    if isinstance(seconds, int) and not isinstance(seconds, bool):
        short = [name for name in sorted(os.listdir(run_dir)) if name.endswith(".log")
                 and not log_complete(os.path.join(run_dir, name), seconds)]
        if short:
            print(f"warning: {len(short)} logs end before second {seconds - 1}, so their points "
                  f"rest on fewer samples: {', '.join(short)}")
    out_dir = os.path.abspath(args.out) if args.out else run_dir
    os.makedirs(out_dir, exist_ok=True)
    return max(plot(spec, source, data, run_dir, out_dir) for spec, source, data in jobs)


if __name__ == "__main__":
    sys.exit(main())
