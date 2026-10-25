# Config and reload

The user changes an option in Settings, in the config file (`$CONF` for the verify instance) or with the CLI, and CatWM applies it at once. A HUD shows "Config reloaded" or the number of errors.

## Sub-features

- `config-set` changes one option, writes the config file and reloads it.
- `config-reload` reads the config file again after a hand edit.
- `config-error` reports a bad value in the log and the HUD, and keeps the other options.

## How to get to it (user POV)

- Change an option in Settings (menu bar > Settings…, or ⌘, ).
- Edit `$CONF` (the config of the verify instance), then press Shift R in window mode, or run `catwm reload`.
- Run `catwm config.set <key> <value>` and `catwm config.get <key>`.

## Driving it with the catwm CLI

Preconditions:

- The baseline preconditions in the README are true.
- Copy the config before you start: `cp "$CONF" "$RUN/catwm.conf.before"`.
- Use the option `window-margins` (bool). Record its value: `$CLI config.get window-margins`.

- **Set.** Start `$CLI events config.reloaded > $RUN/config.jsonl &` and record `$!`. Run `$CLI config.set window-margins false`. A `config.reloaded` line arrives. `$CLI config.get window-margins` prints `false`. `grep '^window-margins' "$CONF"` shows `false`. In `dump`, the test windows touch each other with no gaps.
- **Proof.** Run `$S/evidence.sh config-set-after`.
- **Put it back.** Run `$CLI config.set window-margins <recorded value>`. `diff "$RUN/catwm.conf.before" "$CONF"` prints nothing.
- **Reload.** Run `$CLI reload`. The exit code is 0, and a new `config.reloaded` line arrives.
- Kill the events pid that you recorded.

## Gotchas

- This is the user's real config. Always put back each value, and check with `diff` against the copy.
- `config.set` can write the option in a new place in the file. If `diff` shows a moved line, copy `$RUN/catwm.conf.before` back and run `$CLI reload`.
- Do not test `config-error` by writing a bad value into the user's file unless you put the copy back right after it.
- Settings writes the same file. Do not drive Settings while you edit the file by hand.
