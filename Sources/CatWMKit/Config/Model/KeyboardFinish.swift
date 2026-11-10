import Foundation

package enum KeyboardFinish {
    package static let families = ["macbook-pro", "macbook-air", "macbook-neo", "magic-keyboard", "imac"]

    package static func slug(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "·", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .joined(separator: "-")
    }

    package static func isValid(_ setting: String) -> Bool {
        let wanted = slug(setting)
        return wanted == "auto" || families.contains { wanted == $0 || wanted.hasPrefix($0 + "-") }
    }
}
