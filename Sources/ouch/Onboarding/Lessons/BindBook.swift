import AppKit

struct BindBook {
    let binds: [KeyBinding]
    let enter: KeyBinding?
    let mode: String

    init(binds: [KeyBinding]) {
        self.binds = binds
        enter = binds.first { $0.submap.isEmpty && $0.dispatcher == "submap" && !["", "reset"].contains($0.arg.lowercased()) }
        mode = enter?.arg ?? ""
    }

    func find(_ dispatchers: [String], _ arg: String? = nil, global: Bool = false) -> KeyBinding? {
        let submap = global ? "" : mode
        return binds.first { b in
            b.submap == submap && dispatchers.contains(b.dispatcher) && (arg.map { KeyWords.same(b.arg, $0) } ?? true)
        }
    }

    var exits: [KeyBinding] {
        binds.filter { $0.submap == mode && $0.dispatcher == "submap" && ["", "reset"].contains($0.arg.lowercased()) && $0.mods.isEmpty }
    }

    func enterCaps(long: Bool) -> [String] { enter.map { KeyWords.caps($0, long: long) } ?? [] }

    var wasd: Bool { find(["movefocus"], "u")?.keyCode == 13 }

    var directions: [String] { wasd ? ["u", "l", "d", "r"] : ["l", "d", "u", "r"] }

    var resize: (grow: KeyBinding, shrink: KeyBinding)? {
        let ratio = binds.filter { $0.submap == mode }.compactMap { b in KeyWords.ratioDirection(b.dispatcher, b.arg).map { (b, $0) } }
        guard let g = ratio.first(where: { $0.1 })?.0, let s = ratio.first(where: { !$0.1 })?.0 else { return nil }
        return (g, s)
    }
}
