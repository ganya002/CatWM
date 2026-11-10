import CatWMKit
import Foundation
import ServiceManagement

final class LoginItem {
    static let shared = LoginItem()
    private var status = SMAppService.mainApp.status
    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh(then done: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let next = SMAppService.mainApp.status
            DispatchQueue.main.async {
                self.status = next
                done()
            }
        }
    }

    static let isAvailable = !Instance.isNamed

    @discardableResult
    func set(_ enabled: Bool, available: Bool = LoginItem.isAvailable,
             service: (Bool) throws -> Void = LoginItem.applyToMainApp) -> Bool {
        guard available else { return false }
        do {
            try service(enabled)
            status = SMAppService.mainApp.status
            Log.info("launch at login \(enabled ? "on" : "off") (status \(status.rawValue))")
            return true
        } catch {
            Log.info("launch at login: \(error.localizedDescription)")
            return false
        }
    }

    static func applyToMainApp(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    func enableOnFirstLaunch() {
        let key = "didSetUpLaunchAtLogin"
        guard !Instance.defaults.bool(forKey: key) else { return }
        Instance.defaults.set(true, forKey: key)
        set(true)
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
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
            Log.attempt("cli: create \(folder.path)") {
                try files.createDirectory(at: folder, withIntermediateDirectories: true)
            }
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
