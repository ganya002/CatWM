import AppKit
import SwiftUI

struct ScrollingPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI

    private var allPadding: Binding<CGFloat> {
        Binding(get: { doc.config.paddingTop }, set: { value in
            doc.config.paddingTop = value; doc.config.paddingBottom = value
            doc.config.paddingLeft = value; doc.config.paddingRight = value
        })
    }

    var body: some View {
        let config = doc.config
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            OGroup("Columns") {
                OptionRows(pane: .scrolling, section: "Columns", doc: doc, settingsUI: settingsUI)
            }

            OGroup("Gaps") {
                GapsPreview(config: config)
                    .frame(height: 170)
                    .padding(.vertical, 12)
                OptionRows(pane: .scrolling, section: "Gaps", doc: doc, settingsUI: settingsUI)
                if settingsUI.linkedPadding {
                    ORow(ScrollingPane.searchPadding.title, description: "Space between windows and the screen edges") {
                        points(allPadding, "Screen padding")
                    }
                        .setting(ScrollingPane.searchPadding.id, settingsUI)
                } else {
                    ORow("Top padding") { points($doc.config.paddingTop, "Top padding") }
                        .setting(ScrollingPane.searchPadding.id, settingsUI)
                    ORow("Bottom padding") { points($doc.config.paddingBottom, "Bottom padding") }
                    ORow("Left padding") { points($doc.config.paddingLeft, "Left padding") }
                    ORow("Right padding") { points($doc.config.paddingRight, "Right padding") }
                }
                OptionRows(pane: .scrolling, section: "Padding", doc: doc, settingsUI: settingsUI)
            }

            AdditionalOptionGroups(pane: .scrolling, doc: doc, settingsUI: settingsUI)

            AdvancedSection(pane: .scrolling, settingsUI: settingsUI) {
                OGroup("Gaps and padding") {
                    OSwitchRow(ScrollingPane.searchLinked.title,
                               isOn: Binding(get: { settingsUI.linkedPadding }, set: { linked in
                                   withAnimation(Motion.easeOut) { settingsUI.linkedPadding = linked }
                                   if linked { allPadding.wrappedValue = config.paddingTop }
                               }))
                    .setting(ScrollingPane.searchLinked.id, settingsUI)
                    OptionRows(pane: .scrolling, section: "Gaps and padding", advanced: true, doc: doc,
                               settingsUI: settingsUI)
                }
                AdditionalOptionGroups(pane: .scrolling, advanced: true, doc: doc, settingsUI: settingsUI)
            }
        }
    }

    private func points(_ value: Binding<CGFloat>, _ label: String) -> some View {
        OSlider(value: Binding(get: { Double(value.wrappedValue) },
                               set: { value.wrappedValue = CGFloat($0.rounded()) }),
                range: 0...60, step: 1, ticks: [10], resetValue: 10, width: 180, label: label,
                format: { "\(Int($0)) pt" })
    }
}

extension ScrollingPane {
    static let searchPadding = SettingEntry(id: "layout.padding", title: "Screen padding", pane: .scrolling,
                                            keywords: "edges margin inset")
    static let searchLinked = SettingEntry(id: "layout.linked", title: "Same padding on every side",
                                           pane: .scrolling, advanced: true, keywords: "top bottom left right")
}
