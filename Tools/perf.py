#!/usr/bin/env python3
"""Measure CPU and memory, check each P99 against Tools/Perf/budgets.json and write a Markdown table.

Run `swift build -c release` and `CATWM_INSTANCE=perf ./build.sh` first. Each engine scenario runs
in a new CatWMPerf process. The app scenario starts build/CatWM.app as the named instance `perf`,
scoped to this process, so it manages no window. The exit status is 1 when a value is over its cap.

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
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PERF = ROOT / ".build/release/CatWMPerf"
APP = ROOT / "build/CatWM.app/Contents/MacOS/CatWM"
BUDGETS = ROOT / "Tools/Perf/budgets.json"
ENGINE_SCENARIOS = ["engine-idle", "engine-tile", "engine-actions", "config-load"]
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


def run_app():
    env = {**os.environ, "CATWM_INSTANCE": "perf", "CATWM_SCOPE": f"pids:{os.getpid()}"}
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


def percentile(values, share):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(share * len(ordered)) - 1)]


def stats(values):
    return {"median": statistics.median(values), "mean": statistics.fmean(values), "p99": percentile(values, 0.99)}


def number(value):
    if value == int(value):
        return f"{value:,.0f}"
    return f"{value:,.0f}" if abs(value) >= 100 else f"{value:.2f}" if abs(value) >= 1 else f"{value:.3f}"


def report(samples, budgets):
    tables, failed = {}, []
    for metric, budget in budgets.items():
        values = samples.get(metric)
        row = stats(values) if values else None
        ok = row is not None and row["p99"] <= budget["cap"]
        if not ok:
            failed.append(metric)
        if row:
            p99 = number(row["p99"]) if ok else f"**{number(row['p99'])}**"
            cells = f"{number(row['median'])} | {number(row['mean'])} | {p99}"
        else:
            cells = "| | **none**"
        cap = number(budget["cap"]) if budget["cap"] >= 1 else f"{budget['cap']:g}"
        tables.setdefault(budget["group"], []).append(
            f"| {budget['label']} | {cells} | ≤ {cap} {budget['unit']} | {'✅' if ok else '❌'} |")
    lines = ["### ✅ Performance" if not failed else f"### ❌ Performance: {len(failed)} over the cap"]
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
        budgets = {key: value for key, value in budgets.items() if not key.startswith("app.")}
    samples = {}
    for run in range(args.runs):
        for scenario in ENGINE_SCENARIOS:
            for metric, values in run_engine(scenario).items():
                samples.setdefault(metric, []).extend(values)
        if not args.skip_app:
            for metric, values in run_app().items():
                samples.setdefault(metric, []).extend(values)
        print(f"perf: run {run + 1} of {args.runs} done", file=sys.stderr)

    table, failed = report(samples, budgets)
    print(table)
    if args.out:
        args.out.write_text(table)
    if args.json:
        args.json.write_text(json.dumps(samples, indent=1, sort_keys=True))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
