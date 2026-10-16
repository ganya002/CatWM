// Checks that the option table, the saved file, the default config and the agent docs agree.
import Foundation
import Testing
@testable import ouch

/// Every option at a value that is not its default, written as a hand-edited file would be (aliases, `_`, case).
private let changed = """
floating = com.example.app
floating_is_blacklist = no
window-margins = off
window_margin_size = 4
smart-gaps = yes
screen-padding-left = 1
screen-padding-right = 2
screen-padding-top = 3
screen-padding-bottom = 4
disable-padding-on-builtin-display = true
ignore-menu-bar = true
Mouse-Follows-Focus = true
follow_mouse = 1
focus-follows-mouse-in-mode-only = true
mouse-swaps-windows = false
mouse-resizes-windows = false
new_is_master = on
float-small-windows = false
window-resize-step = 0.005
enables-layout-hud = false
enables-layout-hud-on-space-change = false
dim_inactive = true
dim-strength = 45
blur-other-windows = true
blur-radius = 33.4
virtual-workspaces = false
stay-on-workspace-after-close = false
sort-strategy = APP
sort-nudge = 9
keyboard-help = false
keyboard-help-key = ##
keyboard-finish = macbook-air
cursor-actions = false
animations = off
animation-duration = 250
animation-curve = cubic-bezier(0.1, 1.5, 0.3, 1)
animation-bounce = 70
panel-animation = pop
mode-effect = ripple
debug-logging = true
perf-reports = true
"""

private func values(_ c: Config) -> [String: String] {
    Dictionary(uniqueKeysWithValues: Options.all.map { ($0.key, $0.text(c)) })
}

@Test func defaultTextHasEveryOptionAtItsDefault() {
    let c = Config.parse(defaultText)
    #expect(c.errors.isEmpty)
    #expect(values(c) == values(Config()))
}

@Test func savedFileReadsBackTheSame() {
    for text in [defaultText, changed] {
        let first = Config.parse(text)
        #expect(first.errors.isEmpty, "\(first.errors)")
        let saved = ConfigDocument(text: text).serialize()
        let again = Config.parse(saved)
        #expect(again.errors.isEmpty, "\(again.errors)")
        #expect(values(again) == values(first))
        #expect(again.layouts == first.layouts && again.floating == first.floating)
        // Nothing the parser read is left in the "lines Ouch doesn't recognise" part.
        #expect(!saved.contains("doesn't recognise"))
    }
}

@Test func changedTextChangesEveryOption() {
    let c = Config.parse(changed), d = Config()
    for o in Options.all {
        #expect(o.text(c) != o.text(d), "\(o.key) kept its default")
    }
}

@Test func animationConfigCarriesTheAnimationGroup() {
    let source = ConfigDocument(text: changed)
    let target = ConfigDocument(text: defaultText)
    target.applyAnimation(source.animationText())
    for o in Options.all {
        let expected = o.group == .animation ? source.config : Config.parse(defaultText)
        #expect(o.text(target.config) == o.text(expected), "\(o.key)")
    }
}

@Test func namesAreUniqueAndResolve() {
    let names = Options.all.flatMap(\.names).map(ConfigOption.norm)
    #expect(Set(names).count == names.count)
    for o in Options.all { for n in o.names { #expect(ConfigOption.named(n)?.key == o.key) } }
    let ids = SettingsIndex.all.map(\.id)
    #expect(Set(ids).count == ids.count)
}

@Test func agentDocsListEveryOptionWithItsDefault() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/AgentDocs/config.md")
    let rows = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n").filter { $0.hasPrefix("| `") }
    for o in Options.all {
        let row = rows.first { $0.hasPrefix("| `\(o.key)`") }
        #expect(row != nil, "config.md has no row for \(o.key)")
        guard let row else { continue }
        let first = row.components(separatedBy: "|")[1]
        for alias in o.aliases { #expect(first.contains("`\(alias)`"), "config.md lacks alias \(alias)") }
        #expect(row.contains("| `\(o.defaultText)` |"), "config.md has the wrong default for \(o.key)")
    }
}
