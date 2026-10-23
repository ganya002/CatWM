import AppKit
import SwiftUI

struct SearchResults: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI

    var body: some View {
        let results = SettingsIndex.search(settingsUI.search, doc: doc)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.small) {
                    Text("Search").textStyle(.title).foregroundStyle(Theme.ink).oneLine()
                    Text("“\(settingsUI.search)”").font(Theme.body(15)).foregroundStyle(Theme.inkMuted).oneLine()
                }
                .accessibilityAddTraits(.isHeader)
                if results.isEmpty {
                    Text("Nothing matches. Try another word, like “gaps” or “focus”.")
                        .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).oneLine()
                }
                ForEach(Pane.allCases) { pane in
                    let here = results.filter { $0.pane == pane }
                    if !here.isEmpty {
                        OGroup(pane.rawValue) {
                            ForEach(here) { result in
                                ResultRow(entry: result, first: result.id == results.first?.id) {
                                    settingsUI.open(result)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 40)
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
