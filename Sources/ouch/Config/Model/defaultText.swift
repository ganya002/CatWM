import AppKit

let defaultText: String = {
    var config = Config()
    config.floating = ["com.apple.systempreferences", "com.apple.SystemSettings", "com.apple.calculator"]
    return """
# CatWM config: Amethyst's options with Hyprland-style syntax.
# Edit, then reload from the menu bar or with $mod SHIFT, R.

# SUPER = Command, ALT = Option. Option is the default so app shortcuts (Cmd-Q, Cmd-C...) keep working.
$mod = ALT

""" + Options.lines(config).joined(separator: "\n") + "\n\n" + defaultBinds
}()
