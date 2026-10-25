import Foundation

struct ScopeClaim: Equatable {
    let owner: pid_t
    let scope: WindowScope

    init(owner: pid_t, scope: WindowScope) {
        self.owner = owner
        self.scope = scope
    }

    init?(_ text: String) {
        let lines = text.split(separator: "\n")
        guard lines.count == 2, let owner = pid_t(lines[0]), owner > 0,
              let scope = WindowScope(String(lines[1])) else { return nil }
        self.init(owner: owner, scope: scope)
    }

    var text: String { "\(owner)\n\(scope.text)\n" }
}

final class ScopeClaims {
    private let folder: URL
    private let alive: (pid_t) -> Bool
    private var stamps: [String: Date] = [:]
    private var claims: [ScopeClaim] = []

    init(folder: URL, alive: @escaping (pid_t) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) {
        self.folder = folder
        self.alive = alive
    }

    func claimedPids() -> Set<pid_t> {
        let files = FileManager.default
        let ids = (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
        var stamps: [String: Date] = [:]
        for id in ids {
            let path = folder.appendingPathComponent("\(id)/scope").path
            if let date = (try? files.attributesOfItem(atPath: path))?[.modificationDate] as? Date {
                stamps[path] = date
            }
        }
        if stamps != self.stamps {
            self.stamps = stamps
            claims = stamps.keys.compactMap { path in
                (try? String(contentsOfFile: path, encoding: .utf8)).flatMap(ScopeClaim.init)
            }
        }
        return Set(claims.filter { alive($0.owner) }.flatMap(\.scope.pids))
    }
}
