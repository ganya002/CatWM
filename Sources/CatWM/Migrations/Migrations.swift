import Foundation

enum Migrations {
    static let legacyBundlePrefixes = ["local.ouch", "local.hyprthyst"]
    static let legacyConfigMarker = "ouch"
    static let legacyConfigExtension = "ouchconfig"

    static func run() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        moveOuchConfigFolder(home: home)
        copyHyprthystConfig(home: home)
        migrateDefaults(.standard)
    }

    static func isLegacyBundle(_ bundle: String) -> Bool {
        legacyBundlePrefixes.contains { bundle.hasPrefix($0) }
    }

    static func moveOuchConfigFolder(home: URL, fileManager: FileManager = .default) {
        let old = home.appendingPathComponent(".config/ouch")
        let new = home.appendingPathComponent(".config/catwm")
        guard let names = try? fileManager.contentsOfDirectory(atPath: old.path) else { return }
        try? fileManager.createDirectory(at: new, withIntermediateDirectories: true)
        var moved = 0
        for name in names {
            let source = old.appendingPathComponent(name)
            if name == "ouch.sock" {
                try? fileManager.removeItem(at: source)
                continue
            }
            let target = new.appendingPathComponent(name == "ouch.conf" ? "catwm.conf" : name)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            do {
                try fileManager.moveItem(at: source, to: target)
                moved += 1
            } catch {
                Log.info("migration: could not move \(name): \(error.localizedDescription)")
            }
        }
        try? fileManager.removeItem(at: old.appendingPathComponent(".DS_Store"))
        rmdir(old.path)
        if moved > 0 { Log.info("migrated \(moved) files from ~/.config/ouch to ~/.config/catwm") }
    }

    static func copyHyprthystConfig(home: URL, fileManager: FileManager = .default) {
        let source = home.appendingPathComponent(".config/hyprthyst/hyprthyst.conf")
        let target = home.appendingPathComponent(".config/catwm/catwm.conf")
        guard !fileManager.fileExists(atPath: target.path), fileManager.fileExists(atPath: source.path) else { return }
        try? fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? fileManager.copyItem(at: source, to: target)) != nil {
            Log.info("migrated config from ~/.config/hyprthyst")
        }
    }

    static func migrateDefaults(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: "migratedLegacyDefaults") else { return }
        defaults.set(true, forKey: "migratedLegacyDefaults")
        for domain in ["local.ouch", "local.hyprthyst"] {
            guard let old = defaults.persistentDomain(forName: domain) else { continue }
            for (key, value) in old where defaults.object(forKey: key) == nil
                && !key.hasPrefix("NSWindow Frame")
                && key != "didSetUpLaunchAtLogin" {
                defaults.set(value, forKey: key)
            }
            Log.info("migrated \(old.count) settings from \(domain)")
        }
    }
}
