import CoreGraphics
import Foundation

package final class TabDrag {
    private enum Kind { case lifted, native }
    private struct Session {
        package let id: CGWindowID
        package let kind: Kind
        package var allowsJoin = true
    }

    package struct Completion {
        package let allowsJoin: Bool
        package let preview: (group: Int, index: Int)?
    }

    private var session: Session?
    package private(set) var hover: (host: CGWindowID, settled: Bool)?
    private var hoverWork: DispatchWorkItem?

    package var lifted: CGWindowID? { session?.kind == .lifted ? session?.id : nil }
    package var allowsJoin: Bool { session?.allowsJoin ?? true }

    @discardableResult
    package func beginLifted(_ id: CGWindowID) -> Bool {
        guard lifted != id else { return false }
        session = Session(id: id, kind: .lifted)
        return true
    }

    package func beginNative(_ id: CGWindowID) { session = Session(id: id, kind: .native) }

    package func cancelDrop(on surface: any TilingSurface) -> CGWindowID? {
        guard let session, session.allowsJoin else { return nil }
        self.session?.allowsJoin = false
        clearPreview(of: session.id, on: surface)
        return session.id
    }

    package func finish(_ id: CGWindowID?, on surface: any TilingSurface) -> Completion {
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

    package func track(_ host: CGWindowID?, schedule: (DispatchWorkItem) -> Void = TabDrag.scheduleHover,
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
