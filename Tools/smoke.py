#!/usr/bin/env python3
"""Drive the real build/CatWM.app through one suite of user actions and fail when CatWM crashes or hangs.

After each step, the CatWM process must still run and answer `ping` within HANG_SECONDS, and no new
crash report may name it. A refused command is fine: the check is that CatWM survives, not what it did.

The instance is unscoped, so it tiles every window, drives the Desktops and reads key presses. Run it
only on a Mac that it may take over, such as a CI VM. --scoped limits it to the test windows instead,
for a local check, and CatWM then refuses the commands that reach outside the scope.

Run `./build.sh --dev` first.

    python3 Tools/smoke.py --suite windows|workspaces|app [--out DIR] [--scoped]
"""
import argparse
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Clients/python"))
from catwm import CatWM, CatWMError  # noqa: E402
from catwm.testing import Events, Sandbox, wait_until  # noqa: E402

APP = ROOT / "build/CatWM.app/Contents/MacOS/CatWM"
INSTANCE = "smoke"
FOLDER = Path.home() / f".config/catwm/instances/{INSTANCE}"
LOG = Path.home() / f"Library/Logs/CatWM-{INSTANCE}.log"
REPORTS = Path.home() / "Library/Logs/DiagnosticReports"
HANG_SECONDS = 5
START_SECONDS = 30
EXIT_SECONDS = 15
LAYOUTS = ["tall", "tall-right", "wide", "middle-wide", "fullscreen", "column", "row", "floating", "bsp",
           "3column-left", "3column-middle", "3column-right", "two-pane", "two-pane-right",
           "widescreen-tall", "widescreen-tall-right"]
DIRECTIONS = ["left", "right", "up", "down"]
LAYOUT_MESSAGES = ["swapwithmaster", "swapsides", "focusmaster", "addmaster", "removemaster", "mfact 0.55",
                   "orientationnext", "orientationprev"]
# Virtual key codes.
KEYS = {"tab": 48, "escape": 53, "1": 18, "2": 19, "h": 4, "j": 38, "k": 40, "l": 37, "o": 31, "slash": 44,
        "left": 123, "right": 124}


class Failure(Exception):
    pass


class Smoke:
    def __init__(self, out, scoped):
        self.out = out
        self.scoped = scoped
        self.process = None
        self.stdout = None
        self.apps = []
        self.scope = []
        self.started = time.time()
        self.steps = 0
        self.refused = {}
        self.warnings = []
        schema = json.loads((ROOT / "Clients/schema.json").read_text())
        self.schema = {command["name"]: command for command in schema["commands"]}
        self.desk = Path(tempfile.mkdtemp(prefix="catwm-smoke-"))

    # The app

    def start(self):
        env = dict(os.environ)
        arguments = [str(APP), "--verbose"]
        if self.scoped:
            self.scope = [os.getpid(), *self.apps]
            env["CATWM_SCOPE"] = "pids:" + ",".join(map(str, self.scope))
        else:
            arguments.append("--unscoped")
        self.stdout = open(self.out / "instance.out", "a")
        self.process = subprocess.Popen(arguments, env=env, stdout=self.stdout, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + START_SECONDS
        while True:
            if self.process.poll() is not None:
                raise Failure(f"CatWM quit during launch with status {self.process.returncode}")
            try:
                with CatWM(timeout=HANG_SECONDS) as client:
                    if client.ping()["pid"] == self.process.pid and client.status()["running"]:
                        break
            except (CatWMError, OSError):
                pass
            if time.monotonic() > deadline:
                raise Failure(f"CatWM did not answer within {START_SECONDS} s of launch")
            time.sleep(0.2)
        status = self.call("status")
        if not status["trusted"]:
            raise Failure("CatWM has no Accessibility permission, so it can't manage windows")
        print(f"smoke: CatWM {self.process.pid} runs, {status['tiled']} tiled, {status['floating']} floating",
              flush=True)

    def stop(self, how="exit"):
        """Quit CatWM with the exit command or a signal, and fail when it hangs or dies by a signal."""
        if how == "exit":
            self.call("exit")
        else:
            self.process.send_signal(how)
        try:
            status = self.process.wait(timeout=EXIT_SECONDS)
        except subprocess.TimeoutExpired:
            self.process.kill()
            raise Failure(f"CatWM did not quit within {EXIT_SECONDS} s of {how}") from None
        if status != 0 and not (how == signal.SIGTERM and status == -signal.SIGTERM):
            raise Failure(f"CatWM quit with status {status} after {how}")
        self.process = None

    def call(self, command, args=None):
        """Run a command. A refusal raises CatWMError, and no reply within HANG_SECONDS fails the run."""
        try:
            with CatWM(timeout=HANG_SECONDS) as client:
                return client.call(command, args)
        except CatWMError as error:
            if error.code not in ("not_running", "closed"):
                raise
            self.hang(f"`{command}`", error)
        except OSError as error:
            self.hang(f"`{command}`", error)

    def check(self, name):
        self.call("ping")
        crashes = self.crash_reports()
        if crashes:
            raise Failure(f"crash report after `{name}`: {', '.join(path.name for path in crashes)}")

    def hang(self, name, error):
        """Fail for a CatWM that died or stopped answering, with the stacks of a hung one."""
        try:
            status = self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            subprocess.run(["sample", str(self.process.pid), "3", "-file", str(self.out / "hang.txt")],
                           capture_output=True, check=False)
            raise Failure(f"CatWM didn't answer {name} within {HANG_SECONDS} s: {error}") from error
        raise Failure(f"CatWM died during {name} with status {status}") from error

    def step(self, name, command, args=None):
        """Run one command and check that CatWM survived it."""
        self.steps += 1
        try:
            self.call(command, args)
        except CatWMError as error:
            self.refused[name] = f"{error.code}: {error.message}"
        self.check(name)

    def run(self, command, *args):
        """Run a command by its CLI name, with positional arguments in schema order."""
        spec = self.schema[command]
        values = dict(zip([arg["name"] for arg in spec["args"]], args))
        self.step(" ".join([command, *args]), command, values)

    def crash_reports(self):
        if not REPORTS.exists():
            return []
        return [path for path in REPORTS.iterdir()
                if path.name.startswith("CatWM") and path.stat().st_mtime >= self.started]

    def wait(self, check, message, timeout=15):
        """Wait for `check`, and check that CatWM is healthy on each try."""
        def healthy():
            self.check(message)
            return check()
        try:
            wait_until(healthy, timeout, interval=0.2, message=message)
        except TimeoutError as error:
            raise Failure(str(error)) from None

    def settle(self, timeout=5):
        """Wait until the window frames stop changing. Not a failure when they never do."""
        deadline, last = time.monotonic() + timeout, None
        while time.monotonic() < deadline:
            frames = [(w["id"], w["frame"]) for w in self.call("windows")]
            if frames == last:
                return
            last = frames
            time.sleep(0.25)

    # Test windows

    def open_textedit(self, count, label):
        """Open `count` scratch files in a new TextEdit process and return its pid."""
        files = []
        for number in range(1, count + 1):
            path = self.desk / f"{label}-{number}.txt"
            path.write_text(f"CatWM smoke window {label} {number}\n")
            files.append(str(path))
        before = set(pids("TextEdit"))
        subprocess.run(["open", "-n", "-a", "TextEdit", *files, "--args", "-ApplePersistenceIgnoreState", "YES"],
                       check=True)
        deadline = time.monotonic() + 15
        while not (new := set(pids("TextEdit")) - before):
            if time.monotonic() > deadline:
                raise Failure("TextEdit did not start")
            time.sleep(0.2)
        pid = new.pop()
        self.apps.append(pid)
        return pid

    def add_documents(self, count, label):
        """Open more scratch files in the TextEdit that LaunchServices picks."""
        for number in range(1, count + 1):
            path = self.desk / f"{label}-{number}.txt"
            path.write_text(f"CatWM smoke window {label} {number}\n")
            subprocess.run(["open", "-a", "TextEdit", str(path)], check=True)

    def managed(self, pid=None):
        return [w for w in self.call("windows") if pid is None or w["pid"] == pid]

    def wait_for_windows(self, pid, count):
        if self.scoped and pid not in self.scope:
            return
        self.wait(lambda: len(self.managed(pid)) >= count, f"CatWM to manage {count} windows of pid {pid}")

    def focus_test_window(self):
        if not any(w["focused"] for w in self.managed()):
            self.run("cyclenext")

    def keys(self, *strokes):
        """Press keys at the HID level, where CatWM's key tap reads a real keyboard. A stroke is (key, [mods])."""
        helper = self.desk / "smoke-keys"
        if not helper.exists():
            subprocess.run(["swiftc", "-O", str(ROOT / "Tools/smoke-keys.swift"), "-o", str(helper)], check=True)
        # One process per stroke: events posted back to back can reach the tap before it reads the last one.
        for key, mods in strokes:
            subprocess.run([str(helper), "+".join([str(KEYS[key]), *mods])], check=True, timeout=HANG_SECONDS)
        self.steps += 1
        self.check(f"keys {strokes}")

    def close(self):
        if self.process and self.process.poll() is None:
            self.process.kill()
        for pid in self.apps:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if self.stdout:
            self.stdout.close()
        shutil.rmtree(self.desk, ignore_errors=True)


def pids(name):
    result = subprocess.run(["pgrep", "-x", name], capture_output=True, text=True)
    return [int(line) for line in result.stdout.split()]


# Suites


def windows(smoke):
    """Tiling: every layout, layout message, focus and move direction, floating, full screen, tabs, churn."""
    first = smoke.open_textedit(4, "a")
    second = smoke.open_textedit(2, "b")
    smoke.start()
    smoke.wait_for_windows(first, 4)
    smoke.wait_for_windows(second, 2)
    smoke.focus_test_window()

    for layout in LAYOUTS:
        smoke.run("layout", layout)
    smoke.settle()
    for step in ["next", "next", "next", "prev", "prev", "prev"]:
        smoke.run("cyclelayout", step)
    smoke.run("layout", "tall")
    for value in ["+0.05", "-0.1", "exact 0.6", "exact 0.5"]:
        smoke.run("splitratio", value)
    for message in LAYOUT_MESSAGES:
        smoke.run("layoutmsg", message)

    for layout in ["tall", "bsp", "3column-middle"]:
        smoke.run("layout", layout)
        for command in ["movefocus", "movewindow", "swapwindow"]:
            for direction in DIRECTIONS:
                smoke.run(command, direction)
        for command in ["cyclenext", "swapnext"]:
            for step in ["next", "prev"]:
                smoke.run(command, step)
    smoke.settle()

    for command in ["togglefloating", "togglefloating", "fullscreen", "fullscreen", "toggletiling",
                    "toggletiling", "retile"]:
        smoke.run(command)
    smoke.run("nativefullscreen")
    smoke.settle()
    smoke.run("nativefullscreen")
    smoke.settle()
    smoke.focus_test_window()

    smoke.run("layout", "tall")
    for direction in DIRECTIONS:
        smoke.run("moveintogroup", direction)
    for tab in ["next", "prev", "1", "2"]:
        smoke.run("changegroupactive", tab)
    for step in ["next", "prev"]:
        smoke.run("movegroupwindow", step)
    smoke.run("moveoutofgroup")
    smoke.settle()

    smoke.run("minimize")
    smoke.focus_test_window()
    smoke.run("killactive")
    smoke.settle()

    # Windows that come and go while CatWM moves them.
    smoke.add_documents(4, "c")
    for _ in range(3):
        smoke.focus_test_window()
        smoke.run("killactive")
        smoke.run("cyclelayout", "next")
    os.kill(second, signal.SIGKILL)
    smoke.wait(lambda: not smoke.managed(second), "CatWM to drop the windows of a killed app")
    third = smoke.open_textedit(3, "d")
    smoke.wait_for_windows(third, 3)
    smoke.focus_test_window()
    for layout in LAYOUTS:
        smoke.run("layout", layout)
    smoke.settle()
    smoke.stop()


def workspaces(smoke):
    """Workspaces and Desktops, displays, the Overview, the switcher, key modes and key presses."""
    first = smoke.open_textedit(3, "a")
    smoke.start()
    smoke.wait_for_windows(first, 3)
    smoke.focus_test_window()

    for target in ["2", "3", "1", "previous", "+1", "-1", "e+1", "name:smoke", "1"]:
        smoke.run("workspace", target)
    with Events("workspace.changed") as events:
        smoke.run("workspace", "2")
        if not smoke.scoped:
            events.wait("workspace.changed", timeout=15, where=lambda data: data["workspace"].endswith("/2"))
    smoke.run("workspace", "1")
    smoke.focus_test_window()
    smoke.run("movetoworkspace", "2")
    smoke.focus_test_window()
    smoke.run("movetoworkspacesilent", "3")
    smoke.run("workspace", "3")
    smoke.focus_test_window()
    smoke.run("sethomespace")
    # Key mashing: each switch starts before the last slide ends.
    for target in ["1", "2", "3", "4", "3", "2", "1", "4", "1"]:
        smoke.run("workspace", target)
    smoke.settle()
    second = smoke.open_textedit(2, "b")
    smoke.wait_for_windows(second, 2)

    for target in ["+1", "-1", "1"]:
        smoke.run("focusmonitor", target)
        smoke.focus_test_window()
        smoke.run("movewindowtomonitor", target)

    for command in ["sort", "sort", "sort", "sort-undo", "sort-undo", "toggledim", "toggledim", "toggleblur",
                    "toggleblur"]:
        smoke.run(command)
    for step in ["next", "prev", "next"]:
        smoke.run("switcher", step)
    smoke.run("submap", "window")
    smoke.run("submap", "reset")
    smoke.settle()

    # Key presses go through the event tap, as a user's do.
    if smoke.scoped:
        print("smoke: --scoped reads no key presses, so the key steps are skipped", flush=True)
    else:
        status = smoke.call("status")
        print(f"smoke: key tap {status['keybindsActive']}, Input Monitoring {status['inputMonitoring']}", flush=True)
        # The VM's window server drops synthetic presses in some runs, so a press that never lands is a warning.
        for _ in range(3):
            with Events("workspace.changed") as events:
                smoke.keys(("2", ["control"]))
                try:
                    events.wait("workspace.changed", timeout=5, where=lambda data: data["workspace"].endswith("/2"))
                    break
                except TimeoutError:
                    pass
        else:
            smoke.warnings.append("No key press reached CatWM's key tap, so the key steps tested nothing.")
        smoke.keys(("1", ["control"]))
        smoke.keys(("right", ["control"]), ("left", ["control"]))
        smoke.keys(("h", ["option", "control"]), ("l", ["option", "control"]))
        smoke.keys(("o", ["option"]))
        smoke.keys(("escape", []))
        smoke.keys(("o", ["option"]), ("o", ["option"]))
        smoke.keys(("tab", ["option"]), ("tab", ["option"]), ("tab", ["option", "shift"]))
        smoke.run("submap", "window")
        smoke.keys(("h", []), ("l", []), ("j", []), ("k", []), ("slash", []))
        smoke.keys(("escape", []))
        smoke.run("submap", "reset")
    smoke.settle()
    smoke.run("workspace", "1")
    smoke.stop()


def app(smoke):
    """Launch and quit, every config option, broken config, events, many clients and bad requests."""
    smoke.start()
    first = smoke.open_textedit(3, "a")
    smoke.wait_for_windows(first, 3)
    smoke.focus_test_window()

    events = Events()

    for option in smoke.call("config.options"):
        for value in alternates(option):
            smoke.run("config.set", option["key"], value)
        smoke.run("config.set", option["key"], option["value"])
        smoke.run("layout", "bsp")
    smoke.settle()

    config = FOLDER / "catwm.config.ts"
    good = config.read_text()
    for broken in ["export default {", "export default { layouts: 42 }", "throw new Error('smoke')", ""]:
        config.write_text(broken)
        smoke.run("reload")
    config.write_text(good)
    smoke.run("reload")

    def client_burst():
        for _ in range(20):
            for command in ["windows", "status", "workspaces", "screens", "dump"]:
                smoke.call(command)
    burst = [threading.Thread(target=client_burst) for _ in range(10)]
    for thread in burst:
        thread.start()
    for thread in burst:
        thread.join()
    smoke.check("ten clients at once")

    for line in [b"not json\n", b"{}\n", b'{"id": 1, "command": "nope"}\n',
                 b'{"id": 2, "command": "layout", "args": {"layout": 7}}\n',
                 b'{"id": 3, "command": "dispatch", "args": {"dispatcher": "nope"}}\n',
                 b'{"id": 4, "command": "exec", "args": {}}\n', b"x" * (2 * 1024 * 1024)]:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as raw:
            raw.settimeout(HANG_SECONDS)
            raw.connect(str(FOLDER / "catwm.sock"))
            try:
                raw.sendall(line)
            except OSError:
                pass
        smoke.check(f"raw request {line[:40]!r}")

    smoke.steps += 1
    try:
        with Sandbox() as box:
            window = box.launch("com.apple.calculator")
            box.key(window, "1")
            box.screenshot(window, str(smoke.out / "agent.png"))
            box.text(window)
    except (CatWMError, OSError) as error:
        smoke.refused["agent display"] = str(error)
    smoke.check("agent display")
    # The display belongs to its connection, so CatWM must close it alone when a client vanishes.
    try:
        Sandbox().client.close()
    except (CatWMError, OSError) as error:
        smoke.refused["agent display, connection lost"] = str(error)
    smoke.check("agent display, connection lost")

    for name, style in [("modefx", "all"), ("panelfx", "all")]:
        smoke.step(f"{name} {style}", name, {"style": style})
    smoke.settle()
    received = events.drain()
    events.close()
    if not received:
        raise Failure("no event arrived on the event connection")

    smoke.stop()
    smoke.start()
    smoke.wait_for_windows(first, 3)
    smoke.stop(signal.SIGTERM)
    smoke.start()
    smoke.wait_for_windows(first, 3)
    smoke.stop()


def alternates(option):
    """Values other than the current one, from the option's type text."""
    kind, value = option["type"], option["value"]
    if kind == "bool":
        return ["false" if value == "true" else "true"]
    if "`" in kind:
        return [choice for choice in kind.split("`")[1::2] if choice != value and "(" not in choice]
    if kind.startswith("0–") or kind[:1].isdigit():
        low, _, rest = kind.partition("–")
        high = rest.split()[0] if rest else low
        try:
            return [str((float(low) + float(high)) / 2).removesuffix(".0")]
        except ValueError:
            return []
    if kind in ("number", "milliseconds"):
        return [str(float(value or 0) + 1).removesuffix(".0")]
    return []


SUITES = {"windows": windows, "workspaces": workspaces, "app": app}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--suite", choices=SUITES, required=True)
    parser.add_argument("--out", type=Path, default=Path("smoke"), help="folder for the logs (default ./smoke)")
    parser.add_argument("--scoped", action="store_true", help="manage only the test windows, for a local run")
    args = parser.parse_args()
    if not args.scoped and not os.environ.get("CI"):
        sys.exit("smoke: an unscoped run takes over this Mac. Run it on CI, or pass --scoped.")

    os.environ["CATWM_INSTANCE"] = INSTANCE
    args.out.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(FOLDER, ignore_errors=True)
    LOG.unlink(missing_ok=True)
    smoke = Smoke(args.out, args.scoped)
    failure = None
    try:
        SUITES[args.suite](smoke)
    except Exception as error:  # noqa: BLE001, so a bug in a suite still writes the summary
        failure = error
    finally:
        subprocess.run(["screencapture", "-x", str(args.out / "screen.png")], check=False)
        smoke.close()
    # ReportCrash writes the report a few seconds after the crash.
    deadline = time.monotonic() + (10 if failure else 0)
    while not smoke.crash_reports() and time.monotonic() < deadline:
        time.sleep(0.5)
    for report in smoke.crash_reports():
        shutil.copy(report, args.out / report.name)
    if LOG.exists():
        shutil.copy(LOG, args.out / "catwm.log")

    lines = [f"### {'❌' if failure else '✅'} Smoke: {args.suite}", "",
             f"{smoke.steps} steps, {len(smoke.refused)} refused by CatWM."]
    if failure:
        lines += ["", f"**{failure}**"]
    lines += [f"\n⚠️ {warning}" for warning in smoke.warnings]
    if smoke.refused:
        lines += ["", "<details><summary>Refused commands</summary>", "",
                  *(f"- `{name}`: {reason}" for name, reason in smoke.refused.items()), "", "</details>"]
    summary = "\n".join(lines) + "\n"
    (args.out / "summary.md").write_text(summary)
    print(summary)
    sys.exit(1 if failure else 0)


if __name__ == "__main__":
    main()
