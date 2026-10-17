import AppKit

let defaultText: String = {
    var c = Config()
    c.floating = ["com.apple.systempreferences", "com.apple.SystemSettings", "com.apple.calculator"]
    return """
# Ouch config: Amethyst's options with Hyprland-style syntax.
# Edit, then reload from the menu bar or with $mod SHIFT, R.

# SUPER = Command, ALT = Option. Option is the default so app shortcuts (Cmd-Q, Cmd-C...) keep working.
$mod = ALT

""" + Options.lines(c).joined(separator: "\n") + "\n\n" + defaultBinds
}()
