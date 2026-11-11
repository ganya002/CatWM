import AppKit

extension WindowManager {
    package var hasWorkspaceRules: Bool { !config.workspaceRules.isEmpty }

    package func config(for workspace: String?) -> Config {
        guard hasWorkspaceRules, let workspace else { return config }
        if let resolved = workspaceConfigs[workspace] { return resolved }
        let screens = backend.screens()
        let screen = monitorOf[workspace].flatMap { uuid in screens.first { $0.uuid == uuid } }
        return resolvedConfig(of: workspace, on: screen, among: windows.keys.filter { windows[$0]?.minimized == false })
    }

    package func config(on screen: Screen, workspace: String? = nil) -> Config {
        guard hasWorkspaceRules else { return config }
        return config(for: workspace ?? workspaceKey(for: screen))
    }

    package func motion(on screen: Screen) -> MotionSpec { MotionSpec(config(on: screen)) }

    package func motion(forWorkspace workspace: String?) -> MotionSpec { MotionSpec(config(for: workspace)) }

    package func motion(of window: Window) -> MotionSpec { motion(forWorkspace: workspaceOf[window.id]) }

    package func resolveWorkspaceConfigs(screens: [Screen]) {
        guard hasWorkspaceRules else {
            if !workspaceConfigs.isEmpty { workspaceConfigs = [:] }
            return
        }
        var resolved: [String: Config] = [:]
        for screen in screens {
            guard let workspace = shown[screen.uuid], resolved[workspace] == nil else { continue }
            let config = resolvedConfig(of: workspace, on: screen, among: visible)
            resolved[workspace] = config
            followRuleLayouts(config.layouts, on: workspace)
        }
        workspaceConfigs = resolved
    }

    private func followRuleLayouts(_ layouts: [Layout], on workspace: String) {
        guard let state = states[workspace], let first = layouts.first else { return }
        if state.layouts == nil { state.layouts = config.layouts }
        guard state.layouts != layouts else { return }
        state.layouts = layouts
        if let before = state.layoutBeforeRule, layouts.contains(before) {
            state.layout = before
            state.layoutBeforeRule = nil
        } else if !layouts.contains(state.layout) {
            state.layoutBeforeRule = state.layoutBeforeRule ?? state.layout
            state.layout = first
        }
    }

    package func rulePaths(for workspace: String? = nil) -> Set<String> {
        guard hasWorkspaceRules, let workspace = workspace ?? currentWorkspace else { return [] }
        let facts = workspaceFacts(of: workspace, on: monitorOf[workspace].flatMap { uuid in
            backend.screens().first { $0.uuid == uuid }
        }, among: visible)
        return Set(config.matchingRules(for: facts).flatMap(\.set.keys))
    }

    private func resolvedConfig(of workspace: String, on screen: Screen?,
                                among ids: some Sequence<CGWindowID>) -> Config {
        var resolved = config.resolved(for: workspaceFacts(of: workspace, on: screen, among: ids))
        if scope != nil || !config.features.contains(.dimming) {
            resolved.dimOtherWindows = false
            resolved.blurOtherWindows = false
        }
        return resolved
    }

    private func workspaceFacts(of workspace: String, on screen: Screen?,
                                among ids: some Sequence<CGWindowID>) -> WorkspaceFacts {
        var facts = WorkspaceFacts(layout: states[workspace]?.layout ?? config.layouts.first ?? .tall,
                                   names: [workspaceNumber(workspace)] + (labels[workspace].map { [$0] } ?? []))
        var perApp: [String: Int] = [:]
        var bundles = Set<String>()
        for id in ids where workspaceOf[id] == workspace {
            guard let window = windows[id] else { continue }
            facts.windows += 1
            perApp[window.bundleID ?? "pid \(window.pid)", default: 0] += 1
            if let bundle = window.bundleID { bundles.insert(bundle) }
        }
        facts.sameApp = perApp.values.max() ?? 0
        facts.apps = bundles.sorted()
        facts.focused = reportedFocusedWindow().flatMap { workspaceOf[$0.id] } == workspace
        if let screen { facts.displays = [screen.name, screen.isBuiltin ? "builtin" : "external"] }
        return facts
    }
}
