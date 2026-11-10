import AppKit
import CoreGraphics

package struct WorkspaceObservation {
    package struct Display {
        package let id: String
        package let frame: CGRect
        package let space: UInt64
        package let spaces: Set<UInt64>
    }

    package let displays: [Display]
    package let frames: [CGWindowID: CGRect]
    package let present: Set<CGWindowID>
    package let held: Set<CGWindowID>
    package var fullscreen: [CGWindowID: UInt64] = [:]
}

package struct WorkspaceReconciliation {
    package var model: WorkspaceModel
    package var homeSpace: [String: UInt64]
    package var displayOf: [CGWindowID: String]
    package let visible: Set<CGWindowID>
    package let park: Set<CGWindowID>

    package static func reconcile(_ observation: WorkspaceObservation, model input: WorkspaceModel, virtual: Bool,
                                  homeSpace homes: [String: UInt64], displayOf previous: [CGWindowID: String]) -> Self {
        var model = input
        var homes = homes
        var displayOf = previous
        let displays = observation.displays
        guard let first = displays.first else {
            return Self(model: model, homeSpace: homes, displayOf: displayOf, visible: [], park: [])
        }
        let uuids = Set(displays.map(\.id))
        for uuid in model.shown.keys where !uuids.contains(uuid) { model.shown[uuid] = nil }
        for uuid in model.virtualShown.keys where !uuids.contains(uuid) { model.virtualShown[uuid] = nil }
        if virtual {
            for (workspace, monitor) in model.monitorOf where isVirtual(workspace) && !uuids.contains(monitor) {
                model.monitorOf[workspace] = first.id
            }
        }
        var onHome = Set<String>()
        for display in displays where show(display, in: &model, homes: &homes, virtual: virtual) {
            onHome.insert(display.id)
        }
        hostFullscreen(observation, in: &model)
        followMovedWindows(observation, in: &model, displayOf: &displayOf, uuids: uuids)
        var moves: [CGWindowID: String] = [:]
        for id in observation.present where !model.isShown(model.workspaceOf[id]) {
            if let workspace = model.workspaceOf[id], isVirtual(workspace), let monitor = model.monitorOf[workspace],
               onHome.contains(monitor) { continue }
            let target = display(containing: observation.frames[id] ?? .null, among: displays)
            moves[id] = model.shown[target]
        }
        model.assign(moves)
        let visible = observation.present.filter { model.isShown(model.workspaceOf[$0]) }
        return Self(model: model, homeSpace: homes, displayOf: displayOf, visible: visible,
                    park: virtual ? observation.present.subtracting(visible) : [])
    }

    private static func isVirtual(_ workspace: String) -> Bool { !workspace.hasPrefix(WindowManager.spacePrefix) }

    private static func isPending(_ workspace: String) -> Bool { workspace.hasPrefix(WindowManager.pendingPrefix) }

    private static func show(
        _ display: WorkspaceObservation.Display, in model: inout WorkspaceModel, homes: inout [String: UInt64],
        virtual: Bool
    ) -> Bool {
        var isHome = false
        if virtual {
            if let home = homes[display.id], !display.spaces.isEmpty, !display.spaces.contains(home) {
                homes[display.id] = nil
            }
            if homes[display.id] == nil { homes[display.id] = display.space }
        }
        if virtual && display.space == homes[display.id] {
            if model.virtualShown[display.id] == nil {
                model.virtualShown[display.id] = ownWorkspace(of: display.id, in: model) ?? freeWorkspace(in: model)
            }
            model.show(model.virtualShown[display.id], on: display.id)
            isHome = true
        } else {
            model.show(WindowManager.spaceWorkspace(display: display.id, space: display.space), on: display.id)
        }
        if let workspace = model.shown[display.id] { model.monitorOf[workspace] = display.id }
        return isHome
    }

    private static func ownWorkspace(of display: String, in model: WorkspaceModel) -> String? {
        model.monitorOf.filter {
            $0.value == display && isVirtual($0.key) && !isPending($0.key)
                && !model.virtualShown.values.contains($0.key)
        }.map(\.key).min(by: workspaceSort)
    }

    private static func freeWorkspace(in model: WorkspaceModel) -> String {
        let used = Set(model.workspaceOf.values).union(model.virtualShown.values)
        var number = 1
        while used.contains(String(number)) { number += 1 }
        return String(number)
    }

    private static func hostFullscreen(_ observation: WorkspaceObservation, in model: inout WorkspaceModel) {
        model.fullscreenHost = [:]
        for (id, space) in observation.fullscreen.sorted(by: { $0.key < $1.key }) {
            guard let owner = observation.displays.first(where: { $0.spaces.contains(space) }) else { continue }
            let workspace = WindowManager.spaceWorkspace(display: owner.id, space: space)
            model.hostMaximised(id, in: workspace)
            model.monitorOf[workspace] = owner.id
            model.fullscreenHost[workspace] = id
        }
    }

    private static func followMovedWindows(
        _ observation: WorkspaceObservation, in model: inout WorkspaceModel,
        displayOf: inout [CGWindowID: String], uuids: Set<String>
    ) {
        let displays = observation.displays
        for id in observation.present where !observation.held.contains(id) {
            guard let workspace = model.workspaceOf[id], model.isShown(workspace),
                  let frame = observation.frames[id], !frame.isNull,
                  displays.reduce(CGFloat(0), { $0 + area($1.frame.intersection(frame)) }) >= 400 else { continue }
            let now = display(containing: frame, among: displays)
            defer { displayOf[id] = now }
            guard let was = displayOf[id], was != now, uuids.contains(was),
                  let monitor = model.monitorOf[workspace], monitor != now,
                  let destination = model.shown[now] else { continue }
            model.assign(id, to: destination)
        }
    }

    private static func display(containing frame: CGRect, among displays: [WorkspaceObservation.Display]) -> String {
        let fallback = displays.first?.id ?? ""
        guard !frame.isNull else { return fallback }
        return displays.max { first, second in
            area(first.frame.intersection(frame)) < area(second.frame.intersection(frame))
        }?.id ?? fallback
    }

    private static func area(_ frame: CGRect) -> CGFloat { frame.isNull ? 0 : frame.width * frame.height }

    package static func workspaceSort(_ first: String, _ second: String) -> Bool {
        switch (Int(WorkspaceKey.number(first)), Int(WorkspaceKey.number(second))) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return first < second
        }
    }
}

package enum SharedSpaces {
    package static func isOn(displays count: Int) -> Bool { count > 1 && !NSScreen.screensHaveSeparateSpaces }

    package static func display(of frame: CGRect, kept: String?, target: CGRect?, settling: Bool,
                                in screens: [(id: String, frame: CGRect)]) -> String? {
        let kept = kept.flatMap { id in screens.contains { $0.id == id } ? id : nil }
        if let kept, settling || target.map { frame.approxEqual($0) } == true { return kept }
        guard !frame.isNull else { return kept ?? screens.first?.id }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        if let hit = screens.first(where: { $0.frame.contains(centre) }) { return hit.id }
        func overlap(_ rect: CGRect) -> CGFloat {
            let shared = rect.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        let best = screens.max { overlap($0.frame) < overlap($1.frame) }
        return best.map { overlap($0.frame) > 0 } == true ? best?.id : kept ?? screens.first?.id
    }
}
