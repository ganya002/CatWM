import Foundation
import ServiceManagement

enum LoginItem {
    private static var status = SMAppService.mainApp.status
    static var isEnabled: Bool { status == .enabled }
    static var needsApproval: Bool { status == .requiresApproval }

    static func refresh(then done: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let next = SMAppService.mainApp.status
            DispatchQueue.main.async {
                status = next
                done()
            }
        }
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            status = SMAppService.mainApp.status
            Log.info("launch at login \(enabled ? "on" : "off") (status \(status.rawValue))")
            return true
        } catch {
            Log.info("launch at login: \(error.localizedDescription)")
            return false
        }
    }

    static func enableOnFirstLaunch() {
        let key = "didSetUpLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(true)
    }

    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

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
            let path = folder.appendingPathComponent("catwm").path
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
