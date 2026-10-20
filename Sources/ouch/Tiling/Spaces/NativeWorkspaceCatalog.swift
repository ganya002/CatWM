import Foundation

struct NativeWorkspaceCatalog {
    struct Entry: Equatable {
        let name: String
        let display: String
        let space: UInt64
    }
    struct Display {
        let id: String
        let spaces: [UInt64]
    }
    private(set) var entries: [Entry] = []
    var saved: [String: UInt64] = [:]

    mutating func synchronize(_ displays: [Display]) {
        let live = Set(displays.flatMap(\.spaces).filter { $0 != 0 })
        saved = saved.filter { live.contains($0.value) }
        var assigned = Set<UInt64>()
        saved = saved.sorted { $0.key < $1.key }.reduce(into: [:]) { result, pair in
            if assigned.insert(pair.value).inserted { result[pair.key] = pair.value }
        }
        for display in displays {
            for space in display.spaces where space != 0 && !saved.values.contains(space) {
                var number = 1
                while saved[String(number)] != nil { number += 1 }
                saved[String(number)] = space
            }
        }
        entries = displays.flatMap { display in
            display.spaces.compactMap { space in
                saved.first { $0.value == space }.map { Entry(name: $0.key, display: display.id, space: space) }
            }
        }
    }

    mutating func bind(_ name: String, to space: UInt64, on display: String) {
        saved = saved.filter { $0.value != space && $0.key != name }
        saved[name] = space
        entries.removeAll { $0.space == space || $0.name == name }
        entries.append(Entry(name: name, display: display, space: space))
    }

    func entry(_ name: String) -> Entry? { entries.first { $0.name == name } }
    func entry(space: UInt64) -> Entry? { entries.first { $0.space == space } }
    func step(from name: String, by delta: Int) -> String? {
        guard let source = entry(name) else { return nil }
        let local = entries.filter { $0.display == source.display }
        guard let index = local.firstIndex(of: source) else { return nil }
        return local.indices.contains(index + delta) ? local[index + delta].name : nil
    }
}
