import Foundation

enum Badge: Equatable {
    case count(Int)
    case dot

    init?(label: String?) {
        guard let label = label?.trimmingCharacters(in: .whitespaces), !label.isEmpty else { return nil }
        let digits = label.filter(\.isNumber)
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
