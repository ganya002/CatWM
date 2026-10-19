import CoreGraphics

struct WorkspaceObservation {
    struct Display {
        let id: String
        let frame: CGRect
        let space: UInt64
        let spaces: Set<UInt64>
    }

    let displays: [Display]
    let frames: [CGWindowID: CGRect]
    let present: Set<CGWindowID>
    let held: Set<CGWindowID>
    var fullscreen: [CGWindowID: UInt64] = [:]
}

struct WorkspaceReconciliation {
    var model: WorkspaceModel
    var homeSpace: [String: UInt64]
    var displayOf: [CGWindowID: String]
    let visible: Set<CGWindowID>
    let park: Set<CGWindowID>

    static func reconcile(_ observation: WorkspaceObservation, model input: WorkspaceModel, virtual: Bool,
                          homeSpace homes: [String: UInt64], displayOf previous: [CGWindowID: String]) -> Self {
        var model = input
        var homes = homes
        var displayOf = previous
        let displays = observation.displays
        guard let first = displays.first else {
            return Self(model: model, homeSpace: homes, displayOf: displayOf, visible: [], park: [])
        }
        let uuids = Set(displays.map(\.id))
        func isVirtual(_ ws: String) -> Bool { !ws.hasPrefix(WindowManager.spacePrefix) }
        func isPending(_ ws: String) -> Bool { ws.hasPrefix(WindowManager.pendingPrefix) }
        for u in model.shown.keys where !uuids.contains(u) { model.shown[u] = nil }
        for u in model.virtualShown.keys where !uuids.contains(u) { model.virtualShown[u] = nil }
        if virtual {
            for (ws, m) in model.monitorOf where isVirtual(ws) && !uuids.contains(m) { model.monitorOf[ws] = first.id }
        }
        var onHome = Set<String>()
        for display in displays {
            if virtual {
                if let home = homes[display.id], !display.spaces.isEmpty, !display.spaces.contains(home) { homes[display.id] = nil }
                if homes[display.id] == nil { homes[display.id] = display.space }
            }
            if virtual && display.space == homes[display.id] {
                if model.virtualShown[display.id] == nil {
                    let own = model.monitorOf.filter {
                        $0.value == display.id && isVirtual($0.key) && !isPending($0.key) && !model.virtualShown.values.contains($0.key)
                    }.map(\.key).sorted(by: workspaceSort).first
                    let used = Set(model.workspaceOf.values).union(model.virtualShown.values)
                    var n = 1
                    while used.contains(String(n)) { n += 1 }
                    model.virtualShown[display.id] = own ?? String(n)
                }
                model.show(model.virtualShown[display.id], on: display.id)
                onHome.insert(display.id)
            } else {
                model.show(WindowManager.spaceWorkspace(display: display.id, space: display.space), on: display.id)
            }
            if let ws = model.shown[display.id] { model.monitorOf[ws] = display.id }
        }
        model.fullscreenHost = [:]
        for (id, space) in observation.fullscreen.sorted(by: { $0.key < $1.key }) {
            guard let owner = displays.first(where: { $0.spaces.contains(space) }) else { continue }
            let ws = WindowManager.spaceWorkspace(display: owner.id, space: space)
            model.assign(id, to: ws)
            model.monitorOf[ws] = owner.id
            model.fullscreenHost[ws] = id
        }
        func display(containing frame: CGRect) -> String {
            guard !frame.isNull else { return first.id }
            return displays.max { a, b in
                area(a.frame.intersection(frame)) < area(b.frame.intersection(frame))
            }?.id ?? first.id
        }
        for id in observation.present where !observation.held.contains(id) {
            guard let ws = model.workspaceOf[id], model.isShown(ws), let frame = observation.frames[id], !frame.isNull,
                  displays.reduce(CGFloat(0), { $0 + area($1.frame.intersection(frame)) }) >= 400 else { continue }
            let now = display(containing: frame)
            defer { displayOf[id] = now }
            guard let was = displayOf[id], was != now, uuids.contains(was),
                  let monitor = model.monitorOf[ws], monitor != now, let destination = model.shown[now] else { continue }
            model.assign(id, to: destination)
        }
        for id in observation.present where !model.isShown(model.workspaceOf[id]) {
            if let ws = model.workspaceOf[id], isVirtual(ws), let monitor = model.monitorOf[ws], onHome.contains(monitor) { continue }
            model.assign(id, to: model.shown[display(containing: observation.frames[id] ?? .null)])
        }
        let visible = observation.present.filter { model.isShown(model.workspaceOf[$0]) }
        return Self(model: model, homeSpace: homes, displayOf: displayOf, visible: visible,
                    park: virtual ? observation.present.subtracting(visible) : [])
    }

    private static func area(_ frame: CGRect) -> CGFloat { frame.isNull ? 0 : frame.width * frame.height }

    private static func workspaceSort(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a < b
        }
    }
}
