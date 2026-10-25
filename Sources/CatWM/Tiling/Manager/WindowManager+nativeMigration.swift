import AppKit

extension WindowManager {
    func loadNativeMigration(_ defaults: UserDefaults) {
        if defaults.integer(forKey: "ws.nativeVersion") == 0 {
            defaults.set(defaults.dictionary(forKey: "ws.windows") ?? [:], forKey: "ws.legacy.windows")
            defaults.set(defaults.dictionary(forKey: "ws.owners") ?? [:], forKey: "ws.legacy.owners")
            defaults.set(1, forKey: "ws.nativeVersion")
        }
        if defaults.dictionary(forKey: "ws.nativeMigration") == nil {
            defaults.set(defaults.dictionary(forKey: "ws.legacy.windows") ?? [:], forKey: "ws.nativeMigration")
            if defaults.dictionary(forKey: "ws.legacy.owners") == nil {
                defaults.set(defaults.dictionary(forKey: "ws.owners") ?? [:], forKey: "ws.legacy.owners")
            }
        }
        let pending = defaults.dictionary(forKey: "ws.nativeMigration") as? [String: String] ?? [:]
        desktops.nativeMigration = Dictionary(pending.compactMap { key, value in
            CGWindowID(key).map { ($0, value) }
        }, uniquingKeysWith: { first, _ in first })
    }

    func restoreNativeMigration(_ window: Window) {
        guard let workspace = desktops.nativeMigration[window.id] else { return }
        let owners = UserDefaults.standard.dictionary(forKey: "ws.legacy.owners") as? [String: String] ?? [:]
        guard owners[String(window.id)] == owner(window), isVirtual(workspace), !isPending(workspace) else {
            completeNativeMigration(window.id, workspace: workspace)
            return
        }
        model.assign(window.id, to: workspace)
        desktops.nativeMoveTargets[window.id] = workspace
        DispatchQueue.main.async { [weak self] in
            self?.moveNativeWindow(window, to: workspace, follow: false)
        }
    }

    func completeNativeMigration(_ id: CGWindowID, workspace: String) {
        guard desktops.nativeMigration[id] == workspace else { return }
        desktops.nativeMigration[id] = nil
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: desktops.nativeMigration.map {
            (String($0.key), $0.value)
        }), forKey: "ws.nativeMigration")
    }
}
