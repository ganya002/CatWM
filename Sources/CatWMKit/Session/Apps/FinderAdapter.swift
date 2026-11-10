import Foundation

package struct FinderAdapter: AppAdapter {
    package let bundleIDs: Set<String> = ["com.apple.finder"]
    package let captureNeedsAutomation = true
    package let restoreNeedsAutomation = false

    package func capture(bundleID: String, windows _: [AppStateCapture.Window],
                         timeout: TimeInterval) async -> [ScriptedWindow] {
        let source = ScriptText.frameHelper + """
        function run() {
          const app = Application("\(bundleID)");
          return JSON.stringify(app.finderWindows().map(w => safe(() => ({
            title: safe(() => w.name(), ""), frame: safe(() => frameOf(w.bounds()), null),
            tabs: [safe(() => w.target().url(), "")], selected: 0
          }), null)));
        }
        """
        let output = await AppScript.run(source, language: .javaScript, timeout: timeout)
        return WindowTabs.merged(ScriptedEntry.decode(output).compactMap { entry in
            entry.window(tabs: entry.tabs.map { URL(string: $0)?.isFileURL == true ? $0 : "" })
        })
    }

    package func restore(_ state: AppState, bundleID _: String, appURL: URL, timeout _: TimeInterval) async -> Bool {
        guard let current = state.current, let url = URL(string: current), url.isFileURL else { return false }
        return await Launcher.open(url, withApp: appURL)
    }
}
