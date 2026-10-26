import Foundation

public enum Find {
    /// Windows that match the query, best first. Ties keep the input order.
    public static func rank(_ query: String, _ windows: [WindowInfo]) -> [WindowInfo] {
        let needle = fold(query)
        guard !needle.isEmpty else { return windows }
        struct Scored { let window: WindowInfo; let score: Int; let index: Int }
        let scored = windows.enumerated().compactMap { index, window -> Scored? in
            let best = [score(needle, fold(window.app)), score(needle, fold(window.title))].compactMap(\.self).max()
            return best.map { Scored(window: window, score: $0, index: index) }
        }
        return scored.sorted { ($0.score, -$0.index) > ($1.score, -$1.index) }.map(\.window)
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
