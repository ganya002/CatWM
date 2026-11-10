import Darwin
import Foundation

package struct TerminalAdapter: AppAdapter {
    package let bundleIDs: Set<String> = ["com.apple.Terminal"]
    package let captureNeedsAutomation = true
    package let restoreNeedsAutomation = false

    package func capture(bundleID: String, windows _: [AppStateCapture.Window],
                         timeout: TimeInterval) async -> [ScriptedWindow] {
        let source = ScriptText.frameHelper + """
        function run() {
          const app = Application("\(bundleID)");
          return JSON.stringify(app.windows().map(w => safe(() => {
            const tabs = w.tabs();
            if (tabs.length === 0) return null;
            return { title: safe(() => w.name(), ""), frame: safe(() => frameOf(w.bounds()), null),
                     tabs: tabs.map(t => safe(() => t.tty(), "")),
                     selected: Math.max(0, tabs.findIndex(t => safe(() => t.selected(), false))) };
          }, null)));
        }
        """
        let output = await AppScript.run(source, language: .javaScript, timeout: timeout)
        return ScriptedEntry.decode(output).compactMap { entry in
            entry.window(tabs: entry.tabs.map { WorkingDirectory.url(tty: $0) })
        }
    }

    package func restore(_ state: AppState, bundleID _: String, appURL: URL, timeout _: TimeInterval) async -> Bool {
        let (tabs, selected) = state.kept { URL(string: $0)?.isFileURL == true }
        let folders = tabs.compactMap { URL(string: $0) }
        guard let current = state.current.flatMap({ URL(string: $0) }), current.isFileURL else { return false }
        guard folders.count > 1 else { return await Launcher.open(current, withApp: appURL) }
        let profile = UserDefaults(suiteName: "com.apple.Terminal")?
            .string(forKey: "Default Window Settings") // style-ok: a Terminal preference key, not ours
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("CatWM-\(UUID().uuidString).terminal")
        guard let data = TerminalGroup.file(folders: folders, selected: selected,
                                            profile: profile ?? "Basic"),
              (try? data.write(to: file)) != nil else { return false }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) {
            try? FileManager.default.removeItem(at: file)
        }
        return await Launcher.open(file, withApp: appURL)
    }
}

package enum TerminalGroup {
    package static func file(folders: [URL], selected: Int, profile: String) -> Data? {
        let tabs: [[String: Any]] = folders.enumerated().map { index, folder in
            [
                "Tab Settings Name": profile,
                "Tab Settings": ["name": profile, "type": "Window Settings"],
                "Tab Working Directory URL": URL(fileURLWithPath: folder.path, isDirectory: true).absoluteString,
                "Tab Working Directory URL String": URL(fileURLWithPath: folder.path).absoluteString,
                "TabSelected": index == selected
            ]
        }
        let group: [String: Any] = [
            "name": "CatWM",
            "type": "Window Group",
            "WindowList": [["ShowsTabBar": folders.count > 1, "Window Settings": tabs]]
        ]
        return try? PropertyListSerialization.data(fromPropertyList: group, format: .xml, options: 0)
    }
}

package struct ITermAdapter: AppAdapter {
    package let bundleIDs: Set<String> = ["com.googlecode.iterm2"]
    package let captureNeedsAutomation = true
    package let restoreNeedsAutomation = true

    package func capture(bundleID: String, windows _: [AppStateCapture.Window],
                         timeout: TimeInterval) async -> [ScriptedWindow] {
        let source = ScriptText.frameHelper + """
        function run() {
          const app = Application("\(bundleID)");
          return JSON.stringify(app.windows().map(w => safe(() => {
            const tabs = w.tabs();
            if (tabs.length === 0) return null;
            const current = safe(() => w.currentTab().currentSession().tty(), "");
            const ttys = tabs.map(t => safe(() => t.currentSession().tty(), ""));
            return { title: safe(() => w.name(), ""), frame: safe(() => frameOf(w.bounds()), null),
                     tabs: ttys, selected: Math.max(0, ttys.indexOf(current)) };
          }, null)));
        }
        """
        let output = await AppScript.run(source, language: .javaScript, timeout: timeout)
        return ScriptedEntry.decode(output).compactMap { entry in
            entry.window(tabs: entry.tabs.map { WorkingDirectory.url(tty: $0) })
        }
    }

    package func restore(_ state: AppState, bundleID: String, appURL _: URL, timeout: TimeInterval) async -> Bool {
        let (tabs, selected) = state.kept { URL(string: $0)?.isFileURL == true }
        let paths = tabs.compactMap { URL(string: $0)?.path }
        guard !paths.isEmpty else { return false }
        let source = """
        on run argv
          tell application id "\(bundleID)"
            set targetWindow to (create window with default profile)
            tell current session of targetWindow to write text ("cd " & quoted form of (item 2 of argv))
            repeat with i from 3 to count argv
              tell targetWindow to set newTab to (create tab with default profile)
              tell current session of newTab to write text ("cd " & quoted form of (item i of argv))
            end repeat
            tell tab ((item 1 of argv) as integer) of targetWindow to select
          end tell
        end run
        """
        let output = await AppScript.run(source, language: .appleScript,
                                         arguments: [String(selected + 1)] + paths, timeout: timeout)
        return output != nil
    }
}

package enum WorkingDirectory {
    package static func url(tty: String) -> String {
        path(tty: tty).map { URL(fileURLWithPath: $0, isDirectory: true).absoluteString } ?? ""
    }

    package static func path(tty: String) -> String? {
        guard !tty.isEmpty else { return nil }
        var info = stat()
        guard stat(tty.hasPrefix("/dev/") ? tty : "/dev/" + tty, &info) == 0 else { return nil }
        guard let group = foregroundGroup(device: info.st_rdev) else { return nil }
        return directory(of: group)
    }

    private static func foregroundGroup(device: dev_t) -> pid_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, Int32(bitPattern: UInt32(device))]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 4)
        size = processes.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &processes, &size, nil, 0) == 0 else { return nil }
        let count = size / MemoryLayout<kinfo_proc>.stride
        guard count > 0 else { return nil }
        let group = processes[0].kp_eproc.e_tpgid
        return group > 0 ? group : nil
    }

    private static func directory(of pid: pid_t) -> String? {
        var vnode = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, size) == size else { return nil }
        let path = withUnsafePointer(to: vnode.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }
}
