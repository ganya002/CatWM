import Foundation

package struct SafariAdapter: AppAdapter {
    package let bundleIDs: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
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
            return { title: safe(() => w.name(), ""), frame: safe(() => frameOf(w.bounds()), null),
                     tabs: tabs.map(t => safe(() => t.url() || "", "")),
                     selected: safe(() => w.currentTab().index() - 1, 0) };
          }, null)));
        }
        """
        let output = await AppScript.run(source, language: .javaScript, timeout: timeout)
        return ScriptedEntry.decode(output).compactMap { $0.window() }
    }

    package func restore(_ state: AppState, bundleID: String, appURL _: URL, timeout: TimeInterval) async -> Bool {
        let source = """
        on run argv
          set selectedIndex to (item 1 of argv) as integer
          tell application id "\(bundleID)"
            make new document with properties {URL:item 2 of argv}
            set targetWindow to front window
            repeat with i from 3 to count argv
              tell targetWindow to make new tab at end of tabs with properties {URL:item i of argv}
            end repeat
            set current tab of targetWindow to tab selectedIndex of targetWindow
          end tell
        end run
        """
        return await BrowserScript.restore(source, state: state, timeout: timeout)
    }
}

package struct ChromiumAdapter: AppAdapter {
    package let bundleIDs: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
                                          "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.edgemac",
                                          "com.vivaldi.Vivaldi", "net.imput.helium"]
    package let captureNeedsAutomation = true
    package let restoreNeedsAutomation = true

    package func capture(bundleID: String, windows _: [AppStateCapture.Window],
                         timeout: TimeInterval) async -> [ScriptedWindow] {
        let source = ScriptText.frameHelper + """
        function run() {
          const app = Application("\(bundleID)");
          return JSON.stringify(app.windows().map(w => safe(() => {
            if (safe(() => w.mode(), "normal") === "incognito") return null;
            const tabs = w.tabs();
            if (tabs.length === 0) return null;
            return { title: safe(() => w.name(), ""), frame: safe(() => frameOf(w.bounds()), null),
                     tabs: tabs.map(t => safe(() => t.url() || "", "")),
                     selected: safe(() => w.activeTabIndex() - 1, 0) };
          }, null)));
        }
        """
        let output = await AppScript.run(source, language: .javaScript, timeout: timeout)
        return ScriptedEntry.decode(output).compactMap { $0.window() }
    }

    package func restore(_ state: AppState, bundleID: String, appURL _: URL, timeout: TimeInterval) async -> Bool {
        let source = """
        on run argv
          set selectedIndex to (item 1 of argv) as integer
          tell application id "\(bundleID)"
            set targetWindow to make new window
            set URL of active tab of targetWindow to item 2 of argv
            repeat with i from 3 to count argv
              tell targetWindow to make new tab with properties {URL:item i of argv}
            end repeat
            set active tab index of targetWindow to selectedIndex
          end tell
        end run
        """
        return await BrowserScript.restore(source, state: state, timeout: timeout)
    }
}

package enum BrowserScript {
    package static func restore(_ source: String, state: AppState, timeout: TimeInterval) async -> Bool {
        let (tabs, selected) = state.kept(isOpenable)
        guard !tabs.isEmpty else { return false }
        let output = await AppScript.run(source, language: .appleScript,
                                         arguments: [String(selected + 1)] + tabs, timeout: timeout)
        return output != nil
    }

    package static func isOpenable(_ raw: String) -> Bool {
        guard let scheme = URL(string: raw)?.scheme?.lowercased() else { return false }
        return !["javascript", "data"].contains(scheme)
    }
}
