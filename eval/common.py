"""Shared pieces of eval/run.py and eval/plot.py.

An experiment is a directory under eval/ holding a config, experiment.yaml
unless -c names another, and the figure scripts that plot its results.
This module reads and checks configs, expands sweeps, names logs and finds
result directories.

Beside the standard library it needs only PyYAML, and it keeps to Python
3.10, so eval/run.py works with a testbed's system Python.
"""
import ast
import datetime
import hashlib
import itertools
import math
import operator
import os
import re
import shlex
import string
import subprocess
import sys

try:
    import yaml
except ImportError:
    sys.exit("eval: PyYAML is missing; install it with: python3 -m pip install pyyaml")

EVAL_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(EVAL_DIR)
DEFAULT_CONFIG = "experiment.yaml"
TARGET_KEY = "O"                # the key whose value picks the target

CONFIG_KEYS = ("description", "program", "tpa_cfg", "latency_log", "targets", "server",
               "functions", "instances", "together", "trace", "params", "sweep", "name", "samples",
               "fperf", "plot")
PROGRAM_MODES = ("every_run", "once")
FUNCTION_KEY = "f"              # the key whose value picks an entry of the functions table
INSTANCE_KEY = "k"              # the key whose value picks an entry of the instances table
# fperf -E sends each row of a trace to the slot of its app, as func_slots[] in
# libtpa's app/fperf/trace.c maps them: top_k (1) to slot 0, logit (3) to 1,
# the CNN (2) to 2 and norm (5) to 3.
TRACE_SLOTS = {1: 0, 3: 1, 2: 2, 5: 3}
TRACE_HEADER = "app,sleep_time,request_size,response_size"
TARGET_KEYS = ("bitstream", "partials", "slots", "sha256")
PLOT_KEYS = ("script", "data", "merge", "set", "fresh", "prepare")
# What run.py adds to a server's fperf arguments itself
SERVER_OPTIONS = ("-s", "-c", "-p", "-S")
BUILD_KEYS = ("job", "payload", "frac", "spinhdl", "vivado", "started", "staged")


class ConfigError(Exception):
    """A config or command line that cannot be run as given."""


def rel(path):
    """`path` relative to the repository root if it lies inside, else absolute."""
    path = os.path.abspath(path)
    inside = os.path.relpath(path, REPO_DIR)
    if inside == os.pardir or inside.startswith(os.pardir + os.sep):
        return path
    return inside


def abs_path(path, base=REPO_DIR):
    """`path` with ~ expanded, taken relative to `base` unless it is absolute."""
    path = os.path.expanduser(str(path))
    return os.path.normpath(path if os.path.isabs(path) else os.path.join(base, path))


def now():
    """The local time with its UTC offset, to the second."""
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def read_yaml(path):
    """A YAML file's top-level mapping; {} for an empty file."""
    try:
        with open(path) as f:
            data = yaml.safe_load(f)
    except OSError as e:
        raise ConfigError(f"cannot read {rel(path)}: {e.strerror}")
    except yaml.YAMLError as e:
        raise ConfigError(f"{rel(path)}: {e}")
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ConfigError(f"{rel(path)}: expected a mapping at the top level")
    return data


def write_yaml(path, data):
    """Write `data` to `path` in one step, keeping its key order."""
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        yaml.safe_dump(data, f, sort_keys=False, default_flow_style=False, width=100)
    os.replace(tmp, path)


def merge(base, over):
    """`over` laid on `base`, recursing into mappings present in both.  An
    empty mapping in `over` replaces the one in `base`, so a variant config
    can clear a target's slots with `slots: {}`."""
    out = dict(base)
    for key, value in over.items():
        if isinstance(value, dict) and value and isinstance(out.get(key), dict):
            out[key] = merge(out[key], value)
        else:
            out[key] = value
    return out


def read_config(path, chain=()):
    """An experiment config with the file its `base` key names laid underneath."""
    path = os.path.abspath(path)
    if path in chain:
        raise ConfigError(f"{rel(path)}: its base chain loops back to itself")
    data = read_yaml(path)
    base = data.pop("base", None)
    if base is None:
        return data
    if not isinstance(base, str):
        raise ConfigError(f"{rel(path)}: base must name a config file")
    return merge(read_config(os.path.join(os.path.dirname(path), base), chain + (path,)), data)


def template_fields(template, where):
    """The names a str.format template uses."""
    try:
        parsed = list(string.Formatter().parse(template))
    except ValueError as e:
        raise ConfigError(f"{where}: {e} in {template!r}")
    names = set()
    for _, field, _, _ in parsed:
        if field is None:
            continue
        name = re.split(r"[.\[]", field, maxsplit=1)[0]
        if not name or name.isdigit():
            raise ConfigError(f"{where}: use named fields such as {{n}} in {template!r}")
        names.add(name)
    return names


_ARITH = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
          ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod}


def arith(text):
    """`text` as an integer when it is integer arithmetic such as "2048 - 64",
    else `text` unchanged."""
    def value(node):
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.BinOp) and type(node.op) in _ARITH:
            return _ARITH[type(node.op)](value(node.left), value(node.right))
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            return -value(node.operand)
        raise ValueError(text)

    try:
        return value(ast.parse(text.strip(), mode="eval").body)
    except (SyntaxError, ValueError, ZeroDivisionError):
        return text


def derive(field, point):
    """A functions-table value for one sweep point: a template such as
    "{X} - 64" is filled in from the point and, if it is arithmetic, worked out."""
    if isinstance(field, str) and "{" in field:
        return arith(field.format(**point))
    return field


def find_experiment(name):
    """The directory of experiment `name`: a directory under eval/, or a path."""
    for candidate in (os.path.join(EVAL_DIR, name), name):
        if os.path.isdir(candidate):
            return os.path.abspath(candidate)
    known = sorted(entry for entry in os.listdir(EVAL_DIR)
                   if os.path.isfile(os.path.join(EVAL_DIR, entry, DEFAULT_CONFIG)))
    raise ConfigError(f"no experiment {name!r} in {rel(EVAL_DIR)}; "
                      f"the experiments there are: {', '.join(known) or 'none'}")


def sha256_file(path):
    """The sha256 of a file, in hex."""
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def build_record(build_dir):
    """What our build tooling noted about a build, from the RUN and STAGED
    files it leaves next to the bitstreams; {} for any other directory."""
    found = {}
    for name in ("RUN", "STAGED"):
        path = os.path.join(build_dir, name)
        if not os.path.isfile(path):
            continue
        with open(path, errors="replace") as f:
            for line in f:
                parts = line.split(None, 1)
                if len(parts) == 2 and not parts[0].startswith("#"):
                    found[parts[0]] = parts[1].strip()
    return {key: found[key] for key in BUILD_KEYS if key in found}


def git_info(path):
    """Commit, branch and dirtiness of the git checkout holding `path`, or None."""
    def git(*args):
        try:
            done = subprocess.run(["git", "-C", path] + list(args),
                                  capture_output=True, text=True)
        except OSError:
            return None
        return done.stdout.strip() if done.returncode == 0 else None

    commit = git("rev-parse", "--short=12", "HEAD")
    if not commit:
        return None
    status = git("status", "--porcelain", "--untracked-files=no")
    return {"commit": commit, "branch": git("rev-parse", "--abbrev-ref", "HEAD"),
            "dirty": bool(status)}


def log_complete(path, seconds):
    """Whether an fperf log reached its last second, `seconds` - 1, and
    printed that second's Total-Throughput line."""
    last = re.compile(r"^\s*%d\s+\S+\s+Total-Throughput\b" % (seconds - 1))
    try:
        with open(path, errors="replace") as f:
            return any(last.match(line) for line in f)
    except OSError:
        return False


def trace_replayed(path, rows=None):
    """Whether an fperf -E log says it replayed its whole trace, of `rows`
    rows when that is given."""
    done = re.compile(r"^trace: all (\d+) rows replayed")
    try:
        with open(path, errors="replace") as f:
            for line in f:
                match = done.match(line)
                if match and (rows is None or int(match.group(1)) == rows):
                    return True
    except OSError:
        pass
    return False


class Trace:
    """A CSV trace for fperf -E, checked the way fperf reads it: the header,
    then one request per row, sent sleep_time seconds after the response to
    the row before, with request_size bytes after its 64-byte header."""

    def __init__(self, path, where):
        self.path = path
        label = f"{where}: trace {rel(path)}"
        try:
            with open(path, errors="replace") as f:
                lines = f.read().split("\n")
        except OSError as e:
            raise ConfigError(f"{label}: {e.strerror}")
        if lines[0].rstrip("\r") != TRACE_HEADER:
            raise ConfigError(f"{label}: its first line must be the header {TRACE_HEADER}")
        self.rows, self.seconds, apps = 0, 0.0, set()
        for number, line in enumerate(lines[1:], 2):
            line = line.rstrip("\r")
            if not line:
                continue
            try:
                app, sleep, request, response = line.split(",")
                app, sleep, request, response = int(app), float(sleep), int(request), int(response)
            except ValueError:
                raise ConfigError(f"{label}:{number}: expected {TRACE_HEADER}, not {line!r}")
            if app not in TRACE_SLOTS:
                raise ConfigError(f"{label}:{number}: app {app} has no slot; fperf knows apps "
                                  f"{', '.join(map(str, sorted(TRACE_SLOTS)))}")
            if not (0 <= sleep < 1e9 and request > 0 and response > 0):
                raise ConfigError(f"{label}:{number}: sleep_time must be 0 or more, and the "
                                  "sizes more than 0")
            self.rows += 1
            self.seconds += sleep
            apps.add(app)
        if not self.rows:
            raise ConfigError(f"{label}: it has no rows")
        self.slots = {TRACE_SLOTS[app]: app for app in apps}     # slot: the app sent there
        self.sha256 = sha256_file(path)


class Target:
    """What one value of O runs on: the full image to program over JTAG, and
    the partial bitstreams to load into slots after programming it."""

    def __init__(self, key, spec, where):
        if isinstance(spec, str):
            spec = {"bitstream": spec}
        if not isinstance(spec, dict) or not spec.get("bitstream"):
            raise ConfigError(f"{where}: targets.{key} needs a bitstream, the full image to program")
        unknown = set(spec) - set(TARGET_KEYS)
        if unknown:
            raise ConfigError(f"{where}: targets.{key}: unknown keys: "
                              f"{', '.join(sorted(map(str, unknown)))}")
        self.key = key
        self.bitstream = abs_path(spec["bitstream"])
        self.partials = abs_path(spec["partials"]) if spec.get("partials") else None
        slots = spec.get("slots") or {}
        if not isinstance(slots, dict):
            raise ConfigError(f"{where}: targets.{key}.slots must map slot numbers to files")
        self.slots = {}
        for slot, name in slots.items():
            if isinstance(slot, bool) or not re.fullmatch(r"\d+", str(slot)):
                raise ConfigError(f"{where}: targets.{key}.slots: {slot!r} is not a slot number")
            if not isinstance(name, str) or not name:
                raise ConfigError(f"{where}: targets.{key}.slots.{slot}: give the file name "
                                  "of a partial bitstream in partials")
            self.slots[int(slot)] = name
        if self.slots and not self.partials:
            raise ConfigError(f"{where}: targets.{key} loads slots, so it needs partials, "
                              "the directory of its partial bitstreams")
        pin = spec.get("sha256")
        if pin is not None and not re.fullmatch(r"[0-9a-fA-F]{8,64}", str(pin)):
            raise ConfigError(f"{where}: targets.{key}.sha256 must be 8 to 64 hex digits, "
                              "in quotes")
        self.sha256 = None if pin is None else str(pin).lower()

    def set_bitstream(self, path, base):
        """Program `path` instead, taken relative to `base`."""
        self.bitstream = abs_path(path, base)

    def set_partials(self, path, base):
        """Take the partial bitstreams from `path` instead, relative to `base`."""
        self.partials = abs_path(path, base)


class PlotSpec:
    """One figure script, and how to point it at a run."""

    def __init__(self, spec, exp, where):
        if isinstance(spec, str):
            spec = {"script": spec}
        if not isinstance(spec, dict) or not spec.get("script"):
            raise ConfigError(f"{where}: every plot entry needs a script")
        label = f"{where}: plot {spec['script']}"
        unknown = set(spec) - set(PLOT_KEYS)
        if unknown:
            raise ConfigError(f"{label}: unknown keys: {', '.join(sorted(map(str, unknown)))}")
        self.script = abs_path(spec["script"], exp.dir)
        data = spec.get("data") or f"data/{exp.name}"
        if isinstance(data, str):
            data = {data: "run"}
        if not isinstance(data, dict):
            raise ConfigError(f"{label}: data must be a path such as data/{exp.name}, or map "
                              "such paths to run, empty or a directory")
        # Each path the script reads leads to: ("run", None), this run's directory;
        # ("empty", None), an empty directory; or ("dir", path), another directory,
        # relative to the run's.
        self.data = {}
        for path, source in data.items():
            path = str(path).strip("/")
            if not path or path == "." or os.pardir in path.split("/"):
                raise ConfigError(f"{label}: {path!r} must be a relative path such as "
                                  f"data/{exp.name}")
            if source == "run":
                self.data[path] = ("run", None)
            elif source is None or source == "empty":
                self.data[path] = ("empty", None)
            elif isinstance(source, str) and source:
                self.data[path] = ("dir", source)
            else:
                raise ConfigError(f"{label}: data.{path} must be run, empty or a directory")
        fresh = spec.get("fresh") or []
        fresh = [fresh] if isinstance(fresh, str) else fresh
        if not isinstance(fresh, list) or not all(
                isinstance(name, str) and name and "/" not in name and name not in (".", "..")
                for name in fresh):
            raise ConfigError(f"{label}: fresh must list file names in the run directory")
        self.fresh = list(fresh)     # files the script caches results in: removed before it runs
        prepare = spec.get("prepare") or []
        prepare = [prepare] if isinstance(prepare, str) else prepare
        if not isinstance(prepare, list) or not all(isinstance(name, str) and name for name in prepare):
            raise ConfigError(f"{label}: prepare must list scripts in the experiment directory")
        # scripts run just before the figure script, in its scratch directory
        self.prepare = [abs_path(name, exp.dir) for name in prepare]
        # merge: data paths that also take in the newest run of other
        # experiments, such as a baseline measured on its own.
        merge = spec.get("merge") or {}
        if not isinstance(merge, dict):
            raise ConfigError(f"{label}: merge must map data paths to experiments")
        self.merge = {}
        for path, names in merge.items():
            path = str(path).strip("/")
            if path not in self.data:
                raise ConfigError(f"{label}: merge.{path} is not one of its data paths")
            names = [names] if isinstance(names, str) else names
            if not isinstance(names, list) or not names or not all(
                    isinstance(name, str) and name for name in names):
                raise ConfigError(f"{label}: merge.{path} must name experiments, such as "
                                  "scalability_cpu")
            self.merge[path] = list(names)
        settings = spec.get("set") or {}
        if not isinstance(settings, dict):
            raise ConfigError(f"{label}: set must map module constants to values")
        self.settings = {}
        for name, template in settings.items():
            name = str(name)
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
                raise ConfigError(f"{label}: {name!r} is not a Python name")
            template = str(template)
            unknown = template_fields(template, f"{label}: set.{name}") - set(exp.params)
            if unknown:
                raise ConfigError(f"{label}: set.{name} uses {', '.join(sorted(unknown))}; "
                                  "only params can be used there")
            self.settings[name] = template


class Experiment:
    """One experiment config, checked and ready to expand."""

    def __init__(self, exp_dir, config=DEFAULT_CONFIG):
        self.dir = exp_dir
        self.name = os.path.basename(os.path.normpath(exp_dir))
        path = os.path.join(exp_dir, config)
        if not os.path.isfile(path) and os.path.isfile(config):
            path = config
        self.config_path = os.path.abspath(path)
        stem = os.path.splitext(os.path.basename(path))[0]
        self.variant = None if stem == "experiment" else stem
        where = rel(path)
        raw = read_config(path)

        unknown = set(raw) - set(CONFIG_KEYS)
        if unknown:
            raise ConfigError(f"{where}: unknown keys: {', '.join(sorted(map(str, unknown)))}")
        self.description = str(raw.get("description") or "")
        self.program = str(raw.get("program") or "every_run")
        if self.program not in PROGRAM_MODES:
            raise ConfigError(f"{where}: program must be {' or '.join(PROGRAM_MODES)}, "
                              f"not {self.program!r}")
        # Added to the testbed's TPA_CFG for this experiment's runs; never
        # formatted, since libtpa's syntax is full of braces.
        self.tpa_cfg = str(raw.get("tpa_cfg") or "").strip()
        # fperf -L 1: record every request's latency, as the paper's runs did.
        # On unless the config says otherwise; samples keeps the records.
        self.latency_log = raw.get("latency_log", True)
        if not isinstance(self.latency_log, bool):
            raise ConfigError(f"{where}: latency_log must be true or false")

        params = raw.get("params") or {}
        if not isinstance(params, dict):
            raise ConfigError(f"{where}: params must be a mapping")
        self.params = {str(key): value for key, value in params.items()}

        sweep = raw.get("sweep")
        if not isinstance(sweep, dict) or not sweep:
            raise ConfigError(f"{where}: sweep must map each swept key to its values")
        self.sweep = []
        for key, values in sweep.items():
            key = str(key)
            values = values if isinstance(values, list) else [values]
            if not values:
                raise ConfigError(f"{where}: sweep.{key} has no values")
            if key in self.params:
                raise ConfigError(f"{where}: {key} is both a param and a sweep key")
            self.sweep.append((key, values))
        self.keys = set(self.params) | set(self.swept)
        self.trace = self._trace(raw.get("trace"), where)
        for key in (TARGET_KEY, "d"):
            if key not in self.keys:
                raise ConfigError(f"{where}: {key} must be a param or a sweep key")
        for seconds in self.values("d"):
            if isinstance(seconds, bool) or not isinstance(seconds, int) or seconds < 1:
                raise ConfigError(f"{where}: d is the run length in whole seconds, "
                                  f"not {seconds!r}")
        self.server_template = self._server(raw, where)
        if self.server_template:
            self.program = None         # there is no FPGA to program
        self.functions = self._functions(raw.get("functions"), where)
        self.instances = self._instances(raw.get("instances"), where)
        self.together = self._together(raw.get("together"), where)
        if self.trace and (self.functions or self.instances or self.together):
            raise ConfigError(f"{where}: a trace picks each request's slot itself and replays "
                              "on one connection, so it cannot be combined with functions, "
                              "instances or together")

        if self.server_template:
            self.targets = {}           # the clients talk to a CPU server: nothing to program
        else:
            targets = raw.get("targets")
            if not isinstance(targets, dict) or not targets:
                raise ConfigError(f"{where}: targets must map each value of {TARGET_KEY} "
                                  "to a directory of bitstreams")
            self.targets = {str(key): Target(str(key), spec, where)
                            for key, spec in targets.items()}
            for value in self.values(TARGET_KEY):
                if str(value) not in self.targets:
                    raise ConfigError(f"{where}: no target for {TARGET_KEY}={value}")
        if self.functions:
            for target in self.targets.values():
                if not target.partials:
                    raise ConfigError(f"{where}: targets.{target.key} needs partials, the "
                                      "directory the functions' partial bitstreams are in")
        if self.trace:
            # A slot left with whatever the full image put there answers too,
            # and often with the size fperf waits for, so check here.
            for target in self.targets.values():
                for slot, app in sorted(self.trace.slots.items()):
                    if slot not in target.slots:
                        raise ConfigError(f"{where}: the trace sends app {app} to slot {slot}, "
                                          f"but targets.{target.key}.slots loads nothing there")

        self.name_template = self._template(raw, "name", where)
        self.fperf_template = self._template(raw, "fperf", where)
        if self.trace:
            given = {"-E", "-d"} & set(shlex.split(self.fperf_template))
            if given:
                raise ConfigError(f"{where}: leave {' and '.join(sorted(given))} out of fperf: "
                                  "run.py adds -E with the trace, and the replay ends with it")
        # samples: where every client thread's per-request latencies gather, one
        # directory per sweep point, and how many seconds to drop from the start
        # of each thread's file.
        self.samples_template, self.samples_skip = None, 0
        samples = raw.get("samples")
        if samples is not None:
            samples = {"dir": samples} if isinstance(samples, str) else samples
            if not isinstance(samples, dict) or not samples.get("dir"):
                raise ConfigError(f"{where}: samples needs dir, a directory for each sweep point")
            unknown = set(samples) - {"dir", "skip"}
            if unknown:
                raise ConfigError(f"{where}: samples: unknown keys: "
                                  f"{', '.join(sorted(map(str, unknown)))}")
            self.samples_template = self._template(samples, "dir", f"{where}: samples")
            shared = template_fields(self.samples_template, f"{where}: samples") & {"slot", "instance"}
            if shared:
                raise ConfigError(f"{where}: samples.dir is one directory per sweep point, for "
                                  f"all its processes; it cannot use {', '.join(sorted(shared))}")
            skip = samples.get("skip", 0)
            if isinstance(skip, bool) or not isinstance(skip, int) or skip < 0:
                raise ConfigError(f"{where}: samples.skip is whole seconds, not {skip!r}")
            if skip >= min(self.values("d")):
                raise ConfigError(f"{where}: samples.skip of {skip} s would drop every run")
            self.samples_skip = skip
            if not self.latency_log:
                raise ConfigError(f"{where}: samples needs latency_log, which records them")
            if self.together:
                raise ConfigError(f"{where}: samples and together cannot be combined")
        hint = "every swept key" + (" and {slot}" if self.instances else "")
        names, samples = set(), set()
        for point in self.points():
            if self.samples_template:
                directory = self.samples_name(point)
                if directory in samples:
                    raise ConfigError(f"{where}: two sweep points share the samples directory "
                                      f"{directory}; samples must use every swept key")
                samples.add(directory)
            for run in self.instance_points(point):
                name = self.log_name(run)
                if name in names:
                    raise ConfigError(f"{where}: two runs share the log name {name}; name must "
                                      f"use {hint}")
                names.add(name)
                self.fperf_args(run)
            if self.server_template:
                self.server_args(point)
            if "_members" in point:
                slots = [run["slot"] for run in point["_members"]]
                shared = sorted({slot for slot in slots if slots.count(slot) > 1})
                if shared:
                    raise ConfigError(f"{where}: together runs {FUNCTION_KEY}={point[FUNCTION_KEY]} "
                                      f"at once, but they share slot {shared[0]}; give each "
                                      "function a slot of its own")

        plots = raw.get("plot") or []
        if isinstance(plots, (str, dict)):
            plots = [plots]
        if not isinstance(plots, list):
            raise ConfigError(f"{where}: plot must list figure scripts")
        self.plots = [PlotSpec(spec, self, where) for spec in plots]

    def _functions(self, functions, where):
        """The functions table: for each value of f, the slot and the partial
        bitstream to load before its runs, plus params of its own such as its
        response size.  Those may be templates over params and sweep keys,
        such as "{X} - 64".  Its keys join the fields templates can use."""
        if not functions:
            return {}
        if not isinstance(functions, dict):
            raise ConfigError(f"{where}: functions must map values of {FUNCTION_KEY} to a slot "
                              "and a partial bitstream")
        if FUNCTION_KEY not in self.keys:
            raise ConfigError(f"{where}: functions needs {FUNCTION_KEY} as a param or a sweep key")
        table, fields = {}, None
        for value, spec in functions.items():
            label = f"{where}: functions.{value}"
            if not isinstance(spec, dict):
                raise ConfigError(f"{label} must be a mapping with slot and partial")
            spec = {str(key): field for key, field in spec.items()}
            missing = [key for key in ("slot", "partial") if key not in spec]
            if missing:
                raise ConfigError(f"{label} needs {' and '.join(missing)}")
            slot = spec["slot"]
            if isinstance(slot, bool) or not isinstance(slot, int) or slot < 0:
                raise ConfigError(f"{label}.slot must be a slot number, not {slot!r}")
            if not isinstance(spec["partial"], str) or not spec["partial"] or "{" in spec["partial"]:
                raise ConfigError(f"{label}.partial must name a file in the target's partials")
            for key, field in spec.items():
                if key in ("slot", "partial") or not isinstance(field, str):
                    continue
                unknown = template_fields(field, f"{label}.{key}") - self.keys
                if unknown:
                    raise ConfigError(f"{label}.{key} uses {', '.join(sorted(unknown))}, which "
                                      "is neither a param nor a sweep key")
            clash = set(spec) & self.keys
            if clash:
                raise ConfigError(f"{label} sets {', '.join(sorted(clash))}, which the params "
                                  "or the sweep set already")
            if fields is not None and set(spec) != fields:
                raise ConfigError(f"{where}: every functions entry must set the same keys")
            fields = set(spec)
            table[str(value)] = spec
        for value in self.values(FUNCTION_KEY):
            if str(value) not in table:
                raise ConfigError(f"{where}: functions has no entry for {FUNCTION_KEY}={value}")
        self.keys |= fields
        return table

    def _instances(self, instances, where):
        """The instances table: for each value of k, the slots that one fperf
        process each drives at the same time, with the n clients split evenly
        between them.  Adds n_per, slot and instance to the template fields."""
        if not instances:
            return {}
        if not isinstance(instances, dict):
            raise ConfigError(f"{where}: instances must map values of {INSTANCE_KEY} to lists "
                              "of slots")
        if self.functions:
            raise ConfigError(f"{where}: instances and functions cannot be combined; both set "
                              "the slot")
        for key in (INSTANCE_KEY, "n"):
            if key not in self.keys:
                raise ConfigError(f"{where}: instances needs {key} as a param or a sweep key")
        clash = {"n_per", "slot", "instance"} & self.keys
        if clash:
            raise ConfigError(f"{where}: instances sets {', '.join(sorted(clash))}, which the "
                              "params or the sweep set already")
        table = {}
        for value, slots in instances.items():
            label = f"{where}: instances.{value}"
            if not isinstance(slots, list) or not slots:
                raise ConfigError(f"{label} must list the slots, such as [0, 1]")
            for slot in slots:
                if isinstance(slot, bool) or not isinstance(slot, int) or slot < 0:
                    raise ConfigError(f"{label}: {slot!r} is not a slot number")
            if len(set(slots)) != len(slots):
                raise ConfigError(f"{label} lists a slot twice")
            table[str(value)] = list(slots)
        for value in self.values(INSTANCE_KEY):
            if str(value) not in table:
                raise ConfigError(f"{where}: instances has no entry for {INSTANCE_KEY}={value}")
        for clients in self.values("n"):
            if isinstance(clients, bool) or not isinstance(clients, int) or clients < 1:
                raise ConfigError(f"{where}: n must be a whole number of clients, not {clients!r}")
        self.keys |= {"n_per", "slot", "instance"}
        return table

    def _together(self, together, where):
        """together: {KEY: VALUE}.  The sweep points whose KEY is VALUE, alike
        in every other swept key but f, run at the same time: one fperf
        process for each value of f, each its function's own run, with its
        slot, partial, fields and log.  The other points run one at a time."""
        if not together:
            return None
        if not isinstance(together, dict) or len(together) != 1:
            raise ConfigError(f"{where}: together must be one KEY: VALUE, such as mix: mixed")
        (key, value), = together.items()
        key = str(key)
        if not self.functions:
            raise ConfigError(f"{where}: together runs functions at once, so it needs a "
                              "functions table")
        if self.instances:
            raise ConfigError(f"{where}: together and instances cannot be combined")
        if FUNCTION_KEY not in self.swept:
            raise ConfigError(f"{where}: together needs {FUNCTION_KEY} swept, for functions "
                              "to run at once")
        if key not in self.swept or key in (FUNCTION_KEY, TARGET_KEY):
            raise ConfigError(f"{where}: together.{key} must be a swept key other than "
                              f"{FUNCTION_KEY} and {TARGET_KEY}")
        if str(value) not in [str(known) for known in self.values(key)]:
            raise ConfigError(f"{where}: together.{key} is {value!r}, which the sweep never sets")
        return key, value

    def _trace(self, trace, where):
        """trace: the CSV file fperf -E replays, relative to the experiment
        directory.  The replay lasts as long as the trace, so d is not given
        but taken from it: its sleep times in whole seconds, the least the
        replay can take."""
        if trace is None:
            return None
        if not isinstance(trace, str) or not trace:
            raise ConfigError(f"{where}: trace must name a CSV file for fperf -E")
        if "d" in self.keys:
            raise ConfigError(f"{where}: a trace run lasts as long as its replay, so leave d "
                              "out; run.py takes it from the trace's sleep times")
        trace = Trace(abs_path(trace, self.dir), where)
        self.params["d"] = max(1, math.ceil(trace.seconds))
        self.keys.add("d")
        return trace

    def _server(self, raw, where):
        """server: fperf's own server arguments for one sweep point, such as
        -n {k}.  With it the clients talk to that server, which computes the
        function in software on the machine the testbed file's server section
        names, instead of to the FPGA, so there is nothing to program."""
        if raw.get("server") is None:
            return None
        template = self._template(raw, "server", where)
        try:
            given = set(SERVER_OPTIONS) & set(shlex.split(template))
        except ValueError as e:
            raise ConfigError(f"{where}: server {template!r}: {e}")
        if given:
            raise ConfigError(f"{where}: leave {' and '.join(sorted(given))} out of server: "
                              "run.py adds -s, and -p and -S from the testbed file")
        clash = [key for key in ("targets", "program", "functions", "instances", "together",
                                 "trace") if raw.get(key)]
        if clash:
            raise ConfigError(f"{where}: server replaces the FPGA, so it cannot be combined "
                              f"with {', '.join(clash)}")
        return template

    def _template(self, raw, key, where):
        template = raw.get(key)
        if not isinstance(template, str) or not template.strip():
            raise ConfigError(f"{where}: {key} must be a template string")
        unknown = template_fields(template, f"{where}: {key}") - self.keys
        if unknown:
            raise ConfigError(f"{where}: {key} uses {', '.join(sorted(unknown))}, "
                              "which is neither a param nor a sweep key")
        return template

    @property
    def together_spec(self):
        """together as the config wrote it, for the manifest: {KEY: VALUE} or None."""
        return {self.together[0]: self.together[1]} if self.together else None

    @property
    def trace_spec(self):
        """The trace for the manifest: its file, sha256, rows and sleep seconds, or None."""
        if not self.trace:
            return None
        return {"file": rel(self.trace.path), "sha256": self.trace.sha256,
                "rows": self.trace.rows, "seconds": round(self.trace.seconds, 1)}

    def trace_args(self):
        """What run.py adds to every fperf command for the trace: -E FILE."""
        return ["-E", self.trace.path] if self.trace else []

    def run_complete(self, path, point):
        """Whether the fperf log at `path` shows a whole run: its last second,
        or with a trace, every row replayed."""
        if self.trace:
            return trace_replayed(path, self.trace.rows)
        return log_complete(path, point["d"])

    def timeout(self, point):
        """Seconds after which run.py stops a run as hung: two minutes past its
        length, and with a trace a quarter more, for the latencies its sleep
        times leave out."""
        seconds = point["d"] + 120
        return seconds + point["d"] // 4 if self.trace else seconds

    @property
    def swept(self):
        """The swept keys, outermost first."""
        return [key for key, _ in self.sweep]

    def values(self, key):
        """The values `key` takes: its sweep values, or its param alone."""
        for swept, values in self.sweep:
            if swept == key:
                return list(values)
        return [self.params[key]]

    def parse_only(self, specs):
        """--only KEY=V1,V2 options as {key: {values}}, checked against the sweep."""
        only = {}
        swept = dict(self.sweep)
        for spec in specs or []:
            key, sep, values = spec.partition("=")
            if not sep or not values:
                raise ConfigError(f"--only {spec}: expected KEY=VALUE[,VALUE...]")
            if key not in swept:
                raise ConfigError(f"--only {spec}: {key} is not swept; "
                                  f"the swept keys are {', '.join(swept)}")
            known = [str(value) for value in swept[key]]
            chosen = [value.strip() for value in values.split(",") if value.strip()]
            missing = [value for value in chosen if value not in known]
            if missing:
                raise ConfigError(f"--only {spec}: {key} never takes {', '.join(missing)}; "
                                  f"it takes {', '.join(known)}")
            only.setdefault(key, set()).update(chosen)
        return only

    def _expand(self, only):
        """Every sweep point as (point, None), or (point, why) for one that
        cannot run: n clients that do not split evenly over its slots."""
        only = only or {}
        lists = []
        for key, values in self.sweep:
            if key in only:
                values = [value for value in values if str(value) in only[key]]
            lists.append(values)
        for combo in itertools.product(*lists):
            point = dict(self.params)
            point.update(zip(self.swept, combo))
            why = None
            if self.functions:
                base = dict(point)
                for key, field in self.functions[str(point[FUNCTION_KEY])].items():
                    point[key] = derive(field, base)
            if self.instances:
                slots = self.instances[str(point[INSTANCE_KEY])]
                if point["n"] % len(slots):
                    why = (f"{point['n']} clients do not split evenly over "
                           f"{len(slots)} slots")
                else:
                    point["n_per"] = point["n"] // len(slots)
            yield point, why

    def _ordered(self, points):
        """`points` with those of one target together, in the order of the O
        values, so each image is programmed once."""
        order = [str(value) for value in self.values(TARGET_KEY)]
        return sorted(points, key=lambda point: order.index(str(point[TARGET_KEY])))

    def _grouped(self, points):
        """`points` with each together group merged into one point, whose
        members, in `_members`, run at the same time.  The merged point keeps
        what its members share; its f lists theirs, such as "1,3,5,2"."""
        if not self.together:
            return points
        key, value = self.together
        fields = set(next(iter(self.functions.values())))
        merged, groups = [], {}
        for point in points:
            if str(point[key]) != str(value):
                merged.append(point)
                continue
            ident = tuple(str(point[other]) for other in self.swept if other != FUNCTION_KEY)
            if ident not in groups:
                groups[ident] = {field: point[field] for field in point if field not in fields}
                groups[ident]["_members"] = []
                merged.append(groups[ident])
            groups[ident]["_members"].append(point)
        for group in groups.values():
            group[FUNCTION_KEY] = ",".join(str(run[FUNCTION_KEY]) for run in group["_members"])
        return merged

    def points(self, only=None):
        """Every sweep point that can run, as a dict of params and sweep
        values, ordered so each target's image is programmed once.  A together
        group is one point, whose members run at once."""
        return self._ordered(self._grouped([point for point, why in self._expand(only)
                                            if why is None]))

    def excluded(self, only=None):
        """(point, why) for each sweep point left out."""
        return [(point, why) for point, why in self._expand(only) if why is not None]

    def instance_points(self, point):
        """One point per fperf process of a sweep point: one for each slot of
        its instances entry, the members of a together group, or the point
        itself."""
        if "_members" in point:
            return list(point["_members"])
        if not self.instances:
            return [point]
        slots = self.instances[str(point[INSTANCE_KEY])]
        return [dict(point, slot=slot, instance=index) for index, slot in enumerate(slots)]

    def threads(self, point):
        """Client threads of each fperf process of a sweep point."""
        return point["n_per"] if self.instances else int(point.get("n", 1))

    def samples_name(self, point):
        """The directory, relative to the run, where a sweep point's per-request
        latencies gather."""
        return self._relative(self.samples_template, point, "samples")

    def point_id(self, point):
        """What names a sweep point: its samples directory, its one log, or
        for a together group the directory its logs share."""
        if self.samples_template:
            return self.samples_name(point)
        if "_members" in point:
            names = [self.log_name(run) for run in point["_members"]]
            folders = {os.path.dirname(name) for name in names}
            if len(folders) == 1 and "" not in folders:
                return folders.pop() + "/"
            return " + ".join(names)
        return self.log_name(point)

    def log_name(self, point):
        """The log file name of one fperf run, relative to the run directory."""
        return self._relative(self.name_template, point, "name")

    def _relative(self, template, point, label):
        try:
            name = template.format(**point)
        except (KeyError, IndexError, ValueError) as e:
            raise ConfigError(f"{label} template {template!r}: {e!r}")
        if os.path.isabs(name) or os.pardir in name.split("/"):
            raise ConfigError(f"{label} {name!r} must stay inside the run directory")
        return name

    def fperf_args(self, point):
        """The fperf arguments of one sweep point, from the fperf template."""
        try:
            return shlex.split(self.fperf_template.format(**point))
        except (KeyError, IndexError, ValueError) as e:
            raise ConfigError(f"fperf template {self.fperf_template!r}: {e!r}")

    def server_args(self, point):
        """The server's fperf arguments for one sweep point, from the server template."""
        try:
            return shlex.split(self.server_template.format(**point))
        except (KeyError, IndexError, ValueError) as e:
            raise ConfigError(f"server template {self.server_template!r}: {e!r}")

    @property
    def results(self):
        """Where this experiment's runs go."""
        return os.path.join(self.dir, "results")

    @property
    def latest(self):
        """The link in results/ to this config's newest run: latest, or
        latest-<variant> for a config such as smoke.yaml."""
        return "latest" + (f"-{self.variant}" if self.variant else "")

    def new_run(self):
        """A new, empty run directory, which this config's latest link then
        points at."""
        os.makedirs(self.results, exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y-%m-%dT%H%M%S")
        base = stamp + (f"-{self.variant}" if self.variant else "")
        name, count = base, 1
        while True:
            try:
                os.mkdir(os.path.join(self.results, name))
                break
            except FileExistsError:
                count += 1
                name = f"{base}-{count}"
        link = os.path.join(self.results, self.latest)
        tmp = link + ".tmp"
        if os.path.lexists(tmp):
            os.remove(tmp)
        os.symlink(name, tmp)
        os.replace(tmp, link)
        return os.path.join(self.results, name)

    def find_run(self, run=None):
        """The directory of an earlier run: a name in results/, this config's
        latest link by default, or the path of any directory of logs."""
        run = run or self.latest
        for candidate in (os.path.join(self.results, run), os.path.expanduser(run)):
            if os.path.isdir(candidate):
                return os.path.realpath(candidate)
        raise ConfigError(f"no run {run!r}: it is neither in {rel(self.results)} nor a directory")
