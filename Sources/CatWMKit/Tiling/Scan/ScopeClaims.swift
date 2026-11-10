import Foundation

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

package final class ScopeClaims {
    private let folder: URL
    private let alive: (pid_t) -> Bool
    private let queue = DispatchQueue(label: "catwm.scope-claims")
    private var stamp: Date?
    private var claims: [ScopeClaim] = []
    private var pids: Set<pid_t> = []
    private var changed: (() -> Void)?
    private var folderWatch: DispatchSourceFileSystemObject?
    private var ownerWatches: [pid_t: DispatchSourceProcess] = [:]

    package init(folder: URL, alive: @escaping (pid_t) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) {
        self.folder = folder
        self.alive = alive
    }

    deinit {
        folderWatch?.cancel()
        ownerWatches.values.forEach { $0.cancel() }
    }

    package func claimedPids() -> Set<pid_t> { queue.sync { read() } }

    package func watch(_ changed: @escaping () -> Void) {
        Log.attempt("create \(folder.path)") {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let handle = open(folder.path, O_EVTONLY)
        guard handle >= 0 else {
            Log.info("claims: cannot watch \(folder.path) (errno \(errno))")
            return
        }
        queue.sync {
            self.changed = changed
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: handle, eventMask: .write,
                                                                   queue: .global(qos: .utility))
            source.setEventHandler { [weak self] in self?.folderChanged() }
            source.setCancelHandler { close(handle) }
            source.resume()
            folderWatch = source
            _ = read()
        }
    }

    package func stop() {
        queue.sync {
            changed = nil
            folderWatch?.cancel()
            folderWatch = nil
            ownerWatches.values.forEach { $0.cancel() }
            ownerWatches = [:]
        }
    }

    package func folderChanged() {
        queue.sync {
            guard pids != read() else { return }
            changed?()
        }
    }

    package func ownerExited(_ owner: pid_t) {
        queue.sync { claims.removeAll { $0.owner == owner } }
        folderChanged()
    }

    private func read() -> Set<pid_t> {
        let files = FileManager.default
        let stamp = (try? files.attributesOfItem(atPath: folder.path))?[.modificationDate] as? Date
        if stamp != self.stamp {
            self.stamp = stamp
            let ids = (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
            claims = ids.compactMap { id in
                let file = folder.appendingPathComponent("\(id)/scope")
                return (try? String(contentsOf: file, encoding: .utf8)).flatMap(ScopeClaim.init)
            }
        }
        let live = claims.filter { alive($0.owner) }
        if changed != nil { watchOwners(Set(live.map(\.owner))) }
        pids = Set(live.flatMap(\.scope.pids))
        return pids
    }

    private func watchOwners(_ owners: Set<pid_t>) {
        for (owner, source) in ownerWatches where !owners.contains(owner) {
            source.cancel()
            ownerWatches[owner] = nil
        }
        for owner in owners where ownerWatches[owner] == nil {
            let source = DispatchSource.makeProcessSource(identifier: owner, eventMask: .exit,
                                                          queue: .global(qos: .utility))
            source.setEventHandler { [weak self] in self?.ownerExited(owner) }
            source.resume()
            ownerWatches[owner] = source
        }
    }
}
