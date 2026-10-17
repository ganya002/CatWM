import AppKit
import SwiftUI

struct SearchResults: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    var body: some View {
        let results = SettingsIndex.search(ui.search, doc: doc)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OPageTitle(crumbs: ["Settings", "Search"], title: "“\(ui.search)”")
                if results.isEmpty {
                    Text("Nothing matches. Try another word, like “gaps” or “focus”.")
                        .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).oneLine()
                }
                ForEach(Pane.allCases) { p in
                    let here = results.filter { $0.pane == p }
                    if !here.isEmpty {
                        OGroup(p.rawValue) {
                            ForEach(here) { r in ResultRow(entry: r, first: r.id == results.first?.id) { ui.open(r) } }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, 22).padding(.bottom, 40)
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
