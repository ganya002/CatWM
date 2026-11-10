import AppKit

extension WindowManager {
    package func loadNativeMigration(_ defaults: UserDefaults) {
        if defaults.integer(forKey: DefaultsKey.wsNativeVersion) == 0 {
            defaults.set(defaults.dictionary(forKey: DefaultsKey.wsWindows) ?? [:], forKey: DefaultsKey.wsLegacyWindows)
            defaults.set(defaults.dictionary(forKey: DefaultsKey.wsOwners) ?? [:], forKey: DefaultsKey.wsLegacyOwners)
            defaults.set(1, forKey: DefaultsKey.wsNativeVersion)
        }
        if defaults.dictionary(forKey: DefaultsKey.wsNativeMigration) == nil {
            defaults.set(defaults.dictionary(forKey: DefaultsKey.wsLegacyWindows) ?? [:],
                         forKey: DefaultsKey.wsNativeMigration)
            if defaults.dictionary(forKey: DefaultsKey.wsLegacyOwners) == nil {
                defaults.set(defaults.dictionary(forKey: DefaultsKey.wsOwners) ?? [:],
                             forKey: DefaultsKey.wsLegacyOwners)
            }
        }
        let pending = defaults.dictionary(forKey: DefaultsKey.wsNativeMigration) as? [String: String] ?? [:]
        desktops.nativeMigration = Dictionary(pending.compactMap { key, value in
            CGWindowID(key).map { ($0, value) }
        }, uniquingKeysWith: { first, _ in first })
    }

    package func restoreNativeMigration(_ window: Window) {
        guard let workspace = desktops.nativeMigration[window.id] else { return }
        let owners = Instance.defaults.dictionary(forKey: DefaultsKey.wsLegacyOwners) as? [String: String] ?? [:]
        guard owners[String(window.id)] == owner(window), isVirtual(workspace), !isPending(workspace) else {
            completeNativeMigration(window.id, workspace: workspace)
            return
        }
        model.assign(window.id, to: workspace)
        nativeMoves.requestWorkspace(window.id, workspace: workspace)
        DispatchQueue.main.async { [weak self] in
            self?.moveNativeWindow(window, to: workspace, follow: false)
        }
    }

    package func completeNativeMigration(_ id: CGWindowID, workspace: String) {
        guard desktops.nativeMigration[id] == workspace else { return }
        desktops.nativeMigration[id] = nil
        Instance.defaults.set(Dictionary(uniqueKeysWithValues: desktops.nativeMigration.map {
            (String($0.key), $0.value)
        }), forKey: DefaultsKey.wsNativeMigration)
    }
}
