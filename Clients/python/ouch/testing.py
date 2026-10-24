"""Helpers for tests that drive a running Ouch from Python. Written by hand, not generated.

    from ouch import Ouch
    from ouch.testing import Events, connect, wait_for_window

    ouch = connect()                       # skips the test when Ouch does not run
    with Events("focus.changed") as events:
        ouch.movefocus("left")
        events.wait("focus.changed", timeout=3)
"""
from __future__ import annotations

import json
import queue
import threading
import time
import unittest
from typing import Any, Callable

from . import Ouch, OuchError


def connect(path: str | None = None, timeout: float | None = 10.0) -> Ouch:
    """Connect to Ouch. Raise `unittest.SkipTest` (so pytest skips too) when Ouch does not run."""
    try:
        return Ouch(path, timeout)
    except OuchError as error:
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


def find_windows(ouch: Ouch, *, app: str | None = None, title: str | None = None, focused: bool | None = None,
                 workspace: str | None = None, floating: bool | None = None) -> list[dict[str, Any]]:
    """Windows that match every filter. `app` is a bundle ID. `title` matches a part of the title, ignoring case."""
    found = []
    for window in ouch.windows():
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


def wait_for_window(ouch: Ouch, timeout: float = 5.0, **filters: Any) -> dict[str, Any]:
    """Wait for the first window that matches the filters of `find_windows`."""
    return wait_until(lambda: (find_windows(ouch, **filters) or [None])[0], timeout,
                      message=f"a window that matches {filters}")


def wait_for_gone(ouch: Ouch, window_id: int, timeout: float = 5.0) -> None:
    """Wait until a window ID is no longer in the list of windows."""
    wait_until(lambda: all(w["id"] != window_id for w in ouch.windows()), timeout, message=f"window {window_id} to go")


class Events:
    """Collect events on a connection of its own. Create it BEFORE the action that causes the event."""

    def __init__(self, *names: str, path: str | None = None):
        self._client = Ouch(path, timeout=None)
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
                raise OuchError("closed", "Ouch closed the connection")
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
