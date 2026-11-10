# Test CatWM from Python

Use the Python library to drive a running CatWM and check what it does. It needs Python 3.10 or newer. It has no other dependency.

```sh
export PYTHONPATH="$(catwm docs)/python"     # the library ships inside the app
# In the CatWM repo, use Clients/python instead.
python3 -c "from catwm import CatWM; print(CatWM().status())"
```

CatWM must run. `CatWM()` raises `CatWMError` with code `not_running` when it does not. The library connects to `~/.config/catwm/catwm.sock`. With `CATWM_INSTANCE=<id>` it connects to `~/.config/catwm/instances/<id>/catwm.sock`. Set `CATWM_SOCKET` to use another path.

## Call commands

Every command is a method. A bad argument raises `CatWMError`, and `error.code` says why (`invalid_args`, `unknown_command`, `forbidden`, `failed`).

```python
from catwm import CatWM, CatWMError

with CatWM() as catwm:
    catwm.workspace("2")                 # same as the dispatcher
    catwm.layout("wide")
    windows = catwm.windows()            # list of dicts: id, app, title, focused, workspace, frame, ...
    screens = catwm.screens()            # layout, ratio, workspace, usable area for each display
    catwm.config_set("gaps-in", "8")     # writes catwm.overrides.json. Change it back after your test.
```

`catwm.call("name", {"arg": value})` runs any command by name. `catwm.commands()` lists every command with its arguments. `exec` and `launch` are refused, because they run code.

## Check results

Tiling is asynchronous: a command returns when CatWM accepts it, not when the windows stop moving. Never `sleep`. Wait for the state you expect:

```python
from catwm.testing import connect, wait_until, wait_for_window, find_windows

catwm = connect()                        # skips the test when CatWM does not run
catwm.layout("wide")
wait_until(lambda: catwm.screens()[0]["layout"] == "wide", message="wide layout")
safari = wait_for_window(catwm, app="com.apple.Safari")      # filters: app, title, focused, workspace, floating
```

## Wait for events

Create `Events` **before** the action. An event that happens before you subscribe is lost.

```python
from catwm.testing import Events

with Events("focus.changed", "workspace.changed") as events:
    catwm.workspace("3")
    events.wait("workspace.changed", where={"workspace": "3"}, timeout=3)
```

`events.wait(name, where=..., timeout=...)` returns the next matching event or raises `TimeoutError`. `events.drain()` returns the events that wait now. The events are: `focus.changed`, `window.added`, `window.removed`, `workspace.changed`, `layout.changed`, `tiling.changed`, `mode.changed` and `config.reloaded`.

## Rules for tests

- The user works on the same desktop. Do not move their windows or take their focus. Open your own windows for a test, and close them after.
- Put back what you change: layout, tiling on or off, workspace and config options.
- Use `unittest` or `pytest`. `connect()` raises `unittest.SkipTest`, so both skip the test when CatWM does not run.
- Read `catwm dump` or `~/Library/Logs/CatWM.log` when a test fails.
