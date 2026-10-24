# Notifications: unread badges on tabs

`Notifications.shared` (`Sources/ouch/Notifications/`) holds one `Badge` for each window: a count (`99+` above 99) or a dot. Sources find the badges. Listeners get each change. The tab strip is one listener: `TabCell` draws the `CountBadge` on the trailing edge of the tab. The `tab-notification-badges` option turns it on and off. When it is off, no source runs.

## The rule for each window

- The app badge (the Dock) goes to each window of the app.
- A window that has its own count uses that count when it is less than the app count, or when the app has no badge.
- A window gets its own count from the notifications whose text matches its title.
- The text match: the title or subtitle of the notification is in the title of exactly one window of the app. If two or more windows match, no window gets it.
- When the app badge goes, the banner messages of that app go too.

`Badge.resolve(app:own:)` is the rule. `NotificationsTests` tests it.

`resolve()` runs only when an input changes: a source report, the title of a window of an app that has messages, the window set, or a focus that clears banner messages. The matches of each app stay in a cache until its messages, its titles or the window set change. Each source keeps at most 50 messages for each app.

## Sources

Ouch does not read unread marks such as `(3)` or `•` from window titles. Apps use those marks for other things, such as unsaved changes. While badges are on, Ouch keeps the title of each window current, so that the text match uses the title that is on the screen now.

| Source | Gives | How | Cost |
|---|---|---|---|
| `DockBadgeSource` | app | `AXStatusLabel` of each `AXApplicationDockItem`. The Dock posts no notification when a badge changes, so it polls every 10 s on a utility queue. It also polls 0.5 s after each new notification from the database or a banner, and after each app switch, because a badge usually changes at those times. Without Full Disk Access and with no banner (for example in a Focus), a badge can take up to 10 s. It reads the subrole and URL of each item once, when it builds the item list: when an app launches or quits, when an item is gone, and on every third poll. Each poll reads only `AXStatusLabel`, and it goes to the main queue only when a badge changed. It stops while the displays sleep. | measured before the label-only poll: 0.6 ms CPU in Ouch and 1.4 ms in the Dock for each poll. Label only, measured in CatWM: 0.4 ms CPU (1.4 ms wall) in Ouch and about 1 ms in the Dock |
| `NotificationDatabase` | messages | The `usernoted` database (`record` joined to `app`, `data` is a binary plist with `req.titl`, `req.subt`, `req.body`). It watches `db-wal` and reads 0.25 s after the last write. Each read checks `count(*)` and `max(rec_id)`, and decodes only the rows after the last `rec_id`. It reports only the apps whose messages changed. When the count shows that rows were deleted, it reads all rows again. It also sees notifications that a Focus hid. It runs only with Full Disk Access. | a read with no change or one new row: 0.2 to 0.9 ms. A full read (first read, or after a deletion): 6 ms at 1,000 rows, 28 ms at 5,000 rows |
| `BannerSource` | messages | An `AXObserver` on Notification Center for new windows. It reads the `AXNotificationCenterBanner` and `AXNotificationCenterAlert` groups off the main queue. It runs only without Full Disk Access. Its messages go when their window gets focus. | 2 to 130 ms for each banner, off the main queue |

Full Disk Access is optional. The onboarding permission card has a row for it. When it changes, `AppDelegate` calls `Notifications.shared.refreshSources()`, and the database source and the banner source swap.

## Add a source

1. Make a class that conforms to `NotificationSource`. Give it a unique `name`. Do the slow work on your own queue, and call the sink on the main queue.
2. Report with `report(app:)`, `report(window:)`, `report(messages:for:)` (the full list, for a source that knows all current notifications) or `add(_:from:)` (one new notification).
3. Set `isAvailable` when the source needs a permission. Set `messagesClearOnFocus` when the source cannot tell when a notification is read.
4. Register it in `installBuiltIn()`. The order of registration sets which source wins when two report a badge for the same app or window.

## Listen

```swift
let token = Notifications.shared.listen { change in
    // change.window, change.app, change.badge (nil when it goes), change.source
}
Notifications.shared.stopListening(token)
```

External programs subscribe to the `window.notifications` event through the Control socket. They cannot report badges.
