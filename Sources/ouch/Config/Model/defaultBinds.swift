import AppKit

let defaultBinds = """
# ---- keybinds: bind = MODS, key, dispatcher, args -------------------------
# Global binds work everywhere. Everything else lives in "window mode" (a Hyprland submap):
# press Cmd+Caps Lock, then single keys, vim style. Esc / i / Return or a mouse click leaves it.
bind = CTRL, 1..0, workspace, 1..10
bind = CTRL, left|right, workspace, r-1|r+1
bind = $mod, o, sort
bind = SUPER, capslock, submap, window
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
bind = , n, cyclelayout, next
bind = , p, cyclelayout, prev
bind = , comma, splitratio, -0.05
bind = , period, splitratio, +0.05
bind = SHIFT, comma, layoutmsg, addmaster
bind = SHIFT, period, layoutmsg, removemaster
bind = , m, layoutmsg, swapwithmaster
bind = , tab, cyclenext
bind = SHIFT, tab, cyclenext, prev
bind = , f, fullscreen
bind = SHIFT, f, nativefullscreen
bind = , v, togglefloating
bind = , z, retile
bind = SHIFT, t, toggletiling
bind = SHIFT, r, reload
bind = , escape|i|return, submap, reset
bind = SUPER, capslock, submap, reset
submap = reset
"""
