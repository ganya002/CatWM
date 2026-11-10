@testable import CatWM
import Foundation
import Testing

private let changed = """
floating = com.example.app
floating_is_blacklist = no
window-margins = off
window_margin_size = 4
smart-gaps = no
screen-padding-left = 1
screen-padding-right = 2
screen-padding-top = 3
screen-padding-bottom = 4
disable-padding-on-builtin-display = false
ignore-menu-bar = true
Mouse-Follows-Focus = false
follow_mouse = 0
focus-follows-mouse-in-mode-only = false
mouse-swaps-windows = false
mouse-resizes-windows = false
new_is_master = on
float-small-windows = false
window-resize-step = 0.005
enables-layout-hud = true
enables-layout-hud-on-space-change = false
dim_inactive = true
dim-strength = 45
blur-other-windows = true
blur-radius = 33.4
virtual-workspaces = false
stay-on-workspace-after-close = false
sort-nudge = 9
keyboard-help = false
keyboard-help-key = ##
keyboard-finish = macbook-air
cursor-actions = false
switcher-instant-jump = no
switcher-jump-delay = 120
switcher-exclude = com.example.one, com.example.*
animations = off
animation-duration = 250
animation-curve = cubic-bezier(0.1, 1.5, 0.3, 1)
animation-bounce = 70
panel-animation = pop
mode-effect = ripple
debug-logging = true
perf-reports = true
"""

private func values(_ config: Config) -> [String: String] {
    Dictionary(uniqueKeysWithValues: Options.all.map { ($0.key, $0.text(config)) })
}

@Test func defaultTextHasEveryOptionAtItsDefault() {
    let config = Config.parse(defaultText)
    #expect(config.errors.isEmpty)
    #expect(values(config) == values(Config()))
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
        #expect(!saved.contains("doesn't recognise"))
    }
}

@Test func changedTextExercisesItsDeclaredOptions() {
    let config = Config.parse(changed), defaults = Config()
    let options = changed.components(separatedBy: "\n").compactMap { line -> ConfigOption? in
        guard let key = line.split(separator: "=", maxSplits: 1).first else { return nil }
        return ConfigOption.named(key.trimmingCharacters(in: .whitespaces))
    }
    for option in options {
        #expect(option.text(config) != option.text(defaults), "\(option.key) kept its default")
    }
}

@Test func everyOptionReadsAnAlternateValue() {
    for option in Options.all {
        let candidates = option.choices.map(\.0) + ["true", "false", "1", "2", "0", "0.5", "x", "linear", "macbook-air"]
        let alternate = candidates.first { value in
            var config = Config()
            return option.read(&config, value, option.key) == nil && option.text(config) != option.defaultText
        }
        #expect(alternate != nil, "No alternate value exercises \(option.key)")
        guard let alternate else { continue }
        let config = Config.parse("\(option.key) = \(alternate)")
        #expect(config.errors.isEmpty)
        #expect(option.text(config) != option.defaultText)
        let again = Config.parse(ConfigDocument(text: "\(option.key) = \(alternate)").serialize())
        #expect(option.text(again) == option.text(config))
    }
}

@Test func animationConfigCarriesTheAnimationGroup() {
    let source = ConfigDocument(text: changed)
    let target = ConfigDocument(text: defaultText)
    target.applyAnimation(source.animationText())
    for option in Options.all {
        let expected = option.group == .animation ? source.config : Config.parse(defaultText)
        #expect(option.text(target.config) == option.text(expected), "\(option.key)")
    }
}

@Test func namesAreUniqueAndResolve() {
    let names = Options.all.flatMap(\.names).map(ConfigOption.norm)
    #expect(Set(names).count == names.count)
    for option in Options.all { for name in option.names { #expect(ConfigOption.named(name)?.key == option.key) } }
    let ids = SettingsIndex.all.map(\.id)
    #expect(Set(ids).count == ids.count)
}

@Test func agentDocsListEveryOptionWithItsDefault() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/AgentDocs/config.md")
    let rows = try String(contentsOf: url, encoding: .utf8)
        .components(separatedBy: "\n")
        .filter { $0.hasPrefix("| `") }
    for option in Options.all {
        let row = rows.first { $0.hasPrefix("| `\(option.script)` |") }
        #expect(row != nil, "config.md has no row for \(option.script)")
        guard let row else { continue }
        for name in option.names { #expect(row.contains("`\(name)`"), "config.md lacks the .conf name \(name)") }
        #expect(row.contains("| `\(option.defaultText)` |"), "config.md has the wrong default for \(option.key)")
    }
}

@Test func everyOptionHasItsOwnPathInTheTypeScriptConfig() {
    let paths = Options.all.map(\.script)
    #expect(!paths.contains(""))
    #expect(Set(paths).count == paths.count)
}
