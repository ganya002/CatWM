import AppKit

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
bind = , r, cyclelayout, next
bind = SHIFT, r, cyclelayout, prev
bind = , f, fullscreen
bind = SHIFT, f, nativefullscreen
bind = , c, togglefloating
bind = , g, layoutmsg, swapwithmaster
bind = , space, focusmonitor, +1
bind = SHIFT, space, movewindow, mon:+1
bind = , comma, splitratio, -0.05
bind = , period, splitratio, +0.05
bind = SHIFT, comma, layoutmsg, addmaster
bind = SHIFT, period, layoutmsg, removemaster
bind = , tab, cyclenext
bind = SHIFT, tab, cyclenext, prev
bind = , z, retile
bind = SHIFT, t, toggletiling
bind = CTRL, r, reload
bind = , escape|return, submap, reset
bind = SUPER, capslock, submap, reset
submap = reset

"""
}()
