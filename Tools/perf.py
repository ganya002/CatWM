#!/usr/bin/env python3
"""Measure CPU and memory, check each P99 against Tools/Perf/budgets.json and write a Markdown table.

The caps are for the device in budgets.json. A fixed benchmark (CatWMPerf calibrate) measures how fast
this machine is next to that device, and each CPU time in ms is scaled to that device before the check,
so a faster or slower runner needs no new caps.

Run `swift build -c release` and `CATWM_INSTANCE=perf ./build.sh` first. The runs go in parallel.
Each engine scenario runs in a new CatWMPerf process. The app scenario starts build/CatWM.app as the
named instance `perf-<run>`, scoped to this process, so it manages no window. When a CatWM runs (a developer's
Mac), the instances also go on a private agent display that it opens for this run, and they draw nothing on the
real screens. Without one (CI), they run on the real display as before and the script says so. The exit status is
1 when a value is over its cap.

    python3 Tools/perf.py [--runs N] [--out report.md] [--json samples.json]
"""
import argparse
import ctypes
import json
import math
import os
import signal
import statistics
import subprocess
import sys
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Clients/python"))
from catwm import CatWMError  # noqa: E402
from catwm.testing import Sandbox  # noqa: E402

PERF = ROOT / ".build/release/CatWMPerf"
APP = ROOT / "build/CatWM.app/Contents/MacOS/CatWM"
BUDGETS = ROOT / "Tools/Perf/budgets.json"
ENGINE_SCENARIOS = ["calibrate", "engine-idle", "engine-tile", "engine-actions", "config-load"]
APP_LAUNCH_SECONDS, APP_IDLE_SECONDS = 5, 20

libc = ctypes.CDLL(None)


class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


timebase = Timebase()
libc.mach_timebase_info(ctypes.byref(timebase))
TICK_NS = timebase.numer / timebase.denom


def usage(pid):
    """CPU in ms, idle wakeups, and footprint and lifetime peak in MB, from proc_pid_rusage."""
    # rusage_info_v4: a 16-byte UUID, then uint64 fields.
    buffer = (ctypes.c_uint64 * 64)()
    if libc.proc_pid_rusage(pid, 4, ctypes.byref(buffer)) != 0:
        raise OSError(f"proc_pid_rusage({pid}) failed")
    fields = buffer[2:]
    mb = 1024 * 1024
    return {"cpu": (fields[0] + fields[1]) * TICK_NS / 1e6, "wakeups": fields[2],
            "footprint": fields[7] / mb, "peak": fields[28] / mb}


def run_engine(scenario):
    result = subprocess.run([str(PERF), scenario], capture_output=True, text=True, timeout=300)
    if result.returncode != 0:
        sys.exit(f"perf: {scenario} failed\n{result.stderr}")
    return json.loads(result.stdout)


def open_display():
    """Open an agent display through the running CatWM. Returns (sandbox, uuid), or (None, None) without one."""
    try:
        sandbox = Sandbox(timeout=15)
    except (unittest.SkipTest, CatWMError, OSError) as error:
        print(f"perf: no agent display ({error}); the app scenario runs on the real display", file=sys.stderr)
        return None, None
    return sandbox, sandbox.display["uuid"]


def scope(display):
    return f"pids:{os.getpid()}" + (f";display:{display}" if display else "")


def run_app(run, display=None):
    env = {**os.environ, "CATWM_INSTANCE": f"perf-{run}", "CATWM_SCOPE": scope(display)}
    process = subprocess.Popen([str(APP)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    samples = {}
    try:
        time.sleep(APP_LAUNCH_SECONDS)
        if process.poll() is not None:
            sys.exit(f"perf: CatWM.app quit during launch with status {process.returncode}")
        last = usage(process.pid)
        samples["app.launch.cpu"] = [last["cpu"]]
        for _ in range(APP_IDLE_SECONDS):
            time.sleep(1)
            now = usage(process.pid)
            samples.setdefault("app.idle.cpu", []).append(now["cpu"] - last["cpu"])
            samples.setdefault("app.idle.wakeups", []).append(now["wakeups"] - last["wakeups"])
            last = now
        samples["app.idle.footprint"] = [last["footprint"]]
        samples["app.peak.footprint"] = [last["peak"]]
    finally:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
    return samples


def machine():
    def read(key):
        return subprocess.run(["sysctl", "-n", key], capture_output=True, text=True).stdout.strip()
    return f"{read('machdep.cpu.brand_string')}, {read('hw.ncpu')} cores, {int(read('hw.memsize')) // 2**30} GB"


def percentile(values, share):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(share * len(ordered)) - 1)]


def stats(values):
    return {"median": statistics.median(values), "mean": statistics.fmean(values), "p99": percentile(values, 0.99)}


def number(value):
    if value == int(value):
        return f"{value:,.0f}"
    return f"{value:,.0f}" if abs(value) >= 100 else f"{value:.2f}" if abs(value) >= 1 else f"{value:.3f}"


def report(samples, budgets, runner):
    device = budgets["device"]
    speed = device["calibrate"] / statistics.median(samples["calibrate.cpu"])
    tables, failed = {}, []
    for metric, budget in budgets["rows"].items():
        values = samples.get(metric)
        if values and budget["unit"] == "ms":
            values = [value * speed for value in values]
        row = stats(values) if values else None
        ok = row is not None and row["p99"] <= budget["cap"]
        if not ok:
            failed.append(metric)
        if row:
            p99 = number(row["p99"]) if ok else f"**{number(row['p99'])}**"
            cells = f"{number(row['median'])} | {number(row['mean'])} | {p99}"
        else:
            cells = "| | **none**"
        tables.setdefault(budget["group"], []).append(
            f"| {budget['label']} | {cells} | ≤ {budget['cap']:,g} {budget['unit']} | {'✅' if ok else '❌'} |")
    note = f"(as an {device['name']} · runner: {runner}, speed {speed:.2f}×)"
    lines = [f"### ✅ Performance {note}" if not failed else f"### ❌ Performance: {len(failed)} over the cap {note}"]
    for group, rows in tables.items():
        lines += ["", f"| {group} | Median | Mean | P99 | Cap | |", "|:--|:--|:--|:--|:--|:--|", *rows]
    return "\n".join([*lines, ""]), failed


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runs", type=int, default=5, help="runs of each scenario (default 5)")
    parser.add_argument("--out", type=Path, help="write the Markdown table to this file")
    parser.add_argument("--json", type=Path, help="write the raw samples to this file")
    parser.add_argument("--skip-app", action="store_true", help="measure only the engine scenarios")
    args = parser.parse_args()

    budgets = json.loads(BUDGETS.read_text())
    if args.skip_app:
        budgets["rows"] = {key: value for key, value in budgets["rows"].items() if not key.startswith("app.")}
    sandbox, display = (None, None) if args.skip_app else open_display()

    def run(number):
        results = [run_engine(scenario) for scenario in ENGINE_SCENARIOS]
        if not args.skip_app:
            results.append(run_app(number, display))
        print(f"perf: run {number} done", file=sys.stderr)
        return results

    samples = {}
    try:
        with ThreadPoolExecutor(max_workers=args.runs) as pool:
            for results in pool.map(run, range(1, args.runs + 1)):
                for result in results:
                    for metric, values in result.items():
                        samples.setdefault(metric, []).extend(values)
    finally:
        if sandbox:
            sandbox.close()

    table, failed = report(samples, budgets, machine())
    print(table)
    if args.out:
        args.out.write_text(table)
    if args.json:
        args.json.write_text(json.dumps(samples, indent=1, sort_keys=True))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
