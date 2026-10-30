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
        var uuids: [UInt64: String] = [:]
    }
    private(set) var entries: [Entry] = []
    var saved: [String: UInt64] = [:]
    var homes: [String: String] = [:]
    var uuids: [String: String] = [:]
    var perDisplay = false
    var sharedSpaces = false

    @discardableResult
    mutating func synchronize(_ displays: [Display]) -> Set<String> {
        if perDisplay { follow(displays); return [] }
        let spaceOf = Dictionary(displays.flatMap { $0.uuids.map { ($0.value, $0.key) } },
                                 uniquingKeysWith: { first, _ in first })
        for (name, uuid) in uuids { if let space = spaceOf[uuid] { saved[name] = space } }
        let live = Set(displays.flatMap(\.spaces).filter { $0 != 0 })
        let connected = Set(displays.map(\.id))
        let previousNames = Set(saved.keys)
        saved = saved.filter { live.contains($0.value) || homes[$0.key].map { !connected.contains($0) } == true }
        let removed = previousNames.subtracting(saved.keys)
        var assigned = Set<UInt64>()
        saved = saved.sorted { $0.key < $1.key }.reduce(into: [:]) { result, pair in
            if assigned.insert(pair.value).inserted { result[pair.key] = pair.value }
        }
        for display in displays {
            for space in display.spaces where space != 0 && !saved.values.contains(space) {
                saved[freeName(on: display.id, in: saved)] = space
            }
        }
        entries = displays.flatMap { display in
            display.spaces.compactMap { space in
                saved.first { $0.value == space }.map { Entry(name: $0.key, display: display.id, space: space) }
            }
        }
        for entry in entries { homes[entry.name] = entry.display }
        homes = homes.filter { saved[$0.key] != nil }
        let uuidOf = Dictionary(displays.flatMap(\.uuids), uniquingKeysWith: { first, _ in first })
        for entry in entries { uuids[entry.name] = uuidOf[entry.space] }
        uuids = uuids.filter { saved[$0.key] != nil }
        return removed
    }

    private mutating func follow(_ displays: [Display]) {
        saved = [:]; homes = [:]; uuids = [:]
        entries = displays.flatMap { display in
            display.spaces.filter { $0 != 0 }.enumerated().map { index, space in
                Entry(name: WorkspaceKey.make(String(index + 1), on: display.id, perDisplay: true),
                      display: display.id, space: space)
            }
        }
    }

    mutating func bind(_ name: String, to space: UInt64, on display: String) {
        saved = saved.filter { $0.value != space && $0.key != name }
        saved[name] = space
        homes[name] = display
        uuids = uuids.filter { saved[$0.key] != nil && $0.key != name }
        entries.removeAll { $0.space == space || $0.name == name }
        entries.append(Entry(name: name, display: display, space: space))
    }

    func freeNumber(on display: String) -> String {
        perDisplay ? WorkspaceKey.make(String(entries(on: display).count + 1), on: display, perDisplay: true)
            : freeName(on: display, in: saved)
    }

    private func freeName(on display: String, in taken: [String: UInt64]) -> String {
        var number = 1
        while taken[WorkspaceKey.make(String(number), on: display, perDisplay: perDisplay)] != nil { number += 1 }
        return WorkspaceKey.make(String(number), on: display, perDisplay: perDisplay)
    }

    func entry(_ name: String) -> Entry? { entries.first { $0.name == name } }
    func entry(space: UInt64) -> Entry? { entries.first { $0.space == space } }
    func entries(on display: String) -> [Entry] { entries.filter { $0.display == display } }

    func shown(_ current: [(display: String, space: UInt64)]) -> [String: String] {
        var claimed = Set<String>()
        return current.reduce(into: [:]) { result, item in
            guard let name = entry(space: item.space)?.name, sharedSpaces || claimed.insert(name).inserted else {
                return
            }
            result[item.display] = name
        }
    }

    func successor(of name: String, on display: String) -> UInt64? {
        guard !perDisplay else { return nil }
        return entries(on: display).filter { WorkspaceReconciliation.workspaceSort(name, $0.name) }
            .min { WorkspaceReconciliation.workspaceSort($0.name, $1.name) }?.space
    }

    func step(from name: String, by delta: Int) -> String? {
        guard let source = entry(name) else { return nil }
        let local = entries(on: source.display)
            .sorted { WorkspaceReconciliation.workspaceSort($0.name, $1.name) }
        guard let index = local.firstIndex(of: source) else { return nil }
        guard delta >= -index, delta < local.count - index else { return nil }
        return local[index + delta].name
    }
}
