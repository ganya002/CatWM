import AppKit

extension Notifications {
    func installBuiltIn() {
        let dock = DockBadgeSource(), database = NotificationDatabase(), banner = BannerSource()
        database.changed = { [weak dock] in dock?.pollSoon() }
        banner.changed = { [weak dock] in dock?.pollSoon() }
        register(dock)
        register(database)
        register(banner)
        var queued = false
        listen { _ in
            guard !queued else { return }
            queued = true
            DispatchQueue.main.async {
                queued = false
                TabStrips.shared.update()
            }
        }
    }
}
