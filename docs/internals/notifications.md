# Notifications: the unread badge of each window

`Notifications.shared` (`Sources/CatWMKit/Notifications/`) holds one `Badge` for each window: a count (`99+` above 99) or a dot. Sources find the badges and messages. Listeners get each change. The `tab-notification-badges` option turns it on and off. When it is off, no source runs.

This document tells what the code does and why. Read it before you add a source or change a source.

## The goal

macOS gives no API that tells which window a notification is for. The Dock shows a count for each app, and Notification Center shows messages for each app. CatWM must find a count for each window from these, and it must do this with almost no CPU, because CatWM runs all the time.

## The rule for each window

- The app badge (the Dock) goes to each window of the app.
- A window that has its own count uses that count when it is less than the app count, or when the app has no badge.
- A window gets its own count from the messages whose text matches its title.
- The text match: the title or subtitle of the message is in the title of exactly one window of the app. If two or more windows match, no window gets it.
- When the app badge goes, the banner messages of that app go too.

`Badge.resolve(app:own:)` is the rule. `NotificationsTests` tests it.

Why: the Dock count is correct for the app, but it cannot tell the windows apart. The text match can tell them apart, but it misses messages. So the Dock count is the upper limit, and the text match makes it smaller for one window only when it is sure.

CatWM does not read unread marks such as `(3)` or `•` from window titles. Apps use those marks for other things, such as unsaved changes, and this gave false dots (tldraw). While badges are on, CatWM keeps the title of each window current, so that the text match uses the title that is on the screen now.

## When `resolve()` runs

`resolve()` runs only when an input changes: a source report, the title of a window of an app that has messages, the window set, or a focus that clears banner messages. The matches of each app stay in a cache until its messages, its titles or the window set change. Each source keeps at most 50 messages for each app. With no changed input, a `resolve()` costs about 0.001 to 0.004 ms.

## Sources

| Source | Gives | Runs when | Cost |
|---|---|---|---|
| `DockBadgeSource` | app badges | always | 0.4 to 0.9 ms CPU in CatWM and about 1 to 2 ms in the Dock for each poll |
| `NotificationDatabase` | messages | Full Disk Access is on | 0.2 to 0.9 ms for a read with no change or one new row. A full read: 6 ms at 1,000 rows, 28 ms at 5,000 rows |
| `BannerSource(reportsMessages: true)` | messages | Full Disk Access is off | 2 to 130 ms for each banner, off the main queue |
| `BannerSource(reportsMessages: false)` | a poll trigger only | Full Disk Access is on | one Dock poll for each Notification Center window |

Registration order sets which source wins when two report a badge for the same app or window.

### Dock badges

`DockBadgeSource` reads `AXStatusLabel` of each `AXApplicationDockItem` in the Dock.

- The Dock posts no AX notification when a badge changes, so the source polls on a utility queue.
- It polls every 10 s, and 0.5 s after a new message from the database, after a Notification Center window, and after an app switch, because a badge usually changes at those times. The 0.5 s wait groups the calls into one poll.
- It reads the subrole and URL of each item only when it builds the item list: when an app launches or quits, when an item is gone, and on every third poll. Each poll reads only `AXStatusLabel`. It goes to the main queue only when a badge changed.
- It stops while the displays sleep.

Why 10 s: the cost grows in proportion to the number of polls. Measured with 13 Dock items, CPU each minute:

| Interval | CatWM | Dock |
|---|---|---|
| 10 s | about 5 ms | no visible change |
| 5 s | 10.8 ms | no clear change |
| 3 s | 17.3 ms | about +30 ms |
| 2 s | 25.1 ms | about +70 ms |
| 1 s | 46.2 ms | about +130 ms |

The Dock itself uses 370 to 450 ms each minute when idle, and this changes by about ±35 ms between runs. The triggers catch most changes in about 0.5 s, so the timer only has to catch the rest.

### The Notification Center database

`NotificationDatabase` reads the `usernoted` database: `~/Library/Group Containers/group.com.apple.usernoted/db2/db`.

- The `record` table is joined to the `app` table. `record.data` is a binary plist with `req.titl`, `req.subt` and `req.body`.
- A `DispatchSource` watches `db-wal` and reads 0.25 s after the last write. When the file is deleted or renamed, it watches the new file after 1 s. When the file is missing, it tries again after 5 s.
- Each read first checks `count(*)` and `max(rec_id)`. With no change it stops there. Otherwise it decodes only the rows after the last `rec_id`. When the count shows that rows were deleted, it reads all rows again.
- It reports only the apps whose messages changed.
- It sees the notifications that a Focus hid.

Why it opens the database for each read: reads are rare (only after a write) and each one costs less than 1 ms. A kept connection must be closed and opened again when the file is replaced, and must not keep a read transaction open. That code is not worth the small saving.

Why it is not instant: `usernoted` writes a new notification 5 to 8 s after the Dock badge changes. The file watch sees each write at once, so no other way to read the database is faster. An SQLite `preupdate_hook` or `update_hook` does not help, because SQLite runs it only for changes through the same connection, and `usernoted` writes from its own process.

Full Disk Access is optional. The onboarding permission card has a row for it. When it changes, `AppDelegate` calls `Notifications.shared.refreshSources()`. Then the database source and the two banner sources start or stop. `NotificationDatabase.isReadable` is the check: an `open()` of the database file.

### Banners

`BannerSource` puts an `AXObserver` on the Notification Center process (`com.apple.notificationcenterui`) for new windows and new elements. When Notification Center restarts, it adds the observer again.

- With `reportsMessages: true`, it reads the `AXNotificationCenterBanner` and `AXNotificationCenterAlert` groups off the main queue. It takes the static texts, ignores a banner that it saw in the last 10 s, and finds the app whose `localizedName` is one of the texts. A banner does not tell when its message is read, so its messages go when their window gets focus (`messagesClearOnFocus`).
- With `reportsMessages: false`, it reads nothing. It only starts a Dock poll. This makes a badge show about 0.5 s after a banner, while the database is still 5 to 8 s late.

A banner shows only on the screen. It does not catch:

- notifications that a Focus or Do Not Disturb hid,
- apps with the alert style "None",
- banners while the screen is locked, asleep or mirrored,
- Dock badges that an app sets with no notification,
- badges that go down because the user read the message on another device.

So the Dock poll must stay, also with banners.

## What CatWM sees without Full Disk Access

- Apps that badge their Dock icon: the badge shows in all cases, also in a Focus. Each window of the app gets the app count.
- The split between windows of one app: only for messages whose banner showed. In a Focus, all windows of the app show the app count.
- Apps that notify but do not badge: a count shows only when a banner showed.

With Full Disk Access, the database has each notification, also the hidden ones, so the split between windows is complete.

## Routes that CatWM does not use

| Route | Why not |
|---|---|
| Unread marks in window titles | Apps use the same marks for other things. It gave false dots. |
| AX notifications from the Dock | The Dock posts none when a badge changes. |
| LaunchServices (`lsappinfo`, `StatusLabel`) | It stores the badge, but it posts no notification when the badge changes (tested: 4 changes, 0 notifications). It can only be polled, through a private API. |
| Distributed notifications | macOS does not let an app observe all names. No notification came in 90 s. |
| SQLite hooks on the database | They run only for changes in the same process. |
| The unified log (`log stream`) | It is instant, but it costs a lot, it is noisy, and its messages are private. |
| The Notification Center panel through AX | It can be read only while the user has the panel open. |
| `UNUserNotificationCenter` | It gives only the notifications of CatWM itself. |

## Add a source

1. Make a class that conforms to `NotificationSource`. Give it a unique `name`. Do the slow work on your own queue, and call the sink on the main queue.
2. Report with `report(app:)`, `report(window:)`, `report(messages:for:)` (the full list, for a source that knows all current notifications) or `add(_:from:)` (one new notification).
3. Set `isAvailable` when the source needs a permission. Set `messagesClearOnFocus` when the source cannot tell when a notification is read.
4. Register it in `installBuiltIn()`.
5. Measure its CPU cost when idle and the time from a notification to the badge. Add both to the table in this document.

## Listen

```swift
let token = Notifications.shared.listen { change in
    // change.window, change.app, change.badge (nil when it goes), change.source
}
Notifications.shared.stopListening(token)
```

External programs subscribe to the `window.notifications` event through the Control socket. They cannot report badges.
