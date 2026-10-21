import Foundation

enum CommandLineTool {
    static func install() {
        guard let exe = Bundle.main.executableURL, exe.path.contains("/Applications/") else { return }
        DispatchQueue.global(qos: .utility).async { link(to: exe) }
    }

    private static func link(to exe: URL) {
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        let folders = [URL(fileURLWithPath: "/usr/local/bin"), home.appendingPathComponent(".local/bin")]
        for folder in folders {
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
            guard files.isWritableFile(atPath: folder.path) else { continue }
            let path = folder.appendingPathComponent("ouch").path
            if let current = try? files.destinationOfSymbolicLink(atPath: path) {
                if current == exe.path { return }
            } else if files.fileExists(atPath: path) {
                continue
            }
            do {
                try? files.removeItem(atPath: path)
                try files.createSymbolicLink(atPath: path, withDestinationPath: exe.path)
                Log.info("cli: linked \(path)")
                return
            } catch {
                Log.info("cli: link \(path) failed: \(error.localizedDescription)")
            }
        }
    }
}
