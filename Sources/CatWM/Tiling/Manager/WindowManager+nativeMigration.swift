import AppKit

extension WindowManager {
    func loadNativeMigration(_ defaults: UserDefaults) {
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

    func restoreNativeMigration(_ window: Window) {
        guard let workspace = desktops.nativeMigration[window.id] else { return }
        let owners = UserDefaults.standard.dictionary(forKey: DefaultsKey.wsLegacyOwners) as? [String: String] ?? [:]
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
        }), forKey: DefaultsKey.wsNativeMigration)
    }
}
