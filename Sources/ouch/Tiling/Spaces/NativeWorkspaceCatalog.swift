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
        var current: UInt64?
    }
    private(set) var entries: [Entry] = []
    private(set) var spares: [UInt64: String] = [:]
    var saved: [String: UInt64] = [:]
    var homes: [String: String] = [:]

    mutating func synchronize(_ displays: [Display]) {
        let live = Set(displays.flatMap(\.spaces).filter { $0 != 0 })
        let connected = Set(displays.map(\.id))
        let current = Set(displays.compactMap(\.current))
        spares = displays.reduce(into: [:]) { result, display in
            for space in display.spaces where spares[space] != nil && !current.contains(space) {
                result[space] = display.id
            }
        }
        saved = saved.filter { live.contains($0.value) || homes[$0.key].map { !connected.contains($0) } == true }
        var assigned = Set<UInt64>()
        saved = saved.sorted { $0.key < $1.key }.reduce(into: [:]) { result, pair in
            if assigned.insert(pair.value).inserted { result[pair.key] = pair.value }
        }
        for display in displays {
            for space in display.spaces where space != 0 && spares[space] == nil && !saved.values.contains(space) {
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
        for entry in entries { homes[entry.name] = entry.display }
        homes = homes.filter { saved[$0.key] != nil }
    }

    mutating func bind(_ name: String, to space: UInt64, on display: String) {
        saved = saved.filter { $0.value != space && $0.key != name }
        saved[name] = space
        homes[name] = display
        entries.removeAll { $0.space == space || $0.name == name }
        entries.append(Entry(name: name, display: display, space: space))
        spares[space] = nil
    }

    mutating func release(_ name: String) {
        guard let entry = entry(name) else { return }
        saved[name] = nil
        homes[name] = nil
        entries.removeAll { $0.name == name }
        spares[entry.space] = entry.display
    }

    func spare(on display: String) -> UInt64? {
        spares.filter { $0.value == display }.keys.min()
    }

    func freeNumber() -> String {
        var number = 1
        while entry(String(number)) != nil { number += 1 }
        return String(number)
    }

    func entry(_ name: String) -> Entry? { entries.first { $0.name == name } }
    func entry(space: UInt64) -> Entry? { entries.first { $0.space == space } }
    func step(from name: String, by delta: Int) -> String? {
        guard let source = entry(name) else { return nil }
        let local = entries.filter { $0.display == source.display }
            .sorted { WorkspaceReconciliation.workspaceSort($0.name, $1.name) }
        guard let index = local.firstIndex(of: source) else { return nil }
        return local.indices.contains(index + delta) ? local[index + delta].name : nil
    }
}
