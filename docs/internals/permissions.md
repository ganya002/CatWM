# Permissions: when `PermissionWatcher` polls

`PermissionWatcher` reads the four permissions off the main thread. Input Monitoring and Screen Recording each cost a TCC round trip to `tccd` (about 0.3 and 0.15 ms of CPU and 10–20 ms of wall time on an M4), so a read is about 0.5 ms of CPU. At a fixed 1.5 s it was the only recurring work of an idle app, about half of the idle CPU row, with a burst in two seconds out of three.

## The rule

The 1.5 s timer runs only while the frontmost app is System Settings or CatWM itself, which are the places where a permission changes. Any other time there is no timer. A check also runs when that state flips on an app switch, so a change made just before the user leaves Settings is seen at once. Accessibility keeps its own trigger, the `com.apple.accessibility.api` distributed notification, which runs a check whatever app is in front.

What the user sees does not change: in Settings the status updates within 1.5 s as before. A change made some other way (`tccutil` from a terminal, MDM) shows at the next switch to Settings or to CatWM instead of within 1.5 s.

## Rejected

- **A slower fixed interval.** It would delay the status in Settings, which is the one place the user waits for it.
- **A TCC change notification.** `tccd` contains `com.apple.tcc.access.changed` and `com.apple.tcc.registry.changed`, but changing a real permission to see who receives them needs the user's own settings, so no route was proven.

`CatWMEngine` builds its watcher with the default `isWatched`, so an embedded host still polls every 1.5 s. A host's own windows are not CatWM's, and its reader may report state that no app switch shows.
