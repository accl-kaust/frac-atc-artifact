"""Shared pieces of eval/run.py and eval/plot.py.

An experiment is a directory under eval/ holding a config, experiment.yaml
unless -c names another, and the figure scripts that plot its results.
This module reads and checks configs, expands sweeps, names logs and finds
result directories.

Beside the standard library it needs only PyYAML, and it keeps to Python
3.10, so eval/run.py works with a testbed's system Python.
"""
import datetime
import hashlib
import itertools
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

CONFIG_KEYS = ("description", "targets", "params", "sweep", "name", "fperf", "plot")
TARGET_KEYS = ("bitstream", "partials", "slots", "sha256")
PLOT_KEYS = ("script", "data", "set")
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
        self.data = str(spec.get("data") or f"data/{exp.name}").strip("/")
        if not self.data or self.data == "." or os.pardir in self.data.split("/"):
            raise ConfigError(f"{label}: data must be a relative path such as data/{exp.name}")
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
        for key in (TARGET_KEY, "d"):
            if key not in self.keys:
                raise ConfigError(f"{where}: {key} must be a param or a sweep key")
        for seconds in self.values("d"):
            if isinstance(seconds, bool) or not isinstance(seconds, int) or seconds < 1:
                raise ConfigError(f"{where}: d is the run length in whole seconds, "
                                  f"not {seconds!r}")

        targets = raw.get("targets")
        if not isinstance(targets, dict) or not targets:
            raise ConfigError(f"{where}: targets must map each value of {TARGET_KEY} "
                              "to a directory of bitstreams")
        self.targets = {str(key): Target(str(key), spec, where) for key, spec in targets.items()}
        for value in self.values(TARGET_KEY):
            if str(value) not in self.targets:
                raise ConfigError(f"{where}: no target for {TARGET_KEY}={value}")

        self.name_template = self._template(raw, "name", where)
        self.fperf_template = self._template(raw, "fperf", where)
        names = set()
        for point in self.points():
            name = self.log_name(point)
            if name in names:
                raise ConfigError(f"{where}: two sweep points share the log name {name}; "
                                  "name must use every swept key")
            names.add(name)
            self.fperf_args(point)

        plots = raw.get("plot") or []
        if isinstance(plots, (str, dict)):
            plots = [plots]
        if not isinstance(plots, list):
            raise ConfigError(f"{where}: plot must list figure scripts")
        self.plots = [PlotSpec(spec, self, where) for spec in plots]

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

    def points(self, only=None):
        """Every sweep point as a dict of params and sweep values.  The points
        of one target stay together, in the order of the O values, so each
        image is programmed once."""
        only = only or {}
        lists = []
        for key, values in self.sweep:
            if key in only:
                values = [value for value in values if str(value) in only[key]]
            lists.append(values)
        order = [str(value) for value in self.values(TARGET_KEY)]
        points = []
        for combo in itertools.product(*lists):
            point = dict(self.params)
            point.update(zip(self.swept, combo))
            points.append(point)
        points.sort(key=lambda point: order.index(str(point[TARGET_KEY])))
        return points

    def log_name(self, point):
        """The log file name of one sweep point, relative to the run directory."""
        try:
            name = self.name_template.format(**point)
        except (KeyError, IndexError, ValueError) as e:
            raise ConfigError(f"name template {self.name_template!r}: {e!r}")
        if os.path.isabs(name) or os.pardir in name.split("/"):
            raise ConfigError(f"log name {name!r} must stay inside the run directory")
        return name

    def fperf_args(self, point):
        """The fperf arguments of one sweep point, from the fperf template."""
        try:
            return shlex.split(self.fperf_template.format(**point))
        except (KeyError, IndexError, ValueError) as e:
            raise ConfigError(f"fperf template {self.fperf_template!r}: {e!r}")

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
