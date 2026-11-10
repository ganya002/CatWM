import CatWMKit
import Foundation

enum Migrations {
    static func run() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        moveOuchConfigFolder(home: home)
        copyHyprthystConfig(home: home)
        migrateDefaults(Instance.defaults)
    }

    static func moveOuchConfigFolder(home: URL, fileManager: FileManager = .default) {
        let old = home.appendingPathComponent(".config/ouch")
        let new = home.appendingPathComponent(".config/catwm")
        guard let names = try? fileManager.contentsOfDirectory(atPath: old.path) else { return }
        Log.attempt("migration: create ~/.config/catwm") {
            try fileManager.createDirectory(at: new, withIntermediateDirectories: true)
        }
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
        Log.attempt("migration: create ~/.config/catwm") {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        if (try? fileManager.copyItem(at: source, to: target)) != nil {
            Log.info("migrated config from ~/.config/hyprthyst")
        }
    }

    static func migrateDefaults(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.migratedLegacyDefaults) else { return }
        defaults.set(true, forKey: DefaultsKey.migratedLegacyDefaults)
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
