import AppKit
import Foundation

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

enum Badge: Equatable {
    case count(Int)
    case dot

    init?(label: String?) {
        guard let label = label?.trimmingCharacters(in: .whitespaces), !label.isEmpty else { return nil }
        let digits = label.filter(\.isNumber).map { $0.wholeNumberValue.map(String.init) ?? String($0) }.joined()
        if let count = Int(digits), count > 0 { self = .count(count) } else { self = .dot }
    }

    var count: Int? {
        if case .count(let count) = self { return count }
        return nil
    }

    var text: String? { count.map { $0 > 99 ? "99+" : String($0) } }

    static func resolve(app: Badge?, own: Badge?) -> Badge? {
        guard let app else { return own }
        guard case .count(let total) = app else { return own ?? app }
        if let mine = own?.count, mine < total { return own }
        return app
    }
}

struct NotificationMessage: Equatable {
    let app: String
    var title = ""
    var subtitle = ""
    var body = ""
}
