import AppKit

struct BindBook {
    let binds: [KeyBinding]
    let enter: KeyBinding?
    let mode: String

    init(binds: [KeyBinding]) {
        self.binds = binds
        enter = binds.first {
            $0.submap.isEmpty && $0.dispatcher == "submap" && !["", "reset"].contains($0.arg.lowercased())
        }
        mode = enter?.arg ?? ""
    }

    func find(_ dispatchers: [String], _ arg: String? = nil, global: Bool = false) -> KeyBinding? {
        let submap = global ? "" : mode
        return binds.first { bind in
            bind.submap == submap
                && dispatchers.contains(bind.dispatcher)
                && (arg.map { KeyWords.same(bind.arg, $0) } ?? true)
        }
    }

    var exits: [KeyBinding] {
        binds.filter {
            $0.submap == mode
                && $0.dispatcher == "submap"
                && ["", "reset"].contains($0.arg.lowercased())
                && $0.mods.isEmpty
        }
    }

    func enterCaps(long: Bool) -> [String] { enter.map { KeyWords.caps($0, long: long) } ?? [] }

    var wasd: Bool { find(["movefocus"], "u")?.keyCode == 13 }

    var directions: [String] { wasd ? ["u", "l", "d", "r"] : ["l", "d", "u", "r"] }

    var resize: (grow: KeyBinding, shrink: KeyBinding)? {
        let ratio = binds.filter { $0.submap == mode }.compactMap { bind in
            KeyWords.ratioDirection(bind.dispatcher, bind.arg).map { (bind, $0) }
        }
        guard let grow = ratio.first(where: { $0.1 == .grow })?.0,
              let shrink = ratio.first(where: { $0.1 == .shrink })?.0 else { return nil }
        return (grow, shrink)
    }
}
