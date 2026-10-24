import AppKit
protocol NotificationSource: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get }
    var messagesClearOnFocus: Bool { get }
    func start(_ sink: NotificationSink)
    func stop()
}

extension NotificationSource {
    var isAvailable: Bool { true }
    var messagesClearOnFocus: Bool { false }
}

protocol NotificationSink: AnyObject {
    func report(app: String, _ badge: Badge?, from source: String)
    func report(window: CGWindowID, _ badge: Badge?, from source: String)
    func report(messages: [NotificationMessage], for app: String, from source: String)
    func add(_ message: NotificationMessage, from source: String)
}
