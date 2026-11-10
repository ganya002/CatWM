import Foundation

package enum DragAnywhere {
    private static let key = "NSWindowShouldDragOnGesture" as CFString

    package static var isEnabled: Bool {
        CFPreferencesGetAppBooleanValue(key, kCFPreferencesAnyApplication, nil)
    }

    package static func set(_ enabled: Bool) {
        CFPreferencesSetValue(key, enabled ? kCFBooleanTrue : nil, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        Log.info("drag windows from anywhere \(enabled ? "on" : "off")")
    }
}
