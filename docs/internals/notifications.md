# Notifications: the unread badge of each window

`Notifications.shared` (`Sources/CatWMKit/Notifications/`) holds one `Badge` per window: a count or a dot. macOS has no API that says which window a notification is for. The Dock knows a count per app, and Notification Center knows messages per app. CatWM has to derive per-window counts from those at almost no CPU, because it runs all the time. With `tab-notification-badges` off, no source runs.

## The rule

`Badge.resolve(app:own:)` gives each window the app's Dock badge. A window gets a lower count of its own only from messages whose title or subtitle is in the title of exactly one window of the app. The Dock count is right for the app but can't tell windows apart, and the text match can tell them apart but misses messages. So the Dock is the upper limit, and the match lowers it only when it's sure. When the app badge goes, that app's banner messages go too.

CatWM doesn't read marks such as `(3)` or `•` from titles. Apps use them for other things, such as unsaved changes, and tldraw got false dots.

`resolve()` runs only when an input changes, and the matches of each app are cached until its messages, titles or window set change.

## Sources

| Source | Gives | Runs when | Cost |
|---|---|---|---|
| `DockBadgeSource` | app badges | always | 0.4–0.9 ms in CatWM and 1–2 ms in the Dock per poll |
| `NotificationDatabase` | messages | Full Disk Access | 0.2–0.9 ms per incremental read, 28 ms for a full read of 5,000 rows |
| `BannerSource(reportsMessages: true)` | messages | no Full Disk Access | 2–130 ms per banner, off the main queue |
| `BannerSource(reportsMessages: false)` | a Dock poll trigger | Full Disk Access | one Dock poll per banner |

Registration order decides which source wins a conflict. Measure a new source's idle CPU and its latency to a badge, and add both here.

**Dock.** The Dock posts no AX notification when a badge changes, so `DockBadgeSource` polls `AXStatusLabel`. It polls every 10 s, plus 0.5 s after a database write, a banner or an app switch, which catches most changes. It stops while the displays sleep. A badge only shows on a managed window, so `Notifications` tells each source which app bundles have one (`track(_:)`). The Dock poll reads `AXStatusLabel` only for those apps and pauses its timer while there are none, so an instance that manages no window (such as a scoped one) never polls. A newly tracked app triggers the 0.5 s nudge, so its badge shows at once. We rejected polling always and filtering later, because the Dock reads are the cost. Polling cost grows with frequency (13 Dock items, CPU per minute):

| Interval | CatWM | Dock |
|---|---|---|
| 10 s | about 5 ms | no visible change |
| 3 s | 17.3 ms | about +30 ms |
| 1 s | 46.2 ms | about +130 ms |

The idle Dock uses 370–450 ms a minute, ±35 ms between runs.

**Database.** `NotificationDatabase` reads the `usernoted` database in `group.com.apple.usernoted/db2/db`. It watches `db-wal`, checks `count(*)` and `max(rec_id)`, and decodes only new rows. It sees notifications that a Focus hid. It opens the database for each read, because reads are rare and cost under 1 ms, and a kept connection would have to survive file replacement without holding a read transaction. It can't be faster: `usernoted` writes 5–8 s after the Dock badge changes, and SQLite hooks fire only for writes on the same connection.

**Banners.** `BannerSource` observes Notification Center's AX tree and matches the app by `localizedName` in the banner text. A banner can't say when its message was read, so its messages clear when their window gets focus. Banners miss Focus, Do Not Disturb, the "None" alert style, a locked or mirrored screen, badges set with no notification and messages read on another device. So the Dock poll stays on even with banners.

## Rejected routes

| Route | Why not |
|---|---|
| Unread marks in titles | Apps use the same marks for other things |
| AX notifications from the Dock | The Dock posts none for badges |
| LaunchServices `StatusLabel` | Stored but never notified (4 changes, 0 notifications), so it's a private-API poll |
| Distributed notifications | Apps can't observe all names, and none came in 90 s |
| SQLite hooks | They fire only in the writing process |
| `log stream` | Instant, but costly, noisy and private |
| Notification Center panel via AX | Readable only while the panel is open |
| `UNUserNotificationCenter` | Only CatWM's own notifications |
