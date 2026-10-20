import AppKit
import SwiftUI

extension WindowsPane {
    @ViewBuilder var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            OGroup("Focus") {
                OptionRows(pane: .windows, section: "Focus", doc: doc, settingsUI: settingsUI)
            }

            OGroup("Mouse") {
                OptionRows(pane: .windows, section: "Mouse", doc: doc, settingsUI: settingsUI)
            }

            OGroup("Pointer menu") {
                OptionRows(pane: .windows, section: "Pointer menu", doc: doc, settingsUI: settingsUI)
            }

            OGroup("Floating") {
                OptionRows(pane: .windows, section: "Floating", doc: doc, settingsUI: settingsUI)
                AppList(ids: $doc.config.floating, empty: "Add one that's running, or by bundle ID under Advanced")
            }

            OGroup("Workspaces") {
                OptionRows(pane: .windows, section: "Workspaces", doc: doc, settingsUI: settingsUI)
            }

            AdditionalOptionGroups(pane: .windows, doc: doc, settingsUI: settingsUI)

            AdvancedSection(pane: .windows, settingsUI: settingsUI) {
                OGroup("Windows") {
                    OptionRows(pane: .windows, section: "Windows", advanced: true, doc: doc, settingsUI: settingsUI)
                    ORow(WindowsPane.searchBundleID.title, description: "Wildcards like com.adobe.* work too") {
                        OTextField(placeholder: "com.example.app", text: $settingsUI.newID, mono: true, onSubmit: add)
                            .frame(width: 190)
                        OButton("Add", size: .small, action: add)
                            .disabled(settingsUI.newID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .setting(WindowsPane.searchBundleID.id, settingsUI)
                }
                OGroup("Workspaces") {
                    OptionRows(pane: .windows, section: "Workspaces", advanced: true, doc: doc, settingsUI: settingsUI)
                    ORow(WindowsPane.searchHome.title,
                         description: WindowManager.shared.homeSpaceSummary.isEmpty
                             ? "The Desktop you're on when Ouch starts"
                             : "Workspaces live on \(WindowManager.shared.homeSpaceSummary)") {
                        OButton("Use This Desktop", size: .small) { WindowManager.shared.makeCurrentSpaceHome() }
                    }
                    .disabled(!doc.config.virtualWorkspaces)
                    .setting(WindowsPane.searchHome.id, settingsUI)
                }
                AdditionalOptionGroups(pane: .windows, advanced: true, doc: doc, settingsUI: settingsUI)
            }
        }
    }
}
