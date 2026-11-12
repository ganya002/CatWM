import Foundation
import os

package struct ScopeClaim: Equatable {
    package let owner: pid_t
    package let scope: WindowScope

    package init(owner: pid_t, scope: WindowScope) {
        self.owner = owner
        self.scope = scope
    }

    package init?(_ text: String) {
        let lines = text.split(separator: "\n")
        guard lines.count == 2, let owner = pid_t(lines[0]), owner > 0,
              let scope = WindowScope(String(lines[1])) else { return nil }
        self.init(owner: owner, scope: scope)
    }

    package var text: String { "\(owner)\n\(scope.text)\n" }
}

package final class ScopeClaims: Sendable {
    private struct State {
        var stamp: Date?
        var claims: [ScopeClaim] = []
        var pids: Set<pid_t> = []
        var changed: (@Sendable (Set<pid_t>) -> Void)?
        var folderWatch: DispatchSourceFileSystemObject?
        var ownerWatches: [pid_t: DispatchSourceProcess] = [:]
    }

    private let folder: URL
    private let alive: @Sendable (pid_t) -> Bool
    private let state = OSAllocatedUnfairLock(initialState: State())

    package init(folder: URL, alive: @escaping @Sendable (pid_t) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) {
        self.folder = folder
        self.alive = alive
    }

    deinit {
        state.withLock { state in
            state.folderWatch?.cancel()
            state.ownerWatches.values.forEach { $0.cancel() }
        }
    }

    package func claimedPids() -> Set<pid_t> { state.withLock { read(&$0) } }

    package func watch(_ changed: @escaping @Sendable (_ pids: Set<pid_t>) -> Void) {
        Log.attempt("create \(folder.path)") {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let handle = open(folder.path, O_EVTONLY)
        guard handle >= 0 else {
            Log.info("claims: cannot watch \(folder.path) (errno \(errno))")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: handle, eventMask: .write,
                                                               queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in self?.folderChanged() }
        source.setCancelHandler { close(handle) }
        source.resume()
        state.withLock { state in
            state.changed = changed
            state.folderWatch = source
            _ = read(&state)
        }
    }

    package func stop() {
        state.withLock { state in
            state.changed = nil
            state.folderWatch?.cancel()
            state.folderWatch = nil
            state.ownerWatches.values.forEach { $0.cancel() }
            state.ownerWatches = [:]
        }
    }

    package func folderChanged() {
        let (notify, pids) = state.withLock { state -> ((@Sendable (Set<pid_t>) -> Void)?, Set<pid_t>) in
            let before = state.pids
            let after = read(&state)
            return before == after ? (nil, []) : (state.changed, before.symmetricDifference(after))
        }
        notify?(pids)
    }

    package func ownerExited(_ owner: pid_t) {
        state.withLock { state in state.claims.removeAll { $0.owner == owner } }
        folderChanged()
    }

    private func read(_ state: inout State) -> Set<pid_t> {
        let files = FileManager.default
        var info = stat()
        let stamp = stat(folder.path, &info) == 0
            ? Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
            : nil
        if stamp != state.stamp {
            state.stamp = stamp
            let ids = (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
            state.claims = ids.compactMap { id in
                (try? String(contentsOfFile: "\(folder.path)/\(id)/scope", encoding: .utf8)).flatMap(ScopeClaim.init)
            }
        }
        let live = state.claims.filter { alive($0.owner) }
        if state.changed != nil { watchOwners(Set(live.map(\.owner)), in: &state) }
        state.pids = Set(live.flatMap(\.scope.pids))
        return state.pids
    }

    private func watchOwners(_ owners: Set<pid_t>, in state: inout State) {
        for (owner, source) in state.ownerWatches where !owners.contains(owner) {
            source.cancel()
            state.ownerWatches[owner] = nil
        }
        for owner in owners where state.ownerWatches[owner] == nil {
            let source = DispatchSource.makeProcessSource(identifier: owner, eventMask: .exit,
                                                          queue: .global(qos: .utility))
            source.setEventHandler { [weak self] in self?.ownerExited(owner) }
            source.resume()
            state.ownerWatches[owner] = source
        }
    }
}
