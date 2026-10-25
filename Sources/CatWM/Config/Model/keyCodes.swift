import AppKit

let keyCodes: [String: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "equal": 24, "=": 24, "9": 25, "7": 26, "minus": 27, "-": 27, "8": 28, "0": 29,
    "bracketright": 30, "]": 30, "o": 31, "u": 32, "bracketleft": 33, "[": 33, "i": 34, "p": 35,
    "return": 36, "enter": 36, "l": 37, "j": 38, "apostrophe": 39, "quote": 39, "'": 39, "k": 40,
    "semicolon": 41, ";": 41, "backslash": 42, "\\": 42, "comma": 43, "n": 45, "m": 46,
    "slash": 44, "/": 44, "period": 47, ".": 47, "tab": 48, "space": 49, "grave": 50, "`": 50,
    "backspace": 51, "escape": 53, "esc": 53, "capslock": 57, "caps": 57, "caps_lock": 57,
    "section": 10, "yen": 93, "underscore_jis": 94, "eisu": 102, "kana": 104,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
    "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    "home": 115, "pageup": 116, "prior": 116, "delete": 117, "end": 119, "pagedown": 121, "next": 121,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "mouse_up": SpecialKey.mouseUp, "mouse_down": SpecialKey.mouseDown,
    "mouse_left": SpecialKey.mouseLeft, "mouse_right": SpecialKey.mouseRight,
    "swipe_left": SpecialKey.swipeLeft, "swipe_right": SpecialKey.swipeRight,
    "swipe_up": SpecialKey.swipeUp, "swipe_down": SpecialKey.swipeDown
]
