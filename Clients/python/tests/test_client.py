"""Tests for the Python client against a fake CatWM server. Run: python3 -m unittest discover Clients/python/tests"""
import json
import os
import socket
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from catwm import CatWM, CatWMError  # noqa: E402
from catwm.testing import Events, Sandbox, connect, find_windows, wait_for_window, wait_until  # noqa: E402

WINDOWS = [
    {"id": 1, "app": "com.apple.Safari", "title": "Docs", "focused": True, "workspace": "1", "floating": False},
    {"id": 2, "app": "com.apple.Terminal", "title": None, "focused": False, "workspace": "2", "floating": True},
]


class FakeCatWM:
    """Speaks the CatWM protocol. A `fake.emit` request pushes the events given in its args."""

    def __init__(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.directory.name, "catwm.sock")
        self.requests = []
        self.subscribers = []
        self.polls = 0
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.path)
        self.server.listen(8)
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self):
        while True:
            try:
                connection, _ = self.server.accept()
            except OSError:
                return
            threading.Thread(target=self._serve, args=(connection,), daemon=True).start()

    def _send(self, connection, message):
        connection.sendall((json.dumps(message) + "\n").encode())

    def _serve(self, connection):
        self._send(connection, {"hello": {"protocol": 1, "version": "test", "pid": 1}})
        for line in connection.makefile("r"):
            request = json.loads(line)
            self.requests.append(request)
            name, args, rid = request["command"], request["args"], request["id"]
            if name == "windows":
                reply = {"id": rid, "ok": True, "result": WINDOWS}
            elif name == "movefocus" and args.get("direction") not in ("left", "right", "up", "down"):
                reply = {"id": rid, "ok": False, "error": {"code": "invalid_args", "message": "bad direction"}}
            elif name == "subscribe":
                self.subscribers.append(connection)
                reply = {"id": rid, "ok": True, "result": {"events": args["events"]}}
            elif name == "agent.open":
                reply = {"id": rid, "ok": True, "result": {"uuid": "U", "frame": {"x": 0, "y": 0, "w": 1, "h": 1}}}
            elif name == "agent.launch" and args["app"] == "running.app":
                reply = {"id": rid, "ok": False, "error": {"code": "app_running", "message": "already runs"}}
            elif name == "agent.launch":
                reply = {"id": rid, "ok": True, "result": {"pid": 7}}
            elif name == "agent.windows":
                self.polls += 1
                found = [{"id": 9, "pid": 7, "app": "a", "title": None, "frame": {}}] if self.polls > 1 else []
                reply = {"id": rid, "ok": True, "result": found}
            elif name == "agent.type":
                reply = {"id": rid, "ok": True, "result": {"method": "ax"}}
            elif name == "agent.text":
                reply = {"id": rid, "ok": True, "result": "hello"}
            elif name == "agent.screenshot":
                reply = {"id": rid, "ok": True, "result": args["path"]}
            elif name == "fake.emit":
                for target in self.subscribers:
                    for event in args["events"]:
                        self._send(target, event)
                reply = {"id": rid, "ok": True, "result": None}
            else:
                reply = {"id": rid, "ok": True, "result": None}
            self._send(connection, reply)
        connection.close()

    def close(self):
        self.server.close()
        self.directory.cleanup()


class ClientTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeCatWM()
        self.addCleanup(self.fake.close)
        self.catwm = CatWM(self.fake.path, timeout=3)
        self.addCleanup(self.catwm.close)

    def test_hello_and_result(self):
        self.assertEqual(self.catwm.hello["version"], "test")
        self.assertEqual(self.catwm.windows(), WINDOWS)

    def test_typed_method_sends_named_arguments_and_skips_none(self):
        self.catwm.movefocus("left")
        self.catwm.cyclenext()
        sent = [(r["command"], r["args"]) for r in self.fake.requests]
        self.assertEqual(sent, [("movefocus", {"direction": "left"}), ("cyclenext", {})])

    def test_errors_become_exceptions(self):
        with self.assertRaises(CatWMError) as caught:
            self.catwm.call("movefocus", {"direction": "sideways"})
        self.assertEqual(caught.exception.code, "invalid_args")

    def test_not_running_skips_the_test(self):
        with self.assertRaises(unittest.SkipTest):
            connect("/nonexistent/catwm.sock")
        with self.assertRaises(CatWMError) as caught:
            CatWM("/nonexistent/catwm.sock")
        self.assertEqual(caught.exception.code, "not_running")

    def test_window_filters(self):
        self.assertEqual([w["id"] for w in find_windows(self.catwm, app="com.apple.Safari")], [1])
        self.assertEqual([w["id"] for w in find_windows(self.catwm, title="doc")], [1])
        self.assertEqual([w["id"] for w in find_windows(self.catwm, floating=True)], [2])
        self.assertEqual(wait_for_window(self.catwm, workspace="2")["id"], 2)
        with self.assertRaises(TimeoutError):
            wait_for_window(self.catwm, timeout=0.2, app="nothing")

    def test_wait_until_returns_the_value(self):
        values = iter([None, 0, "ready"])
        self.assertEqual(wait_until(lambda: next(values), interval=0.01), "ready")


class EventTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeCatWM()
        self.addCleanup(self.fake.close)
        self.catwm = CatWM(self.fake.path, timeout=3)
        self.addCleanup(self.catwm.close)

    def emit(self, *events):
        self.catwm.call("fake.emit", {"events": [{"event": n, "data": d} for n, d in events]})

    def test_wait_filters_by_name_and_data(self):
        with Events("focus.changed", "mode.changed", path=self.fake.path) as events:
            self.emit(("mode.changed", {"mode": "window"}), ("focus.changed", {"window": 1}),
                      ("focus.changed", {"window": 2}))
            self.assertEqual(events.wait("focus.changed", where={"window": 2}, timeout=3)["data"], {"window": 2})

    def test_wait_accepts_a_function(self):
        with Events(path=self.fake.path) as events:
            self.emit(("focus.changed", {"window": 5}))
            self.assertEqual(events.wait(where=lambda data: data["window"] == 5, timeout=3)["event"], "focus.changed")

    def test_timeout_and_drain(self):
        with Events("focus.changed", path=self.fake.path) as events:
            with self.assertRaises(TimeoutError):
                events.wait("focus.changed", timeout=0.2)
            self.emit(("focus.changed", {"window": 1}))
            wait_until(lambda: events._queue.qsize(), interval=0.01)
            self.assertEqual(len(events.drain()), 1)

    def test_close_wakes_a_waiting_reader(self):
        events = Events("focus.changed", path=self.fake.path)
        threading.Timer(0.2, events.close).start()
        with self.assertRaises(CatWMError):
            events.wait("focus.changed", timeout=3)


if __name__ == "__main__":
    unittest.main()


class SandboxTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeCatWM()
        self.addCleanup(self.fake.close)

    def commands(self):
        return [r["command"] for r in self.fake.requests]

    def test_flow_waits_for_the_window_and_closes_at_the_end(self):
        with Sandbox(self.fake.path) as box:
            window = box.launch("com.apple.TextEdit")
            self.assertEqual(window["id"], 9)
            self.assertEqual(box.type(window, "hello"), "ax")
            self.assertEqual(box.text(window), "hello")
            path = box.screenshot(window)
            self.addCleanup(os.remove, path)
            self.assertTrue(os.path.isabs(path))
        self.assertGreaterEqual(self.fake.polls, 2)
        self.assertEqual(self.commands()[0], "agent.open")
        self.assertEqual(self.commands()[-1], "agent.close")

    def test_exit_closes_after_an_exception(self):
        with self.assertRaises(ZeroDivisionError):
            with Sandbox(self.fake.path):
                1 / 0
        self.assertEqual(self.commands()[-1], "agent.close")

    def test_a_running_app_is_refused_with_its_code(self):
        with Sandbox(self.fake.path) as box:
            with self.assertRaises(CatWMError) as caught:
                box.launch("running.app")
        self.assertEqual(caught.exception.code, "app_running")

    def test_skips_when_catwm_does_not_run(self):
        with self.assertRaises(unittest.SkipTest):
            Sandbox("/nonexistent/catwm.sock")
