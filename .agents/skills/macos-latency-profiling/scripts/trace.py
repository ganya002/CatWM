#!/usr/bin/env python3
"""Bounded xctrace capture and XML export without target launch or restart."""
import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def identity(pid):
    result = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "lstart=,comm="],
                            capture_output=True, text=True, check=False)
    return result.stdout.strip() if result.returncode == 0 else None


def information(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10, check=False)
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def fresh_path(path):
    if path.exists() or path.is_symlink():
        raise ValueError(f"Refusing to overwrite {path}")


def command_for(args):
    if args.action == "templates":
        return ["xcrun", "xctrace", "list", "templates"]
    if args.action == "record":
        if args.pid is not None and args.pid <= 0:
            raise ValueError("pid must be greater than 0")
        if not math.isfinite(args.seconds) or args.seconds <= 0:
            raise ValueError("seconds must be finite and greater than 0")
        if args.output.suffix != ".trace":
            raise ValueError("The output path must end in .trace")
        fresh_path(args.output)
        command = ["xcrun", "xctrace", "record", "--template", args.template,
                   "--time-limit", f"{args.seconds:g}s", "--output", str(args.output)]
        command += ["--attach", str(args.pid)] if args.pid is not None else ["--all-processes"]
        if args.no_prompt:
            command.append("--no-prompt")
        return command
    if not args.trace.is_dir():
        raise ValueError(f"Trace bundle not found: {args.trace}")
    fresh_path(args.output)
    return ["xcrun", "xctrace", "export", "--input", str(args.trace)] + (
        ["--toc"] if args.action == "toc" else ["--xpath", args.xpath])


def stop_recording(process):
    if process.poll() is None:
        try:
            process.send_signal(signal.SIGINT)
        except ProcessLookupError:
            process.wait()
            return
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            try:
                process.kill()
            except ProcessLookupError:
                pass
            process.wait()


def record(args, command):
    metadata = args.output.with_suffix(".metadata.json")
    logfile = args.output.with_suffix(".xctrace.log")
    for path in (metadata, logfile):
        fresh_path(path)
    target = identity(args.pid) if args.pid is not None else None
    if args.pid is not None and not target:
        raise ValueError(f"Target PID {args.pid} is not running")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report = {"command": command, "started_utc": datetime.now(timezone.utc).isoformat(),
              "target_pid": args.pid, "target_before": target,
              "macos_version": information(["sw_vers", "-productVersion"]),
              "macos_build": information(["sw_vers", "-buildVersion"]),
              "xcode": information(["xcodebuild", "-version"]), "status": "starting"}
    # Reserve sidecars before recording so an existing experiment cannot be replaced.
    with metadata.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2)
    started = time.monotonic()
    process = None
    exit_code = 1
    try:
        with logfile.open("x", encoding="utf-8") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            try:
                exit_code = process.wait(timeout=args.seconds + 30)
                report["status"] = "completed" if exit_code == 0 and args.output.is_dir() else "failed"
            except subprocess.TimeoutExpired:
                stop_recording(process)
                report["status"] = "timed_out"
                exit_code = 124
            except KeyboardInterrupt:
                stop_recording(process)
                report["status"] = "interrupted"
                exit_code = 130
    except OSError as error:
        report["status"] = "failed"
        report["error"] = str(error)
    finally:
        if process is not None:
            stop_recording(process)
        report["elapsed_seconds"] = time.monotonic() - started
        report["xctrace_exit_code"] = process.returncode if process else None
        report["target_after"] = identity(args.pid) if args.pid is not None else None
        report["target_identity_changed"] = bool(target and report["target_after"] and target != report["target_after"])
        if report["target_identity_changed"]:
            report["status"] = "target_identity_changed"
            exit_code = 1
        temporary = metadata.with_name(metadata.name + ".new")
        with temporary.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2)
        os.replace(temporary, metadata)
    print(json.dumps({"status": report["status"], "trace": str(args.output),
                      "metadata": str(metadata), "log": str(logfile)}, indent=2))
    return exit_code if exit_code else (0 if report["status"] == "completed" else 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    actions.add_parser("templates")
    capture = actions.add_parser("record")
    target = capture.add_mutually_exclusive_group(required=True)
    target.add_argument("--pid", type=int)
    target.add_argument("--all-processes", action="store_true")
    capture.add_argument("--seconds", type=float, required=True)
    capture.add_argument("--template", default="Time Profiler")
    capture.add_argument("--output", type=Path, required=True)
    capture.add_argument("--dry-run", action="store_true")
    capture.add_argument("--no-prompt", action="store_true", help="Pass xctrace's noninteractive flag without changing OS permissions")
    for name in ("toc", "export"):
        export = actions.add_parser(name)
        export.add_argument("trace", type=Path)
        export.add_argument("--output", type=Path, required=True)
        export.add_argument("--dry-run", action="store_true")
        if name == "export":
            export.add_argument("--xpath", required=True)
    args = parser.parse_args()
    try:
        if hasattr(args, "output"):
            args.output = args.output.expanduser().absolute()
        if hasattr(args, "trace"):
            args.trace = args.trace.expanduser().absolute()
        command = command_for(args)
        if getattr(args, "dry_run", False):
            print(json.dumps({"command": command, "executes_target_actions": False}, indent=2))
            return 0
        if sys.platform != "darwin":
            raise ValueError("xctrace requires macOS and the Xcode profiling tools")
        if args.action == "record":
            return record(args, command)
        if args.action == "templates":
            return subprocess.run(command, check=False, timeout=30).returncode
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8") as output:
            return subprocess.run(command, stdout=output, check=False, timeout=60).returncode
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    sys.exit(main())
