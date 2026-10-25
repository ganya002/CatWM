# Migrations

`Sources/CatWM/Migrations/` holds the code that moves data from the old names (Ouch, Hyprthyst) to CatWM. `main.swift` calls `Migrations.run()` before the CLI, the socket, the config, the templates or the log are read.

- `~/.config/ouch/` moves file by file to `~/.config/catwm/`. `ouch.conf` becomes `catwm.conf`. `ouch.sock` is stale and CatWM deletes it. A file that already exists in the new folder is never replaced, and its old copy stays. The old folder is removed only when it is empty.
- `~/.config/hyprthyst/hyprthyst.conf` is copied to `catwm.conf` only when no `catwm.conf` exists. The Ouch step runs first, so an Ouch config wins.
- The `local.ouch` and `local.hyprthyst` settings domains are copied once into the CatWM domain (flag `migratedLegacyDefaults`).
- Import accepts the `app: "ouch"` marker and the `.ouchconfig` extension. Export writes `app: "catwm"` and `.catwmconfig`.
- `~/Library/Logs/ouch.log` is not moved. CatWM writes a new `CatWM.log`.

Each step does nothing when the old data is missing, so it is safe to run at each launch.
