import AppKit

enum Options {
    static let all: [ConfigOption] = [
        .bool("floating-is-blacklist", \.floatingIsDenylist).script("floating.listedAppsFloat")
            .documented("bool", "true: listed apps float. false: only listed apps are tiled")
            .setting(.windows, "windows.floatingMode", "Apps in the list",
                     keywords: "floating apps float exclude blacklist whitelist tile only", section: "Floating"),

        .bool("window-margins", \.windowMargins).script("gaps.enabled")
            .documented("bool", "gaps between windows")
            .section("gaps")
            .note("Hyprland names also work: gaps_in = per-window gap, gaps_out = screen padding.")
            .setting(.layout, "layout.gaps", "Gaps between windows", keywords: "margin spacing"),
        .points("window-margin-size", \.windowMarginSize, valid: 0...100).script("gaps.size")
            .documented("0–100 points", "`gaps_in` is accepted and doubled")
            .setting(.layout, "layout.gapSize", "Gap size", keywords: "margin spacing points", range: 0...60,
                     enabled: { $0.windowMargins }, width: 180),
        .bool("smart-window-margins", \.smartWindowMargins).script("gaps.smart")
            .documented("bool", "no gaps with a single window").aliases("smart-gaps")
            .setting(.layout, "layout.smartGaps", "Smart gaps", help: "No gaps when a window is alone",
                     keywords: "single window no gaps", enabled: { $0.windowMargins }),
        .points("screen-padding-left", \.paddingLeft, valid: 0...500).script("padding.left")
            .documented("0–500 points", "`screen-padding` or `gaps_out` sets all four sides"),
        .points("screen-padding-right", \.paddingRight, valid: 0...500).script("padding.right")
            .documented("0–500 points", ""),
        .points("screen-padding-top", \.paddingTop, valid: 0...500).script("padding.top")
            .documented("0–500 points", ""),
        .points("screen-padding-bottom", \.paddingBottom, valid: 0...500).script("padding.bottom")
            .documented("0–500 points", ""),
        .bool("disable-padding-on-builtin-display", \.disablePaddingOnBuiltinDisplay)
            .script("noPaddingOnBuiltinDisplay")
            .documented("bool", "")
            .setting(.layout, "layout.builtin", "No padding on the built-in display", keywords: "laptop macbook",
                     section: "Padding"),
        .bool("ignore-menu-bar", \.ignoreMenuBar).script("ignoreMenuBar")
            .documented("bool", "tile over the menu bar area")
            .setting(.layout, "layout.menuBar", "Ignore menu bar when tiling",
                     help: "Use this if you hide the menu bar", keywords: "tile over hidden menubar", advanced: true,
                     section: "Gaps and padding"),

        .bool("mouse-follows-focus", \.mouseFollowsFocus).script("focus.mouseFollowsFocus")
            .documented("bool", "").section("behaviour")
            .setting(.windows, "windows.mff", "Mouse follows focus", help: "The pointer jumps to the window you focus",
                     keywords: "pointer cursor warp", order: 2),
        .bool("focus-follows-mouse", \.focusFollowsMouse).script("focus.followsMouse")
            .documented("bool", "").aliases("follow_mouse")
            .setting(.windows, "windows.ffm", "Focus follows mouse", help: "Hovering a window focuses it",
                     keywords: "hover pointer"),
        .bool("focus-follows-mouse-in-mode-only", \.focusFollowsMouseInModeOnly).script("focus.followsMouseInModeOnly")
            .documented("bool", "with `focus-follows-mouse` on, hovering focuses a window only while window mode is on")
            .note("With focus-follows-mouse on: hovering focuses a window only while window mode is on.")
            .setting(.windows, "windows.ffmModeOnly", "Only in window mode",
                     help: "Hovering focuses a window only while window mode is on",
                     keywords: "focus follows mouse hover pointer submap", order: 1, enabled: { $0.focusFollowsMouse }),
        .bool("mouse-swaps-windows", \.mouseSwapsWindows).script("mouse.swapsWindows")
            .documented("bool", "drag a tile onto another to swap")
            .setting(.windows, "windows.dragSwap", "Drag to swap", help: "Drop a window on another to trade places",
                     keywords: "mouse move", section: "Mouse"),
        .bool("mouse-resizes-windows", \.mouseResizesWindows).script("mouse.resizesWindows")
            .documented("bool", "drag edges to resize")
            .setting(.windows, "windows.resizeMain", "Drag window edges to resize the main pane",
                     help: "Resize a tiled window with the mouse, and the main pane follows", keywords: "mouse ratio",
                     section: "Mouse"),
        .bool("split-handle", \.splitHandle).script("mouse.splitHandle")
            .documented("bool", "a bar on the main split: drag it to resize, click it to swap the sides")
            .setting(.windows, "windows.splitHandle", "Split handle",
                     help: "Drag the bar between the sides to resize. Click it to swap the sides",
                     keywords: "divider bar grip mouse ratio swap", section: "Mouse"),
        .bool("auto-hide-tab-strip", \.autoHideTabStrip).script("tabs.autoHideStrip")
            .documented("bool", "hide each tab strip until the pointer reaches the top of its window")
            .setting(.windows, "windows.autoHideTabStrip", "Auto-hide tab strip",
                     help: "Tab groups hide their tabs. Move the pointer to the window top to show them",
                     keywords: "tabs group bar strip hide collapse reveal", section: "Tab groups"),
        .bool("tab-notification-badges", \.tabNotificationBadges).script("tabs.notificationBadges")
            .documented("bool", "show a red badge with the unread count on each tab")
            .setting(.windows, "windows.tabNotificationBadges", "Show notification badges on tabs",
                     help: "A tab shows the unread count of its app or window",
                     keywords: "tabs unread count badge notification dock red", section: "Tab groups"),
        .bool("new-windows-to-main", \.newWindowsToMain).script("newWindowsToMain")
            .documented("bool", "").aliases("new_is_master")
            .setting(.windows, "windows.newMain", "New windows become main", keywords: "open", advanced: true,
                     section: "Windows"),
        .bool("float-small-windows", \.floatSmallWindows).script("floating.smallWindows")
            .documented("bool", "")
            .setting(.windows, "windows.floatSmall", "Float small windows", help: "Dialogs and panels stay put",
                     keywords: "dialogs panels", advanced: true, section: "Windows"),
        .number("window-resize-step", \.windowResizeStep, convert: { $0 >= 1 ? $0 / 100 : $0 }, make: { CGFloat($0) },
                text: { String(format: "%g", Double($0 >= 0.01 ? $0 * 100 : $0)) }, number: { Double($0) })
            .script("resizeStep")
            .documented("number", "percent (`5`) or fraction (`0.05`); 1 or more is read as percent")
            .note("How far the main pane grows or shrinks each time, in percent (5) or as a fraction (0.05).")
            .setting(.layout, "layout.resizeStep", "Main pane resize step", help: "How much the split moves each time",
                     keywords: "ratio grow shrink percent", range: 1...25, scale: 100, section: "Main pane", unit: "%"),
        .bool("enables-layout-hud", \.enablesLayoutHUD).script("layoutHud.enabled")
            .documented("bool", "HUD when the layout changes")
            .setting(.layout, "layout.hud", "Show layout name on change",
                     help: "A short card in the middle of the screen", keywords: "hud overlay", section: "Feedback"),
        .bool("enables-layout-hud-on-space-change", \.enablesLayoutHUDOnSpaceChange).script("layoutHud.onSpaceChange")
            .documented("bool", "")
            .setting(.layout, "layout.hudSpaces", "Also when switching spaces",
                     keywords: "show layout name hud desktop", advanced: true, section: "Feedback",
                     enabled: { $0.enablesLayoutHUD })
    ] + FocusDim.features.flatMap(\.options) + workspaces + [
        .bool("keyboard-help", \.keyboardHelp).script("keyboardHelp.enabled")
            .documented("bool", "on-screen keyboard help in window mode")
            .section("keyboard help")
            .note("Keep holding the window-mode chord's modifier (or press keyboard-help-key in window mode) to see\n"
                + "every window-mode key on an on-screen keyboard.")
            .setting(.shortcuts, "shortcuts.keyboardHelp", "Show keyboard help",
                     keywords: "on-screen hold command cmd caps lock question mark"),
        ConfigOption("keyboard-help-key", \Config.keyboardHelpKey, read: { value, _ -> (String?, String?) in
            guard value.count == 1 else { return (nil, "keyboard-help-key must be a single character, such as ?") }
            return (value, nil)
        }, text: { $0 }).script("keyboardHelp.key")
            .documented("one character", "toggles the keyboard help in window mode"),
        ConfigOption("keyboard-finish", \Config.keyboardFinish, read: { value, _ -> (String?, String?) in
            guard MacKeyboard.isValid(value) else {
                return (nil, "unknown keyboard finish `\(value)` (auto, macbook-pro, macbook-air, macbook-neo, "
                    + "magic-keyboard, or a finish like macbook-pro-space-black)")
            }
            return (MacKeyboard.slug(value), nil)
        }, text: { $0 })
            .script("keyboardHelp.finish",
                    type: ["auto", "macbook-pro", "macbook-air", "macbook-neo", "magic-keyboard"]
                        .map { "\"\($0)\"" }.joined(separator: " | ") + " | (string & {})")
            .documented("`auto`, `macbook-pro`, `macbook-air`, `macbook-neo`, `magic-keyboard`, "
                            + "or a finish such as `macbook-pro-space-black`", "look of the Shortcut Map keyboard")
            .note("The keyboard drawn there and in Settings: auto follows this Mac (model, colour, layout). "
                + "Or pick a model\n"
                + "(macbook-pro, macbook-air, macbook-neo, magic-keyboard) or a finish, e.g. macbook-pro-space-black,\n"
                + "macbook-air-midnight, macbook-air-starlight, macbook-neo-citrus, imac-blue.")
            .setting(.shortcuts, "shortcuts.keyboardFinish", "Keyboard finish",
                     help: "Used by keyboard help and Shortcut Map",
                     keywords: "keyboard model colour color auto macbook air pro neo magic"),
        .bool("cursor-actions", \.cursorActions).script("cursorActions")
            .documented("bool", "in window mode, a dot at the pointer; a tap of the mode modifier opens saved "
                            + "workspace templates and the Save workspace action")
            .note("In window mode a dot follows the pointer; "
                + "tap the mode's modifier to save or open workspace templates.")
            .setting(.windows, "windows.cursorActions", "Quick actions at the pointer",
                     help: "In window mode, tap the mode's modifier to save or open a workspace template",
                     keywords: "cursor mouse menu window mode tap modifier template save", section: "Pointer menu"),
        .bool("template-app-scripting", \.templateAppScripting).script("templateAppScripting")
            .documented("bool", "workspace templates also save browser tabs, Terminal and iTerm2 tab folders, "
                            + "Finder folders and code editor projects; macOS asks once for each scripted app")
            .section("templates")
            .note("Templates also save browser tabs, terminal folders, Finder folders and editor projects.\n"
                + "macOS asks you once for each app to let CatWM control it.")
            .setting(.templates, "templates.appScripting", "Save tabs and folders",
                     help: "Browser tabs, terminal tabs, Finder folders and editor projects. "
                        + "macOS asks once for each app",
                     keywords: "automation applescript safari chrome browser url terminal iterm finder folder tabs "
                        + "vscode cursor zed xcode project",
                     section: "Apps"),

        .bool("switcher-instant-jump", \.switcherInstantJump).script("switcher.instantJump")
            .documented("bool", "in the window switcher, a search with one prefix match opens that window by itself")
            .section("window switcher")
            .note("The window switcher: tap $mod Tab for the last window, hold it to browse, type to search.\n"
                + "Instant jump opens a search with one prefix match by itself after the delay (0 opens it at once).")
            .setting(.windows, "windows.switcherJump", "Instant jump",
                     help: "A search with one prefix match opens by itself",
                     keywords: "switcher alt tab search type jump", section: "Switcher"),
        .number("switcher-jump-delay", \.switcherJumpDelay, valid: 0...2000, make: { Int($0) }, text: { "\($0)" },
                number: { Double($0) }).script("switcher.jumpDelay")
            .documented("milliseconds", "wait before instant jump opens the match; `0` opens it at once")
            .setting(.windows, "windows.switcherJumpDelay", "Jump delay", help: "0 opens the match at once",
                     keywords: "switcher instant jump wait milliseconds", range: 0...1000, section: "Switcher",
                     enabled: { $0.switcherInstantJump }, unit: " ms", width: 180),
        .list("switcher-exclude", \.switcherExclude).script("switcher.exclude")
            .documented("bundle IDs, comma separated", "apps the window switcher never shows; wildcards like "
                            + "com.adobe.* work")
            .note("Bundle IDs the switcher never shows, comma separated (wildcards like com.adobe.* work).")
            .setting(.windows, "windows.switcherExclude", "Apps the switcher hides",
                     keywords: "switcher exclude hide ignore apps bundle", section: "Switcher"),

        .bool("animate", \.animate).script("animation.enabled")
            .documented("bool", "`animations { enabled = … }` also works").aliases("animations").animation()
            .section("animation")
            .note("These also set how windows slide when you switch workspaces.")
            .setting(.motion, "motion.animate", "Animate windows", help: "Windows glide to their new place",
                     keywords: "animation off motion"),
        .number("animation-duration", \.animationDuration, valid: 0...5, convert: { $0 > 5 ? $0 / 1000 : $0 },
                make: { $0 }, text: { String(format: "%g", ($0 * 1000).rounded() / 1000) }, number: { $0 })
            .script("animation.duration")
            .documented("seconds, or ms if above 5", "").animation()
            .note("Seconds; a value above 5 is read as milliseconds.")
            .setting(.motion, "motion.duration", "Duration", keywords: "speed time milliseconds animation",
                     range: 0.05...1, enabled: { $0.animate }),
        ConfigOption("animation-curve", \Config.animationCurve, read: { value, _ -> (AnimationCurve?, String?) in
            guard let curve = AnimationCurve(value) else {
                return (nil, "unknown animation curve `\(value)` (ease-out, ease-in-out, linear, spring, bounce, "
                    + "overshoot or cubic-bezier(x1, y1, x2, y2))")
            }
            return (curve, nil)
        }, text: { $0.name })
            .script("animation.curve", type: AnimationCurve.named.map { "\"\($0.name)\"" }.joined(separator: " | ")
                + " | `cubic-bezier(${number}, ${number}, ${number}, ${number})`")
            .documented("`ease-out` `ease-in-out` `linear` `spring` `bounce` `overshoot` "
                            + "`cubic-bezier(x1, y1, x2, y2)`", "").animation()
            .note("ease-out, ease-in-out, linear, spring, bounce, overshoot or cubic-bezier(x1, y1, x2, y2)\n"
                + "like CSS (y past 0...1 overshoots).")
            .setting(.motion, "motion.curve", "Curve", help: "How windows speed up and settle",
                     keywords: "easing ease spring bounce overshoot linear", advanced: true, section: "Curve",
                     enabled: { $0.animate }),
        .number("animation-bounce", \.animationBounce, valid: 0...1, convert: { $0 > 1 ? $0 / 100 : $0 }, make: { $0 },
                text: { String(format: "%g", ($0 * 100).rounded() / 100) }, number: { $0 }).script("animation.bounce")
            .documented("0–1 (or 0–100)", "liveliness of spring/bounce/overshoot").animation()
            .note("How lively spring, bounce and overshoot are, 0-1.")
            .setting(.motion, "motion.bounce", "Bounciness",
                     help: "How far springs swing, balls bounce and overshoot goes",
                     keywords: "spring overshoot", advanced: true, range: 0...1, section: "Curve",
                     enabled: { $0.animate && $0.animationCurve.usesBounce }),

        .choice("panel-animation", \.panelAnimation, noun: "panel animation").script("panelAnimation")
            .documented(nil, "how Overview and keyboard help come and go; `tile` follows the animation curve; "
                            + "`catwm panelfx <style>` previews")
            .section("panels and window mode")
            .note("How Overview and keyboard help come and go: rise, pop, focus, tile or draw.")
            .setting(.motion, "motion.panels", "Panel animation", help: "How Overview and keyboard help come and go",
                     keywords: "overview sort windows keyboard help rise pop focus tile draw open appear",
                     advanced: true, section: "Panels and window mode"),
        .choice("mode-effect", \.modeEffect, noun: "mode effect").script("modeEffect")
            .documented(nil, "visual while window mode is on; `catwm modefx <style>` previews")
            .note("The screen-edge effect while window mode is on: draw, ripple, corners or none.")
            .setting(.motion, "motion.modeEffect", "Window mode effect",
                     help: "Shown at the screen edges while window mode is on",
                     keywords: "border edge draw ripple corners submap indicator", advanced: true,
                     section: "Panels and window mode"),

        .bool("debug-logging", \.debugLogging).script("debugLogging")
            .documented("bool", "verbose log; prefer `--verbose`").section("diagnostics"),
        .bool("perf-reports", \.perfReports).script("perfReports")
            .documented("bool", "sends repeated slow animations and hangs (numbers and app bundle IDs only) "
                            + "to the developers")
            .note("Send repeated animation slowdowns and hangs (numbers and app IDs only) to the developers.")
    ]
}

extension Options {
    static func lines(_ config: Config, includeAnimation: Bool = true) -> [String] {
        func heading(_ title: String) -> [String] {
            let head = "# ---- \(title) "
            return ["", head + String(repeating: "-", count: max(3, 78 - head.count))]
        }
        var out = Array(heading("layouts").dropFirst()) + [
            "# " + Layout.allCases.prefix(10).map(\.rawValue).joined(separator: ", ") + ",",
            "# " + Layout.allCases.dropFirst(10).map(\.rawValue).joined(separator: ", "),
            "layouts = " + config.layouts.map(\.rawValue).joined(separator: ", ")
        ]
        out += heading("floating apps") + [
            "# Bundle IDs to float (wildcards like com.adobe.* work). Set floating-is-blacklist = false",
            "# to make this a list of the ONLY apps that get tiled.",
            "floating = " + ConfigText.escape(config.floating.joined(separator: ", "))
        ]
        for option in all where includeAnimation || option.group != .animation {
            if let section = option.section { out += heading(section) }
            if let note = option.note { out += note.components(separatedBy: "\n").map { "# " + $0 } }
            out.append("\(option.key) = \(ConfigText.escape(option.text(config)))")
        }
        return out
    }
}

extension Options {
    static let workspaces: [ConfigOption] = [
        .bool("virtual-workspaces", \.virtualWorkspaces).script("workspaces.virtual")
            .documented("bool", "true: CatWM controls native Desktops. false: macOS controls switching. "
                + "See [workspaces.md](workspaces.md)")
            .section("workspaces")
            .note("CatWM controls native Desktops, workspace keys, animation and Overview.")
            .setting(.windows, "windows.workspaces", "Control macOS Desktops with CatWM",
                     help: "CatWM controls workspace keys, animation and Overview",
                     keywords: "spaces desktops virtual", section: "Workspaces"),
        .bool("stay-on-workspace-after-close", \.stayOnWorkspaceAfterClose).script("workspaces.stayAfterClose")
            .documented("bool", "")
            .setting(.windows, "windows.stay", "Stay on this workspace when closing a window", keywords: "close jump",
                     advanced: true, section: "Workspaces", enabled: { $0.virtualWorkspaces }),
        .bool("remove-empty-workspaces", \.removesEmptyWorkspaces).script("workspaces.removeEmpty")
            .documented("bool", "true: an empty workspace and its Desktop go away when you leave it")
            .setting(.windows, "windows.removeEmpty", "Remove empty workspaces when you leave them",
                     help: "Removes the empty Desktop too",
                     keywords: "clean auto delete desktop", section: "Workspaces",
                     enabled: { $0.virtualWorkspaces }),
        .bool("workspaces-per-display", \.workspacesPerDisplay).script("workspaces.perDisplay")
            .documented("bool", "true: each display counts its own workspaces from 1, and `workspace 2` selects the "
                + "second workspace on the current display. false: workspace numbers are shared by all displays")
            .setting(.windows, "windows.perDisplay", "Number workspaces on each display",
                     help: "Each display starts at workspace 1. Off: all displays share one set of numbers",
                     keywords: "monitor screen display shared separate per", section: "Workspaces",
                     enabled: { $0.virtualWorkspaces }),
        .number("sort-nudge", \.sortNudge, valid: 0...100, make: { Int($0) }, text: { "\($0)" }, number: { Double($0) })
            .script("workspaces.sortNudge")
            .documented("0–100 (whole number)",
                        "windows on one workspace before CatWM offers Overview; `0` turns the offer off")
            .setting(.windows, "windows.sortNudge", "Suggest Overview for a crowded workspace",
                     help: "A tip under the menu bar icon, at most once a day",
                     keywords: "tip packed many windows organize", range: 3...20, section: "Workspaces",
                     enabled: { $0.virtualWorkspaces })
    ]
}
