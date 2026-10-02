#!/usr/bin/env python3
"""Measure one experiment on the fRAC testbed.

    eval/run.py latency_throughput                  # the full sweep
    eval/run.py latency_throughput -c smoke.yaml    # a short variant
    eval/run.py latency_throughput --dry-run        # print the plan, touch nothing
    eval/run.py latency_throughput --resume         # finish the newest run

run.py runs libtpa's fperf once per sweep point, one target after the
other.  Before every run it programs the target's bitstream, its full
image, with scripts/programfpga.sh, waits until the link is up and the FPGA
answers ping, and loads the partial bitstreams its slots name from its
partials directory with scripts/reconfslots.go.  With `program: once` in
the config, it does that once per target instead.  A config with a
functions table also loads each run's function into its slot first, unless
that slot holds it already.  Each run's complete
output, named by the config's name template, goes to a new directory
eval/<experiment>/results/<time>.  A run that fails keeps its output as
<name>.part instead, so it is neither plotted nor kept by --resume.
manifest.yaml there records the config, the testbed, the sha256 of every
bitstream loaded and how each run ended; runner.out keeps run.py's own
output.

Run it on the machine cabled to the U280.  That machine's settings, such as
its NIC, JTAG target and tool paths, come from eval/testbed.yaml: copy
eval/testbed.example.yaml to start one.  Plot the results with eval/plot.py.
"""
import argparse
import copy
import fcntl
import itertools
import os
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import traceback

from common import (DEFAULT_CONFIG, EVAL_DIR, FUNCTION_KEY, REPO_DIR, TARGET_KEY, ConfigError,
                    Experiment,
                    abs_path, build_record, find_experiment, git_info, log_complete, merge, now,
                    read_yaml, rel, sha256_file, write_yaml)

TESTBED_DEFAULTS = {
    "fpga": {"addr": "172.24.1.52", "port": 2888},
    "nic": "",
    "jtag": "",
    "start_cpu": 0,
    "tpa": "",
    "fperf": "",
    "tpa_id": "client",
    "tpa_cfg": "tcp {tso = 0; } dpdk { socket-mem = 8192; mbuf_mem_size = 6GB; }",
    "sudo": "sudo",
    "programfpga": "scripts/programfpga.sh",
    "reconfslots": "go run scripts/reconfslots.go",
    "reconf": {"chunk_size": 256, "hbm_addr": "0x10004000"},
    "settle": 10,
    "ready_timeout": 90,
    "pause": 3,
}
PROGRAM_SECONDS = 70            # programming plus link-up, for the time estimate only
RUN_OVERHEAD = 5                # fperf start-up and tear-down, for the estimate only


RESUME_TESTBED_KEYS = ("fpga", "start_cpu", "tpa_id", "tpa_cfg", "tpa", "fperf")


class RunError(Exception):
    """Something on the testbed that stops the whole run."""


class Log:
    """Timestamped progress lines, to the terminal and to runner.out."""

    def __init__(self):
        self.file = None

    def open(self, path):
        self.file = open(path, "a")

    def __call__(self, message):
        self.raw(f"{time.strftime('%H:%M:%S')}  {message}\n")

    def raw(self, text):
        console(text)
        if self.file:
            self.file.write(text)
            self.file.flush()


def console(text):
    sys.stdout.write(text)
    sys.stdout.flush()


log = Log()


def interrupted(signum, frame):
    raise KeyboardInterrupt


# ---------------------------------------------------------------- settings

def load_testbed(path=None):
    """The testbed settings, and the file they came from or None for the defaults."""
    if path is None:
        path = os.path.join(EVAL_DIR, "testbed.yaml")
        if not os.path.isfile(path):
            return copy.deepcopy(TESTBED_DEFAULTS), None
    else:
        path = abs_path(path, os.getcwd())
    # An empty mapping would replace a default one in merge(): drop it instead.
    data = {key: value for key, value in read_yaml(path).items() if value != {}}
    where = rel(path)
    for key, value in data.items():
        if key not in TESTBED_DEFAULTS:
            raise ConfigError(f"{where}: unknown key {key}")
        default = TESTBED_DEFAULTS[key]
        if isinstance(default, dict):
            if not isinstance(value, dict):
                raise ConfigError(f"{where}: {key} must be a mapping")
            unknown = set(value) - set(default)
            if unknown:
                raise ConfigError(f"{where}: {key}: unknown keys: "
                                  f"{', '.join(sorted(map(str, unknown)))}")
    tb = merge(copy.deepcopy(TESTBED_DEFAULTS), data)
    for key in ("nic", "jtag", "tpa", "fperf", "tpa_id", "tpa_cfg", "sudo",
                "programfpga", "reconfslots"):
        tb[key] = "" if tb[key] is None else str(tb[key])
    tb["fpga"]["addr"] = str(tb["fpga"]["addr"])
    hbm = tb["reconf"]["hbm_addr"]
    if isinstance(hbm, int) and not isinstance(hbm, bool):
        tb["reconf"]["hbm_addr"] = hex(hbm)
    else:
        tb["reconf"]["hbm_addr"] = str(hbm)
    for name, value, kind in (("fpga.port", tb["fpga"]["port"], int),
                              ("start_cpu", tb["start_cpu"], int),
                              ("reconf.chunk_size", tb["reconf"]["chunk_size"], int),
                              ("settle", tb["settle"], (int, float)),
                              ("ready_timeout", tb["ready_timeout"], (int, float)),
                              ("pause", tb["pause"], (int, float))):
        if isinstance(value, bool) or not isinstance(value, kind) or value < 0:
            raise ConfigError(f"{where}: {name} must be a non-negative number, not {value!r}")
    return tb, path


def executable(path):
    return os.path.isfile(path) and os.access(path, os.X_OK)


def find_tools(tb, need_program, need_reconf):
    """Where the programs to drive are, and the names of any not found."""
    tools, missing = {}, []

    def pick(label, setting, *fallbacks):
        if setting:
            if "/" in setting or setting.startswith("~"):
                path = abs_path(setting)
            else:
                path = shutil.which(setting) or setting
            if executable(path):
                return path
            missing.append(f"{label} ({setting})")
            return path
        for candidate in fallbacks:
            if candidate and executable(os.path.expanduser(candidate)):
                return os.path.expanduser(candidate)
        missing.append(label)
        return label

    tools["tpa"] = pick("tpa", tb["tpa"], shutil.which("tpa"), "~/.local/bin/tpa")
    tools["fperf"] = pick("fperf", tb["fperf"], "~/libtpa/build/bin/app/fperf",
                          "~/.local/bin/fperf", shutil.which("fperf"))
    if need_program:
        tools["programfpga"] = pick("programfpga", tb["programfpga"])
    if need_reconf:
        argv = shlex.split(tb["reconfslots"])
        if not argv:
            missing.append("reconfslots")
        else:
            found = abs_path(argv[0]) if "/" in argv[0] else shutil.which(argv[0])
            if found and executable(found):
                argv[0] = found
            else:
                missing.append(f"reconfslots ({argv[0]})")
        tools["reconfslots"] = argv
    return tools, missing


# ---------------------------------------------------------------- bitstreams

class TargetPlan:
    """A target checked on disk: its full image and its partial bitstreams,
    each with its sha256."""

    def __init__(self, target, functions):
        self.key = target.key
        self.bit = target.bitstream
        if not os.path.isfile(self.bit):
            raise ConfigError(f"target {self.key}: bitstream {rel(self.bit)} does not exist; "
                              f"fix the config or pass --bitstream {self.key}=FILE")
        self.bit_sha256 = sha256_file(self.bit)
        if target.sha256 and not self.bit_sha256.startswith(target.sha256):
            raise ConfigError(f"target {self.key}: {rel(self.bit)} has sha256 "
                              f"{self.bit_sha256[:16]}..., not the pinned {target.sha256}")
        # Our build tooling leaves RUN and STAGED beside jtag/, one level up.
        bit_dir = os.path.dirname(self.bit)
        self.build = build_record(bit_dir) or build_record(os.path.dirname(bit_dir))
        self.partials = target.partials
        self.slots = []                     # (slot, file name, path, sha256)
        self.functions = {}                 # f value: (slot, file name, path, sha256)
        if (target.slots or functions) and not (self.partials and os.path.isdir(self.partials)):
            raise ConfigError(f"target {self.key}: partials {rel(self.partials or '.')} is not a "
                              f"directory; fix the config or pass --partials {self.key}=DIR")
        for slot, name in sorted(target.slots.items()):
            path = abs_path(name, self.partials)
            if not os.path.isfile(path):
                raise ConfigError(f"target {self.key}: slot {slot}: {rel(path)} does not exist")
            self.slots.append((slot, name, path, sha256_file(path)))
        for value, spec in functions.items():
            path = abs_path(spec["partial"], self.partials)
            if not os.path.isfile(path):
                raise ConfigError(f"target {self.key}: functions.{value}: {rel(path)} "
                                  "does not exist")
            self.functions[value] = (spec["slot"], spec["partial"], path, sha256_file(path))

    def manifest(self, programmed=True):
        entry = {"bitstream": rel(self.bit), "sha256": self.bit_sha256}
        if not programmed:
            entry["programmed"] = False     # --no-program: whatever was loaded was measured
        if self.build:
            entry["build"] = dict(self.build)
        if self.slots or self.functions:
            entry["partials"] = rel(self.partials)
        if self.slots:
            entry["slots"] = {str(slot): {"file": name, "sha256": sha}
                              for slot, name, _, sha in self.slots}
        if self.functions:
            entry["functions"] = {value: {"slot": slot, "file": name, "sha256": sha}
                                  for value, (slot, name, _, sha) in self.functions.items()}
        return entry


# ---------------------------------------------------------------- commands

def program_argv(bit, tools):
    return [tools["programfpga"], bit]


def slot_argv(slot, path, tb, tools):
    return tools["reconfslots"] + [
        "-addr", f"{tb['fpga']['addr']}:{tb['fpga']['port']}",
        "-slot", str(slot),
        "-chunk-size", str(tb["reconf"]["chunk_size"]),
        "-hbm-addr", tb["reconf"]["hbm_addr"],
        "-query-status", path]


def fperf_argv(exp, point, tb, tools, nic):
    # timeout ends a hung run, and -k follows up with SIGKILL.  It runs under
    # sudo, since fperf runs as root and an unprivileged timeout cannot kill it.
    return (shlex.split(tb["sudo"]) + ["timeout", "-k", "15", str(point["d"] + 120)] +
            ["env", f"TPA_ID={tb['tpa_id']}", f"TPA_ETH_DEV={nic}",
             "TPA_CFG=" + " ".join(cfg for cfg in (tb["tpa_cfg"], exp.tpa_cfg) if cfg),
             tools["tpa"], "run", tools["fperf"],
             "-c", tb["fpga"]["addr"], "-p", str(tb["fpga"]["port"]),
             "-S", str(tb["start_cpu"])] +
            exp.fperf_args(point))


def stop(proc):
    """Stop a child gently, then firmly."""
    for sig, grace in ((signal.SIGINT, 20), (signal.SIGTERM, 10), (signal.SIGKILL, 5)):
        if proc.poll() is not None:
            return
        try:
            proc.send_signal(sig)
            proc.wait(grace)
            return
        except ProcessLookupError:
            return
        except subprocess.TimeoutExpired:
            continue


def run_streamed(argv, sinks, env=None):
    """Run `argv` from the repository root and hand each line it prints to
    every sink; return its exit status."""
    proc = subprocess.Popen(argv, cwd=REPO_DIR, env=env, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, errors="replace", bufsize=1)
    try:
        for line in proc.stdout:
            for sink in sinks:
                sink(line)
        return proc.wait()
    except BaseException:
        stop(proc)
        raise


def quiet_run(argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True)
    except OSError:
        return None


# ---------------------------------------------------------------- the testbed

def detect_nic(addr):
    """The interface with a direct route to `addr`, or None."""
    done = quiet_run(["ip", "-o", "route", "get", addr])
    if not done or done.returncode != 0:
        return None
    words = done.stdout.split()
    if "via" in words or "dev" not in words or words.index("dev") + 1 >= len(words):
        return None
    return words[words.index("dev") + 1]


def ipv4_of(nic):
    done = quiet_run(["ip", "-4", "-o", "addr", "show", "dev", nic])
    lines = done.stdout.splitlines() if done and done.returncode == 0 else []
    for line in lines:
        words = line.split()
        if "inet" in words and words.index("inet") + 1 < len(words):
            return words[words.index("inet") + 1]
    return None


def operstate(nic):
    try:
        with open(os.path.join("/sys/class/net", nic, "operstate")) as f:
            return f.read().strip()
    except OSError:
        return "missing"


def answers_ping(addr):
    done = quiet_run(["ping", "-c", "1", "-W", "1", addr])
    return done is not None and done.returncode == 0


def wait_ready(tb, state, timeout, quiet=False):
    """Wait until the NIC facing the FPGA has an address and the FPGA answers
    ping, and remember the NIC in state["nic"].  False after `timeout` s."""
    addr = tb["fpga"]["addr"]
    deadline = time.monotonic() + timeout
    waited = False
    while True:
        nic = tb["nic"] or detect_nic(addr)
        ip4 = ipv4_of(nic) if nic else None
        if not nic:
            why = f"no interface has a direct route to {addr}; set nic in the testbed file"
        elif not ip4:
            why = f"{nic} is {operstate(nic)} and has no IPv4 address"
        elif not answers_ping(addr):
            why = f"{nic} is {operstate(nic)}, but {addr} does not answer ping"
        else:
            state["nic"] = nic
            if waited or not quiet:
                log(f"{nic} ({ip4}) is up and {addr} answers ping")
            return True
        if time.monotonic() >= deadline:
            log(f"no FPGA after {timeout:g} s: {why}")
            return False
        waited = True
        time.sleep(2)


def program(bit, tb, tools):
    """Program the FPGA with a full image over JTAG."""
    env = dict(os.environ)
    if tb["jtag"]:
        env["HW_TARGET"] = tb["jtag"]
    log(f"programming {rel(bit)}")
    rc = run_streamed(program_argv(bit, tools), [log.raw], env)
    if rc != 0:
        log(f"programfpga.sh failed with status {rc}")
    return rc == 0


def load_slot(slot, path, tb, tools):
    """Load one partial bitstream into a slot through the reconfiguration controller."""
    log(f"loading {rel(path)} into slot {slot}")
    rc = run_streamed(slot_argv(slot, path, tb, tools), [log.raw])
    if rc != 0:
        log(f"reconfslots failed with status {rc}")
    return rc == 0


def run_fperf(exp, point, tb, tools, nic, path):
    """One fperf run; (status, exit status).  The output goes to `path`.part
    and takes its final name only when the run completed."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    part = path + ".part"
    with open(part, "w") as out:
        def save(text):
            out.write(text)
            out.flush()
        rc = run_streamed(fperf_argv(exp, point, tb, tools, nic), [save, console])
    if rc == 0 and log_complete(part, point["d"]):
        os.replace(part, path)
        return "ok", rc
    if rc == 124:
        return "timed out", rc
    return ("failed" if rc else "incomplete"), rc


class SudoKeeper:
    """Ask for the sudo password once if one is needed, then keep sudo's
    timestamp fresh, since a sweep can outlast it."""

    def __init__(self, sudo):
        self._stop = threading.Event()
        argv = shlex.split(sudo)
        if not argv or os.path.basename(argv[0]) != "sudo":
            return
        quiet = {"stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
        if subprocess.run(["sudo", "-n", "true"], **quiet).returncode != 0:
            if "-n" in argv[1:]:
                raise RunError("sudo wants a password here, but the testbed's sudo setting has -n")
            log("fperf needs root for DPDK, so sudo asks for your password once")
            if subprocess.run(["sudo", "-v"]).returncode != 0:
                raise RunError("sudo authentication failed")
        threading.Thread(target=self._refresh, daemon=True).start()

    def _refresh(self):
        while not self._stop.wait(60):
            subprocess.run(["sudo", "-n", "-v"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)

    def stop(self):
        self._stop.set()


def lock_testbed():
    """Refuse to share the testbed with another run.py on this machine."""
    path = os.path.join(tempfile.gettempdir(), "frac-eval-run.lock")
    try:
        # Open before creating: with fs.protected_regular, O_CREAT on another
        # user's file in /tmp fails even when the file already exists.
        fd = os.open(path, os.O_RDONLY)
    except FileNotFoundError:
        fd = os.open(path, os.O_RDONLY | os.O_CREAT, 0o666)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        raise RunError("another eval/run.py is running on this machine")
    return fd


def warn_cores(points, tb):
    """Warn when fperf would pin more client threads than there are cpus."""
    clients = [point["n"] for point in points if isinstance(point.get("n"), int)]
    try:
        cpus = len(os.sched_getaffinity(0))
    except AttributeError:
        cpus = os.cpu_count() or 0
    if clients and cpus and tb["start_cpu"] + max(clients) > cpus:
        log(f"warning: fperf pins one client thread per cpu from cpu {tb['start_cpu']}, "
            f"and {max(clients)} threads do not fit in the {cpus} cpus here")


# ---------------------------------------------------------------- the run

def estimate(exp, points, plans, tb, args):
    """Rough seconds the runs take."""
    every_run = exp.program == "every_run" and not args.no_program
    seconds = 0
    for key, group in itertools.groupby(points, key=lambda point: str(point[TARGET_KEY])):
        group = list(group)
        setup = PROGRAM_SECONDS + tb["settle"] + 2 * len(plans[key].slots)
        if every_run:
            seconds += setup * len(group)
        elif not args.no_program:
            seconds += setup
        if exp.functions and not args.no_program:
            seconds += 2 * len(group)       # a function load before each run, at most
        seconds += sum(point["d"] + RUN_OVERHEAD + tb["pause"] for point in group)
    return seconds


def record(manifest, entry):
    """Add a run to the manifest, replacing an earlier entry for the same log."""
    runs = manifest.setdefault("runs", [])
    for index, old in enumerate(runs):
        if isinstance(old, dict) and old.get("log") == entry["log"]:
            runs[index] = entry
            return
    runs.append(entry)


def testbed_summary(tb, tb_path, tools):
    return {
        "file": rel(tb_path) if tb_path else None,
        "fpga": f"{tb['fpga']['addr']}:{tb['fpga']['port']}",
        "nic": tb["nic"] or "auto",
        "jtag": tb["jtag"] or "first target",
        "start_cpu": tb["start_cpu"],
        "tpa_id": tb["tpa_id"],
        "tpa_cfg": tb["tpa_cfg"],
        "tpa": tools["tpa"],
        "fperf": tools["fperf"],
    }


def check_resumable(manifest, exp, plans, testbed, programmed, run_dir):
    """Refuse to mix runs of different configs, testbeds or bitstreams in one
    directory."""
    where = rel(run_dir)
    config = os.path.basename(exp.config_path)
    if manifest.get("config", config) != config:
        raise ConfigError(f"{where} was measured with {manifest['config']}; resume it with "
                          f"-c {manifest['config']}, or start a new run")
    for key, mine in (("program", exp.program), ("tpa_cfg", exp.tpa_cfg),
                      ("functions", exp.functions), ("params", exp.params),
                      ("name", exp.name_template), ("fperf", exp.fperf_template)):
        if key in manifest and manifest[key] != mine:
            raise ConfigError(f"{where} was measured with a different {key}; "
                              "start a new run instead")
    old_testbed = manifest.get("testbed") or {}
    for key in RESUME_TESTBED_KEYS:
        if key in old_testbed and old_testbed[key] != testbed[key]:
            raise ConfigError(f"{where} was measured with testbed {key} {old_testbed[key]!r}, "
                              f"not {testbed[key]!r}; start a new run instead")
    for key, plan in plans.items():
        old = (manifest.get("targets") or {}).get(key)
        if not old:
            continue
        new = plan.manifest(programmed)
        for field in ("sha256", "slots", "functions", "programmed"):
            if old.get(field) != new.get(field):
                raise ConfigError(f"{where} measured {TARGET_KEY}_{key} with other bitstreams, "
                                  "or without programming them; start a new run instead")


def open_run(exp, plans, tb, tb_path, tools, resume_dir, programmed):
    """The run directory and its manifest: a new one, or the one to resume."""
    testbed = testbed_summary(tb, tb_path, tools)
    if resume_dir is None:
        run_dir = exp.new_run()
        manifest = {
            "experiment": exp.name,
            "config": os.path.basename(exp.config_path),
            "description": exp.description,
            "started": now(),
            "host": socket.gethostname(),
            "repo": git_info(REPO_DIR),
            "libtpa": git_info(os.path.dirname(tools["fperf"])),
            "testbed": testbed,
            "params": exp.params,
            "sweep": {key: values for key, values in exp.sweep},
            "name": exp.name_template,
            "fperf": exp.fperf_template,
            "program": exp.program,
            "functions": exp.functions,
            "tpa_cfg": exp.tpa_cfg,
            "targets": {},
            "runs": [],
        }
    else:
        run_dir = resume_dir
        path = os.path.join(run_dir, "manifest.yaml")
        manifest = read_yaml(path) if os.path.isfile(path) else {}
        check_resumable(manifest, exp, plans, testbed, programmed, run_dir)
        manifest.setdefault("resumed", []).append(now())
        manifest.setdefault("config", os.path.basename(exp.config_path))
        manifest.setdefault("testbed", testbed)
        manifest.setdefault("params", exp.params)
        manifest.setdefault("name", exp.name_template)
        manifest.setdefault("fperf", exp.fperf_template)
        manifest.setdefault("program", exp.program)
        manifest.setdefault("functions", exp.functions)
        manifest.setdefault("tpa_cfg", exp.tpa_cfg)
        manifest.setdefault("targets", {})
        manifest.setdefault("runs", [])
    for key, plan in plans.items():
        manifest["targets"][key] = plan.manifest(programmed)
    write_yaml(os.path.join(run_dir, "manifest.yaml"), manifest)
    return run_dir, manifest


def measure(exp, args, points, plans, tb, tools, run_dir, manifest):
    """Program, load and run every point in turn; return this session's statuses."""
    manifest_path = os.path.join(run_dir, "manifest.yaml")
    state = {"nic": tb["nic"] or None, "slots": {}}     # slots: what run.py loaded where
    statuses = []

    def finish(point, name, status, started=None, rc=None):
        entry = {"log": name}
        entry.update((key, point[key]) for key in exp.swept)
        entry["status"] = status
        if started:
            entry["started"] = started[0]
            entry["seconds"] = round(time.monotonic() - started[1], 1)
        if rc is not None:
            entry["exit"] = rc
        if status != "ok" and os.path.exists(os.path.join(run_dir, name + ".part")):
            entry["partial"] = name + ".part"
        record(manifest, entry)
        if state["nic"] and isinstance(manifest.get("testbed"), dict):
            manifest["testbed"]["nic"] = state["nic"]
        write_yaml(manifest_path, manifest)
        statuses.append(status)

    def prepare(plan, label):
        """Program the target's image and load its slots; None, or why that failed."""
        if args.no_program:
            log(f"{label}: measuring the image already on the FPGA")
        elif program(plan.bit, tb, tools):
            state["slots"] = {}
            log(f"settling for {tb['settle']:g} s")
            time.sleep(tb["settle"])
        else:
            return "programming failed"
        if not wait_ready(tb, state, tb["ready_timeout"]):
            return "the FPGA did not come up"
        if not args.no_program:
            for slot, _, path, _ in plan.slots:
                if not load_slot(slot, path, tb, tools):
                    state["slots"].pop(slot, None)
                    return f"loading slot {slot} failed"
                state["slots"][slot] = path
        return None

    def load_function(plan, point):
        """Load the point's function into its slot unless it is there already;
        None, or why that failed."""
        if not exp.functions or args.no_program:
            return None
        slot, _, path, _ = plan.functions[str(point[FUNCTION_KEY])]
        if state["slots"].get(slot) == path:
            return None
        if load_slot(slot, path, tb, tools):
            state["slots"][slot] = path
            return None
        state["slots"].pop(slot, None)
        return f"loading {rel(path)} into slot {slot} failed"

    every_run = exp.program == "every_run" and not args.no_program
    for key, group in itertools.groupby(points, key=lambda point: str(point[TARGET_KEY])):
        plan, label = plans[key], f"{TARGET_KEY}_{key}"
        todo = []
        for point in group:
            name = exp.log_name(point)
            path = os.path.join(run_dir, name)
            if args.resume is not None and log_complete(path, point["d"]):
                log(f"keep {name}")
                statuses.append("kept")
            else:
                todo.append((point, name, path))
        if not todo:
            continue

        if not every_run:
            why = prepare(plan, label)
            if why:
                log(f"{label}: {why}; skipping its {len(todo)} runs")
                for point, name, _ in todo:
                    finish(point, name, f"skipped: {why}")
                continue

        for index, (point, name, path) in enumerate(todo):
            if every_run:
                why = prepare(plan, label)
                if why:
                    log(f"{label}: {why}; skipping {name}")
                    finish(point, name, f"skipped: {why}")
                    continue
            elif not wait_ready(tb, state, tb["ready_timeout"], quiet=True):
                for later, later_name, _ in todo[index:]:
                    finish(later, later_name, "skipped: the FPGA stopped answering")
                break
            why = load_function(plan, point)
            if why:
                log(f"{label}: {why}; skipping {name}")
                finish(point, name, f"skipped: {why}")
                continue
            shown = "  ".join(f"{k}={point[k]}" for k in exp.swept if k != TARGET_KEY)
            log(f"{label}  {shown}  {name}")
            started = (now(), time.monotonic())
            try:
                status, rc = run_fperf(exp, point, tb, tools, state["nic"], path)
            except KeyboardInterrupt:
                finish(point, name, "interrupted", started)
                raise
            finish(point, name, status, started, rc)
            if status != "ok":
                log(f"{name}: {status}, exit status {rc}")
            time.sleep(tb["pause"])
    return statuses


def summarize(exp, run_dir, manifest):
    runs = [run for run in manifest.get("runs") or [] if isinstance(run, dict)]
    bad = [run for run in runs if run.get("status") != "ok"]
    log(f"{len(runs) - len(bad)} of {len(runs)} runs are complete in {rel(run_dir)}")
    for run in bad:
        log(f"  {run.get('status')}: {run.get('log')}")
    config = f" -c {os.path.basename(exp.config_path)}" if exp.variant else ""
    name = os.path.basename(run_dir)
    if bad:
        log(f"redo those with: eval/run.py {exp.name}{config} --resume {name}")
    log(f"plot with: eval/plot.py {exp.name}{config} --run {name}")


def print_plan(exp, points, plans, tb, tb_path, tools, missing, args, resume_dir):
    """What a run would do, with every command it would run."""
    nic = tb["nic"] or detect_nic(tb["fpga"]["addr"]) or "<nic>"
    every_run = exp.program == "every_run" and not args.no_program
    testbed = rel(tb_path) if tb_path else "built-in defaults; there is no eval/testbed.yaml"
    print(f"experiment  {exp.name}, {rel(exp.config_path)}")
    if exp.description:
        print(f"            {exp.description}")
    print(f"testbed     {testbed}")
    print(f"fpga        {tb['fpga']['addr']}:{tb['fpga']['port']} through {nic}")
    if missing:
        print(f"not found   {', '.join(missing)}")
    print(f"results     {rel(resume_dir) if resume_dir else 'a new directory in ' + rel(exp.results)}")
    print(f"runs        {len(points)}, about {estimate(exp, points, plans, tb, args) / 60:.0f} min")
    for key, group in itertools.groupby(points, key=lambda point: str(point[TARGET_KEY])):
        plan = plans[key]
        print(f"\n{TARGET_KEY}_{key}  {rel(plan.bit)}")
        print(f"  sha256 {plan.bit_sha256}")
        if plan.build:
            print("  built " + ", ".join(f"{k} {v}" for k, v in plan.build.items()))
        if args.no_program:
            print("  not programmed: --no-program")
        else:
            print("  before every run:" if exp.program == "every_run" else "  once:")
            prefix = f"HW_TARGET={shlex.quote(tb['jtag'])} " if tb["jtag"] else ""
            print("    $ " + prefix + shlex.join(program_argv(plan.bit, tools)))
            for slot, _, path, sha in plan.slots:
                print(f"    # slot {slot}: {rel(path)}, sha256 {sha}")
                print("    $ " + shlex.join(slot_argv(slot, path, tb, tools)))
        loaded = {slot: path for slot, _, path, _ in plan.slots}
        for point in group:
            name = exp.log_name(point)
            if resume_dir and log_complete(os.path.join(resume_dir, name), point["d"]):
                print(f"  keep {name}")
                continue
            if every_run:
                loaded = {slot: path for slot, _, path, _ in plan.slots}
            if exp.functions and not args.no_program:
                slot, _, path, sha = plan.functions[str(point[FUNCTION_KEY])]
                if loaded.get(slot) != path:
                    print(f"  # {FUNCTION_KEY}={point[FUNCTION_KEY]}: load {rel(path)} into "
                          f"slot {slot}, sha256 {sha}")
                    print("  $ " + shlex.join(slot_argv(slot, path, tb, tools)))
                    loaded[slot] = path
            print("  $ " + shlex.join(fperf_argv(exp, point, tb, tools, nic)))
            print(f"      > {name}")


def parse_args(argv):
    parser = argparse.ArgumentParser(prog="eval/run.py", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("experiment", help="a directory under eval/, such as latency_throughput")
    parser.add_argument("-c", "--config", default=DEFAULT_CONFIG, metavar="FILE",
                        help=f"config in the experiment directory (default {DEFAULT_CONFIG})")
    parser.add_argument("--testbed", metavar="FILE",
                        help="testbed settings (default eval/testbed.yaml, else built-in defaults)")
    parser.add_argument("--bitstream", action="append", default=[], metavar="O=FILE",
                        help="program FILE for target O instead; repeatable")
    parser.add_argument("--partials", action="append", default=[], metavar="O=DIR",
                        help="take target O's partial bitstreams from DIR instead; repeatable")
    parser.add_argument("--only", action="append", default=[], metavar="KEY=V1,V2",
                        help="run only these values of a swept key, such as --only n=1,22; "
                             "repeatable")
    parser.add_argument("--resume", nargs="?", const="", metavar="RUN",
                        help="continue RUN, by default this config's newest, keeping its "
                             "complete logs")
    parser.add_argument("--no-program", action="store_true",
                        help="neither program the FPGA nor load slots: measure what is loaded")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the plan and its commands, and touch nothing")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    try:
        exp = Experiment(find_experiment(args.experiment), args.config)
        for option, specs, setter in (("--bitstream", args.bitstream, "set_bitstream"),
                                      ("--partials", args.partials, "set_partials")):
            for spec in specs:
                key, sep, path = spec.partition("=")
                if not sep or not path:
                    raise ConfigError(f"{option} {spec}: expected O=PATH")
                if key not in exp.targets:
                    raise ConfigError(f"{option} {spec}: the config has no target {key}")
                getattr(exp.targets[key], setter)(path, os.getcwd())
        points = exp.points(exp.parse_only(args.only))
        keys = list(dict.fromkeys(str(point[TARGET_KEY]) for point in points))
        if args.no_program and len(keys) > 1:
            raise ConfigError("--no-program measures whatever image is loaded, so choose one "
                              f"target with --only {TARGET_KEY}=VALUE")
        if (args.no_program and exp.functions
                and len({str(point[FUNCTION_KEY]) for point in points}) > 1):
            raise ConfigError("--no-program cannot switch functions, so choose one with "
                              f"--only {FUNCTION_KEY}=VALUE")
        tb, tb_path = load_testbed(args.testbed)
        plans = {key: TargetPlan(exp.targets[key], exp.functions) for key in keys}
        need_reconf = not args.no_program and bool(
            exp.functions or any(plans[key].slots for key in keys))
        tools, missing = find_tools(tb, not args.no_program, need_reconf)
        resume_dir = None if args.resume is None else exp.find_run(args.resume or None)
        if missing and not args.dry_run:
            where = rel(tb_path) if tb_path else "eval/testbed.yaml, starting from testbed.example.yaml"
            raise ConfigError(f"not found: {', '.join(missing)}; set the paths in {where}")
    except ConfigError as e:
        sys.exit(f"run.py: {e}")

    if args.dry_run:
        print_plan(exp, points, plans, tb, tb_path, tools, missing, args, resume_dir)
        return 0

    signal.signal(signal.SIGTERM, interrupted)
    if signal.getsignal(signal.SIGHUP) is not signal.SIG_IGN:     # nohup keeps it ignored
        signal.signal(signal.SIGHUP, interrupted)
    keeper = None
    try:
        lock = lock_testbed()
        keeper = SudoKeeper(tb["sudo"])     # before any run directory exists
        run_dir, manifest = open_run(exp, plans, tb, tb_path, tools, resume_dir,
                                     not args.no_program)
    except (ConfigError, RunError, OSError) as e:
        if keeper:
            keeper.stop()
        sys.exit(f"run.py: {e}")
    except KeyboardInterrupt:
        print("run.py: interrupted", file=sys.stderr)
        return 130
    log.open(os.path.join(run_dir, "runner.out"))
    log(f"{exp.name}: {len(points)} runs, about {estimate(exp, points, plans, tb, args) / 60:.0f} min, "
        f"into {rel(run_dir)}")
    code = 0
    try:
        warn_cores(points, tb)
        statuses = measure(exp, args, points, plans, tb, tools, run_dir, manifest)
        code = 0 if all(status in ("ok", "kept") for status in statuses) else 1
    except KeyboardInterrupt:
        log("interrupted")
        code = 130
    except RunError as e:
        log(f"stopped: {e}")
        code = 1
    except Exception:
        log.raw(traceback.format_exc())
        log("stopped by the error above")
        code = 1
    finally:
        keeper.stop()
        manifest["finished"] = now()
        write_yaml(os.path.join(run_dir, "manifest.yaml"), manifest)
        os.close(lock)
    summarize(exp, run_dir, manifest)
    return code


if __name__ == "__main__":
    sys.exit(main())
