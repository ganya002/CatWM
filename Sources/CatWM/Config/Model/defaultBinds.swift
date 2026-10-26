import AppKit

let defaultBinds = """
# ---- keybinds: bind = MODS, key, dispatcher, args -------------------------
# Global binds work everywhere. Everything else lives in "window mode" (a Hyprland submap):
# press Cmd+Caps Lock, then single keys, vim style. Esc / i / Return or a mouse click leaves it.
bind = CTRL, 1..0, workspace, 1..10
bind = CTRL, left|right, workspace, r-1|r+1
bind = CTRL SHIFT, 1..0, movetoworkspace, 1..10
bind = CTRL SHIFT, left|right, movetoworkspace, r-1|r+1
bind = $mod, o, sort
# Tap for the last window, hold to browse every window, type to search:
bind = $mod, tab, switcher
bind = $mod SHIFT, tab, switcher, prev
bind = SUPER, capslock, submap, window
# Control+Option works in every app, outside window mode:
bind = $mod CTRL, h|j|k|l, movefocus, l|d|u|r
bind = $mod CTRL SHIFT, h|j|k|l, movewindow, l|d|u|r
bind = $mod CTRL, f, fullscreen
bind = $mod CTRL, v, togglefloating
bind = $mod CTRL, r, columnwidth, cycle
bind = $mod CTRL, m, columnwidth, max
bind = $mod CTRL, minus|equal, columnwidth, -10|+10
bind = $mod CTRL, c, centercolumn
bind = $mod CTRL, comma|period, consumeorexpel, left|right
bind = $mod CTRL, w, togglecolumntabs
# Scroll wheel / trackpad scroll while holding the modifier, and trackpad swipes:
# bind = $mod, mouse_down, workspace, e+1
# bind = $mod, mouse_up, workspace, e-1
# bind = $mod CTRL, swipe_left, workspace, e+1

submap = window
bind = , h|j|k|l, movefocus, l|d|u|r
bind = , left|down|up|right, movefocus, l|d|u|r
bind = SHIFT, h|j|k|l, movewindow, l|d|u|r
bind = SHIFT, left|down|up|right, movewindow, l|d|u|r
bind = , 1..0, workspace, 1..10
bind = SHIFT, 1..0, movetoworkspace, 1..10
bind = , w, focusmonitor, +1
bind = , b, focusmonitor, -1
bind = SHIFT, w, movewindow, mon:+1
bind = SHIFT, b, movewindow, mon:-1
bind = , r, columnwidth, cycle
bind = , m, columnwidth, max
bind = , comma|period, columnwidth, -10|+10
bind = SHIFT, comma|period, windowheight, -10|+10
bind = , c, centercolumn
bind = , s, consumeorexpel, left
bind = SHIFT, s, consumeorexpel, right
bind = , g, togglecolumntabs
bind = , tab, cyclenext
bind = SHIFT, tab, cyclenext, prev
bind = CTRL, h|j|k|l, moveintogroup, l|d|u|r
bind = , t, moveoutofgroup
bind = , bracketleft|bracketright, changegroupactive, b|f
bind = SHIFT, bracketleft|bracketright, movegroupwindow, b|f
bind = , f, fullscreen
bind = SHIFT, f, nativefullscreen
bind = , v, togglefloating
bind = , z, retile
bind = SHIFT, t, toggletiling
bind = SHIFT, r, reload
bind = , o, sort
bind = , slash, switcher
bind = , grave, workspace, previous
bind = , x, killactive
bind = , minus, minimize
bind = , d, toggledim
bind = SHIFT, d, toggleblur
bind = , escape|i|return, submap, reset
bind = SUPER, capslock, submap, reset
submap = reset
"""

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

let wasdText: String = {
    let head = defaultText.components(separatedBy: "submap = window").first ?? defaultText
    return head + """
submap = window
bind = , w|a|s|d, movefocus, u|l|d|r
bind = , left|down|up|right, movefocus, l|d|u|r
bind = SHIFT, w|a|s|d, movewindow, u|l|d|r
bind = SHIFT, left|down|up|right, movewindow, l|d|u|r
bind = , q|e, workspace, e-1|e+1
bind = SHIFT, q|e, movetoworkspace, e-1|e+1
bind = , 1..0, workspace, 1..10
bind = SHIFT, 1..0, movetoworkspace, 1..10
bind = , r, columnwidth, cycle
bind = , m, columnwidth, max
bind = , f, fullscreen
bind = SHIFT, f, nativefullscreen
bind = , c, togglefloating
bind = , g, consumeorexpel, left
bind = SHIFT, g, consumeorexpel, right
bind = , t, togglecolumntabs
bind = , v, centercolumn
bind = , space, focusmonitor, +1
bind = SHIFT, space, movewindow, mon:+1
bind = , comma|period, columnwidth, -10|+10
bind = SHIFT, comma|period, windowheight, -10|+10
bind = , tab, cyclenext
bind = SHIFT, tab, cyclenext, prev
bind = , z, retile
bind = SHIFT, t, toggletiling
bind = CTRL, r, reload
bind = , o, sort
bind = , slash, switcher
bind = , grave, workspace, previous
bind = , x, killactive
bind = , minus, minimize
bind = , escape|return, submap, reset
bind = SUPER, capslock, submap, reset
submap = reset

"""
}()
