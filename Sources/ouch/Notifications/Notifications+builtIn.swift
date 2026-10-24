import AppKit

extension Notifications {
    func installBuiltIn() {
        let dock = DockBadgeSource(), database = NotificationDatabase()
        let banners = [BannerSource(reportsMessages: true), BannerSource(reportsMessages: false)]
        database.changed = { [weak dock] in dock?.pollSoon() }
        register(dock)
        register(database)
        for banner in banners {
            banner.changed = { [weak dock] in dock?.pollSoon() }
            register(banner)
        }
    }
}
