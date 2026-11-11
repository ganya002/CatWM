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

## Test apps on a private display

`Sandbox` opens a virtual display that only your test uses. Apps you launch there never take the user's focus, Desktop or cursor, and the user's CatWM does not tile them. It needs Accessibility and Screen Recording for CatWM, and it skips the test when CatWM does not run.

```python
from catwm.testing import Sandbox

with Sandbox() as box:
    panel = box.launch("com.apple.TextEdit")  # returns when its first window exists (TextEdit: the Open panel)
    box.press(panel, "New Document")          # AX press, no focus
    edit = box.window(title="Untitled")       # waits for the window
    box.type(edit, "hello")                   # no focus, no cursor
    assert box.text(edit) == "hello"
    box.screenshot(edit, "/tmp/edit.png")     # one PNG frame of that window
```

- `launch` refuses an app that already runs (`CatWMError` code `app_running`), because the display takes over every window of the app. Pick another app or quit it first.
- `box.key(window, "cmd+a")` posts a key to the app. Key events can miss an app that is not active, so prefer `press` and `type`. `box.type` returns `ax` when it set the text field directly, or `events` when it posted key events.
- Leaving the block quits the apps and closes the display, also after an exception or `kill -9` of your script. The display belongs to the connection.
- The apps are not in `catwm.windows()` and send no `window.added`. `box.client` is the connection, and `box.client.agent_windows()` lists the windows.

## Rules for tests

- The user works on the same desktop. Do not move their windows or take their focus. Test apps go in a `Sandbox`. Close any other window you open.
- Put back what you change: layout, tiling on or off, workspace and config options.
- Use `unittest` or `pytest`. `connect()` raises `unittest.SkipTest`, so both skip the test when CatWM does not run.
- Read `catwm dump` or `~/Library/Logs/CatWM.log` when a test fails.
