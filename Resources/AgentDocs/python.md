# Test CatWM from Python

Use the Python library to drive a running CatWM and check what it does. It needs Python 3.10 or newer. It has no other dependency.

```sh
export PYTHONPATH="$(ouch docs)/python"     # the library ships inside the app
# In the Ouch repo, use Clients/python instead.
python3 -c "from ouch import Ouch; print(Ouch().status())"
```

CatWM must run. `Ouch()` raises `OuchError` with code `not_running` when it does not. The library connects to `~/.config/ouch/ouch.sock`. Set `OUCH_SOCKET` to use another path.

## Call commands

Every command is a method. A bad argument raises `OuchError`, and `error.code` says why (`invalid_args`, `unknown_command`, `forbidden`, `failed`).

```python
from ouch import Ouch, OuchError

with Ouch() as ouch:
    ouch.workspace("2")                 # same as the dispatcher
    ouch.layout("wide")
    windows = ouch.windows()            # list of dicts: id, app, title, focused, workspace, frame, ...
    screens = ouch.screens()            # layout, ratio, workspace, usable area for each display
    ouch.config_set("gaps-in", "8")     # changes ouch.conf. Change it back after your test.
```

`ouch.call("name", {"arg": value})` runs any command by name. `ouch.commands()` lists every command with its arguments. `exec` and `launch` are refused, because they run code.

## Check results

Tiling is asynchronous: a command returns when CatWM accepts it, not when the windows stop moving. Never `sleep`. Wait for the state you expect:

```python
from ouch.testing import connect, wait_until, wait_for_window, find_windows

ouch = connect()                        # skips the test when CatWM does not run
ouch.layout("wide")
wait_until(lambda: ouch.screens()[0]["layout"] == "wide", message="wide layout")
safari = wait_for_window(ouch, app="com.apple.Safari")      # filters: app, title, focused, workspace, floating
```

## Wait for events

Create `Events` **before** the action. An event that happens before you subscribe is lost.

```python
from ouch.testing import Events

with Events("focus.changed", "workspace.changed") as events:
    ouch.workspace("3")
    events.wait("workspace.changed", where={"workspace": "3"}, timeout=3)
```

`events.wait(name, where=..., timeout=...)` returns the next matching event or raises `TimeoutError`. `events.drain()` returns the events that wait now. The events are: `focus.changed`, `window.added`, `window.removed`, `workspace.changed`, `layout.changed`, `tiling.changed`, `mode.changed` and `config.reloaded`.

## Rules for tests

- The user works on the same desktop. Do not move their windows or take their focus. Open your own windows for a test, and close them after.
- Put back what you change: layout, tiling on or off, workspace and config options.
- Use `unittest` or `pytest`. `connect()` raises `unittest.SkipTest`, so both skip the test when CatWM does not run.
- Read `ouch dump` or `~/Library/Logs/ouch.log` when a test fails.
