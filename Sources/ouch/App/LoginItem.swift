import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            Log.info("launch at login \(on ? "on" : "off") (status \(SMAppService.mainApp.status.rawValue))")
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
