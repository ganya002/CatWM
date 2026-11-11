"""Helpers for tests that drive a running CatWM from Python. Written by hand, not generated.

    from catwm import CatWM
    from catwm.testing import Events, connect, wait_for_window

    catwm = connect()                       # skips the test when CatWM does not run
    with Events("focus.changed") as events:
        catwm.movefocus("left")
        events.wait("focus.changed", timeout=3)
"""
from __future__ import annotations

import json
import os
import queue
import tempfile
import threading
import time
import unittest
from typing import Any, Callable

from . import CatWM, CatWMError


def connect(path: str | None = None, timeout: float | None = 10.0) -> CatWM:
    """Connect to CatWM. Raise `unittest.SkipTest` (so pytest skips too) when CatWM does not run."""
    try:
        return CatWM(path, timeout)
    except CatWMError as error:
        if error.code == "not_running":
            raise unittest.SkipTest(str(error)) from error
        raise


def wait_until(check: Callable[[], Any], timeout: float = 5.0, interval: float = 0.05, message: str = "the condition") -> Any:
    """Call `check` until it returns a truthy value. Return that value, or raise `TimeoutError`."""
    deadline = time.monotonic() + timeout
    while True:
        value = check()
        if value:
            return value
        if time.monotonic() >= deadline:
            raise TimeoutError(f"Timed out after {timeout}s waiting for {message}")
        time.sleep(interval)


def find_windows(catwm: CatWM, *, app: str | None = None, title: str | None = None, focused: bool | None = None,
                 workspace: str | None = None, floating: bool | None = None) -> list[dict[str, Any]]:
    """Windows that match every filter. `app` is a bundle ID. `title` matches a part of the title, ignoring case."""
    found = []
    for window in catwm.windows():
        if app is not None and window["app"] != app:
            continue
        if title is not None and title.lower() not in (window["title"] or "").lower():
            continue
        if focused is not None and window["focused"] != focused:
            continue
        if workspace is not None and window["workspace"] != workspace:
            continue
        if floating is not None and window["floating"] != floating:
            continue
        found.append(window)
    return found


def wait_for_window(catwm: CatWM, timeout: float = 5.0, **filters: Any) -> dict[str, Any]:
    """Wait for the first window that matches the filters of `find_windows`."""
    return wait_until(lambda: (find_windows(catwm, **filters) or [None])[0], timeout,
                      message=f"a window that matches {filters}")


def wait_for_gone(catwm: CatWM, window_id: int, timeout: float = 5.0) -> None:
    """Wait until a window ID is no longer in the list of windows."""
    wait_until(lambda: all(w["id"] != window_id for w in catwm.windows()), timeout, message=f"window {window_id} to go")


class Events:
    """Collect events on a connection of its own. Create it BEFORE the action that causes the event."""

    def __init__(self, *names: str, path: str | None = None):
        self._client = CatWM(path, timeout=None)
        self._client.call("subscribe", {"events": list(names)})
        self._queue: queue.Queue[dict[str, Any] | None] = queue.Queue()
        self._reader = threading.Thread(target=self._read, daemon=True)
        self._reader.start()

    def _read(self) -> None:
        try:
            while True:
                text = self._client._reader.readline()
                if not text:
                    break
                message = json.loads(text)
                if "event" in message:
                    self._queue.put(message)
        except (OSError, ValueError):
            pass
        self._queue.put(None)

    def wait(self, name: str | None = None, timeout: float = 5.0,
             where: dict[str, Any] | Callable[[dict[str, Any]], bool] | None = None) -> dict[str, Any]:
        """Return the next event with this name whose data matches `where`. Other events are dropped.

        `where` is a dict of data fields that must be equal, or a function that takes the data.
        """
        deadline = time.monotonic() + timeout
        while True:
            try:
                event = self._queue.get(timeout=max(0.0, deadline - time.monotonic()))
            except queue.Empty:
                raise TimeoutError(f"Timed out after {timeout}s waiting for {name or 'an event'}") from None
            if event is None:
                self._queue.put(None)
                raise CatWMError("closed", "CatWM closed the connection")
            if name is not None and event["event"] != name:
                continue
            data = event["data"]
            if callable(where):
                if where(data):
                    return event
            elif where is None or all(data.get(key) == value for key, value in where.items()):
                return event

    def drain(self) -> list[dict[str, Any]]:
        """Return every event that is waiting now, without blocking."""
        events = []
        while True:
            try:
                event = self._queue.get_nowait()
            except queue.Empty:
                return events
            if event is None:
                self._queue.put(None)
                return events
            events.append(event)

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "Events":
        return self

    def __exit__(self, *exc: Any) -> None:
        self.close()


class Sandbox:
    """A private display for test apps. The user's focus, Desktop and cursor never change.

        with Sandbox() as box:
            panel = box.launch("com.apple.TextEdit")    # refuses an app that already runs
            box.press(panel, "New Document")
            edit = box.window(title="Untitled")
            box.type(edit, "hello")
            assert box.text(edit) == "hello"
            box.screenshot(edit, "/tmp/edit.png")

    The display belongs to this connection. Leaving the block, or losing the connection (even `kill -9`),
    quits the apps and closes the display. The user's CatWM does not see these windows, so no `window.added`
    event arrives: `launch` waits with `wait_until` on `agent_windows`. Skips like `connect()`.
    """

    def __init__(self, path: str | None = None, timeout: float = 30.0):
        self.client = connect(path, timeout)
        try:
            self.display = self.client.agent_open()
        except BaseException:
            self.client.close()
            raise

    def launch(self, bundle_id: str, timeout: float = 15.0) -> dict[str, Any]:
        """Open an app and return its first window: id, pid, app, title, frame."""
        pid = self.client.agent_launch(bundle_id)["pid"]
        return wait_until(lambda: next((w for w in self.client.agent_windows() if w["pid"] == pid), None),
                          timeout, message=f"a window of {bundle_id} on the agent display")

    def type(self, window: dict[str, Any], text: str) -> str:
        """Add text to the window. Returns `ax` or `events`, the way it got in."""
        return self.client.agent_type(window["id"], text)["method"]

    def key(self, window: dict[str, Any], keys: str) -> None:
        self.client.agent_key(window["id"], keys)

    def press(self, window: dict[str, Any], button: str) -> None:
        """Press a button by its title, without focus."""
        self.client.agent_press(window["id"], button)

    def window(self, timeout: float = 5.0, **filters: Any) -> dict[str, Any]:
        """Wait for a window on the display. Filters: `title` (part, any case), `app`, `not_id`."""
        def match() -> dict[str, Any] | None:
            for found in self.client.agent_windows():
                if "title" in filters and filters["title"].lower() not in (found["title"] or "").lower():
                    continue
                if "app" in filters and found["app"] != filters["app"]:
                    continue
                if found["id"] != filters.get("not_id"):
                    return found
            return None
        return wait_until(match, timeout, message=f"a window that matches {filters}")

    def text(self, window: dict[str, Any]) -> str:
        return self.client.agent_text(window["id"])

    def screenshot(self, window: dict[str, Any], path: str | None = None) -> str:
        """Save one frame of the window as a PNG file. Returns the path."""
        if path is None:
            handle, path = tempfile.mkstemp(suffix=".png", prefix="catwm-")
            os.close(handle)
        return self.client.agent_screenshot(window["id"], os.path.abspath(path))

    def close(self) -> None:
        try:
            self.client.agent_close()
        except (CatWMError, OSError):
            pass
        finally:
            self.client.close()

    def __enter__(self) -> "Sandbox":
        return self

    def __exit__(self, *exc: Any) -> None:
        self.close()
