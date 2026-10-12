import Foundation

/// macOS's hidden "drag windows from anywhere" setting: hold Ctrl+Cmd and drag any part of a window.
/// It's a global default (`NSWindowShouldDragOnGesture`) that apps read at launch, so apps that are
/// already running need a restart to pick up a change.
enum DragAnywhere {
    private static let key = "NSWindowShouldDragOnGesture" as CFString

    static var isEnabled: Bool {
        CFPreferencesGetAppBooleanValue(key, kCFPreferencesAnyApplication, nil)
    }

    static func set(_ on: Bool) {
        CFPreferencesSetValue(key, on ? kCFBooleanTrue : nil, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        Log.info("drag windows from anywhere \(on ? "on" : "off")")
    }
}
