import CoreGraphics
import Foundation

final class TabDrag {
    private enum Kind { case lifted, native }
    private struct Session {
        let id: CGWindowID
        let kind: Kind
        var allowsJoin = true
    }

    struct Completion {
        let allowsJoin: Bool
        let preview: (group: Int, index: Int)?
    }

    private var session: Session?
    private(set) var hover: (host: CGWindowID, settled: Bool)?
    private var hoverWork: DispatchWorkItem?

    var lifted: CGWindowID? { session?.kind == .lifted ? session?.id : nil }
    var allowsJoin: Bool { session?.allowsJoin ?? true }

    @discardableResult
    func beginLifted(_ id: CGWindowID) -> Bool {
        guard lifted != id else { return false }
        session = Session(id: id, kind: .lifted)
        return true
    }

    func beginNative(_ id: CGWindowID) { session = Session(id: id, kind: .native) }

    func cancelDrop(on surface: any TilingSurface) -> CGWindowID? {
        guard let session, session.allowsJoin else { return nil }
        self.session?.allowsJoin = false
        clearPreview(of: session.id, on: surface)
        return session.id
    }

    func finish(_ id: CGWindowID?, on surface: any TilingSurface) -> Completion {
        let joins = allowsJoin
        session = nil
        let preview = clearPreview(of: id, on: surface)
        return Completion(allowsJoin: joins, preview: preview)
    }

    @discardableResult
    private func clearPreview(of id: CGWindowID?, on surface: any TilingSurface) -> (group: Int, index: Int)? {
        track(nil, changed: {})
        let preview = id.flatMap { surface.endTabPreview(of: $0) }
        surface.hideTabDropHint()
        return preview
    }

    private static func scheduleHover(_ work: DispatchWorkItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work) // style-ok: hover dwell time
    }

    func track(_ host: CGWindowID?, schedule: (DispatchWorkItem) -> Void = TabDrag.scheduleHover,
               changed: @escaping () -> Void) {
        guard host != hover?.host else { return }
        hoverWork?.cancel()
        hoverWork = nil
        hover = host.map { ($0, false) }
        guard let host else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hover?.host == host else { return }
            self.hover?.settled = true
            changed()
        }
        hoverWork = work
        schedule(work)
    }
}
