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
