import Foundation

enum SwitcherSearch {
    static func results(_ items: [SwitcherItem], query: String) -> [SwitcherItem] {
        let needle = fold(query)
        guard !needle.isEmpty else { return items }
        let scored: [(item: SwitcherItem, score: Int)] = items.compactMap { item in
            score(item, needle).map { (item, $0) }
        }
        return scored.enumerated()
            .sorted { lhs, rhs in
                lhs.element.score == rhs.element.score ? lhs.offset < rhs.offset : lhs.element.score > rhs.element.score
            }
            .map(\.element.item)
    }

    static func soleJump(_ items: [SwitcherItem], query: String) -> SwitcherItem? {
        let needle = fold(query)
        guard !needle.isEmpty else { return nil }
        let hits = items.filter { item in [item.app, item.title].contains { fold($0).hasPrefix(needle) } }
        return hits.count == 1 ? hits[0] : nil
    }

    static func score(_ item: SwitcherItem, _ needle: String) -> Int? {
        let app: Int? = match(needle, in: item.app).map { $0 + 2 }
        let scores: [Int?] = [app, match(needle, in: item.title), match(needle, in: item.workspace)]
        return scores.compactMap(\.self).max()
    }

    static func match(_ needle: String, in text: String) -> Int? {
        let hay = Array(fold(text)), raw = Array(text)
        let camel = raw.count == hay.count
        guard !needle.isEmpty else { return nil }
        var score = 0, start = 0, last = -2
        for char in needle {
            guard let found = hay[start...].firstIndex(of: char) else { return nil }
            score += 1
            if found == last + 1 { score += 2 }
            if startsWord(found, hay, camel ? raw : hay) { score += 3 }
            last = found
            start = found + 1
        }
        return score - (hay.firstIndex(of: needle.first ?? " ") ?? 0) / 4
    }

    private static func startsWord(_ index: Int, _ hay: [Character], _ raw: [Character]) -> Bool {
        guard index > 0 else { return true }
        let before = hay[index - 1]
        if !before.isLetter && !before.isNumber { return true }
        return raw[index].isUppercase && raw[index - 1].isLowercase
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
