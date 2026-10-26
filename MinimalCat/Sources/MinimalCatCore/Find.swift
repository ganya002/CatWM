import Foundation

public enum Find {
    /// Windows that match the query, best first. Ties keep the input order.
    public static func rank(_ query: String, _ windows: [WindowInfo]) -> [WindowInfo] {
        let needle = fold(query)
        guard !needle.isEmpty else { return windows }
        let scored = windows.enumerated().compactMap { index, window -> (WindowInfo, Int, Int)? in
            let best = [score(needle, fold(window.app)), score(needle, fold(window.title))].compactMap { $0 }.max()
            return best.map { (window, $0, index) }
        }
        return scored.sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }.map(\.0)
    }

    static func score(_ needle: String, _ text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        if text == needle { return 6 }
        if text.hasPrefix(needle) { return 5 }
        let words = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: { $0.hasPrefix(needle) }) { return 4 }
        if text.contains(needle) { return 3 }
        if String(words.compactMap(\.first)).hasPrefix(needle) { return 2 }
        var rest = Substring(needle)
        for char in text where char == rest.first { rest = rest.dropFirst() }
        return rest.isEmpty ? 1 : nil
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}
