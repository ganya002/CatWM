import AppKit
import CatWMKit
import SwiftUI

struct WindowsPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
}

extension WindowsPane {
    static let searchSortCrowded = SettingEntry(id: "windows.sortCrowded", title: "Crowded from", pane: .windows,
                                                keywords: "overview sort windows workspace count tip")
    static let searchBundleID = SettingEntry(id: "windows.bundleID", title: "Add app by bundle ID", pane: .windows,
                                             advanced: true, keywords: "floating wildcard identifier")
}
